import AppKit
import CryptoKit
import Foundation
import Network

public struct GoogleCalendarOAuthConfiguration: Sendable {
    public let clientID: String
    public let clientSecret: String?

    public init(
        clientID: String,
        clientSecret: String? = nil
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

public enum GoogleCalendarConnectorError: Equatable, LocalizedError, Sendable {
    case missingClientID
    case unableToOpenBrowser
    case authorizationCancelled
    case authorizationTimedOut
    case authorizationFailed(String)
    case invalidCallback
    case tokenExchangeFailed(Int, String?)
    case missingRefreshToken
    case unexpectedAccount
    case profileRequestFailed(Int)
    case calendarRequestFailed(Int, String?)
    case networkUnavailable
    case requestTimedOut
    case requestFailed
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "This build is not configured to connect Google Calendar."
        case .unableToOpenBrowser:
            return "The Google sign-in page couldn’t be opened. Open your default browser, then try again."
        case .authorizationCancelled:
            return "Google sign-in was cancelled. No account was connected."
        case .authorizationTimedOut:
            return "Google sign-in timed out. Start again when you’re ready."
        case .authorizationFailed:
            return "Google sign-in couldn’t be completed. Try again."
        case .invalidCallback:
            return "Google sign-in couldn’t be verified. Close the browser window, then try again."
        case .tokenExchangeFailed:
            return "Google sign-in couldn’t be completed. Try again."
        case .missingRefreshToken:
            return "Google didn’t grant ongoing calendar access. Reconnect the account and approve read-only calendar access."
        case .unexpectedAccount:
            return "That is a different Google account. Choose the account shown in In Your Face to reconnect it."
        case .profileRequestFailed(let statusCode):
            return Self.googleAccessFailureDescription(statusCode: statusCode, subject: "account")
        case .calendarRequestFailed(let statusCode, _):
            return Self.googleAccessFailureDescription(statusCode: statusCode, subject: "calendars")
        case .networkUnavailable:
            return "Can’t reach Google Calendar. Check your internet connection, then try again."
        case .requestTimedOut:
            return "Google Calendar took too long to respond. Try again."
        case .requestFailed:
            return "Google Calendar couldn’t be reached. Try again."
        case .malformedResponse:
            return "Google Calendar sent a response In Your Face couldn’t read. Try again; if this continues, reconnect the account."
        }
    }

    private static func googleAccessFailureDescription(statusCode: Int, subject: String) -> String {
        switch statusCode {
        case 401:
            return "Google Calendar access expired. Reconnect this account."
        case 403:
            return "Google Calendar access was denied. Reconnect the account and approve read-only calendar access."
        case 429:
            return "Google Calendar is temporarily limiting requests. Try again in a few minutes."
        case 500...599:
            return "Google Calendar is temporarily unavailable. Try again later."
        default:
            return "The Google \(subject) couldn’t be loaded. Try again; if this continues, reconnect the account."
        }
    }
}

public struct GoogleCalendarConnector: GoogleCalendarConnecting, Sendable {
    typealias RequestExecutor = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let configuration: GoogleCalendarOAuthConfiguration
    private let requestExecutor: RequestExecutor
    private let credentialSession: GoogleSessionCredentialStore

    public init(configuration: GoogleCalendarOAuthConfiguration) {
        self.init(
            configuration: configuration,
            requestExecutor: { request in
                try await URLSession.shared.data(for: request)
            },
            credentialSession: GoogleSessionCredentialStore()
        )
    }

    init(
        configuration: GoogleCalendarOAuthConfiguration,
        requestExecutor: @escaping RequestExecutor,
        credentialSession: GoogleSessionCredentialStore = GoogleSessionCredentialStore()
    ) {
        self.configuration = configuration
        self.requestExecutor = requestExecutor
        self.credentialSession = credentialSession
    }

    public func connect() async throws -> GoogleCalendarConnection {
        try await connect(expectedAccountID: nil)
    }

    public func connect(expectedAccountID: String?) async throws -> GoogleCalendarConnection {
        guard !configuration.clientID.isEmpty else {
            throw GoogleCalendarConnectorError.missingClientID
        }

        let callbackServer = try OAuthCallbackServer()
        let redirectURI = try await callbackServer.start()
        let codeVerifier = makeCodeVerifier()
        let state = makeRandomString(byteCount: 32)
        let authorizationURL = try makeAuthorizationURL(
            redirectURI: redirectURI,
            codeVerifier: codeVerifier,
            state: state
        )

        let callbackTask = Task {
            try await callbackServer.waitForCallback()
        }
        defer {
            callbackTask.cancel()
            callbackServer.stop()
        }

        let opened = await MainActor.run {
            NSWorkspace.shared.open(authorizationURL)
        }
        guard opened else {
            throw GoogleCalendarConnectorError.unableToOpenBrowser
        }

        let callbackURL = try await callbackTask.value
        let callbackValues = try callbackValues(from: callbackURL)
        guard callbackValues["state"] == state else {
            throw GoogleCalendarConnectorError.invalidCallback
        }
        if let authorizationError = callbackValues["error"] {
            if authorizationError == "access_denied" {
                throw GoogleCalendarConnectorError.authorizationCancelled
            }
            throw GoogleCalendarConnectorError.authorizationFailed(authorizationError)
        }
        guard let code = callbackValues["code"] else {
            throw GoogleCalendarConnectorError.invalidCallback
        }

        let token = try await exchangeAuthorizationCode(
            code: code,
            redirectURI: redirectURI,
            codeVerifier: codeVerifier
        )
        guard let refreshToken = token.refreshToken else {
            throw GoogleCalendarConnectorError.missingRefreshToken
        }

        let connection = try await loadConnection(accessToken: token.accessToken)
        guard expectedAccountID == nil || connection.account.id == expectedAccountID else {
            throw GoogleCalendarConnectorError.unexpectedAccount
        }
        credentialSession.save(
            refreshToken: refreshToken,
            accountID: connection.account.id
        )
        return connection
    }

    public func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        guard let refreshToken = credentialSession.load(accountID: accountID) else {
            return nil
        }

        let token = try await refreshAccessToken(refreshToken: refreshToken)
        if let rotatedRefreshToken = token.refreshToken {
            credentialSession.save(refreshToken: rotatedRefreshToken, accountID: accountID)
        }
        return try await loadConnection(accessToken: token.accessToken)
    }

    public func disconnect(accountID: String) throws {
        credentialSession.remove(accountID: accountID)
    }

    public func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        guard let refreshToken = credentialSession.load(accountID: accountID) else {
            throw GoogleCalendarConnectorError.missingRefreshToken
        }

        let token = try await refreshAccessToken(refreshToken: refreshToken)
        if let rotatedRefreshToken = token.refreshToken {
            credentialSession.save(refreshToken: rotatedRefreshToken, accountID: accountID)
        }
        return try await loadEvents(
            accessToken: token.accessToken,
            accountID: accountID,
            calendarID: calendarID,
            from: startDate,
            to: endDate
        )
    }

    private func makeAuthorizationURL(
        redirectURI: String,
        codeVerifier: String,
        state: String
    ) throws -> URL {
        guard var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth") else {
            throw GoogleCalendarConnectorError.invalidCallback
        }

        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile https://www.googleapis.com/auth/calendar.readonly"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: codeChallenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components.url else {
            throw GoogleCalendarConnectorError.invalidCallback
        }
        return url
    }

    private func exchangeAuthorizationCode(
        code: String,
        redirectURI: String,
        codeVerifier: String
    ) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var parameters = [
            ("client_id", configuration.clientID),
            ("code", code),
            ("code_verifier", codeVerifier),
            ("grant_type", "authorization_code"),
            ("redirect_uri", redirectURI)
        ]
        appendClientSecret(to: &parameters)
        request.httpBody = formEncoded(parameters.map { URLQueryItem(name: $0.0, value: $0.1) })

        let data = try await requestData(request, failure: { statusCode, data in
            .tokenExchangeFailed(statusCode, googleFailureReason(from: data))
        })
        return try decode(TokenResponse.self, from: data)
    }

    private func refreshAccessToken(refreshToken: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var parameters = [
            ("client_id", configuration.clientID),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token")
        ]
        appendClientSecret(to: &parameters)
        request.httpBody = formEncoded(parameters.map { URLQueryItem(name: $0.0, value: $0.1) })

        let data = try await requestData(request, failure: { statusCode, data in
            .tokenExchangeFailed(statusCode, googleFailureReason(from: data))
        })
        return try decode(TokenResponse.self, from: data)
    }

    private func loadConnection(accessToken: String) async throws -> GoogleCalendarConnection {
        let profileRequest = authorizedRequest(
            url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!,
            accessToken: accessToken
        )
        let profileData = try await requestData(profileRequest, failure: { statusCode, _ in
            .profileRequestFailed(statusCode)
        })
        let profile = try decode(UserInfoResponse.self, from: profileData)

        let calendarItems = try await loadCalendarList(accessToken: accessToken)

        guard let rawAccountID = profile.sub, let rawEmail = profile.email else {
            throw GoogleCalendarConnectorError.malformedResponse
        }
        let accountID = rawAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountID.isEmpty, !email.isEmpty else {
            throw GoogleCalendarConnectorError.malformedResponse
        }
        let trimmedDisplayName = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = GoogleAccount(
            id: accountID,
            email: email,
            displayName: trimmedDisplayName.flatMap { $0.isEmpty ? nil : $0 } ?? email
        )
        let calendars = calendarItems.compactMap { item -> CalendarOption? in
            guard let id = item.id else { return nil }
            let preferredName = item.summaryOverride ?? item.summary
            let trimmedName = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CalendarOption(
                id: id,
                name: trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? id,
                accountID: account.id
            )
        }
        return GoogleCalendarConnection(account: account, calendars: calendars)
    }

    private func loadCalendarList(accessToken: String) async throws -> [CalendarListItem] {
        var items: [CalendarListItem] = []
        var pageToken: String?
        var seenPageTokens: Set<String> = []

        for _ in 0..<100 {
            var components = URLComponents(
                string: "https://www.googleapis.com/calendar/v3/users/me/calendarList"
            )!
            var queryItems = [
                URLQueryItem(name: "minAccessRole", value: "reader"),
                URLQueryItem(name: "maxResults", value: "250")
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems

            let request = authorizedRequest(url: components.url!, accessToken: accessToken)
            let data = try await requestData(request, failure: { statusCode, data in
                .calendarRequestFailed(statusCode, googleFailureReason(from: data))
            })
            let page = try decode(CalendarListResponse.self, from: data)
            items.append(contentsOf: page.items ?? [])

            guard let nextPageToken = page.nextPageToken?.nilIfBlank else {
                return items
            }
            guard seenPageTokens.insert(nextPageToken).inserted else {
                throw GoogleCalendarConnectorError.malformedResponse
            }
            pageToken = nextPageToken
        }

        throw GoogleCalendarConnectorError.malformedResponse
    }

    private func loadEvents(
        accessToken: String,
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var events: [CalendarEvent] = []
        var pageToken: String?
        var seenPageTokens: Set<String> = []

        for _ in 0..<100 {
            var components = URLComponents(
                string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events"
            )!
            var queryItems = [
                URLQueryItem(name: "timeMin", value: formatter.string(from: startDate)),
                URLQueryItem(name: "timeMax", value: formatter.string(from: endDate)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "conferenceDataVersion", value: "1"),
                URLQueryItem(name: "maxResults", value: "2500")
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems

            let request = authorizedRequest(url: components.url!, accessToken: accessToken)
            let data = try await requestData(request, failure: { statusCode, responseData in
                .calendarRequestFailed(statusCode, googleFailureReason(from: responseData))
            })
            let page = try decodeGoogleCalendarEventPage(
                from: data,
                accountID: accountID,
                calendarID: calendarID
            )
            events.append(contentsOf: page.events)

            guard let nextPageToken = page.nextPageToken?.nilIfBlank else {
                return events
            }
            guard seenPageTokens.insert(nextPageToken).inserted else {
                throw GoogleCalendarConnectorError.malformedResponse
            }
            pageToken = nextPageToken
        }

        throw GoogleCalendarConnectorError.malformedResponse
    }

    private func authorizedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func appendClientSecret(to parameters: inout [(String, String)]) {
        guard let clientSecret = configuration.clientSecret, !clientSecret.isEmpty else {
            return
        }
        parameters.append(("client_secret", clientSecret))
    }

    private func requestData(
        _ request: URLRequest,
        failure: (Int, Data) -> GoogleCalendarConnectorError
    ) async throws -> Data {
        do {
            let (data, response) = try await requestExecutor(request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleCalendarConnectorError.malformedResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw failure(httpResponse.statusCode, data)
            }
            return data
        } catch let error as GoogleCalendarConnectorError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw GoogleCalendarConnectorError.requestTimedOut
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed:
                throw GoogleCalendarConnectorError.networkUnavailable
            case .cancelled:
                throw CancellationError()
            default:
                throw GoogleCalendarConnectorError.requestFailed
            }
        } catch {
            throw GoogleCalendarConnectorError.requestFailed
        }
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GoogleCalendarConnectorError.malformedResponse
        }
    }
}

func decodeGoogleCalendarEvents(
    from data: Data,
    accountID: String,
    calendarID: String
) throws -> [CalendarEvent] {
    try decodeGoogleCalendarEventPage(
        from: data,
        accountID: accountID,
        calendarID: calendarID
    ).events
}

private struct DecodedGoogleCalendarEventPage {
    let events: [CalendarEvent]
    let nextPageToken: String?
}

private func decodeGoogleCalendarEventPage(
    from data: Data,
    accountID: String,
    calendarID: String
) throws -> DecodedGoogleCalendarEventPage {
    let response = try JSONDecoder().decode(GoogleEventListResponse.self, from: data)
    let events: [CalendarEvent] = (response.items ?? []).compactMap { item -> CalendarEvent? in
        guard let id = item.id, item.status != "cancelled" else { return nil }

        let isAllDay = item.start.date != nil
        let start = item.start.dateTime.flatMap(parseGoogleDate)
        let end = item.end.dateTime.flatMap(parseGoogleDate)
        let eventType = item.eventType.flatMap(CalendarEventType.init(rawValue:))
        let isAccepted = item.attendees?.contains {
            $0.isSelf == true && $0.responseStatus == "accepted"
        } == true || item.organizer?.isSelf == true
        let trimmedTitle = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines)

        return CalendarEvent(
            id: id,
            title: trimmedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled commitment",
            startDate: start,
            endDate: end,
            timeZoneIdentifier: item.start.timeZone,
            isAllDay: isAllDay,
            isAccepted: isAccepted,
            calendarID: calendarID,
            accountID: accountID,
            recognizedMeetingLinks: recognizedMeetingLinks(for: item),
            eventType: eventType
        )
    }
    return DecodedGoogleCalendarEventPage(
        events: events,
        nextPageToken: response.nextPageToken
    )
}

private func recognizedMeetingLinks(for item: GoogleEventItem) -> [RecognizedMeetingLink] {
    var links: [RecognizedMeetingLink] = []
    if let hangoutLink = item.hangoutLink.flatMap(URL.init(string:)),
       isRecognizedMeetingLink(hangoutLink) {
        links.append(RecognizedMeetingLink(url: hangoutLink, isPrimary: true))
    }

    for entryPoint in item.conferenceData?.entryPoints ?? [] {
        guard let url = entryPoint.uri.flatMap(URL.init(string:)),
              isRecognizedMeetingLink(url),
              !links.contains(where: { $0.url == url }) else {
            continue
        }
        links.append(RecognizedMeetingLink(url: url, isPrimary: false))
    }
    return links
}

private func isRecognizedMeetingLink(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https",
          url.user == nil,
          url.password == nil,
          let host = url.host?.lowercased() else {
        return false
    }
    return host == "meet.google.com" ||
        host == "zoom.us" || host.hasSuffix(".zoom.us") ||
        host == "teams.microsoft.com" || host.hasSuffix(".teams.microsoft.com") ||
        host == "webex.com" || host.hasSuffix(".webex.com")
}

private struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct OAuthFailureResponse: Decodable, Sendable {
    let error: String?
    let errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CalendarAPIErrorResponse: Decodable, Sendable {
    let error: CalendarAPIError
}

private struct CalendarAPIError: Decodable, Sendable {
    let code: Int?
    let message: String?
}

func googleFailureReason(from data: Data) -> String? {
    if let response = try? JSONDecoder().decode(OAuthFailureResponse.self, from: data) {
        switch (response.error, response.errorDescription) {
        case let (code?, description?):
            return "\(code): \(description)"
        case let (code?, nil):
            return code
        case let (nil, description?):
            return description
        case (nil, nil):
            return nil
        }
    }

    guard let response = try? JSONDecoder().decode(CalendarAPIErrorResponse.self, from: data) else {
        return nil
    }
    switch (response.error.code, response.error.message) {
    case let (code?, message?):
        return "\(code): \(message)"
    case let (code?, nil):
        return String(code)
    case let (nil, message?):
        return message
    case (nil, nil):
        return nil
    }
}

private struct UserInfoResponse: Decodable, Sendable {
    let sub: String?
    let email: String?
    let name: String?
}

private struct CalendarListResponse: Decodable, Sendable {
    let items: [CalendarListItem]?
    let nextPageToken: String?
}

private struct CalendarListItem: Decodable, Sendable {
    let id: String?
    let summary: String?
    let summaryOverride: String?
}

private struct GoogleEventListResponse: Decodable, Sendable {
    let items: [GoogleEventItem]?
    let nextPageToken: String?
}

private struct GoogleEventItem: Decodable, Sendable {
    let id: String?
    let summary: String?
    let status: String?
    let eventType: String?
    let hangoutLink: String?
    let start: GoogleEventDateTime
    let end: GoogleEventDateTime
    let attendees: [GoogleEventAttendee]?
    let organizer: GoogleEventAttendee?
    let conferenceData: GoogleConferenceData?
}

private struct GoogleConferenceData: Decodable, Sendable {
    let entryPoints: [GoogleConferenceEntryPoint]?
}

private struct GoogleConferenceEntryPoint: Decodable, Sendable {
    let entryPointType: String?
    let uri: String?
}

private struct GoogleEventDateTime: Decodable, Sendable {
    let date: String?
    let dateTime: String?
    let timeZone: String?

    private enum CodingKeys: String, CodingKey {
        case date
        case dateTime = "dateTime"
        case timeZone
    }
}

private struct GoogleEventAttendee: Decodable, Sendable {
    let isSelf: Bool?
    let responseStatus: String?

    private enum CodingKeys: String, CodingKey {
        case isSelf = "self"
        case responseStatus
    }
}

private func parseGoogleDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
        return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

final class GoogleSessionCredentialStore: @unchecked Sendable {
    private static let legacyDefaultsPrefix = "google.refreshToken."

    private let lock = NSLock()
    private var refreshTokensByAccountID: [String: String] = [:]

    init(legacyDefaults: UserDefaults = .standard) {
        Self.removeLegacyPersistedCredentials(from: legacyDefaults)
    }

    func save(refreshToken: String, accountID: String) {
        lock.withLock {
            refreshTokensByAccountID[accountID] = refreshToken
        }
    }

    func load(accountID: String) -> String? {
        lock.withLock {
            refreshTokensByAccountID[accountID]
        }
    }

    func remove(accountID: String) {
        lock.withLock {
            refreshTokensByAccountID[accountID] = nil
        }
    }

    private static func removeLegacyPersistedCredentials(from defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix(legacyDefaultsPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

private final class OAuthCallbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "in-your-face.google-oauth-callback")
    private var startContinuation: CheckedContinuation<String, any Error>?
    private var callbackContinuation: CheckedContinuation<URL, any Error>?

    init() throws {
        let loopback = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: 0)!
        )
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = loopback
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state)
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.start(queue: queue)
        }
    }

    func waitForCallback() async throws -> URL {
        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.queue.async { [weak self] in
                self?.failCallback(GoogleCalendarConnectorError.authorizationTimedOut)
            }
        }
        defer { timeoutTask.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
        }
    }

    func stop() {
        listener.cancel()
        callbackContinuation?.resume(throwing: GoogleCalendarConnectorError.authorizationCancelled)
        callbackContinuation = nil
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port else {
                failStart(GoogleCalendarConnectorError.invalidCallback)
                return
            }
            startContinuation?.resume(returning: "http://127.0.0.1:\(port)/oauth/callback")
            startContinuation = nil
        case .failed:
            failStart(GoogleCalendarConnectorError.invalidCallback)
        case .cancelled:
            failStart(GoogleCalendarConnectorError.authorizationCancelled)
        default:
            break
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            if let error {
                self?.failCallback(error)
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8) else {
                self?.failCallback(GoogleCalendarConnectorError.invalidCallback)
                return
            }
            self?.finishCallback(request: request, connection: connection)
        }
    }

    private func finishCallback(request: String, connection: NWConnection) {
        let callbackResult: Result<URL, Error>
        if let target = request.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).first?.split(separator: " ").dropFirst().first,
           let callbackURL = URL(string: "http://127.0.0.1\(target)") {
            callbackResult = .success(callbackURL)
        } else {
            callbackResult = .failure(GoogleCalendarConnectorError.invalidCallback)
        }

        let body = "You can close this window and return to In Your Face."
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })

        switch callbackResult {
        case .success(let callbackURL):
            callbackContinuation?.resume(returning: callbackURL)
        case .failure(let error):
            callbackContinuation?.resume(throwing: error)
        }
        callbackContinuation = nil
    }

    private func failStart(_ error: Error) {
        startContinuation?.resume(throwing: error)
        startContinuation = nil
    }

    private func failCallback(_ error: Error) {
        callbackContinuation?.resume(throwing: error)
        callbackContinuation = nil
    }
}

func callbackValues(from url: URL) throws -> [String: String] {
    guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
        throw GoogleCalendarConnectorError.invalidCallback
    }

    var values: [String: String] = [:]
    var names = Set<String>()
    for item in queryItems {
        guard names.insert(item.name).inserted else {
            throw GoogleCalendarConnectorError.invalidCallback
        }
        guard let value = item.value else { continue }
        values[item.name] = value
    }
    return values
}

private func formEncoded(_ items: [URLQueryItem]) -> Data? {
    var components = URLComponents()
    components.queryItems = items
    return components.percentEncodedQuery?.data(using: .utf8)
}

private func makeCodeVerifier() -> String {
    makeRandomString(byteCount: 64)
}

private func makeRandomString(byteCount: Int) -> String {
    var generator = SystemRandomNumberGenerator()
    let bytes = (0..<byteCount).map { _ in
        generator.next() as UInt8
    }
    return Data(bytes)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func codeChallenge(for verifier: String) -> String {
    let digest = SHA256.hash(data: Data(verifier.utf8))
    return Data(digest)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
