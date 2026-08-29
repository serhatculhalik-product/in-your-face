import Foundation
import XCTest
@testable import CommitmentProtection

final class GoogleCalendarConnectorHardeningTests: XCTestCase {
    func testAuthorizationUsesOnlyNarrowCalendarScopesAndPKCE() throws {
        let connector = GoogleCalendarConnector(configuration: testConfiguration)

        let url = try connector.makeAuthorizationURL(
            redirectURI: "http://127.0.0.1:49152/oauth/callback",
            codeVerifier: "known-code-verifier",
            state: "known-state"
        )
        let query = queryValues(in: url)

        XCTAssertEqual(
            query["scope"],
            "https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/calendar.events.readonly"
        )
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertNotNil(query["code_challenge"])
        XCTAssertNotEqual(query["code_challenge"], "known-code-verifier")
        XCTAssertNil(query["client_secret"])
        XCTAssertFalse(query["scope", default: ""].contains("openid"))
        XCTAssertFalse(query["scope", default: ""].contains("email"))
        XCTAssertFalse(query["scope", default: ""].contains("profile"))
        XCTAssertFalse(query["scope", default: ""].contains("calendar.readonly"))

        let tokenRequest = connector.makeAuthorizationCodeTokenRequest(
            code: "authorization-code",
            redirectURI: "http://127.0.0.1:49152/oauth/callback",
            codeVerifier: "known-code-verifier"
        )
        let tokenBody = formValues(
            in: tokenRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        )
        XCTAssertEqual(tokenRequest.httpMethod, "POST")
        XCTAssertEqual(tokenBody["code_verifier"], "known-code-verifier")
        XCTAssertEqual(tokenBody["client_id"], "client-id")
        XCTAssertNil(tokenBody["client_secret"])
    }

    func testAuthorizationCodeExchangeIncludesConfiguredClientSecret() {
        let connector = GoogleCalendarConnector(
            configuration: GoogleCalendarOAuthConfiguration(
                clientID: "client-id",
                clientSecret: "configured-secret"
            )
        )

        let tokenRequest = connector.makeAuthorizationCodeTokenRequest(
            code: "authorization-code",
            redirectURI: "http://127.0.0.1:49152/oauth/callback",
            codeVerifier: "known-code-verifier"
        )
        let tokenBody = formValues(
            in: tokenRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        )

        XCTAssertEqual(tokenBody["client_secret"], "configured-secret")
        XCTAssertEqual(tokenBody["code_verifier"], "known-code-verifier")
    }

    func testRefreshExchangeIncludesConfiguredClientSecret() async throws {
        let accountID = "person@example.com"
        let credentialSession = makeCredentialSession(accountID: accountID)
        let stub = GoogleAPIStub(scenario: .calendarPages(accountID: accountID))
        let connector = GoogleCalendarConnector(
            configuration: GoogleCalendarOAuthConfiguration(
                clientID: "client-id",
                clientSecret: "configured-secret"
            ),
            requestExecutor: { request in
                try await stub.execute(request)
            },
            credentialSession: credentialSession
        )

        _ = try await connector.restore(accountID: accountID)

        let requests = await stub.observedRequests()
        let tokenRequest = try XCTUnwrap(requests.first { $0.path == "/token" })
        let tokenBody = formValues(in: tokenRequest.body)
        XCTAssertEqual(tokenBody["client_secret"], "configured-secret")
        XCTAssertEqual(tokenBody["refresh_token"], "refresh-token")
    }

    func testBlankClientSecretIsOmittedFromTokenExchanges() async throws {
        let accountID = "person@example.com"
        let credentialSession = makeCredentialSession(accountID: accountID)
        let stub = GoogleAPIStub(scenario: .calendarPages(accountID: accountID))
        let connector = GoogleCalendarConnector(
            configuration: GoogleCalendarOAuthConfiguration(
                clientID: "client-id",
                clientSecret: " \n\t "
            ),
            requestExecutor: { request in
                try await stub.execute(request)
            },
            credentialSession: credentialSession
        )

        let authorizationRequest = connector.makeAuthorizationCodeTokenRequest(
            code: "authorization-code",
            redirectURI: "http://127.0.0.1:49152/oauth/callback",
            codeVerifier: "known-code-verifier"
        )
        _ = try await connector.restore(accountID: accountID)

        let authorizationBody = formValues(
            in: authorizationRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        )
        let requests = await stub.observedRequests()
        let refreshRequest = try XCTUnwrap(requests.first { $0.path == "/token" })
        XCTAssertNil(authorizationBody["client_secret"])
        XCTAssertNil(formValues(in: refreshRequest.body)["client_secret"])
    }

    func testTokenExchangeFailureDoesNotExposeConfiguredClientSecret() async throws {
        let accountID = "person@example.com"
        let clientSecret = "server-echoed-secret"
        let credentialSession = makeCredentialSession(accountID: accountID)
        let stub = GoogleAPIStub(
            scenario: .refreshFailure(
                statusCode: 400,
                body: #"{"error":"invalid_request","error_description":"Rejected client_secret server-echoed-secret"}"#
            )
        )
        let connector = GoogleCalendarConnector(
            configuration: GoogleCalendarOAuthConfiguration(
                clientID: "client-id",
                clientSecret: clientSecret
            ),
            requestExecutor: { request in
                try await stub.execute(request)
            },
            credentialSession: credentialSession
        )

        do {
            _ = try await connector.restore(accountID: accountID)
            XCTFail("A rejected token request should fail")
        } catch let error as GoogleCalendarConnectorError {
            XCTAssertFalse(String(reflecting: error).contains(clientSecret))
            XCTAssertFalse(error.localizedDescription.contains(clientSecret))
        }
    }

    func testCalendarRestoreLoadsEveryPageAndNormalizesBlankNames() async throws {
        let accountID = "person@example.com"
        let credentialSession = makeCredentialSession(accountID: accountID)

        let stub = GoogleAPIStub(scenario: .calendarPages(accountID: accountID))
        let connector = makeConnector(stub: stub, credentialSession: credentialSession)

        let restoredConnection = try await connector.restore(accountID: accountID)
        let connection = try XCTUnwrap(restoredConnection)

        XCTAssertEqual(
            connection.account,
            GoogleAccount(id: accountID, email: accountID, displayName: accountID)
        )
        XCTAssertEqual(connection.calendars.map(\.id), ["calendar-1", accountID])
        XCTAssertEqual(connection.calendars.map(\.name), ["calendar-1", "仕事 🗓️"])
        let observedPageTokens = await stub.observedPageTokens()
        XCTAssertEqual(observedPageTokens, [nil, "calendar-page-2"])
        let minAccessRoles = await stub.observedCalendarMinAccessRoles()
        XCTAssertEqual(minAccessRoles, ["reader", "reader"])
        let hosts = await stub.observedHosts()
        XCTAssertFalse(hosts.contains("openidconnect.googleapis.com"))

        let observedRequests = await stub.observedRequests()
        let tokenRequest = try XCTUnwrap(observedRequests.first { $0.path == "/token" })
        XCTAssertEqual(formValues(in: tokenRequest.body)["client_id"], "client-id")
        XCTAssertNil(formValues(in: tokenRequest.body)["client_secret"])
    }

    func testEventLoadingFollowsPaginationNormalizesBlankTitlesAndRejectsUnsafeLinks() async throws {
        let accountID = "event-pages-\(UUID().uuidString)"
        let credentialSession = makeCredentialSession(accountID: accountID)

        let stub = GoogleAPIStub(scenario: .eventPages)
        let connector = makeConnector(stub: stub, credentialSession: credentialSession)
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)

        let events = try await connector.loadEvents(
            accountID: accountID,
            calendarID: "calendar-1",
            from: startDate,
            to: startDate.addingTimeInterval(86_400)
        )

        XCTAssertEqual(events.map(\.id), ["event-1", "event-2"])
        XCTAssertEqual(events.map(\.title), ["Untitled commitment", "مرحبا 仕事 👋"])
        XCTAssertTrue(events[0].recognizedMeetingLinks.isEmpty)
        XCTAssertEqual(events[1].recognizedMeetingLinks.map(\.url.absoluteString), ["https://zoom.us/j/123"])
        let observedPageTokens = await stub.observedPageTokens()
        XCTAssertEqual(observedPageTokens, [nil, "event-page-2"])
    }

    func testOfflineAndTimeoutFailuresRemainActionable() async throws {
        let accountID = "transport-errors-\(UUID().uuidString)"
        let credentialSession = makeCredentialSession(accountID: accountID)

        let offlineConnector = GoogleCalendarConnector(
            configuration: testConfiguration,
            requestExecutor: { _ in throw URLError(.notConnectedToInternet) },
            credentialSession: credentialSession
        )
        do {
            _ = try await offlineConnector.restore(accountID: accountID)
            XCTFail("An offline request should fail")
        } catch let error as GoogleCalendarConnectorError {
            XCTAssertEqual(error, .networkUnavailable)
            XCTAssertEqual(
                error.errorDescription,
                "Can’t reach Google Calendar. Check your internet connection, then try again."
            )
        }

        let timeoutConnector = GoogleCalendarConnector(
            configuration: testConfiguration,
            requestExecutor: { _ in throw URLError(.timedOut) },
            credentialSession: credentialSession
        )
        do {
            _ = try await timeoutConnector.restore(accountID: accountID)
            XCTFail("A timed-out request should fail")
        } catch let error as GoogleCalendarConnectorError {
            XCTAssertEqual(error, .requestTimedOut)
            XCTAssertEqual(
                error.errorDescription,
                "Google Calendar took too long to respond. Try again."
            )
        }
    }

    func testHTTPFailuresLeadWithRecoveryInsteadOfRawDiagnostics() {
        XCTAssertEqual(
            GoogleCalendarConnectorError.calendarRequestFailed(401, "invalid_token").errorDescription,
            "Google Calendar access expired. Reconnect this account."
        )
        XCTAssertEqual(
            GoogleCalendarConnectorError.calendarRequestFailed(403, "insufficientPermissions").errorDescription,
            "Google Calendar access was denied. Reconnect the account and approve read-only calendar access."
        )
        XCTAssertEqual(
            GoogleCalendarConnectorError.calendarRequestFailed(429, "rateLimitExceeded").errorDescription,
            "Google Calendar is temporarily limiting requests. Try again in a few minutes."
        )
        XCTAssertEqual(
            GoogleCalendarConnectorError.calendarRequestFailed(503, nil).errorDescription,
            "Google Calendar is temporarily unavailable. Try again later."
        )
        XCTAssertEqual(
            GoogleCalendarConnectorError.tokenExchangeFailed(400, "invalid_grant: Bad Request").errorDescription,
            "Google sign-in couldn’t be completed. Try again."
        )
        XCTAssertEqual(
            GoogleCalendarConnectorError.tokenExchangeFailed(
                400,
                "invalid_grant: Bad Request"
            ).credentialFailureDisposition,
            .invalid
        )
        XCTAssertEqual(
            GoogleCalendarConnectorError.tokenExchangeFailed(
                503,
                "temporarily_unavailable"
            ).credentialFailureDisposition,
            .transient
        )
        XCTAssertEqual(
            GoogleCalendarConnectorError.calendarRequestFailed(
                401,
                "invalid_token"
            ).credentialFailureDisposition,
            .invalid
        )
        XCTAssertNil(
            GoogleCalendarConnectorError.calendarRequestFailed(
                403,
                "insufficientPermissions"
            ).credentialFailureDisposition
        )
        XCTAssertEqual(
            GoogleCalendarConnectorError.calendarRequestFailed(
                403,
                "userRateLimitExceeded"
            ).credentialFailureDisposition,
            .transient
        )
        XCTAssertEqual(GoogleCalendarConnectorError.networkUnavailable.credentialFailureDisposition, .transient)
    }

    func testMissingOAuthClientSecretExplainsTheBuildConfigurationProblem() {
        let failureReasons = [
            "invalid_request: client_secret is missing.",
            "invalid_request: client_secret is required."
        ]

        for reason in failureReasons {
            let error = GoogleCalendarConnectorError.tokenExchangeFailed(400, reason)
            XCTAssertEqual(
                error.errorDescription,
                "This build is missing its Google OAuth client secret. Add the matching client secret, then try again."
            )
            XCTAssertNil(error.credentialFailureDisposition)
        }
    }

    func testRejectedOAuthCredentialExplainsTheBuildConfigurationProblem() {
        let error = GoogleCalendarConnectorError.tokenExchangeFailed(
            400,
            "invalid_client: The OAuth client was not found."
        )

        XCTAssertEqual(
            error.errorDescription,
            "This build’s Google OAuth credential was rejected. Rebuild with the matching Desktop app client ID and client secret, then try again."
        )
        XCTAssertNil(error.credentialFailureDisposition)
    }

    func testTargetedReconnectRevokesTheNewGrantWhenADifferentGoogleAccountIsChosen() async throws {
        let savedAccountID = "saved@example.com"
        let chosenAccountID = "chosen@example.com"
        let credentialSession = makeCredentialSession(accountID: nil)
        let stub = GoogleAPIStub(
            scenario: .newAuthorization(
                accountID: chosenAccountID,
                revocationStatusCode: 503
            )
        )
        let connector = GoogleCalendarConnector(
            configuration: testConfiguration,
            requestExecutor: { request in
                try await stub.execute(request)
            },
            credentialSession: credentialSession,
            authorizationExecutor: {
                (
                    code: "authorization-code",
                    redirectURI: "http://127.0.0.1:49152/oauth/callback",
                    codeVerifier: "known-code-verifier"
                )
            }
        )

        do {
            _ = try await connector.connect(expectedAccountID: savedAccountID)
            XCTFail("Choosing a different account should not complete targeted reconnect")
        } catch let error as GoogleCalendarConnectorError {
            XCTAssertEqual(error, .unexpectedAccount)
        }

        let observedRequests = await stub.observedRequests()
        let revocationRequest = try XCTUnwrap(
            observedRequests.first { $0.path == "/revoke" }
        )
        XCTAssertEqual(revocationRequest.method, "POST")
        XCTAssertEqual(revocationRequest.contentType, "application/x-www-form-urlencoded")
        XCTAssertEqual(
            formValues(in: revocationRequest.body)["token"],
            "new-refresh-token"
        )
        XCTAssertNil(credentialSession.load(accountID: savedAccountID))
        XCTAssertNil(credentialSession.load(accountID: chosenAccountID))
    }

    func testMissingPrimaryCalendarIsRejectedInsteadOfCreatingAnInvisibleAccount() async throws {
        let accountID = "missing-primary@example.com"
        let credentialSession = makeCredentialSession(accountID: accountID)

        let connector = makeConnector(
            stub: GoogleAPIStub(scenario: .missingPrimary),
            credentialSession: credentialSession
        )

        do {
            _ = try await connector.restore(accountID: accountID)
            XCTFail("A blank account identity should be rejected")
        } catch let error as GoogleCalendarConnectorError {
            XCTAssertEqual(error, .malformedResponse)
        }
    }

    func testAmbiguousPrimaryCalendarsAreRejected() async throws {
        let accountID = "ambiguous-primary@example.com"
        let credentialSession = makeCredentialSession(accountID: accountID)
        let connector = makeConnector(
            stub: GoogleAPIStub(scenario: .ambiguousPrimary),
            credentialSession: credentialSession
        )

        do {
            _ = try await connector.restore(accountID: accountID)
            XCTFail("More than one primary calendar should be rejected")
        } catch let error as GoogleCalendarConnectorError {
            XCTAssertEqual(error, .malformedResponse)
        }
    }

    func testRemoteRevocationDeletesCredentialOnlyAfterGoogleAcceptsIt() async throws {
        let accountID = "revoke@example.com"
        let credentialSession = makeCredentialSession(accountID: accountID)
        let stub = GoogleAPIStub(scenario: .revocation(statusCode: 200, body: ""))
        let connector = makeConnector(stub: stub, credentialSession: credentialSession)

        let result = try await connector.revokeAuthorization(accountID: accountID)

        XCTAssertEqual(result, .revoked)
        XCTAssertNil(credentialSession.load(accountID: accountID))
        let observedRequests = await stub.observedRequests()
        let request = try XCTUnwrap(observedRequests.first)
        XCTAssertEqual(request.host, "oauth2.googleapis.com")
        XCTAssertEqual(request.path, "/revoke")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.contentType, "application/x-www-form-urlencoded")
        XCTAssertNil(request.query)
        XCTAssertEqual(formValues(in: request.body)["token"], "refresh-token")
    }

    func testRemoteRevocationTreatsInvalidTokenAsIdempotentSuccess() async throws {
        let accountID = "already-invalid@example.com"
        let credentialSession = makeCredentialSession(accountID: accountID)
        let stub = GoogleAPIStub(
            scenario: .revocation(
                statusCode: 400,
                body: #"{"error":"invalid_token","error_description":"Token is already invalid"}"#
            )
        )
        let connector = makeConnector(stub: stub, credentialSession: credentialSession)

        let result = try await connector.revokeAuthorization(accountID: accountID)

        XCTAssertEqual(result, .alreadyInvalid)
        XCTAssertNil(credentialSession.load(accountID: accountID))
    }

    func testRemoteRevocationRetainsCredentialWhenGoogleIsTransientlyUnavailable() async throws {
        let accountID = "revoke-retry@example.com"
        let credentialSession = makeCredentialSession(accountID: accountID)
        let stub = GoogleAPIStub(
            scenario: .revocation(
                statusCode: 503,
                body: #"{"error":"temporarily_unavailable"}"#
            )
        )
        let connector = makeConnector(stub: stub, credentialSession: credentialSession)

        do {
            _ = try await connector.revokeAuthorization(accountID: accountID)
            XCTFail("A transient revoke failure should be surfaced")
        } catch let error as GoogleCalendarConnectorError {
            XCTAssertEqual(error, .tokenRevocationFailed(503, "temporarily_unavailable"))
            XCTAssertEqual(error.credentialFailureDisposition, .transient)
        }
        XCTAssertEqual(credentialSession.load(accountID: accountID), "refresh-token")
    }

    func testRemoteRevocationWithoutLocalCredentialIsExplicitAndMakesNoGoogleRequest() async throws {
        let accountID = "missing-token@example.com"
        let credentialSession = makeCredentialSession(accountID: nil)
        let stub = GoogleAPIStub(scenario: .revocation(statusCode: 500, body: ""))
        let connector = makeConnector(stub: stub, credentialSession: credentialSession)

        let result = try await connector.revokeAuthorization(accountID: accountID)

        XCTAssertEqual(result, .localCredentialMissing)
        let observedRequests = await stub.observedRequests()
        XCTAssertTrue(observedRequests.isEmpty)
    }

    func testInvalidRefreshTokenIsErasedButTransientFailureIsRetained() async throws {
        let invalidAccountID = "invalid-refresh@example.com"
        let invalidCredentials = makeCredentialSession(accountID: invalidAccountID)
        let invalidConnector = makeConnector(
            stub: GoogleAPIStub(
                scenario: .refreshFailure(
                    statusCode: 400,
                    body: #"{"error":"invalid_grant","error_description":"Token revoked"}"#
                )
            ),
            credentialSession: invalidCredentials
        )

        do {
            _ = try await invalidConnector.restore(accountID: invalidAccountID)
            XCTFail("A revoked refresh token should fail")
        } catch let error as GoogleCalendarConnectorError {
            XCTAssertEqual(error.credentialFailureDisposition, .invalid)
        }
        XCTAssertNil(invalidCredentials.load(accountID: invalidAccountID))

        let transientAccountID = "transient-refresh@example.com"
        let transientCredentials = makeCredentialSession(accountID: transientAccountID)
        let transientConnector = makeConnector(
            stub: GoogleAPIStub(
                scenario: .refreshFailure(
                    statusCode: 503,
                    body: #"{"error":"temporarily_unavailable"}"#
                )
            ),
            credentialSession: transientCredentials
        )

        do {
            _ = try await transientConnector.restore(accountID: transientAccountID)
            XCTFail("A transient refresh failure should fail for now")
        } catch let error as GoogleCalendarConnectorError {
            XCTAssertEqual(error.credentialFailureDisposition, .transient)
        }
        XCTAssertEqual(transientCredentials.load(accountID: transientAccountID), "refresh-token")
    }

    func testCredentialStoreLoadFailurePropagatesWithoutStartingGoogleRequest() async throws {
        let store = ThrowingGoogleCredentialStore(token: "refresh-token", failure: .load)
        let stub = GoogleAPIStub(scenario: .refreshFailure(statusCode: 500, body: ""))
        let connector = makeConnector(stub: stub, credentialSession: store)

        do {
            _ = try await connector.restore(accountID: "person@example.com")
            XCTFail("Protected credential read failure should be surfaced")
        } catch let error as TestCredentialStoreError {
            XCTAssertEqual(error, .load)
        }
        let requests = await stub.observedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testSuccessfulRemoteRevokeDoesNotReportSuccessWhenCredentialRemovalFails() async throws {
        let store = ThrowingGoogleCredentialStore(token: "refresh-token", failure: .remove)
        let stub = GoogleAPIStub(scenario: .revocation(statusCode: 200, body: ""))
        let connector = makeConnector(stub: stub, credentialSession: store)

        do {
            _ = try await connector.revokeAuthorization(accountID: "person@example.com")
            XCTFail("Revocation must not report success before protected credential removal succeeds")
        } catch let error as TestCredentialStoreError {
            XCTAssertEqual(error, .remove)
        }
        let retainedToken = await store.currentToken()
        XCTAssertEqual(retainedToken, "refresh-token")
    }

    private var testConfiguration: GoogleCalendarOAuthConfiguration {
        GoogleCalendarOAuthConfiguration(clientID: "client-id")
    }

    private func makeConnector(
        stub: GoogleAPIStub,
        credentialSession: any GoogleCredentialStoring
    ) -> GoogleCalendarConnector {
        GoogleCalendarConnector(
            configuration: testConfiguration,
            requestExecutor: { request in
                try await stub.execute(request)
            },
            credentialSession: credentialSession
        )
    }

    private func makeCredentialSession(accountID: String?) -> GoogleSessionCredentialStore {
        let suiteName = "GoogleCalendarConnectorHardeningTests.\(UUID().uuidString)"
        guard let legacyDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated test defaults")
        }
        defer { legacyDefaults.removePersistentDomain(forName: suiteName) }

        let credentialSession = GoogleSessionCredentialStore(legacyDefaults: legacyDefaults)
        if let accountID {
            credentialSession.save(refreshToken: "refresh-token", accountID: accountID)
        }
        return credentialSession
    }

    private func queryValues(in url: URL) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .compactMap { item in item.value.map { (item.name, $0) } }
        )
    }

    private func formValues(in body: String?) -> [String: String] {
        guard let body else { return [:] }
        var components = URLComponents()
        components.percentEncodedQuery = body
        return Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? [])
                .compactMap { item in item.value.map { (item.name, $0) } }
        )
    }
}

private enum TestCredentialStoreError: Error, Equatable {
    case load
    case save
    case remove
}

private actor ThrowingGoogleCredentialStore: GoogleCredentialStoring {
    private var token: String?
    private let failure: TestCredentialStoreError?

    init(token: String?, failure: TestCredentialStoreError? = nil) {
        self.token = token
        self.failure = failure
    }

    func save(refreshToken: String, accountID: String) throws {
        if failure == .save { throw TestCredentialStoreError.save }
        token = refreshToken
    }

    func load(accountID: String) throws -> String? {
        if failure == .load { throw TestCredentialStoreError.load }
        return token
    }

    func remove(accountID: String) throws {
        if failure == .remove { throw TestCredentialStoreError.remove }
        token = nil
    }

    func currentToken() -> String? {
        token
    }
}

private struct ObservedGoogleRequest: Sendable {
    let host: String?
    let path: String
    let query: String?
    let method: String?
    let body: String?
    let contentType: String?
    let minAccessRole: String?
}

private actor GoogleAPIStub {
    enum Scenario: Sendable {
        case calendarPages(accountID: String)
        case eventPages
        case missingPrimary
        case ambiguousPrimary
        case revocation(statusCode: Int, body: String)
        case refreshFailure(statusCode: Int, body: String)
        case newAuthorization(accountID: String, revocationStatusCode: Int)
    }

    enum StubError: Error {
        case unexpectedRequest(URL?)
    }

    private let scenario: Scenario
    private var pageTokens: [String?] = []
    private var requests: [ObservedGoogleRequest] = []

    init(scenario: Scenario) {
        self.scenario = scenario
    }

    func observedPageTokens() -> [String?] {
        pageTokens
    }

    func observedCalendarMinAccessRoles() -> [String?] {
        requests
            .filter { $0.path.hasSuffix("/calendarList") }
            .map(\.minAccessRole)
    }

    func observedHosts() -> [String] {
        requests.compactMap(\.host)
    }

    func observedRequests() -> [ObservedGoogleRequest] {
        requests
    }

    func execute(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw StubError.unexpectedRequest(nil)
        }

        requests.append(
            ObservedGoogleRequest(
                host: url.host,
                path: url.path,
                query: url.query,
                method: request.httpMethod,
                body: request.httpBody.flatMap { String(data: $0, encoding: .utf8) },
                contentType: request.value(forHTTPHeaderField: "Content-Type"),
                minAccessRole: URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "minAccessRole" })?
                    .value
            )
        )

        if url.host == "oauth2.googleapis.com" {
            switch scenario {
            case .revocation(let statusCode, let body) where url.path == "/revoke":
                return response(body, statusCode: statusCode, for: url)
            case .refreshFailure(let statusCode, let body) where url.path == "/token":
                return response(body, statusCode: statusCode, for: url)
            case .newAuthorization where url.path == "/token":
                return response(
                    #"{"access_token":"new-access-token","refresh_token":"new-refresh-token"}"#,
                    for: url
                )
            case .newAuthorization(_, let statusCode) where url.path == "/revoke":
                return response("", statusCode: statusCode, for: url)
            case .calendarPages, .eventPages, .missingPrimary, .ambiguousPrimary:
                guard url.path == "/token" else {
                    throw StubError.unexpectedRequest(url)
                }
                return response(#"{"access_token":"access-token"}"#, for: url)
            default:
                throw StubError.unexpectedRequest(url)
            }
        }

        switch scenario {
        case .calendarPages(let accountID):
            guard url.path.hasSuffix("/calendarList") else {
                throw StubError.unexpectedRequest(url)
            }
            let token = pageToken(in: url)
            pageTokens.append(token)
            if token == nil {
                return response(
                    #"{"items":[{"id":"calendar-1","summary":"   "}],"nextPageToken":"calendar-page-2"}"#,
                    for: url
                )
            }
            guard token == "calendar-page-2" else {
                throw StubError.unexpectedRequest(url)
            }
            return response(
                #"{"items":[{"id":"\#(accountID)","summary":"仕事 🗓️","primary":true}]}"#,
                for: url
            )

        case .eventPages:
            guard url.path.hasSuffix("/events") else {
                throw StubError.unexpectedRequest(url)
            }
            let token = pageToken(in: url)
            pageTokens.append(token)
            if token == nil {
                return response(
                    #"{"items":[{"id":"event-1","summary":" \n ","hangoutLink":"http://meet.google.com/unsafe","start":{"dateTime":"2027-01-15T10:00:00Z"},"end":{"dateTime":"2027-01-15T11:00:00Z"},"attendees":[{"self":true,"responseStatus":"accepted"}]}],"nextPageToken":"event-page-2"}"#,
                    for: url
                )
            }
            guard token == "event-page-2" else {
                throw StubError.unexpectedRequest(url)
            }
            return response(
                #"{"items":[{"id":"event-2","summary":"مرحبا 仕事 👋","hangoutLink":"https://zoom.us/j/123","start":{"dateTime":"2027-01-15T12:00:00Z"},"end":{"dateTime":"2027-01-15T13:00:00Z"},"attendees":[{"self":true,"responseStatus":"accepted"}]}]}"#,
                for: url
            )

        case .missingPrimary:
            guard url.path.hasSuffix("/calendarList") else {
                throw StubError.unexpectedRequest(url)
            }
            return response(
                #"{"items":[{"id":"calendar-1","summary":"Calendar"}]}"#,
                for: url
            )

        case .ambiguousPrimary:
            guard url.path.hasSuffix("/calendarList") else {
                throw StubError.unexpectedRequest(url)
            }
            return response(
                #"{"items":[{"id":"ambiguous-primary@example.com","primary":true},{"id":"other@example.com","primary":true}]}"#,
                for: url
            )

        case .newAuthorization(let accountID, _):
            guard url.path.hasSuffix("/calendarList") else {
                throw StubError.unexpectedRequest(url)
            }
            return response(
                #"{"items":[{"id":"\#(accountID)","summary":"Primary","primary":true}]}"#,
                for: url
            )

        case .revocation, .refreshFailure:
            throw StubError.unexpectedRequest(url)
        }
    }

    private func pageToken(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "pageToken" })?
            .value
    }

    private func response(
        _ body: String,
        statusCode: Int = 200,
        for url: URL
    ) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}
