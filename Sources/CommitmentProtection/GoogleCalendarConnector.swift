import AppKit
import CryptoKit
import Foundation
import Network

public struct GoogleCalendarOAuthConfiguration: Sendable {
    public let clientID: String
    public let clientSecret: String?

    public init(clientID: String, clientSecret: String? = nil) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

public enum GoogleCalendarConnectorError: Equatable, LocalizedError, Sendable {
    case missingClientID
    case unableToOpenBrowser
    case authorizationCancelled
    case authorizationFailed(String)
    case invalidCallback
    case tokenExchangeFailed(Int, String?)
    case missingRefreshToken
    case profileRequestFailed(Int)
    case calendarRequestFailed(Int, String?)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Google Calendar is not configured yet. Set GOOGLE_OAUTH_CLIENT_ID and try again."
        case .unableToOpenBrowser:
            return "The Google sign-in page could not be opened."
        case .authorizationCancelled:
            return "Google sign-in was cancelled."
        case .authorizationFailed:
            return "Google sign-in was not completed."
        case .invalidCallback:
            return "Google sign-in returned an invalid response."
        case .tokenExchangeFailed(_, let reason):
            if let reason, !reason.isEmpty {
                return "Google sign-in could not be completed (\(reason))."
            }
            return "Google sign-in could not be completed."
        case .missingRefreshToken:
            return "Google did not provide a refresh token. Try connecting again."
        case .profileRequestFailed:
            return "The Google account could not be loaded."
        case .calendarRequestFailed(_, let reason):
            if let reason, !reason.isEmpty {
                return "The Google calendars could not be loaded (\(reason))."
            }
            return "The Google calendars could not be loaded."
        case .malformedResponse:
            return "Google returned data the app could not read."
        }
    }
}

public struct GoogleCalendarConnector: GoogleCalendarConnecting, Sendable {
    private let configuration: GoogleCalendarOAuthConfiguration

    public init(configuration: GoogleCalendarOAuthConfiguration) {
        self.configuration = configuration
    }

    public func connect() async throws -> GoogleCalendarConnection {
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
        GoogleRefreshTokenStore.save(refreshToken: refreshToken, accountID: connection.account.id)
        return connection
    }

    public func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        guard let refreshToken = GoogleRefreshTokenStore.load(accountID: accountID) else {
            return nil
        }

        let token = try await refreshAccessToken(refreshToken: refreshToken)
        return try await loadConnection(accessToken: token.accessToken)
    }

    public func disconnect(accountID: String) throws {
        GoogleRefreshTokenStore.remove(accountID: accountID)
    }

    public func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        guard let refreshToken = GoogleRefreshTokenStore.load(accountID: accountID) else {
            throw GoogleCalendarConnectorError.missingRefreshToken
        }

        let token = try await refreshAccessToken(refreshToken: refreshToken)
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

        var calendarURL = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        calendarURL.queryItems = [
            URLQueryItem(name: "minAccessRole", value: "reader"),
            URLQueryItem(name: "maxResults", value: "250")
        ]
        let calendarRequest = authorizedRequest(url: calendarURL.url!, accessToken: accessToken)
        let calendarData = try await requestData(calendarRequest, failure: { statusCode, data in
            .calendarRequestFailed(statusCode, googleFailureReason(from: data))
        })
        let calendarList = try decode(CalendarListResponse.self, from: calendarData)

        guard let accountID = profile.sub, let email = profile.email else {
            throw GoogleCalendarConnectorError.malformedResponse
        }
        let account = GoogleAccount(
            id: accountID,
            email: email,
            displayName: profile.name ?? email
        )
        let calendars = calendarList.items.compactMap { item -> CalendarOption? in
            guard let id = item.id else { return nil }
            return CalendarOption(
                id: id,
                name: item.summaryOverride ?? item.summary ?? id,
                accountID: account.id
            )
        }
        return GoogleCalendarConnection(account: account, calendars: calendars)
    }

    private func loadEvents(
        accessToken: String,
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        var components = URLComponents(
            string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events"
        )!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: startDate)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: endDate)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "conferenceDataVersion", value: "1"),
            URLQueryItem(name: "maxResults", value: "2500")
        ]

        let request = authorizedRequest(url: components.url!, accessToken: accessToken)
        let data = try await requestData(request, failure: { statusCode, responseData in
            .calendarRequestFailed(statusCode, googleFailureReason(from: responseData))
        })
        return try decodeGoogleCalendarEvents(from: data, accountID: accountID, calendarID: calendarID)
    }
    private func authorizedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
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
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleCalendarConnectorError.malformedResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw failure(httpResponse.statusCode, data)
            }
            return data
        } catch let error as GoogleCalendarConnectorError {
            throw error
        } catch {
            throw GoogleCalendarConnectorError.malformedResponse
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
    let response = try JSONDecoder().decode(GoogleEventListResponse.self, from: data)
    return response.items.compactMap { item in
        guard let id = item.id, item.status != "cancelled" else { return nil }

        let isAllDay = item.start.date != nil
        let start = item.start.dateTime.flatMap(parseGoogleDate)
        let end = item.end.dateTime.flatMap(parseGoogleDate)
        let isAccepted = item.attendees?.contains {
            $0.isSelf == true && $0.responseStatus == "accepted"
        } == true || item.organizer?.isSelf == true

        return CalendarEvent(
            id: id,
            title: item.summary ?? "Untitled commitment",
            startDate: start,
            endDate: end,
            timeZoneIdentifier: item.start.timeZone,
            isAllDay: isAllDay,
            isAccepted: isAccepted,
            calendarID: calendarID,
            accountID: accountID,
            recognizedMeetingLink: recognizedMeetingLink(for: item)
        )
    }
}

private func recognizedMeetingLink(for item: GoogleEventItem) -> URL? {
    let candidates = [item.hangoutLink]
        .compactMap { $0.flatMap(URL.init(string:)) }
        + (item.conferenceData?.entryPoints ?? [])
            .compactMap { $0.uri.flatMap(URL.init(string:)) }

    return candidates.first(where: isRecognizedMeetingLink)
}

private func isRecognizedMeetingLink(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
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
    let items: [CalendarListItem]
}

private struct CalendarListItem: Decodable, Sendable {
    let id: String?
    let summary: String?
    let summaryOverride: String?
}

private struct GoogleEventListResponse: Decodable, Sendable {
    let items: [GoogleEventItem]
}

private struct GoogleEventItem: Decodable, Sendable {
    let id: String?
    let summary: String?
    let status: String?
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

enum GoogleRefreshTokenStore {
    private static let defaultsPrefix = "google.refreshToken."

    static func save(refreshToken: String, accountID: String) {
        UserDefaults.standard.set(refreshToken, forKey: key(accountID: accountID))
    }

    static func load(accountID: String) -> String? {
        UserDefaults.standard.string(forKey: key(accountID: accountID))
    }

    static func remove(accountID: String) {
        UserDefaults.standard.removeObject(forKey: key(accountID: accountID))
    }

    private static func key(accountID: String) -> String {
        "\(defaultsPrefix)\(accountID)"
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
        try await withCheckedThrowingContinuation { continuation in
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
