import Foundation
import XCTest
@testable import CommitmentProtection

final class GoogleCalendarConnectorHardeningTests: XCTestCase {
    func testCalendarRestoreLoadsEveryPageAndNormalizesBlankNames() async throws {
        let accountID = "calendar-pages-\(UUID().uuidString)"
        let credentialSession = makeCredentialSession(accountID: accountID)

        let stub = GoogleAPIStub(scenario: .calendarPages(accountID: accountID))
        let connector = makeConnector(stub: stub, credentialSession: credentialSession)

        let restoredConnection = try await connector.restore(accountID: accountID)
        let connection = try XCTUnwrap(restoredConnection)

        XCTAssertEqual(connection.calendars.map(\.id), ["calendar-1", "calendar-2"])
        XCTAssertEqual(connection.calendars.map(\.name), ["calendar-1", "仕事 🗓️"])
        let observedPageTokens = await stub.observedPageTokens()
        XCTAssertEqual(observedPageTokens, [nil, "calendar-page-2"])
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
    }

    func testBlankProfileIdentityIsRejectedInsteadOfCreatingAnInvisibleAccount() async throws {
        let accountID = "blank-profile-\(UUID().uuidString)"
        let credentialSession = makeCredentialSession(accountID: accountID)

        let connector = makeConnector(
            stub: GoogleAPIStub(scenario: .blankProfile),
            credentialSession: credentialSession
        )

        do {
            _ = try await connector.restore(accountID: accountID)
            XCTFail("A blank account identity should be rejected")
        } catch let error as GoogleCalendarConnectorError {
            XCTAssertEqual(error, .malformedResponse)
        }
    }

    private var testConfiguration: GoogleCalendarOAuthConfiguration {
        GoogleCalendarOAuthConfiguration(clientID: "client-id")
    }

    private func makeConnector(
        stub: GoogleAPIStub,
        credentialSession: GoogleSessionCredentialStore
    ) -> GoogleCalendarConnector {
        GoogleCalendarConnector(
            configuration: testConfiguration,
            requestExecutor: { request in
                try await stub.execute(request)
            },
            credentialSession: credentialSession
        )
    }

    private func makeCredentialSession(accountID: String) -> GoogleSessionCredentialStore {
        let suiteName = "GoogleCalendarConnectorHardeningTests.\(UUID().uuidString)"
        guard let legacyDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated test defaults")
        }
        defer { legacyDefaults.removePersistentDomain(forName: suiteName) }

        let credentialSession = GoogleSessionCredentialStore(legacyDefaults: legacyDefaults)
        credentialSession.save(refreshToken: "refresh-token", accountID: accountID)
        return credentialSession
    }
}

private actor GoogleAPIStub {
    enum Scenario: Sendable {
        case calendarPages(accountID: String)
        case eventPages
        case blankProfile
    }

    enum StubError: Error {
        case unexpectedRequest(URL?)
    }

    private let scenario: Scenario
    private var pageTokens: [String?] = []

    init(scenario: Scenario) {
        self.scenario = scenario
    }

    func observedPageTokens() -> [String?] {
        pageTokens
    }

    func execute(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw StubError.unexpectedRequest(nil)
        }

        if url.host == "oauth2.googleapis.com" {
            return response(#"{"access_token":"access-token"}"#, for: url)
        }

        switch scenario {
        case .calendarPages(let accountID):
            if url.host == "openidconnect.googleapis.com" {
                return response(
                    #"{"sub":"\#(accountID)","email":"person@example.com","name":"Person"}"#,
                    for: url
                )
            }
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
                #"{"items":[{"id":"calendar-2","summary":"仕事 🗓️"}]}"#,
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

        case .blankProfile:
            if url.host == "openidconnect.googleapis.com" {
                return response(
                    #"{"sub":"   ","email":" \n ","name":"  "}"#,
                    for: url
                )
            }
            guard url.path.hasSuffix("/calendarList") else {
                throw StubError.unexpectedRequest(url)
            }
            return response(#"{"items":[]}"#, for: url)
        }
    }

    private func pageToken(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "pageToken" })?
            .value
    }

    private func response(_ body: String, for url: URL) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}
