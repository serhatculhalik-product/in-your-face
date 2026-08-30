import Combine
import Foundation

public struct GoogleAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let email: String
    public let displayName: String

    public init(id: String, email: String, displayName: String) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }
}

private extension GoogleAccount {
    var protectionDisplayLabel: String {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty {
            return trimmedEmail
        }
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDisplayName.isEmpty ? "Google Account" : trimmedDisplayName
    }
}

public struct CalendarOption: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let accountID: String

    public init(id: String, name: String, accountID: String) {
        self.id = id
        self.name = name
        self.accountID = accountID
    }
}

public struct ProtectionProvenanceSource: Codable, Equatable, Hashable, Sendable {
    public let accountID: String
    public let accountEmail: String
    public let accountDisplayName: String
    public let calendarID: String?
    public let calendarName: String?

    public init(
        accountID: String,
        accountEmail: String,
        accountDisplayName: String,
        calendarID: String? = nil,
        calendarName: String? = nil
    ) {
        self.accountID = accountID
        self.accountEmail = accountEmail
        self.accountDisplayName = accountDisplayName
        self.calendarID = calendarID
        self.calendarName = calendarName
    }
}

public struct GoogleCalendarConnection: Codable, Equatable, Sendable {
    public let account: GoogleAccount
    public let calendars: [CalendarOption]

    public init(account: GoogleAccount, calendars: [CalendarOption]) {
        self.account = account
        self.calendars = calendars
    }
}

public struct CalendarEventOccurrenceID: Hashable, Sendable {
    public let eventID: String
    public let startDate: Date?
    public let calendarID: String
    public let accountID: String

    public init(
        eventID: String,
        startDate: Date?,
        calendarID: String,
        accountID: String
    ) {
        self.eventID = eventID
        self.startDate = startDate
        self.calendarID = calendarID
        self.accountID = accountID
    }
}

public enum CalendarEventType: String, Codable, Equatable, Sendable {
    case outOfOffice
}

public struct RecognizedMeetingLink: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let url: URL
    public let isPrimary: Bool

    public var id: String { url.absoluteString }

    public init(url: URL, isPrimary: Bool) {
        self.url = url
        self.isPrimary = isPrimary
    }
}

public struct CalendarEvent: Codable, Equatable, Identifiable, Sendable {
    public static let maximumMeetingDescriptionCharacterCount = 2_000
    private static let maximumMeetingDescriptionInputCharacterCount = 20_000

    public let id: String
    public let title: String
    public let meetingDescription: String?
    public let startDate: Date?
    public let endDate: Date?
    public let timeZoneIdentifier: String?
    public let isAllDay: Bool
    public let isAccepted: Bool
    public let calendarID: String
    public let accountID: String
    public let recognizedMeetingLinks: [RecognizedMeetingLink]
    public let eventType: CalendarEventType?

    public var occurrenceID: CalendarEventOccurrenceID {
        CalendarEventOccurrenceID(
            eventID: id,
            startDate: startDate,
            calendarID: calendarID,
            accountID: accountID
        )
    }

    public var recognizedMeetingLink: URL? {
        primaryRecognizedMeetingLink ?? recognizedMeetingLinks.first?.url
    }

    public var primaryRecognizedMeetingLink: URL? {
        recognizedMeetingLinks.first(where: \.isPrimary)?.url
    }

    public init(
        id: String,
        title: String,
        meetingDescription: String? = nil,
        startDate: Date?,
        endDate: Date?,
        timeZoneIdentifier: String?,
        isAllDay: Bool,
        isAccepted: Bool,
        calendarID: String,
        accountID: String,
        recognizedMeetingLink: URL? = nil,
        recognizedMeetingLinks: [RecognizedMeetingLink] = [],
        eventType: CalendarEventType? = nil
    ) {
        self.id = id
        self.title = title
        self.meetingDescription = Self.normalizedMeetingDescription(meetingDescription)
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isAllDay = isAllDay
        self.isAccepted = isAccepted
        self.calendarID = calendarID
        self.accountID = accountID
        var links = recognizedMeetingLinks
        if links.isEmpty, let recognizedMeetingLink {
            links = [RecognizedMeetingLink(url: recognizedMeetingLink, isPrimary: false)]
        } else if let recognizedMeetingLink,
                  !links.contains(where: { $0.url == recognizedMeetingLink }) {
            links.insert(RecognizedMeetingLink(url: recognizedMeetingLink, isPrimary: true), at: 0)
        }
        self.recognizedMeetingLinks = Self.deduplicatedMeetingLinks(links)
        self.eventType = eventType
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case meetingDescription
        case startDate
        case endDate
        case timeZoneIdentifier
        case isAllDay
        case isAccepted
        case calendarID
        case accountID
        case recognizedMeetingLink
        case recognizedMeetingLinks
        case eventType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        meetingDescription = Self.normalizedMeetingDescription(
            try container.decodeIfPresent(String.self, forKey: .meetingDescription)
        )
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        isAllDay = try container.decode(Bool.self, forKey: .isAllDay)
        isAccepted = try container.decode(Bool.self, forKey: .isAccepted)
        calendarID = try container.decode(String.self, forKey: .calendarID)
        accountID = try container.decode(String.self, forKey: .accountID)
        if let links = try container.decodeIfPresent([RecognizedMeetingLink].self, forKey: .recognizedMeetingLinks) {
            recognizedMeetingLinks = Self.deduplicatedMeetingLinks(links)
        } else if let legacyLink = try container.decodeIfPresent(URL.self, forKey: .recognizedMeetingLink) {
            recognizedMeetingLinks = [RecognizedMeetingLink(url: legacyLink, isPrimary: false)]
        } else {
            recognizedMeetingLinks = []
        }
        eventType = try container.decodeIfPresent(CalendarEventType.self, forKey: .eventType)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(meetingDescription, forKey: .meetingDescription)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encodeIfPresent(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encode(isAllDay, forKey: .isAllDay)
        try container.encode(isAccepted, forKey: .isAccepted)
        try container.encode(calendarID, forKey: .calendarID)
        try container.encode(accountID, forKey: .accountID)
        try container.encode(recognizedMeetingLinks, forKey: .recognizedMeetingLinks)
        try container.encodeIfPresent(eventType, forKey: .eventType)
    }

    private static func normalizedMeetingDescription(_ rawDescription: String?) -> String? {
        guard let rawDescription else { return nil }
        let boundedInput = String(rawDescription.prefix(maximumMeetingDescriptionInputCharacterCount))
        var plainText = ""
        var index = boundedInput.startIndex
        var suppressedElement: String?

        func appendSeparator() {
            guard !plainText.hasSuffix("\n") else { return }
            plainText.append("\n")
        }

        while index < boundedInput.endIndex {
            let character = boundedInput[index]
            if character == "<" {
                guard let closingBracket = boundedInput[index...].firstIndex(of: ">") else {
                    break
                }
                let tagContents = boundedInput[
                    boundedInput.index(after: index)..<closingBracket
                ]
                let tag = parsedHTMLTag(String(tagContents))
                if let suppressedElementName = suppressedElement {
                    if tag.isClosing && tag.name == suppressedElementName {
                        suppressedElement = nil
                    }
                } else if !tag.isClosing && (tag.name == "script" || tag.name == "style") {
                    suppressedElement = tag.name
                } else if Self.blockHTMLTags.contains(tag.name) {
                    appendSeparator()
                }
                index = boundedInput.index(after: closingBracket)
                continue
            }

            if suppressedElement != nil {
                index = boundedInput.index(after: index)
                continue
            }

            if character == "&",
               let semicolon = boundedInput[index...].prefix(16).firstIndex(of: ";") {
                let entityStart = boundedInput.index(after: index)
                let entity = String(boundedInput[entityStart..<semicolon])
                if let decoded = decodedHTMLEntity(entity) {
                    plainText.append(decoded)
                    index = boundedInput.index(after: semicolon)
                    continue
                }
            }

            plainText.append(character)
            index = boundedInput.index(after: index)
        }

        let sanitizedScalars = plainText.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) || scalar == "\n" || scalar == "\r" || scalar == "\t"
        }
        let normalizedLines = String(String.UnicodeScalarView(sanitizedScalars))
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                let normalizedLine = line
                    .split(whereSeparator: { $0.isWhitespace })
                    .joined(separator: " ")
                return normalizedLine.isEmpty ? nil : normalizedLine
            }
        let normalized = normalizedLines.joined(separator: "\n")
        guard !normalized.isEmpty else { return nil }
        guard normalized.count > maximumMeetingDescriptionCharacterCount else {
            return normalized
        }
        return String(normalized.prefix(maximumMeetingDescriptionCharacterCount - 1)) + "…"
    }

    private static let blockHTMLTags: Set<String> = [
        "blockquote", "br", "div", "h1", "h2", "h3", "h4", "h5", "h6",
        "hr", "li", "p", "pre", "tr"
    ]

    private static func parsedHTMLTag(_ contents: String) -> (name: String, isClosing: Bool) {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        let isClosing = trimmed.hasPrefix("/")
        let nameStart = isClosing ? trimmed.dropFirst() : trimmed[...]
        let name = nameStart
            .drop(while: { $0.isWhitespace })
            .prefix(while: { $0.isLetter || $0.isNumber })
            .lowercased()
        return (name, isClosing)
    }

    private static func decodedHTMLEntity(_ entity: String) -> String? {
        switch entity.lowercased() {
        case "amp": return "&"
        case "apos": return "'"
        case "gt": return ">"
        case "lt": return "<"
        case "nbsp": return " "
        case "quot": return "\""
        default:
            let scalarValue: UInt32?
            if entity.lowercased().hasPrefix("#x") {
                scalarValue = UInt32(entity.dropFirst(2), radix: 16)
            } else if entity.hasPrefix("#") {
                scalarValue = UInt32(entity.dropFirst(), radix: 10)
            } else {
                scalarValue = nil
            }
            guard let scalarValue,
                  let scalar = UnicodeScalar(scalarValue),
                  !CharacterSet.controlCharacters.contains(scalar) else {
                return nil
            }
            return String(scalar)
        }
    }

    fileprivate static func normalizedMeetingLinkKey(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.string ?? url.absoluteString
    }

    fileprivate static func deduplicatedMeetingLinks(
        _ links: [RecognizedMeetingLink]
    ) -> [RecognizedMeetingLink] {
        var deduplicated: [RecognizedMeetingLink] = []
        for link in links {
            let linkKey = normalizedMeetingLinkKey(link.url)
            guard let existingIndex = deduplicated.firstIndex(where: {
                normalizedMeetingLinkKey($0.url) == linkKey
            }) else {
                deduplicated.append(link)
                continue
            }
            if link.isPrimary && !deduplicated[existingIndex].isPrimary {
                deduplicated[existingIndex] = link
            }
        }
        return deduplicated
    }

    public var hasProtectionWindow: Bool {
        eventType != .outOfOffice && !isAllDay && startDate != nil && endDate != nil
    }

    public var isEligibleForProtection: Bool {
        isAccepted && hasProtectionWindow
    }
}

public struct CommitmentConflict: Equatable, Identifiable, Sendable {
    public let id: String
    public let primaryCommitment: CalendarEvent?
    public let commitments: [CalendarEvent]

    public var requiresPrimarySelection: Bool {
        primaryCommitment == nil
    }

    public init(
        id: String,
        primaryCommitment: CalendarEvent?,
        commitments: [CalendarEvent]
    ) {
        self.id = id
        self.primaryCommitment = primaryCommitment
        self.commitments = commitments
    }
}

public protocol GoogleCalendarConnecting: Sendable {
    func connect() async throws -> GoogleCalendarConnection
    func connect(expectedAccountID: String?) async throws -> GoogleCalendarConnection
    func restore(accountID: String) async throws -> GoogleCalendarConnection?
    func disconnect(accountID: String) throws
    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent]
}

public extension GoogleCalendarConnecting {
    func connect(expectedAccountID: String?) async throws -> GoogleCalendarConnection {
        let connection = try await connect()
        guard expectedAccountID == nil || connection.account.id == expectedAccountID else {
            throw GoogleCalendarConnectorError.unexpectedAccount
        }
        return connection
    }
}

@MainActor
public protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func enable() throws
    func disable() throws
}

public extension LaunchAtLoginControlling {
    func disable() throws {}
}

public enum ProtectionStatus: Equatable, Sendable {
    case noCoverage
    case active
    case unavailable
}

public enum PauseDuration: Equatable, Sendable {
    case oneHour
    case endOfDay
    case custom(Date)
}

public enum AppManagedDataResetFlowError: Error, Equatable, LocalizedError, Sendable {
    case accountPositionOutOfBounds

    public var errorDescription: String? {
        switch self {
        case .accountPositionOutOfBounds:
            return "The Saved Account reset step no longer matches protected storage."
        }
    }
}

public enum ProtectionActivityActor: String, Codable, Equatable, Sendable {
    case user
    case system
}

public enum ProtectionActivityKind: String, Codable, Equatable, Sendable {
    case accountConnected
    case accountDisconnected
    case accountConnectionFailed
    case accountDisconnectFailed
    case configurationChanged
    case blockingModeChanged
    // Legacy decode-only: older Protection Activity records may contain these values.
    case testAlertShown
    case testAlertDismissed
    case earlyReminderShown
    case earlyReminderCleared
    case snoozed
    case strongAlertShown
    case strongAlertRepeated
    case strongAlertClosed
    case joined
    case handled
    case dismissed
    case protectionRestored
    case conflictPrimarySelected
    case pauseStarted
    case pauseEnded
    // Kept for decoding activity logs written before the passive missed status was removed.
    case missedCommitment
    case missedCommitmentAcknowledged
    case coverageUnavailable
    case coverageRestored

    fileprivate var activityTitle: String {
        switch self {
        case .joined:
            return "Meeting link opened"
        case .handled:
            return "Commitment handled"
        case .dismissed:
            return "Reminders stopped"
        case .strongAlertShown:
            return "Strong Alert shown"
        case .strongAlertRepeated:
            return "Strong Alert repeated"
        case .conflictPrimarySelected:
            return "Conflict primary selected"
        default:
            return rawValue
        }
    }
}

public struct ProtectionActivity: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let occurredAt: Date
    public let actor: ProtectionActivityActor
    public let kind: ProtectionActivityKind
    public let title: String
    public let detail: String
    public let commitmentTitle: String?
    public let commitmentID: String?
    public let commitmentStartDate: Date?
    public let accountID: String?
    public let accountEmail: String?
    public let calendarID: String?
    public let calendarName: String?
    public let sourceAccountIDs: [String]?
    public let provenanceSources: [ProtectionProvenanceSource]?

    public var resolvedProvenanceSources: [ProtectionProvenanceSource] {
        if let provenanceSources {
            return provenanceSources
        }
        guard let accountID else {
            return []
        }
        return [
            ProtectionProvenanceSource(
                accountID: accountID,
                accountEmail: accountEmail ?? "",
                accountDisplayName: "",
                calendarID: calendarID,
                calendarName: calendarName
            )
        ]
    }

    public init(
        id: UUID = UUID(),
        occurredAt: Date,
        actor: ProtectionActivityActor,
        kind: ProtectionActivityKind,
        title: String,
        detail: String,
        commitmentTitle: String? = nil,
        commitmentID: String? = nil,
        commitmentStartDate: Date? = nil,
        accountID: String? = nil,
        accountEmail: String? = nil,
        calendarID: String? = nil,
        calendarName: String? = nil,
        sourceAccountIDs: [String]? = nil,
        provenanceSources: [ProtectionProvenanceSource]? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.actor = actor
        self.kind = kind
        self.title = title
        self.detail = detail
        self.commitmentTitle = commitmentTitle
        self.commitmentID = commitmentID
        self.commitmentStartDate = commitmentStartDate
        self.accountID = accountID
        self.accountEmail = accountEmail
        self.calendarID = calendarID
        self.calendarName = calendarName
        let normalizedSourceAccountIDs = Set(
            (sourceAccountIDs ?? []) + (accountID.map { [$0] } ?? [])
        ).filter { !$0.isEmpty }.sorted()
        self.sourceAccountIDs = normalizedSourceAccountIDs.isEmpty
            ? nil
            : normalizedSourceAccountIDs
        self.provenanceSources = provenanceSources
    }
}

private extension ProtectionActivity {
    func withCalendarContext(calendarID: String, calendarName: String?) -> ProtectionActivity {
        ProtectionActivity(
            id: id,
            occurredAt: occurredAt,
            actor: actor,
            kind: kind,
            title: title,
            detail: detail,
            commitmentTitle: commitmentTitle,
            commitmentID: commitmentID,
            commitmentStartDate: commitmentStartDate,
            accountID: accountID,
            accountEmail: accountEmail,
            calendarID: calendarID,
            calendarName: calendarName,
            sourceAccountIDs: sourceAccountIDs,
            provenanceSources: provenanceSources
        )
    }

    func containsProtectedData(forAccountID accountID: String) -> Bool {
        protectedSourceAccountIDs.contains(accountID)
    }

    var protectedSourceAccountIDs: Set<String> {
        Set(
            (provenanceSources?.map(\.accountID) ?? []) +
                (sourceAccountIDs ?? []) +
                (accountID.map { [$0] } ?? [])
        )
    }
}

public enum ConnectionState: Equatable, Sendable {
    case notConnected
    case connecting
    case connected
    case reconnectRequired
    case failed(String)
}

public enum CoverageHealth: Equatable, Sendable {
    case noCoverage
    case checking
    case fresh
    case stale
    case reconnectRequired
    case unavailable(String)
}

public struct AccountCoverage: Equatable, Identifiable, Sendable {
    public let account: GoogleAccount
    public let calendars: [CalendarOption]
    public let selectedCalendarIDs: Set<String>
    public let confirmedCalendarIDs: Set<String>
    public let isProtectionConfirmed: Bool
    public let connectionState: ConnectionState
    public let health: CoverageHealth
    public let lastSuccessfulRefreshAt: Date?

    public var id: String { account.id }

    public init(
        account: GoogleAccount,
        calendars: [CalendarOption],
        selectedCalendarIDs: Set<String>,
        confirmedCalendarIDs: Set<String>? = nil,
        isProtectionConfirmed: Bool = false,
        connectionState: ConnectionState,
        health: CoverageHealth,
        lastSuccessfulRefreshAt: Date?
    ) {
        self.account = account
        self.calendars = calendars
        self.selectedCalendarIDs = selectedCalendarIDs
        self.confirmedCalendarIDs = confirmedCalendarIDs ?? (
            isProtectionConfirmed ? selectedCalendarIDs : []
        )
        self.isProtectionConfirmed = isProtectionConfirmed
        self.connectionState = connectionState
        self.health = health
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
    }
}

public enum CommitmentProtectionDecision: String, Codable, Equatable, Sendable {
    case handled
    case dismissed
    case joined

    public var isRestorable: Bool {
        self == .handled || self == .dismissed
    }
}

public struct EarlyReminderBlockingMode: Equatable, Sendable {
    public private(set) var shouldAttemptBlocking = false

    public init() {}

    public mutating func enableBlocking() {
        shouldAttemptBlocking = true
    }

    public mutating func disableBlocking() {
        shouldAttemptBlocking = false
    }
}

/// Process-local storage used by unit tests and previews. Production supplies an
/// `EncryptedGoogleVault`; this fallback deliberately never writes Google data to
/// UserDefaults or any other plaintext persistence.
@MainActor
private final class VolatileGoogleDataStore {
    private var records: [String: [EncryptedGoogleVaultRecordKind: Data]] = [:]

    var accountIDs: [String] {
        records.keys.sorted()
    }

    func load(_ kind: EncryptedGoogleVaultRecordKind, accountID: String) -> Data? {
        records[accountID]?[kind]
    }

    func store(_ data: Data, kind: EncryptedGoogleVaultRecordKind, accountID: String) {
        records[accountID, default: [:]][kind] = data
    }

    func remove(_ kind: EncryptedGoogleVaultRecordKind, accountID: String) {
        records[accountID]?[kind] = nil
        if records[accountID]?.isEmpty == true {
            records[accountID] = nil
        }
    }

    func removeAccount(_ accountID: String) {
        records[accountID] = nil
    }

    func reset() {
        records.removeAll()
    }
}

@MainActor
private enum VolatileGoogleDataStoreRegistry {
    private static let identifierKey = "commitment-protection.volatile-test-store-id"
    private static var stores: [String: VolatileGoogleDataStore] = [:]

    static func store(for stateStore: UserDefaults) -> VolatileGoogleDataStore {
        let identifier: String
        if let existingIdentifier = stateStore.string(forKey: identifierKey) {
            identifier = existingIdentifier
        } else {
            identifier = UUID().uuidString
            stateStore.set(identifier, forKey: identifierKey)
        }
        if let existing = stores[identifier] {
            return existing
        }
        let store = VolatileGoogleDataStore()
        stores[identifier] = store
        return store
    }
}

public enum CommitmentProtectionStartupMode: Equatable, Sendable {
    case normal
    case activeResetRecovery
    case committedResetRecovery

    fileprivate var isResetRecovery: Bool {
        self != .normal
    }
}

public struct RecoveredEncryptedGoogleStorage: Sendable {
    public let vault: EncryptedGoogleVault
    public let connector: any GoogleCalendarConnecting

    public init(
        vault: EncryptedGoogleVault,
        connector: any GoogleCalendarConnecting
    ) {
        self.vault = vault
        self.connector = connector
    }
}

@MainActor
public final class CommitmentProtectionFlow: ObservableObject {
    @Published public private(set) var connectedAccount: GoogleAccount?
    @Published public private(set) var availableCalendars: [CalendarOption] = []
    @Published public private(set) var selectedCalendarIDs: Set<String> = []
    @Published public private(set) var connectionState: ConnectionState = .notConnected
    @Published public private(set) var isConnectingAccount = false
    @Published public private(set) var connectingAccountID: String?
    @Published public private(set) var accountConnectionError: String?
    @Published public private(set) var accountDisconnectionError: String?
    @Published public private(set) var failedAccountDisconnectionID: String?
    @Published public private(set) var terminatingAccountID: String?
    @Published public private(set) var googleAccessReviewNotice: String?
    @Published public private(set) var encryptedStorageError: String?
    @Published public private(set) var requiresEncryptedStorageReset = false
    @Published public private(set) var isRestoringConnection = false
    @Published public private(set) var isProtectionConfirmed = false
    @Published public private(set) var isBlockingAvailable = true
    @Published public private(set) var isStrongAlertPresented = false
    @Published public private(set) var isLaunchAtLoginEnabled = false
    @Published public private(set) var launchAtLoginError: String?
    @Published public private(set) var upcomingCommitment: CalendarEvent?
    @Published public private(set) var earlyReminderCommitment: CalendarEvent?
    @Published public private(set) var strongAlertCommitment: CalendarEvent?
    @Published public private(set) var pauseUntil: Date?
    @Published public private(set) var activityLog: [ProtectionActivity] = []
    @Published public private(set) var currentCommitmentDecision: CommitmentProtectionDecision?
    @Published public private(set) var decisionCommitment: CalendarEvent?
    @Published public private(set) var lastActionMessage: String?
    @Published public private(set) var isRefreshingCoverage = false
    @Published public private(set) var isEarlyReminderEnabled: Bool
    @Published public private(set) var isOutOfOfficeProtectionEnabled: Bool
    @Published public private(set) var isBlockingModeEnabled: Bool
    @Published public private(set) var earlyReminderLeadTimeMinutes: Int
    @Published public private(set) var strongAlertRepeatIntervalMinutes: Int
    @Published public private(set) var accountCoverages: [AccountCoverage] = []
    @Published public private(set) var isEarlyReminderUnverified = false
    @Published public private(set) var isStrongAlertUnverified = false
    @Published public private(set) var upcomingConflict: CommitmentConflict?
    @Published public private(set) var earlyReminderConflict: CommitmentConflict?
    @Published public private(set) var strongAlertConflict: CommitmentConflict?
    @Published public private(set) var isAppManagedDataResetInProgress = false
    private var appManagedDataResetMutationLockCount = 0

    private var calendarConnector: any GoogleCalendarConnecting
    private let launchAtLogin: any LaunchAtLoginControlling
    private let stateStore: UserDefaults
    private let legacyConfigurationData: Data?
    private var encryptedGoogleVault: EncryptedGoogleVault?
    private let recoverEncryptedGoogleStorage: (@Sendable () throws -> RecoveredEncryptedGoogleStorage)?
    private let volatileGoogleDataStore: VolatileGoogleDataStore
    private let now: () -> Date
    private static let stateKey = "commitment-protection.configuration"
    private static let activityLogKey = "commitment-protection.activity-log"
    private static let legacyGoogleRefreshTokenPrefix = "google.refreshToken."
    private static let pauseUntilKey = "commitment-protection.pause-until"
    private static let earlyReminderEnabledKey = "commitment-protection.early-reminder-enabled"
    private static let outOfOfficeProtectionEnabledKey =
        "commitment-protection.out-of-office-protection-enabled"
    private static let blockingModeEnabledKey = "commitment-protection.blocking-mode-enabled"
    private static let earlyReminderLeadTimeKey = "commitment-protection.early-reminder-lead-time"
    private static let strongAlertRepeatIntervalKey = "commitment-protection.strong-alert-repeat-interval"
    private static let freshEventsSchemaVersion = 1
    private static let coverageFreshnessInterval: TimeInterval = 15 * 60
    private static let eventRetentionInterval: TimeInterval = 24 * 60 * 60
    private static let minimumEarlyReminderPresentationLeadTime: TimeInterval = 60
    private static let maximumPersistedEventsPerAccount = 2_000
    private static let maximumEventSnapshotBytes = 2 * 1_024 * 1_024
    private static let maximumActivitiesAcrossAccounts = 1_000
    private static let maximumActivityBytesAcrossAccounts = 1_024 * 1_024
    private struct AccountRecord {
        var connection: GoogleCalendarConnection
        var selectedCalendarIDs: Set<String>
        var confirmedCalendarIDs: Set<String>
        var connectionState: ConnectionState
        var lastSuccessfulRefreshAt: Date?
        var lastFreshEvents: [CalendarEvent]

        var selectedCalendars: [CalendarOption] {
            connection.calendars.filter { selectedCalendarIDs.contains($0.id) }
        }

        var protectedCalendars: [CalendarOption] {
            connection.calendars.filter {
                selectedCalendarIDs.contains($0.id) && confirmedCalendarIDs.contains($0.id)
            }
        }

        var hasConfiguredProtection: Bool {
            !protectedCalendars.isEmpty
        }

        var isProtectionConfirmed: Bool {
            !selectedCalendarIDs.isEmpty && selectedCalendarIDs == confirmedCalendarIDs
        }

        var requiresProtectionConfirmation: Bool {
            !selectedCalendarIDs.isEmpty && selectedCalendarIDs != confirmedCalendarIDs
        }
    }

    private struct AccountRefreshRequest: Sendable {
        let accountID: String
        let calendars: [CalendarOption]
    }

    private enum AccountRefreshResult: Sendable {
        case success(accountID: String, events: [CalendarEvent])
        case failure(
            accountID: String,
            message: String,
            credentialDisposition: GoogleCredentialFailureDisposition?
        )

        var accountID: String {
            switch self {
            case .success(let accountID, _), .failure(let accountID, _, _):
                return accountID
            }
        }
    }

    private var accountRecords: [String: AccountRecord] = [:]
    private var activeAccountID: String?
    private var unverifiedAccountIDs: Set<String> = []
    private var lastEvaluatedCoverageDate: Date?
    private var upcomingMergedCommitment: MergedCommitment?
    private var earlyReminderMergedCommitment: MergedCommitment?
    private var strongAlertMergedCommitment: MergedCommitment?
    private var currentMergedCommitments: [MergedCommitment] = []
    private var upcomingConflictMergedCommitments: [MergedCommitment] = []
    private var earlyReminderConflictMergedCommitments: [MergedCommitment] = []
    private var strongAlertConflictMergedCommitments: [MergedCommitment] = []
    private var selectedPrimaryOccurrences: Set<OccurrenceIdentity> = []
    private var localDecisions: [OccurrenceIdentity: CommitmentProtectionDecision] = [:]
    private struct OccurrenceIdentity: Hashable, Sendable {
        let eventID: String
        let startDate: Date?
        let calendarID: String?
        let accountID: String?

        init(_ commitment: CalendarEvent) {
            eventID = commitment.id
            startDate = commitment.startDate
            calendarID = commitment.calendarID
            accountID = commitment.accountID
        }

        init(eventID: String, startDate: Date?, calendarID: String? = nil, accountID: String? = nil) {
            self.eventID = eventID
            self.startDate = startDate
            self.calendarID = calendarID
            self.accountID = accountID
        }

        func matches(_ commitment: CalendarEvent) -> Bool {
            eventID == commitment.id &&
                startDate == commitment.startDate &&
                (calendarID == nil || calendarID == commitment.calendarID) &&
                (accountID == nil || accountID == commitment.accountID)
        }

        func matches(_ other: OccurrenceIdentity) -> Bool {
            eventID == other.eventID &&
                startDate == other.startDate &&
                (calendarID == nil || other.calendarID == nil || calendarID == other.calendarID) &&
                (accountID == nil || other.accountID == nil || accountID == other.accountID)
        }
    }

    private struct MergedCommitment: Sendable {
        let representations: [CalendarEvent]
        let displayEvent: CalendarEvent
        let endDate: Date

        var meetingLinks: [RecognizedMeetingLink] {
            CalendarEvent.deduplicatedMeetingLinks(
                representations.flatMap(\.recognizedMeetingLinks)
            )
        }

        var primaryMeetingLink: URL? {
            let primaryLinks = meetingLinks.filter(\.isPrimary)
            guard Set(primaryLinks.map { CalendarEvent.normalizedMeetingLinkKey($0.url) }).count <= 1 else {
                return nil
            }
            return primaryLinks.first?.url
        }

        var sharedMeetingLinkKeys: Set<String> {
            guard let firstRepresentation = representations.first else { return [] }
            let firstKeys = Set(firstRepresentation.recognizedMeetingLinks.map {
                CalendarEvent.normalizedMeetingLinkKey($0.url)
            })
            return representations.dropFirst().reduce(firstKeys) { sharedKeys, representation in
                sharedKeys.intersection(
                    representation.recognizedMeetingLinks.map {
                        CalendarEvent.normalizedMeetingLinkKey($0.url)
                    }
                )
            }
        }

        var occurrences: Set<OccurrenceIdentity> {
            Set(representations.map(OccurrenceIdentity.init))
        }

        func contains(_ commitment: CalendarEvent) -> Bool {
            occurrences.contains(OccurrenceIdentity(commitment))
        }

        func sharesOccurrence(with other: MergedCommitment) -> Bool {
            !occurrences.isDisjoint(with: other.occurrences)
        }
    }

    private struct CalendarSelectionIdentity: Hashable, Sendable {
        let calendarID: String
        let accountID: String
    }

    private var snoozedOccurrence: OccurrenceIdentity?
    private var snoozedUntil: Date?
    private var snoozedOccurrences: Set<OccurrenceIdentity> = []
    private var observedUnacceptedOccurrences: Set<OccurrenceIdentity> = []
    private var suppressedPostStartAcceptanceOccurrences: Set<OccurrenceIdentity> = []
    private var suppressedUntrackedPastOccurrences: Set<OccurrenceIdentity> = []
    private var decisionOccurrence: OccurrenceIdentity?
    private var decisionOccurrences: Set<OccurrenceIdentity> = []
    private var lastActionOccurrence: OccurrenceIdentity?
    private var meetingLinkOpenFailure: (occurrence: OccurrenceIdentity, message: String)?
    private var strongAlertOccurrences: Set<OccurrenceIdentity> = []
    private var clearedEarlyReminderOccurrences: Set<OccurrenceIdentity> = []
    private var strongAlertNextPresentationDate: Date?
    private var newlySelectedCalendars: Set<CalendarSelectionIdentity> = []
    private var accountsRequiringUntrackedPastSuppression: Set<String> = []
    private var monitoringTask: Task<Void, Never>?
    private let refreshCoordinator = RefreshCoordinator()
    internal var onRefreshRequestEnqueued: (@MainActor (RefreshCoordinator.Intent, Date) -> Void)?
    private var refreshGeneration = 0

    private struct SavedOccurrence: Codable {
        let eventID: String
        let startDate: Date?
        let calendarID: String?
        let accountID: String?

        init(_ occurrence: OccurrenceIdentity) {
            eventID = occurrence.eventID
            startDate = occurrence.startDate
            calendarID = occurrence.calendarID
            accountID = occurrence.accountID
        }

        var identity: OccurrenceIdentity {
            OccurrenceIdentity(
                eventID: eventID,
                startDate: startDate,
                calendarID: calendarID,
                accountID: accountID
            )
        }
    }

    private struct SavedDecision: Codable {
        let occurrence: SavedOccurrence
        let decision: CommitmentProtectionDecision
    }

    private struct SavedAccountConfiguration: Codable {
        let account: GoogleAccount
        let calendars: [CalendarOption]
        let selectedCalendarIDs: [String]
        let isProtectionConfirmed: Bool
        let confirmedCalendarIDs: [String]?
        let lastSuccessfulRefreshAt: Date?
        let lastFreshEvents: [CalendarEvent]
        let lastFreshEventsSchemaVersion: Int?

        var resolvedConfirmedCalendarIDs: Set<String> {
            Set(
                confirmedCalendarIDs ??
                    (isProtectionConfirmed ? selectedCalendarIDs : [])
            )
        }
    }

    private struct SavedEventSnapshot: Codable, Sendable {
        let schemaVersion: Int
        let capturedAt: Date
        let lastSuccessfulRefreshAt: Date
        let events: [CalendarEvent]
    }

    private struct SavedConfiguration: Codable {
        let accounts: [SavedAccountConfiguration]
        let decisionOccurrence: SavedOccurrence?
        let decisionOccurrences: [SavedOccurrence]
        let decisions: [SavedDecision]
        let currentCommitmentDecision: CommitmentProtectionDecision?
        let selectedPrimaryOccurrences: [SavedOccurrence]
        let snoozedOccurrence: SavedOccurrence?
        let snoozedOccurrences: [SavedOccurrence]
        let snoozedUntil: Date?
        let pauseUntil: Date?
        let observedUnacceptedOccurrences: [SavedOccurrence]
        let suppressedPostStartAcceptanceOccurrences: [SavedOccurrence]
        let suppressedUntrackedPastOccurrences: [SavedOccurrence]

        private enum CodingKeys: String, CodingKey {
            case accounts
            case decisionOccurrence
            case decisionOccurrences
            case decisions
            case currentCommitmentDecision
            case selectedPrimaryOccurrences
            case snoozedOccurrence
            case snoozedOccurrences
            case snoozedUntil
            case pauseUntil
            case observedUnacceptedOccurrences
            case suppressedPostStartAcceptanceOccurrences
            case suppressedUntrackedPastOccurrences
        }

        private enum LegacyCodingKeys: String, CodingKey {
            case accountID
            case selectedCalendarIDs
            case isProtectionConfirmed
        }

        init(
            accounts: [SavedAccountConfiguration],
            decisionOccurrence: SavedOccurrence?,
            decisionOccurrences: [SavedOccurrence],
            decisions: [SavedDecision],
            currentCommitmentDecision: CommitmentProtectionDecision?,
            selectedPrimaryOccurrences: [SavedOccurrence],
            snoozedOccurrence: SavedOccurrence?,
            snoozedOccurrences: [SavedOccurrence],
            snoozedUntil: Date?,
            pauseUntil: Date?,
            observedUnacceptedOccurrences: [SavedOccurrence],
            suppressedPostStartAcceptanceOccurrences: [SavedOccurrence],
            suppressedUntrackedPastOccurrences: [SavedOccurrence]
        ) {
            self.accounts = accounts
            self.decisionOccurrence = decisionOccurrence
            self.decisionOccurrences = decisionOccurrences
            self.decisions = decisions
            self.currentCommitmentDecision = currentCommitmentDecision
            self.selectedPrimaryOccurrences = selectedPrimaryOccurrences
            self.snoozedOccurrence = snoozedOccurrence
            self.snoozedOccurrences = snoozedOccurrences
            self.snoozedUntil = snoozedUntil
            self.pauseUntil = pauseUntil
            self.observedUnacceptedOccurrences = observedUnacceptedOccurrences
            self.suppressedPostStartAcceptanceOccurrences = suppressedPostStartAcceptanceOccurrences
            self.suppressedUntrackedPastOccurrences = suppressedUntrackedPastOccurrences
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let savedAccounts = try container.decodeIfPresent(
                [SavedAccountConfiguration].self,
                forKey: .accounts
            ) {
                accounts = savedAccounts
            } else {
                let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
                let accountID = try legacyContainer.decode(String.self, forKey: .accountID)
                let selectedCalendarIDs = try legacyContainer.decode([String].self, forKey: .selectedCalendarIDs)
                let account = GoogleAccount(id: accountID, email: "", displayName: "")
                accounts = [
                    SavedAccountConfiguration(
                        account: account,
                        calendars: [],
                        selectedCalendarIDs: selectedCalendarIDs,
                        isProtectionConfirmed: try legacyContainer.decodeIfPresent(
                            Bool.self,
                            forKey: .isProtectionConfirmed
                        ) ?? false,
                        confirmedCalendarIDs: nil,
                        lastSuccessfulRefreshAt: nil,
                        lastFreshEvents: [],
                        lastFreshEventsSchemaVersion: nil
                    )
                ]
            }
            decisionOccurrence = try container.decodeIfPresent(SavedOccurrence.self, forKey: .decisionOccurrence)
            decisionOccurrences = try container.decodeIfPresent(
                [SavedOccurrence].self,
                forKey: .decisionOccurrences
            ) ?? []
            decisions = try container.decodeIfPresent([SavedDecision].self, forKey: .decisions) ?? []
            currentCommitmentDecision = try container.decodeIfPresent(
                CommitmentProtectionDecision.self,
                forKey: .currentCommitmentDecision
            )
            selectedPrimaryOccurrences = try container.decodeIfPresent(
                [SavedOccurrence].self,
                forKey: .selectedPrimaryOccurrences
            ) ?? []
            snoozedOccurrence = try container.decodeIfPresent(SavedOccurrence.self, forKey: .snoozedOccurrence)
            snoozedOccurrences = try container.decodeIfPresent(
                [SavedOccurrence].self,
                forKey: .snoozedOccurrences
            ) ?? []
            snoozedUntil = try container.decodeIfPresent(Date.self, forKey: .snoozedUntil)
            pauseUntil = try container.decodeIfPresent(Date.self, forKey: .pauseUntil)
            observedUnacceptedOccurrences = try container.decodeIfPresent(
                [SavedOccurrence].self,
                forKey: .observedUnacceptedOccurrences
            ) ?? []
            suppressedPostStartAcceptanceOccurrences = try container.decodeIfPresent(
                [SavedOccurrence].self,
                forKey: .suppressedPostStartAcceptanceOccurrences
            ) ?? []
            suppressedUntrackedPastOccurrences = try container.decodeIfPresent(
                [SavedOccurrence].self,
                forKey: .suppressedUntrackedPastOccurrences
            ) ?? []
        }
    }

    private var persistenceCoverageErrors: [String: String] = [:]
    private var activityPersistenceErrorAccountIDs: Set<String> = []
    private var corruptedProtectedAccountIDs: Set<String> = []
    private var didUseLegacyConfiguration = false

    public init(
        calendarConnector: any GoogleCalendarConnecting,
        launchAtLogin: any LaunchAtLoginControlling,
        stateStore: UserDefaults = .standard,
        encryptedGoogleVault: EncryptedGoogleVault? = nil,
        initialEncryptedStorageError: String? = nil,
        initialEncryptedStorageRequiresReset: Bool = false,
        recoverEncryptedGoogleStorage: (@Sendable () throws -> RecoveredEncryptedGoogleStorage)? = nil,
        startupMode: CommitmentProtectionStartupMode = .normal,
        now: @escaping () -> Date = Date.init
    ) {
        self.calendarConnector = calendarConnector
        self.launchAtLogin = launchAtLogin
        self.stateStore = stateStore
        legacyConfigurationData = stateStore.data(forKey: Self.stateKey)
        if !startupMode.isResetRecovery {
            stateStore.removeObject(forKey: Self.stateKey)
            stateStore.removeObject(forKey: Self.activityLogKey)
        }
        self.encryptedGoogleVault = encryptedGoogleVault
        self.recoverEncryptedGoogleStorage = recoverEncryptedGoogleStorage
        volatileGoogleDataStore = startupMode.isResetRecovery
            ? VolatileGoogleDataStore()
            : VolatileGoogleDataStoreRegistry.store(for: stateStore)
        self.now = now
        if !startupMode.isResetRecovery {
            for key in stateStore.dictionaryRepresentation().keys
                where key.hasPrefix(Self.legacyGoogleRefreshTokenPrefix) {
                stateStore.removeObject(forKey: key)
            }
        }
        isEarlyReminderEnabled = stateStore.object(forKey: Self.earlyReminderEnabledKey) as? Bool ?? true
        isOutOfOfficeProtectionEnabled = stateStore.object(
            forKey: Self.outOfOfficeProtectionEnabledKey
        ) as? Bool ?? false
        isBlockingModeEnabled = stateStore.object(forKey: Self.blockingModeEnabledKey) as? Bool ?? false
        let savedLeadTime = stateStore.integer(forKey: Self.earlyReminderLeadTimeKey)
        earlyReminderLeadTimeMinutes = savedLeadTime == 0
            ? 10
            : Self.clampedEarlyReminderLeadTime(savedLeadTime)
        let savedRepeatInterval = stateStore.integer(forKey: Self.strongAlertRepeatIntervalKey)
        strongAlertRepeatIntervalMinutes = savedRepeatInterval == 0
            ? 1
            : Self.clampedStrongAlertRepeatInterval(savedRepeatInterval)
        pauseUntil = stateStore.object(forKey: Self.pauseUntilKey) as? Date
        isLaunchAtLoginEnabled = launchAtLogin.isEnabled
        encryptedStorageError = initialEncryptedStorageError
        requiresEncryptedStorageReset = initialEncryptedStorageRequiresReset
        activityLog = []
        if startupMode.isResetRecovery {
            appManagedDataResetMutationLockCount = 1
            isAppManagedDataResetInProgress = true
        }
    }

    public func refreshLaunchAtLoginStatus() {
        isLaunchAtLoginEnabled = launchAtLogin.isEnabled
        if isLaunchAtLoginEnabled {
            launchAtLoginError = nil
        }
    }

    public func requestLaunchAtLogin() {
        setLaunchAtLoginEnabled(true)
    }

    public func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        guard !isAppManagedDataResetInProgress else { return }

        do {
            if isEnabled {
                try launchAtLogin.enable()
            } else {
                try launchAtLogin.disable()
            }
            isLaunchAtLoginEnabled = launchAtLogin.isEnabled
            launchAtLoginError = self.isLaunchAtLoginEnabled == isEnabled
                ? nil
                : "macOS did not update start at login. Try again or review Login Items in System Settings."
        } catch {
            isLaunchAtLoginEnabled = launchAtLogin.isEnabled
            launchAtLoginError = Self.privacySafeUserFacingErrorDescription(error)
        }
    }

    public func coverage(for accountID: String) -> CoverageHealth? {
        guard let record = accountRecords[accountID] else { return nil }
        return coverageHealth(for: record, at: coverageEvaluationDate)
    }

    public func coverageWarning(for accountID: String) -> String? {
        guard let record = accountRecords[accountID] else {
            return nil
        }

        switch coverageHealth(for: record, at: coverageEvaluationDate) {
        case .reconnectRequired:
            return "Reconnect \(record.connection.account.protectionDisplayLabel) to resume calendar protection. Routine relaunches stay connected; Google authorization or encrypted device data needs attention."
        case .stale:
            return "Calendar data for \(record.connection.account.protectionDisplayLabel) hasn’t refreshed in more than 15 minutes. Known reminders are Unverified; new reminders won’t be created until Google Calendar refreshes successfully."
        case .unavailable(let message):
            let otherAccountsRemainProtected = accountRecords.values.contains { otherRecord in
                otherRecord.connection.account.id != accountID &&
                    coverageHealth(for: otherRecord, at: coverageEvaluationDate) == .fresh
            }
            let otherAccountDetail = otherAccountsRemainProtected
                ? " Other Connected Accounts remain protected."
                : ""
            return "Google Calendar couldn’t refresh \(record.connection.account.protectionDisplayLabel). \(message) New reminders for this account wait until access returns; Meeting Incoming will retry automatically.\(otherAccountDetail)"
        case .noCoverage, .checking, .fresh:
            return nil
        }
    }

    public func activities(forCalendarID calendarID: String, accountID: String) -> [ProtectionActivity] {
        activityLog.filter {
            $0.resolvedProvenanceSources.contains { source in
                source.accountID == accountID && source.calendarID == calendarID
            }
        }
    }

    public func selectedCalendarIDs(for accountID: String) -> Set<String> {
        accountRecords[accountID]?.selectedCalendarIDs ?? []
    }

    public var isProtectionConfirmationRequired: Bool {
        accountRecords.values.contains(where: \.requiresProtectionConfirmation)
    }

    public func isProtectionConfirmed(for accountID: String) -> Bool {
        accountRecords[accountID]?.isProtectionConfirmed ?? false
    }

    public func calendarDeselectionWarning(
        for calendarID: String,
        accountID: String,
        at date: Date? = nil
    ) -> String? {
        guard let record = accountRecords[accountID],
              record.selectedCalendarIDs.contains(calendarID) else {
            return nil
        }

        let currentDate = date ?? now()
        let hasImminentCommitment = record.lastFreshEvents.contains { event in
            guard event.calendarID == calendarID,
                  isEventEligibleForProtection(event),
                  let startDate = event.startDate,
                  let endDate = event.endDate,
                  endDate > currentDate else {
                return false
            }
            return startDate <= currentDate.addingTimeInterval(
                Double(earlyReminderLeadTimeMinutes) * 60
            )
        }

        guard hasImminentCommitment else { return nil }
        let calendarName = record.connection.calendars.first(where: { $0.id == calendarID })?.name ?? calendarID
        return "\(calendarName) in \(record.connection.account.protectionDisplayLabel) has an imminent commitment. Turning off this calendar removes its reminders."
    }

    public var status: ProtectionStatus {
        let configuredAccounts = accountRecords.values.filter(\.hasConfiguredProtection)
        guard !configuredAccounts.isEmpty else { return .noCoverage }

        let hasFreshCoverage = configuredAccounts.contains { record in
            coverageHealth(for: record, at: coverageEvaluationDate) == .fresh
        }
        return hasFreshCoverage ? .active : .unavailable
    }

    public var isCheckingCoverage: Bool {
        let configuredAccounts = accountRecords.values.filter(\.hasConfiguredProtection)
        guard !configuredAccounts.isEmpty else { return false }
        return configuredAccounts.allSatisfy { record in
            coverageHealth(for: record, at: coverageEvaluationDate) == .checking
        }
    }

    public var menuBarTitle: String {
        if isRestoringConnection {
            return "Loading Protection"
        }
        switch status {
        case .noCoverage:
            return "No Coverage"
        case .active:
            if isPaused() {
                return "Protection Paused"
            }
            return "Active Protection"
        case .unavailable:
            return isCheckingCoverage ? "Checking Coverage" : "Coverage Needs Attention"
        }
    }

    public var snoozeOptionsMinutes: [Int] {
        [5, 10, 15, 30]
    }

    public func isPaused(at date: Date? = nil) -> Bool {
        guard let pauseUntil else { return false }
        return pauseUntil > (date ?? now())
    }

    public func pauseExpirationText(at date: Date? = nil) -> String {
        let currentDate = date ?? now()
        guard let pauseUntil, pauseUntil > currentDate else {
            return "Protection is not paused."
        }

        let minutesRemaining = max(Int(ceil(pauseUntil.timeIntervalSince(currentDate) / 60)), 1)
        let relativeText = Self.localizedHoursAndMinutes(minutesRemaining)

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        return "All protection paused · resumes in \(relativeText) (\(formatter.string(from: pauseUntil)))"
    }

    @discardableResult
    public func pause(for duration: PauseDuration, at date: Date? = nil) -> Bool {
        guard !isAppManagedDataResetInProgress else { return false }
        let currentDate = date ?? now()
        guard hasConfiguredProtection else {
            return false
        }

        let expiration: Date
        switch duration {
        case .oneHour:
            expiration = currentDate.addingTimeInterval(60 * 60)
        case .endOfDay:
            expiration = endOfLocalDay(for: currentDate)
        case .custom(let customExpiration):
            expiration = customExpiration
        }
        guard expiration > currentDate else { return false }

        pauseUntil = expiration
        stateStore.set(expiration, forKey: Self.pauseUntilKey)
        earlyReminderCommitment = nil
        earlyReminderConflictMergedCommitments = []
        earlyReminderConflict = nil
        clearStrongAlertState()
        lastActionMessage = pauseExpirationText(at: currentDate)
        recordActivity(
            .pauseStarted,
            actor: .user,
            title: "All protection paused",
            detail: lastActionMessage ?? "All protection paused.",
            at: currentDate
        )
        return true
    }

    public var canSnoozeEarlyReminder: Bool {
        guard let commitment = earlyReminderCommitment,
              let startDate = commitment.startDate else {
            return false
        }
        let occurrence = OccurrenceIdentity(commitment)
        return startDate > now() && snoozedOccurrence != occurrence
    }

    public var canRestoreProtection: Bool {
        guard currentCommitmentDecision?.isRestorable == true,
              let endDate = decisionCommitment?.endDate else {
            return false
        }
        return endDate > now()
    }

    public func actionResultMessage(for commitment: CalendarEvent) -> String? {
        guard lastActionOccurrence?.matches(commitment) == true else { return nil }
        return lastActionMessage
    }

    public func meetingLinkOpenFailureMessage(for commitment: CalendarEvent) -> String? {
        guard let meetingLinkOpenFailure,
              meetingLinkOpenFailure.occurrence.matches(commitment),
              lastActionOccurrence?.matches(commitment) == true,
              lastActionMessage == meetingLinkOpenFailure.message else {
            return nil
        }
        return meetingLinkOpenFailure.message
    }

    public func connectGoogleAccount() async {
        await connectGoogleAccount(expectedAccountID: nil)
    }

    public var isGoogleAccountOperationInProgress: Bool {
        isConnectingAccount || isRestoringConnection || terminatingAccountID != nil ||
            isAppManagedDataResetInProgress
    }

    public func reconnectGoogleAccount(accountID: String) async {
        guard accountRecords[accountID] != nil else { return }
        await connectGoogleAccount(expectedAccountID: accountID)
    }

    private func connectGoogleAccount(expectedAccountID: String?) async {
        guard !isGoogleAccountOperationInProgress else { return }
        isConnectingAccount = true
        connectingAccountID = expectedAccountID
        defer {
            connectingAccountID = nil
            isConnectingAccount = false
        }

        invalidateRefreshes()
        accountConnectionError = nil
        if accountRecords.isEmpty {
            connectionState = .connecting
        }

        do {
            let connection = try await calendarConnector.connect(expectedAccountID: expectedAccountID)
            guard !isAppManagedDataResetInProgress else { return }
            let existingRecord = accountRecords[connection.account.id]
            let availableCalendarIDs = Set(connection.calendars.map(\.id))
            let selectedCalendarIDs = existingRecord?.selectedCalendarIDs.intersection(
                availableCalendarIDs
            ) ?? []
            let confirmedCalendarIDs = existingRecord?.confirmedCalendarIDs.intersection(
                selectedCalendarIDs
            ) ?? []
            if !confirmedCalendarIDs.isEmpty {
                accountsRequiringUntrackedPastSuppression.insert(connection.account.id)
            }
            accountRecords[connection.account.id] = AccountRecord(
                connection: connection,
                selectedCalendarIDs: selectedCalendarIDs,
                confirmedCalendarIDs: confirmedCalendarIDs,
                connectionState: .connected,
                lastSuccessfulRefreshAt: existingRecord?.lastSuccessfulRefreshAt,
                lastFreshEvents: existingRecord?.lastFreshEvents.filter { event in
                    event.accountID == connection.account.id &&
                        confirmedCalendarIDs.contains(event.calendarID) &&
                        connection.calendars.contains { calendar in calendar.id == event.calendarID }
                } ?? []
            )
            activeAccountID = connection.account.id
            syncCoverageAndActiveAccountProjection()
            recordActivity(
                .accountConnected,
                actor: .user,
                title: "Google Calendar connected",
                detail: "Connected \(connection.account.protectionDisplayLabel)."
            )
            await refreshCommitmentProtection()
        } catch {
            guard !isAppManagedDataResetInProgress else { return }
            let errorDescription = Self.privacySafeUserFacingErrorDescription(error)
            accountConnectionError = errorDescription
            if let expectedAccountID, accountRecords[expectedAccountID] != nil {
                accountRecords[expectedAccountID]?.connectionState = .reconnectRequired
                activeAccountID = expectedAccountID
                syncCoverageAndActiveAccountProjection()
            } else {
                connectionState = .failed(errorDescription)
            }
            recordActivity(
                .accountConnectionFailed,
                actor: .system,
                title: "Google Calendar connection failed",
                detail: "Connection could not be completed: \(errorDescription)."
            )
        }
    }

    @discardableResult
    public func disconnectGoogleAccount() async -> Bool {
        guard let accountID = activeAccountID ?? connectedAccount?.id else {
            return false
        }
        return await disconnectGoogleAccount(accountID: accountID)
    }

    @discardableResult
    public func disconnectGoogleAccount(accountID: String) async -> Bool {
        guard !isGoogleAccountOperationInProgress else {
            return false
        }
        invalidateRefreshes()
        accountDisconnectionError = nil
        failedAccountDisconnectionID = nil
        guard let record = accountRecords[accountID] else { return false }
        terminatingAccountID = accountID
        defer { terminatingAccountID = nil }
        do {
            let result = try await revokeGoogleAuthorization(accountID: accountID)
            guard !isAppManagedDataResetInProgress else { return false }
            guard result != .localCredentialMissing else {
                throw ProtectionFlowError.localCredentialMissingForRevocation
            }
            invalidateRefreshes()
            try removeProtectedRecord(.eventSnapshot, accountID: accountID)
        } catch {
            guard !isAppManagedDataResetInProgress else { return false }
            let errorDescription = Self.privacySafeUserFacingErrorDescription(error)
            accountDisconnectionError = "Couldn’t disconnect \(record.connection.account.protectionDisplayLabel). \(errorDescription)"
            failedAccountDisconnectionID = accountID
            if error is EncryptedGoogleVaultError {
                handleProtectedStorageError(error)
            }
            return false
        }

        guard let latestRecord = accountRecords[accountID] else { return false }
        let retainedCalendars = latestRecord.selectedCalendars
        accountRecords[accountID] = AccountRecord(
            connection: GoogleCalendarConnection(
                account: latestRecord.connection.account,
                calendars: retainedCalendars
            ),
            selectedCalendarIDs: latestRecord.selectedCalendarIDs,
            confirmedCalendarIDs: latestRecord.confirmedCalendarIDs,
            connectionState: .reconnectRequired,
            lastSuccessfulRefreshAt: nil,
            lastFreshEvents: []
        )
        unverifiedAccountIDs.insert(accountID)
        clearLocalState(forAccountID: accountID)
        syncCoverageAndActiveAccountProjection()
        recordActivity(
            .accountDisconnected,
            actor: .user,
            title: "Google Calendar disconnected",
            detail: "Google access was revoked. Monitored Calendar choices and today’s local activity were retained.",
            account: latestRecord.connection.account
        )
        reconcileCachedProtectionAfterConfigurationChange(at: now())
        syncCoverageAndActiveAccountProjection()
        return true
    }

    @discardableResult
    public func removeGoogleAccount(accountID: String) async -> Bool {
        guard !isGoogleAccountOperationInProgress else {
            return false
        }
        invalidateRefreshes()
        accountDisconnectionError = nil
        failedAccountDisconnectionID = nil
        guard let record = accountRecords[accountID] else { return false }
        terminatingAccountID = accountID
        defer { terminatingAccountID = nil }

        var unverifiedRevocationReason: String?
        do {
            do {
                let result = try await revokeGoogleAuthorization(accountID: accountID)
                guard !isAppManagedDataResetInProgress else { return false }
                if result == .localCredentialMissing {
                    unverifiedRevocationReason = "its local credential was missing"
                }
            } catch where isPermanentlyUnreadableCredential(error) {
                guard !isAppManagedDataResetInProgress else { return false }
                // A credential that cannot be authenticated or decoded cannot be
                // presented to Google. User-confirmed Remove may still erase the
                // entire local account boundary; Settings retains an independent
                // route to review Google Account access.
                unverifiedRevocationReason = "its protected credential was unreadable"
            }
            invalidateRefreshes()
            try removeProtectedAccount(accountID)
        } catch {
            guard !isAppManagedDataResetInProgress else { return false }
            let errorDescription = Self.privacySafeUserFacingErrorDescription(error)
            accountDisconnectionError = "Couldn’t remove \(record.connection.account.protectionDisplayLabel). \(errorDescription)"
            failedAccountDisconnectionID = accountID
            if error is EncryptedGoogleVaultError {
                handleProtectedStorageError(error)
            }
            return false
        }

        activityLog.removeAll { $0.containsProtectedData(forAccountID: accountID) }
        clearLocalState(forAccountID: accountID)
        accountRecords.removeValue(forKey: accountID)
        let removedCorruptedProtectedAccount = corruptedProtectedAccountIDs.contains(accountID)
        persistenceCoverageErrors[accountID] = nil
        activityPersistenceErrorAccountIDs.remove(accountID)
        corruptedProtectedAccountIDs.remove(accountID)
        unverifiedAccountIDs.remove(accountID)
        newlySelectedCalendars = newlySelectedCalendars.filter { $0.accountID != accountID }
        accountsRequiringUntrackedPastSuppression.remove(accountID)
        if activeAccountID == accountID {
            activeAccountID = accountRecords.keys.sorted().first
        }
        if accountRecords.isEmpty {
            pauseUntil = nil
            stateStore.removeObject(forKey: Self.pauseUntilKey)
            clearProtectionState()
            clearLastActionMessage()
            stateStore.removeObject(forKey: Self.stateKey)
            stateStore.removeObject(forKey: Self.activityLogKey)
        } else {
            saveActivityLog()
            saveConfiguration()
            reconcileCachedProtectionAfterConfigurationChange(at: now())
        }
        syncCoverageAndActiveAccountProjection()
        if removedCorruptedProtectedAccount, corruptedProtectedAccountIDs.isEmpty {
            requiresEncryptedStorageReset = false
            encryptedStorageError = nil
        }
        if let unverifiedRevocationReason {
            googleAccessReviewNotice = "Local data for \(record.connection.account.protectionDisplayLabel) was removed, but Google revocation could not be verified because \(unverifiedRevocationReason). Review Google Account access to remove Meeting Incoming there if it is still listed."
        }
        if !accountRecords.isEmpty {
            Task { await refreshCommitmentProtection() }
        }
        return true
    }

    @discardableResult
    public func resetEncryptedGoogleData() -> Bool {
        guard !isGoogleAccountOperationInProgress else {
            return false
        }
        do {
            if let encryptedGoogleVault {
                try encryptedGoogleVault.reset()
            } else if let recoverEncryptedGoogleStorage {
                let recoveredStorage = try recoverEncryptedGoogleStorage()
                encryptedGoogleVault = recoveredStorage.vault
                calendarConnector = recoveredStorage.connector
            } else {
                volatileGoogleDataStore.reset()
            }
            accountRecords = [:]
            activityLog = []
            persistenceCoverageErrors = [:]
            activityPersistenceErrorAccountIDs = []
            corruptedProtectedAccountIDs = []
            unverifiedAccountIDs = []
            newlySelectedCalendars = []
            accountsRequiringUntrackedPastSuppression = []
            activeAccountID = nil
            clearProtectionState()
            stateStore.removeObject(forKey: Self.stateKey)
            stateStore.removeObject(forKey: Self.activityLogKey)
            stateStore.removeObject(forKey: Self.pauseUntilKey)
            encryptedStorageError = nil
            requiresEncryptedStorageReset = false
            syncCoverageAndActiveAccountProjection()
            return true
        } catch {
            handleProtectedStorageError(error)
            return false
        }
    }

    private func revokeGoogleAuthorization(
        accountID: String
    ) async throws -> GoogleAuthorizationRevocationResult {
        if let revoker = calendarConnector as? any GoogleAuthorizationRevoking {
            return try await revoker.revokeAuthorization(accountID: accountID)
        } else {
            try calendarConnector.disconnect(accountID: accountID)
            return .revoked
        }
    }

    public func restoreSavedConnection() async {
        guard !isAppManagedDataResetInProgress else { return }
        guard let savedConfiguration = loadConfiguration() else { return }
        activityLog = loadActivityLog()

        invalidateRefreshes()
        isRestoringConnection = true
        defer { isRestoringConnection = false }

        accountRecords = [:]
        unverifiedAccountIDs = []
        newlySelectedCalendars = []
        accountsRequiringUntrackedPastSuppression = []
        var accountIDsRequiringLocalStateClear = corruptedProtectedAccountIDs
        for savedAccount in savedConfiguration.accounts {
            let savedAvailableCalendarIDs = Set(savedAccount.calendars.map(\.id))
            let savedSelectedCalendarIDs = Set(savedAccount.selectedCalendarIDs)
                .intersection(savedAvailableCalendarIDs)
            let savedConfirmedCalendarIDs = savedAccount.resolvedConfirmedCalendarIDs
                .intersection(savedSelectedCalendarIDs)
            if corruptedProtectedAccountIDs.contains(savedAccount.account.id) {
                let message = persistenceCoverageErrors[savedAccount.account.id] ??
                    "Protected Google data is damaged. Reset encrypted Google data or remove this account."
                accountRecords[savedAccount.account.id] = AccountRecord(
                    connection: GoogleCalendarConnection(
                        account: savedAccount.account,
                        calendars: savedAccount.calendars
                    ),
                    selectedCalendarIDs: savedSelectedCalendarIDs,
                    confirmedCalendarIDs: savedConfirmedCalendarIDs,
                    connectionState: .failed(message),
                    lastSuccessfulRefreshAt: nil,
                    lastFreshEvents: []
                )
                unverifiedAccountIDs.insert(savedAccount.account.id)
                continue
            }
            do {
                let restoredConnection = try await calendarConnector.restore(
                    accountID: savedAccount.account.id
                )
                guard !isAppManagedDataResetInProgress else { return }
                guard let connection = restoredConnection else {
                    guard !savedAccount.account.id.isEmpty else { continue }
                    do {
                        try removeProtectedRecord(.eventSnapshot, accountID: savedAccount.account.id)
                    } catch {
                        markProtectedAccountStorageFailure(savedAccount.account.id, error: error)
                    }
                    accountIDsRequiringLocalStateClear.insert(savedAccount.account.id)
                    accountRecords[savedAccount.account.id] = AccountRecord(
                        connection: GoogleCalendarConnection(
                            account: savedAccount.account,
                            calendars: savedAccount.calendars
                        ),
                        selectedCalendarIDs: savedSelectedCalendarIDs,
                        confirmedCalendarIDs: savedConfirmedCalendarIDs,
                        connectionState: .reconnectRequired,
                        lastSuccessfulRefreshAt: nil,
                        lastFreshEvents: []
                    )
                    unverifiedAccountIDs.insert(savedAccount.account.id)
                    continue
                }
                guard connection.account.id == savedAccount.account.id else {
                    throw ProtectionFlowError.restoredAccountMismatch
                }
                let availableCalendarIDs = Set(connection.calendars.map(\.id))
                let selectedCalendarIDs = Set(savedAccount.selectedCalendarIDs)
                    .intersection(availableCalendarIDs)
                accountRecords[connection.account.id] = AccountRecord(
                    connection: connection,
                    selectedCalendarIDs: selectedCalendarIDs,
                    confirmedCalendarIDs: savedAccount.resolvedConfirmedCalendarIDs
                        .intersection(selectedCalendarIDs),
                    connectionState: .connected,
                    lastSuccessfulRefreshAt: savedAccount.lastSuccessfulRefreshAt,
                    lastFreshEvents: restoredFreshEvents(
                        from: savedAccount,
                        accountID: connection.account.id,
                        calendars: connection.calendars
                    )
                )
            } catch {
                guard !isAppManagedDataResetInProgress else { return }
                guard !savedAccount.account.id.isEmpty else { continue }
                unverifiedAccountIDs.insert(savedAccount.account.id)
                let connectionState: ConnectionState
                if let connectorError = error as? GoogleCalendarConnectorError,
                   connectorError.credentialFailureDisposition == .invalid {
                    connectionState = .reconnectRequired
                    do {
                        try removeProtectedRecord(.eventSnapshot, accountID: savedAccount.account.id)
                    } catch {
                        markProtectedAccountStorageFailure(savedAccount.account.id, error: error)
                    }
                    accountIDsRequiringLocalStateClear.insert(savedAccount.account.id)
                } else {
                    connectionState = .failed(
                        Self.privacySafeUserFacingErrorDescription(error)
                    )
                }
                if error is EncryptedGoogleVaultError {
                    markProtectedAccountStorageFailure(
                        savedAccount.account.id,
                        error: error
                    )
                }
                accountRecords[savedAccount.account.id] = AccountRecord(
                    connection: GoogleCalendarConnection(
                        account: savedAccount.account,
                        calendars: savedAccount.calendars
                    ),
                    selectedCalendarIDs: savedSelectedCalendarIDs,
                    confirmedCalendarIDs: savedConfirmedCalendarIDs,
                    connectionState: connectionState,
                    lastSuccessfulRefreshAt: connectionState == .reconnectRequired
                        ? nil
                        : savedAccount.lastSuccessfulRefreshAt,
                    lastFreshEvents: connectionState == .reconnectRequired
                        ? []
                        : restoredFreshEvents(
                            from: savedAccount,
                            accountID: savedAccount.account.id,
                            calendars: savedAccount.calendars
                        )
                )
            }
        }

        activeAccountID = accountRecords.keys.sorted().first
        markPendingCalendarsAsNewlySelected()
        restoreLocalState(from: savedConfiguration)
        for accountID in accountIDsRequiringLocalStateClear {
            clearLocalState(forAccountID: accountID)
        }
        syncCoverageAndActiveAccountProjection()
        saveActivityLog()
        saveConfiguration()
        if !accountRecords.isEmpty {
            accountsRequiringUntrackedPastSuppression = Set(
                accountRecords.values
                    .filter(\.hasConfiguredProtection)
                    .map { $0.connection.account.id }
            )
            reconcileCachedProtectionAfterConfigurationChange(at: now())
            syncCoverageAndActiveAccountProjection()
            if accountRecords.values.contains(where: { $0.connectionState == .connected }) {
                await recoverProtection()
            }
        }
    }

    public func setCalendarSelected(_ isSelected: Bool, calendarID: String) {
        guard let accountID = activeAccountID else { return }
        setCalendarSelected(isSelected, calendarID: calendarID, accountID: accountID)
    }

    public func setCalendarSelected(_ isSelected: Bool, calendarID: String, accountID: String) {
        guard !isGoogleAccountOperationInProgress,
              var record = accountRecords[accountID],
              record.connection.calendars.contains(where: { $0.id == calendarID }) else { return }

        if isSelected {
            let wasAlreadySelected = record.selectedCalendarIDs.contains(calendarID)
            record.selectedCalendarIDs.insert(calendarID)
            if !wasAlreadySelected && !record.confirmedCalendarIDs.isEmpty {
                newlySelectedCalendars.insert(
                    CalendarSelectionIdentity(calendarID: calendarID, accountID: accountID)
                )
            }
        } else {
            record.selectedCalendarIDs.remove(calendarID)
            record.confirmedCalendarIDs.remove(calendarID)
            record.lastFreshEvents.removeAll { $0.calendarID == calendarID }
            newlySelectedCalendars.remove(
                CalendarSelectionIdentity(calendarID: calendarID, accountID: accountID)
            )
        }
        accountRecords[accountID] = record
        let selectedCalendar = record.connection.calendars.first(where: { $0.id == calendarID })
        let calendarName = selectedCalendar?.name ?? calendarID
        invalidateRefreshes()
        reconcileCachedProtectionAfterConfigurationChange(at: now())
        syncCoverageAndActiveAccountProjection()
        recordActivity(
            .configurationChanged,
            actor: .user,
            title: "Calendar selection changed",
            detail: isSelected ? "Monitoring \(calendarName)." : "Stopped monitoring \(calendarName).",
            account: record.connection.account,
            calendar: selectedCalendar
        )
        Task { await refreshCommitmentProtection() }
    }

    @discardableResult
    public func confirmProtection() -> Bool {
        guard let accountID = activeAccountID else { return false }
        return confirmProtection(for: accountID)
    }

    @discardableResult
    public func confirmProtection(for accountID: String) -> Bool {
        guard !isGoogleAccountOperationInProgress,
              var record = accountRecords[accountID],
              !record.selectedCalendarIDs.isEmpty else {
            return false
        }
        record.confirmedCalendarIDs = record.selectedCalendarIDs
        accountRecords[accountID] = record
        invalidateRefreshes()
        syncCoverageAndActiveAccountProjection()
        recordActivity(
            .configurationChanged,
            actor: .user,
            title: "Protection confirmed",
            detail: "Protection is enabled for the selected calendars.",
            account: record.connection.account
        )
        Task { await refreshCommitmentProtection() }
        return true
    }

    @discardableResult
    public func confirmAllProtection() -> Bool {
        guard !isGoogleAccountOperationInProgress else { return false }
        let accountIDs = accountRecords.values
            .filter(\.requiresProtectionConfirmation)
            .map { $0.connection.account.id }
        guard !accountIDs.isEmpty else { return false }

        for accountID in accountIDs {
            guard var record = accountRecords[accountID] else { continue }
            record.confirmedCalendarIDs = record.selectedCalendarIDs
            accountRecords[accountID] = record
        }
        invalidateRefreshes()
        syncCoverageAndActiveAccountProjection()
        for accountID in accountIDs {
            guard let account = accountRecords[accountID]?.connection.account else { continue }
            recordActivity(
                .configurationChanged,
                actor: .user,
                title: "Protection confirmed",
                detail: "Protection is enabled for the selected calendars.",
                account: account
            )
        }
        Task { await refreshCommitmentProtection() }
        return true
    }

    public func setBlockingAvailability(_ isAvailable: Bool) {
        guard !isAppManagedDataResetInProgress else { return }
        isBlockingAvailable = isAvailable
    }

    public func setEarlyReminderEnabled(_ isEnabled: Bool) {
        guard !isAppManagedDataResetInProgress else { return }
        guard isEnabled != isEarlyReminderEnabled else { return }

        isEarlyReminderEnabled = isEnabled
        stateStore.set(isEnabled, forKey: Self.earlyReminderEnabledKey)
        invalidateRefreshes()
        if !isEnabled {
            earlyReminderCommitment = nil
            earlyReminderConflictMergedCommitments = []
            earlyReminderConflict = nil
        }
        recordActivity(
            .configurationChanged,
            actor: .user,
            title: "Early Reminder setting changed",
            detail: isEnabled ? "Early Reminder enabled." : "Early Reminder disabled."
        )
        Task { await refreshCommitmentProtection() }
    }

    public func setOutOfOfficeProtectionEnabled(_ isEnabled: Bool) {
        guard !isAppManagedDataResetInProgress else { return }
        guard isEnabled != isOutOfOfficeProtectionEnabled else { return }

        isOutOfOfficeProtectionEnabled = isEnabled
        stateStore.set(isEnabled, forKey: Self.outOfOfficeProtectionEnabledKey)
        invalidateRefreshes()
        if isEnabled {
            // A newly enabled event type follows the same non-retroactive rule as a newly
            // selected calendar: already-started occurrences are observed but not adopted.
            accountsRequiringUntrackedPastSuppression.formUnion(
                accountRecords.values
                    .filter(\.hasConfiguredProtection)
                    .map { $0.connection.account.id }
            )
        } else {
            for accountID in Array(accountRecords.keys) {
                accountRecords[accountID]?.lastFreshEvents.removeAll {
                    $0.eventType == .outOfOffice
                }
            }
        }
        reconcileCachedProtectionAfterConfigurationChange(at: now())
        syncCoverageAndActiveAccountProjection()
        recordActivity(
            .configurationChanged,
            actor: .user,
            title: "Out-of-office protection setting changed",
            detail: isEnabled
                ? "Out-of-office protection enabled."
                : "Out-of-office protection disabled."
        )
        Task { await refreshCommitmentProtection() }
    }

    public func setBlockingModeEnabled(_ isEnabled: Bool) {
        guard !isAppManagedDataResetInProgress else { return }
        guard isEnabled != isBlockingModeEnabled else { return }

        isBlockingModeEnabled = isEnabled
        stateStore.set(isEnabled, forKey: Self.blockingModeEnabledKey)
        recordActivity(
            .blockingModeChanged,
            actor: .user,
            title: "Blocking mode changed",
            detail: isEnabled ? "Blocking mode enabled." : "Blocking mode disabled."
        )
    }

    public func setStrongAlertRepeatInterval(minutes: Int) {
        guard !isAppManagedDataResetInProgress else { return }
        let clampedMinutes = Self.clampedStrongAlertRepeatInterval(minutes)
        guard clampedMinutes != strongAlertRepeatIntervalMinutes else { return }

        strongAlertRepeatIntervalMinutes = clampedMinutes
        stateStore.set(clampedMinutes, forKey: Self.strongAlertRepeatIntervalKey)
        invalidateRefreshes()
        recordActivity(
            .configurationChanged,
            actor: .user,
            title: "Strong Alert setting changed",
            detail: "Strong Alert repeats every \(clampedMinutes) minute\(clampedMinutes == 1 ? "" : "s")."
        )
        Task { await refreshCommitmentProtection() }
    }

    public func setEarlyReminderLeadTime(minutes: Int) {
        guard !isAppManagedDataResetInProgress else { return }
        let clampedMinutes = Self.clampedEarlyReminderLeadTime(minutes)
        guard clampedMinutes != earlyReminderLeadTimeMinutes else { return }

        earlyReminderLeadTimeMinutes = clampedMinutes
        stateStore.set(clampedMinutes, forKey: Self.earlyReminderLeadTimeKey)
        invalidateRefreshes()
        recordActivity(
            .configurationChanged,
            actor: .user,
            title: "Early Reminder setting changed",
            detail: "Early Reminder lead time is \(clampedMinutes) minutes."
        )
        Task { await refreshCommitmentProtection() }
    }

    public func startMonitoring() {
        guard !isAppManagedDataResetInProgress else { return }
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshCommitmentProtection()
                do {
                    try await Task.sleep(nanoseconds: self.monitoringSleepIntervalNanoseconds())
                } catch {
                    return
                }
            }
        }
    }

    /// Stops every source of automatic refresh before an app-managed data reset.
    ///
    /// The reset coordinator must await this method before revoking authorization
    /// or replacing storage. Invalidating the generation prevents an in-flight
    /// provider response from writing protected data after the reset begins.
    public func stopMonitoringForAppManagedDataReset() async {
        monitoringTask?.cancel()
        monitoringTask = nil
        invalidateRefreshes()
        await refreshCoordinator.drain()
        isRefreshingCoverage = false
    }

    /// Closes the production mutation gate before a durable reset is committed.
    /// The reset coordinator calls this synchronously before its first suspension
    /// point so UI actions cannot race journal creation or account enumeration.
    public func lockMutationsForAppManagedDataReset() {
        appManagedDataResetMutationLockCount += 1
        guard appManagedDataResetMutationLockCount == 1 else { return }
        isAppManagedDataResetInProgress = true
        invalidateRefreshes()
    }

    /// Reopens production mutations when recovery discovers that no reset is
    /// active, or when reset setup fails before a journal is committed.
    public func unlockMutationsForAppManagedDataReset() {
        guard appManagedDataResetMutationLockCount > 0 else { return }
        appManagedDataResetMutationLockCount -= 1
        guard appManagedDataResetMutationLockCount == 0 else { return }
        isAppManagedDataResetInProgress = false
    }

    /// Number of encrypted Saved Accounts that still need reset-time revocation.
    /// The reset journal persists only an ordinal, never a Google-derived ID.
    public var appManagedDataResetAccountCount: Int {
        if !accountRecords.isEmpty {
            return accountRecords.count
        }
        return (try? protectedAccountIDs().count) ?? 0
    }

    /// Revokes one Saved Account selected by a stable, sorted ordinal.
    ///
    /// Account records remain in encrypted storage until every revocation step
    /// reaches a terminal result. This keeps ordinals stable across recovery while
    /// avoiding Google-derived identifiers in the plaintext reset journal.
    public func revokeAuthorizationForAppManagedDataReset(
        accountPosition: Int
    ) async throws -> GoogleAuthorizationRevocationResult {
        let accountIDs = accountRecords.isEmpty
            ? try protectedAccountIDs().sorted()
            : accountRecords.keys.sorted()
        guard accountIDs.indices.contains(accountPosition) else {
            throw AppManagedDataResetFlowError.accountPositionOutOfBounds
        }
        do {
            return try await revokeGoogleAuthorization(accountID: accountIDs[accountPosition])
        } catch where isPermanentlyUnreadableCredential(error) {
            return .localCredentialMissing
        }
    }

    public func refreshCommitmentProtection() async {
        await requestRefresh(at: now(), intent: .ordinary)
    }

    public func recoverProtection(at currentDate: Date? = nil) async {
        await requestRefresh(at: currentDate ?? now(), intent: .recovery)
    }

    public func refreshCommitmentProtection(at currentDate: Date) async {
        await requestRefresh(at: currentDate, intent: .ordinary)
    }

    private func requestRefresh(
        at currentDate: Date,
        intent: RefreshCoordinator.Intent
    ) async {
        guard !isAppManagedDataResetInProgress else { return }
        onRefreshRequestEnqueued?(intent, currentDate)
        await refreshCoordinator.submit(at: currentDate, intent: intent) { [weak self] request in
            guard let self, !self.isAppManagedDataResetInProgress else { return }
            self.isRefreshingCoverage = true
            await self.performCommitmentProtectionRefresh(request)
            self.isRefreshingCoverage = false
        }
    }

    private func performCommitmentProtectionRefresh(
        _ request: RefreshCoordinator.Request
    ) async {
        // Revocation is transactional from the UI's perspective. A refresh that
        // treats the pending account as absent would mutate local protection even
        // if Google later returns a transient failure.
        guard refreshCoordinator.isCurrent(request), terminatingAccountID == nil else { return }
        let currentDate = request.date
        lastEvaluatedCoverageDate = currentDate
        if pruneActivityLog(at: currentDate) {
            saveActivityLog()
            saveConfiguration()
        }
        migrateLegacyActivityCalendarContext(with: [])
        let generation = beginRefresh()
        let configuredAccountIDs = accountRecords.values
            .filter {
                $0.hasConfiguredProtection &&
                    !corruptedProtectedAccountIDs.contains($0.connection.account.id)
            }
            .map { $0.connection.account.id }
            .sorted()
        guard !configuredAccountIDs.isEmpty else {
            clearProtectionState()
            syncCoverageAndActiveAccountProjection()
            return
        }

        let startDate = Calendar.current.startOfDay(for: currentDate)
        let endDate = currentDate.addingTimeInterval(24 * 60 * 60)
        let requests = configuredAccountIDs.compactMap { accountID -> AccountRefreshRequest? in
            guard let record = accountRecords[accountID],
                  record.connectionState != .reconnectRequired else { return nil }
            return AccountRefreshRequest(accountID: accountID, calendars: record.protectedCalendars)
        }
        var eventsByAccount = Dictionary(uniqueKeysWithValues: configuredAccountIDs.compactMap {
            accountID -> (String, [CalendarEvent])? in
            guard let record = accountRecords[accountID],
                  record.connectionState != .reconnectRequired else { return nil }
            return (
                accountID,
                record.lastFreshEvents.filter {
                    $0.accountID == accountID && record.confirmedCalendarIDs.contains($0.calendarID)
                }
            )
        })
        var completedAccountIDs: Set<String> = []
        let connector = calendarConnector

        await withTaskGroup(of: AccountRefreshResult.self) { group in
            for request in requests {
                group.addTask { [connector, request] in
                    do {
                        var events: [CalendarEvent] = []
                        for calendar in request.calendars {
                            try Task.checkCancellation()
                            events += try await connector.loadEvents(
                                accountID: request.accountID,
                                calendarID: calendar.id,
                                from: startDate,
                                to: endDate
                            )
                        }
                        return .success(accountID: request.accountID, events: events)
                    } catch {
                        return .failure(
                            accountID: request.accountID,
                            message: Self.privacySafeUserFacingErrorDescription(error),
                            credentialDisposition: (error as? GoogleCalendarConnectorError)?
                                .credentialFailureDisposition
                        )
                    }
                }
            }

            for await result in group {
                guard generation == refreshGeneration,
                      refreshCoordinator.isCurrent(request) else {
                    group.cancelAll()
                    return
                }
                let accountID = result.accountID
                guard var record = accountRecords[accountID] else { continue }
                completedAccountIDs.insert(accountID)

                switch result {
                case .success(_, let freshEvents):
                    let wasUnavailable = record.connectionState != .connected ||
                        unverifiedAccountIDs.contains(accountID)
                    let previouslyTrackedOccurrences = Set(record.lastFreshEvents.map(OccurrenceIdentity.init))
                    let selectedNewCalendars = Set(record.protectedCalendars.map {
                        CalendarSelectionIdentity(calendarID: $0.id, accountID: accountID)
                    }).intersection(newlySelectedCalendars)
                    let protectionEvents = freshEvents.filter { event in
                        isEventEligibleForProtection(event) &&
                            (event.endDate ?? .distantPast) > currentDate
                    }
                    let eventsToSuppress = protectionEvents.filter { event in
                        request.intent == .recovery ||
                            accountsRequiringUntrackedPastSuppression.contains(accountID) ||
                            selectedNewCalendars.contains(
                                CalendarSelectionIdentity(calendarID: event.calendarID, accountID: event.accountID)
                            )
                    }
                    suppressUntrackedPastOccurrences(
                        in: eventsToSuppress,
                        previouslyTracked: previouslyTrackedOccurrences,
                        at: currentDate
                    )
                    record.connectionState = .connected
                    record.lastSuccessfulRefreshAt = currentDate
                    record.lastFreshEvents = protectionEvents
                    accountRecords[accountID] = record
                    unverifiedAccountIDs.remove(accountID)
                    accountsRequiringUntrackedPastSuppression.remove(accountID)
                    newlySelectedCalendars.subtract(selectedNewCalendars)
                    eventsByAccount[accountID] = freshEvents
                    if wasUnavailable {
                        recordActivity(
                            .coverageRestored,
                            actor: .system,
                            title: "Calendar coverage restored",
                            detail: "Calendar protection is available again.",
                            account: record.connection.account,
                            at: currentDate
                        )
                    }

                case .failure(_, let message, let credentialDisposition):
                    let wasAlreadyUnavailable = record.connectionState == .failed(message) ||
                        unverifiedAccountIDs.contains(accountID)
                    if credentialDisposition == .invalid {
                        record.connectionState = .reconnectRequired
                        record.lastSuccessfulRefreshAt = nil
                        record.lastFreshEvents = []
                        eventsByAccount[accountID] = []
                        do {
                            try removeProtectedRecord(.eventSnapshot, accountID: accountID)
                        } catch {
                            handleProtectedStorageError(error)
                        }
                        clearLocalState(forAccountID: accountID)
                    } else {
                        record.connectionState = .failed(message)
                    }
                    accountRecords[accountID] = record
                    unverifiedAccountIDs.insert(accountID)
                    if !wasAlreadyUnavailable {
                        recordActivity(
                            .coverageUnavailable,
                            actor: .system,
                            title: "Calendar coverage unavailable",
                            detail: "Calendar events could not be refreshed: \(message).",
                            account: record.connection.account,
                            at: currentDate
                        )
                    }
                }

                let events = configuredAccountIDs.flatMap { eventsByAccount[$0] ?? [] }
                let isCompleteSnapshot = completedAccountIDs.count == configuredAccountIDs.count
                syncCoverageAndActiveAccountProjection()
                migrateLegacyActivityCalendarContext(with: events)
                reconcileCalendarSnapshot(
                    events,
                    at: currentDate,
                    isCompleteSnapshot: isCompleteSnapshot
                )
                syncCoverageAndActiveAccountProjection()
            }

            guard generation == refreshGeneration,
                  refreshCoordinator.isCurrent(request) else { return }
        }
    }

    public var strongAlertPrimaryActionTitle: String {
        if strongAlertMeetingLinkOptions.isEmpty {
            return "Stop reminders"
        }
        return strongAlertPrimaryMeetingLink == nil && strongAlertMeetingLinkOptions.count > 1
            ? "Choose link"
            : "Join"
    }

    public var strongAlertMeetingLinkOptions: [URL] {
        if let strongAlertMergedCommitment {
            return strongAlertMergedCommitment.meetingLinks.map(\.url)
        }
        return strongAlertCommitment?.recognizedMeetingLinks.map(\.url) ?? []
    }

    public var strongAlertPrimaryMeetingLink: URL? {
        if let strongAlertMergedCommitment {
            return strongAlertMergedCommitment.primaryMeetingLink
        }
        return strongAlertCommitment?.primaryRecognizedMeetingLink
    }

    public var strongAlertActionCommitments: [CalendarEvent] {
        if let conflict = strongAlertConflict {
            if let primaryCommitment = conflict.primaryCommitment {
                return [primaryCommitment]
            }
            return conflict.commitments
        }
        return strongAlertCommitment.map { [$0] } ?? []
    }

    public func strongAlertMeetingLinkOptions(for commitment: CalendarEvent) -> [URL] {
        strongAlertGroup(containing: commitment)?.meetingLinks.map(\.url) ??
            commitment.recognizedMeetingLinks.map(\.url)
    }

    public func strongAlertPrimaryMeetingLink(for commitment: CalendarEvent) -> URL? {
        if let group = strongAlertGroup(containing: commitment) {
            return group.primaryMeetingLink
        }
        return commitment.primaryRecognizedMeetingLink
    }

    @discardableResult
    public func selectPrimary(for commitment: CalendarEvent) -> Bool {
        guard !isAppManagedDataResetInProgress else { return false }
        guard let group = conflictGroup(containing: commitment),
              let groups = displayedConflictGroups(containing: group),
              groups.count > 1,
              areSameStart(groups),
              group.contains(commitment) else {
            return false
        }

        let conflictingOccurrences = groups.reduce(into: Set<OccurrenceIdentity>()) { occurrences, group in
            occurrences.formUnion(group.occurrences)
        }
        selectedPrimaryOccurrences = selectedPrimaryOccurrences.filter { selectedOccurrence in
            !conflictingOccurrences.contains { selectedOccurrence.matches($0) }
        }
        selectedPrimaryOccurrences.formUnion(group.occurrences)
        lastActionMessage = "Primary commitment selected for this conflict."
        lastActionOccurrence = OccurrenceIdentity(commitment)
        recordActivity(
            .conflictPrimarySelected,
            actor: .user,
            title: "Conflict primary selected",
            detail: lastActionMessage ?? "Primary commitment selected for this conflict.",
            commitment: group.displayEvent,
            commitmentGroup: group
        )
        saveConfiguration()
        Task { await refreshCommitmentProtection() }
        return true
    }

    /// Opens a validated meeting link before ending reminders for the occurrence.
    /// If macOS cannot open the link, protection stays active so the user can retry.
    @discardableResult
    public func openStrongAlertMeetingLink(
        open: (URL) -> Bool
    ) -> Bool {
        guard let commitment = strongAlertCommitment else { return false }
        return openStrongAlertMeetingLink(for: commitment, open: open)
    }

    /// Opens the designated link, or the only recognized link, for a commitment.
    /// Multiple undesignated links require the caller to pass an explicit choice.
    @discardableResult
    public func openStrongAlertMeetingLink(
        for commitment: CalendarEvent,
        open: (URL) -> Bool
    ) -> Bool {
        let options = strongAlertMeetingLinkOptions(for: commitment)
        let primaryLink = strongAlertPrimaryMeetingLink(for: commitment)
        guard primaryLink != nil || options.count <= 1,
              let meetingLink = primaryLink ?? options.first else {
            return false
        }
        return openStrongAlertMeetingLink(for: commitment, using: meetingLink, open: open)
    }

    @discardableResult
    public func openStrongAlertMeetingLink(
        using meetingLink: URL,
        open: (URL) -> Bool
    ) -> Bool {
        guard let commitment = strongAlertCommitment else { return false }
        return openStrongAlertMeetingLink(for: commitment, using: meetingLink, open: open)
    }

    /// Opens a validated meeting link before ending reminders for the selected
    /// commitment in a conflict.
    @discardableResult
    public func openStrongAlertMeetingLink(
        for commitment: CalendarEvent,
        using meetingLink: URL,
        open: (URL) -> Bool
    ) -> Bool {
        guard !isAppManagedDataResetInProgress else { return false }
        guard let group = validatedStrongAlertJoinGroup(
            for: commitment,
            using: meetingLink
        ) else { return false }

        guard open(meetingLink) else {
            let message = "Couldn’t open the meeting link. Protection remains active. Try again or open it from Google Calendar."
            let occurrence = OccurrenceIdentity(commitment)
            lastActionMessage = message
            lastActionOccurrence = occurrence
            meetingLinkOpenFailure = (occurrence, message)
            return false
        }
        guard !isAppManagedDataResetInProgress else { return false }

        recordDecision(
            .joined,
            for: commitment,
            group: group,
            message: "Meeting link opened. Reminders stopped for this occurrence."
        )
        return true
    }

    private func validatedStrongAlertJoinGroup(
        for commitment: CalendarEvent,
        using meetingLink: URL
    ) -> MergedCommitment? {
        let meetingLinkKey = CalendarEvent.normalizedMeetingLinkKey(meetingLink)
        guard strongAlertMeetingLinkOptions(for: commitment).contains(where: {
            CalendarEvent.normalizedMeetingLinkKey($0) == meetingLinkKey
        }) else { return nil }
        if let group = strongAlertConflictMergedCommitments.first(where: { $0.contains(commitment) }) {
            return group
        }
        guard let strongAlertMergedCommitment,
              strongAlertMergedCommitment.contains(commitment) else {
            return nil
        }
        return strongAlertMergedCommitment
    }

    public func handleStrongAlert() {
        guard let commitment = strongAlertCommitment else { return }
        _ = handleStrongAlert(for: commitment, at: now())
    }

    @discardableResult
    public func handleStrongAlert(for commitment: CalendarEvent, at date: Date? = nil) -> Bool {
        guard isStrongAlertActionable(commitment) else { return false }
        return handle(commitment, at: date ?? now())
    }

    @discardableResult
    public func handleCommitment(at date: Date? = nil) -> Bool {
        guard let commitment = strongAlertCommitment ?? earlyReminderCommitment ?? upcomingCommitment else {
            return false
        }
        return handleCommitment(for: commitment, at: date)
    }

    @discardableResult
    public func handleCommitment(for commitment: CalendarEvent, at date: Date? = nil) -> Bool {
        guard isActionable(commitment) else { return false }
        return handle(commitment, at: date ?? now())
    }

    @discardableResult
    public func dismissCommitment(at date: Date? = nil) -> Bool {
        guard let commitment = strongAlertCommitment ?? earlyReminderCommitment ?? upcomingCommitment else {
            return false
        }
        return dismissCommitment(for: commitment, at: date)
    }

    @discardableResult
    public func dismissCommitment(for commitment: CalendarEvent, at date: Date? = nil) -> Bool {
        guard !isAppManagedDataResetInProgress else { return false }
        guard isActionable(commitment),
              let endDate = mergedCommitment(containing: commitment)?.endDate ?? commitment.endDate,
              endDate > (date ?? now()) else {
            return false
        }
        recordDecision(
            .dismissed,
            for: commitment,
            group: mergedCommitment(containing: commitment),
            message: "Reminders stopped for this occurrence. Google Calendar RSVP unchanged."
        )
        return true
    }

    @discardableResult
    public func restoreProtection(at date: Date? = nil) -> Bool {
        guard !isAppManagedDataResetInProgress else { return false }
        let currentDate = date ?? now()
        guard currentCommitmentDecision?.isRestorable == true,
              let commitment = decisionCommitment,
              (currentMergedCommitment(containing: commitment, at: currentDate)?.endDate
                ?? commitment.endDate
                ?? .distantPast) > currentDate else {
            return false
        }
        let group = currentMergedCommitment(containing: commitment, at: currentDate)
            ?? makeMergedCommitment(from: [commitment])

        clearLocalDecision()
        lastActionMessage = "Protection restored for this occurrence."
        lastActionOccurrence = OccurrenceIdentity(commitment)
        recordActivity(
            .protectionRestored,
            actor: .user,
            title: "Protection restored",
            detail: lastActionMessage ?? "Protection restored for this occurrence.",
            commitment: group.displayEvent,
            commitmentGroup: group,
            at: currentDate
        )
        restoreDisplayedProtection(for: group, at: currentDate)
        return true
    }

    @discardableResult
    public func snoozeEarlyReminder(minutes: Int, at date: Date? = nil) -> Bool {
        guard !isAppManagedDataResetInProgress else { return false }
        let currentDate = date ?? now()
        guard snoozeOptionsMinutes.contains(minutes),
              let commitment = earlyReminderCommitment,
              let startDate = commitment.startDate,
              startDate > currentDate else {
            return false
        }

        let group = earlyReminderMergedCommitment
        let occurrence = OccurrenceIdentity(commitment)
        let groupOccurrences = group?.occurrences ?? [occurrence]
        guard snoozedOccurrences.isDisjoint(with: groupOccurrences) else { return false }

        snoozedOccurrence = occurrence
        snoozedOccurrences = groupOccurrences
        let requestedSnoozeUntil = currentDate.addingTimeInterval(Double(minutes) * 60)
        let effectiveSnoozeUntil = min(
            group?.endDate ?? commitment.endDate ?? requestedSnoozeUntil,
            requestedSnoozeUntil
        )
        snoozedUntil = effectiveSnoozeUntil
        earlyReminderMergedCommitment = nil
        earlyReminderCommitment = nil
        earlyReminderConflictMergedCommitments = []
        earlyReminderConflict = nil
        lastActionMessage = commitment.endDate == effectiveSnoozeUntil && requestedSnoozeUntil > effectiveSnoozeUntil
            ? "Reminders for this occurrence snoozed until the commitment ends."
            : "Reminders for this occurrence snoozed for \(Self.localizedMinuteDuration(minutes)). Protection remains active."
        lastActionOccurrence = occurrence
        recordActivity(
            .snoozed,
            actor: .user,
            title: "Reminders snoozed",
            detail: lastActionMessage ?? "Reminders snoozed.",
            commitment: commitment,
            commitmentGroup: group,
            at: currentDate
        )
        return true
    }

    @discardableResult
    public func snoozeEarlyReminder(
        minutes: Int,
        for commitment: CalendarEvent,
        at date: Date? = nil
    ) -> Bool {
        guard isCurrentEarlyReminder(commitment) else { return false }
        return snoozeEarlyReminder(minutes: minutes, at: date)
    }

    public func closeStrongAlertSurface(at date: Date = Date()) {
        guard !isAppManagedDataResetInProgress else { return }
        guard isStrongAlertPresented,
              let commitment = strongAlertCommitment else { return }
        isStrongAlertPresented = false
        strongAlertNextPresentationDate = date.addingTimeInterval(
            Double(strongAlertRepeatIntervalMinutes) * 60
        )
        let interval = Self.localizedMinuteDuration(strongAlertRepeatIntervalMinutes)
        lastActionMessage = "Strong Alert closed. Protection remains active and will repeat in \(interval)."
        lastActionOccurrence = OccurrenceIdentity(commitment)
        recordActivity(
            .strongAlertClosed,
            actor: .user,
            title: "Strong Alert closed",
            detail: lastActionMessage ?? "Strong Alert closed.",
            commitment: commitment,
            commitmentGroup: strongAlertMergedCommitment,
            at: date
        )
    }

    public func strongAlertTimingText(for commitment: CalendarEvent, at date: Date) -> String {
        guard let startDate = commitment.startDate,
              let endDate = commitment.endDate else {
            return "Timing unavailable"
        }
        guard date >= startDate else {
            return countdownText(for: commitment, at: date)
        }
        guard date < endDate else { return "Commitment ended" }

        let elapsedMinutes = Int(date.timeIntervalSince(startDate) / 60)
        if elapsedMinutes < 1 {
            return "Starting now"
        }
        return "Overdue · started \(Self.localizedMinuteDuration(elapsedMinutes)) ago"
    }

    public func strongAlertProvenanceSources(
        for commitment: CalendarEvent
    ) -> [ProtectionProvenanceSource] {
        let group = strongAlertGroup(containing: commitment) ?? mergedCommitment(containing: commitment)
        return (group?.representations ?? [commitment]).map(provenanceSource(for:))
    }

    public func clearEarlyReminder() {
        guard let earlyReminderCommitment else { return }
        _ = clearEarlyReminder(for: earlyReminderCommitment)
    }

    @discardableResult
    public func clearEarlyReminder(for commitment: CalendarEvent) -> Bool {
        guard !isAppManagedDataResetInProgress else { return false }
        guard isCurrentEarlyReminder(commitment),
              let earlyReminderCommitment else { return false }
        let group = earlyReminderMergedCommitment
        clearedEarlyReminderOccurrences = group?.occurrences ?? [OccurrenceIdentity(earlyReminderCommitment)]
        self.earlyReminderCommitment = nil
        earlyReminderMergedCommitment = nil
        earlyReminderConflictMergedCommitments = []
        earlyReminderConflict = nil
        lastActionMessage = "Early Reminder closed for now. Strong Alert remains active."
        lastActionOccurrence = OccurrenceIdentity(earlyReminderCommitment)
        recordActivity(
            .earlyReminderCleared,
            actor: .user,
            title: "Early Reminder closed",
            detail: lastActionMessage ?? "Early Reminder closed for now.",
            commitment: earlyReminderCommitment,
            commitmentGroup: group
        )
        return true
    }

    private func isCurrentEarlyReminder(_ commitment: CalendarEvent) -> Bool {
        guard let earlyReminderCommitment else { return false }
        return OccurrenceIdentity(earlyReminderCommitment).matches(commitment)
    }

    public func localStartTimeText(for commitment: CalendarEvent) -> String {
        guard let startDate = commitment.startDate else { return "Time unavailable" }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        var text = "\(formatter.string(from: startDate)) local time"

        if let identifier = commitment.timeZoneIdentifier,
           let eventTimeZone = TimeZone(identifier: identifier),
           eventTimeZone.identifier != TimeZone.autoupdatingCurrent.identifier {
            let label = eventTimeZone.abbreviation(for: startDate) ?? identifier
            text += " · event time zone: \(label)"
        }
        return text
    }

    public func countdownText(for commitment: CalendarEvent, at date: Date) -> String {
        guard let startDate = commitment.startDate else { return "Time unavailable" }

        let secondsRemaining = max(0, startDate.timeIntervalSince(date))
        if secondsRemaining < 60 {
            return "Starting in less than a minute"
        }

        let totalMinutes = Int(ceil(secondsRemaining / 60))
        if totalMinutes < 60 {
            return "Starts in \(Self.localizedMinuteDuration(totalMinutes))"
        }
        return "Starts in \(Self.localizedHoursAndMinutes(totalMinutes))"
    }

    private static func localizedMinuteDuration(_ minutes: Int) -> String {
        String(
            AttributedString(
                localized: "^[\(minutes) minute](inflect: true)",
                locale: .autoupdatingCurrent
            ).characters
        )
    }

    private static func localizedHoursAndMinutes(_ totalMinutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(totalMinutes * 60))
            ?? localizedMinuteDuration(totalMinutes)
    }

    private static func clampedEarlyReminderLeadTime(_ minutes: Int) -> Int {
        min(max(minutes, 5), 30)
    }

    private static func clampedStrongAlertRepeatInterval(_ minutes: Int) -> Int {
        min(max(minutes, 1), 5)
    }

    private func endOfLocalDay(for date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        )!
    }

    private func handle(_ commitment: CalendarEvent, at date: Date) -> Bool {
        guard !isAppManagedDataResetInProgress else { return false }
        let endDate = mergedCommitment(containing: commitment)?.endDate ?? commitment.endDate
        guard let endDate, endDate > date else { return false }
        recordDecision(
            .handled,
            for: commitment,
            group: mergedCommitment(containing: commitment),
            message: "Handled for this occurrence. Protection is off until it ends."
        )
        return true
    }

    private func isActionable(_ commitment: CalendarEvent) -> Bool {
        let displayedGroups = [
            strongAlertMergedCommitment,
            earlyReminderMergedCommitment,
            upcomingMergedCommitment
        ].compactMap { $0 } + strongAlertConflictMergedCommitments + earlyReminderConflictMergedCommitments
        return displayedGroups.contains { $0.contains(commitment) }
    }

    private func isStrongAlertActionable(_ commitment: CalendarEvent) -> Bool {
        let displayedGroups = [strongAlertMergedCommitment].compactMap { $0 } +
            strongAlertConflictMergedCommitments
        return displayedGroups.contains { $0.contains(commitment) }
    }

    private func mergedCommitments(from events: [CalendarEvent]) -> [MergedCommitment] {
        var groups: [MergedCommitment] = []

        for event in events {
            guard let startDate = event.startDate,
                  !event.recognizedMeetingLinks.isEmpty else {
                groups.append(makeMergedCommitment(from: [event]))
                continue
            }
            let eventLinks = Set(event.recognizedMeetingLinks.map {
                CalendarEvent.normalizedMeetingLinkKey($0.url)
            })

            if let index = groups.firstIndex(where: { group in
                group.displayEvent.startDate == startDate &&
                    !eventLinks.isDisjoint(with: group.sharedMeetingLinkKeys)
            }) {
                groups[index] = makeMergedCommitment(from: groups[index].representations + [event])
            } else {
                groups.append(makeMergedCommitment(from: [event]))
            }
        }

        return groups.sorted { left, right in
            guard let leftStart = left.displayEvent.startDate,
                  let rightStart = right.displayEvent.startDate else {
                return left.displayEvent.id < right.displayEvent.id
            }
            return leftStart == rightStart
                ? left.displayEvent.id < right.displayEvent.id
                : leftStart < rightStart
        }
    }

    private func makeMergedCommitment(from representations: [CalendarEvent]) -> MergedCommitment {
        let sortedRepresentations = representations.sorted { left, right in
            if left.id != right.id { return left.id < right.id }
            if left.accountID != right.accountID { return left.accountID < right.accountID }
            if left.calendarID != right.calendarID { return left.calendarID < right.calendarID }
            if left.startDate != right.startDate {
                return (left.startDate ?? .distantPast) < (right.startDate ?? .distantPast)
            }
            return (left.meetingDescription ?? "") < (right.meetingDescription ?? "")
        }
        let canonical = sortedRepresentations[0]
        let endDate = sortedRepresentations.compactMap(\.endDate).max() ?? canonical.endDate ?? .distantPast
        let meetingLinks = CalendarEvent.deduplicatedMeetingLinks(
            sortedRepresentations.flatMap(\.recognizedMeetingLinks)
        )
        let meetingDescription = canonical.meetingDescription ?? sortedRepresentations
            .compactMap(\.meetingDescription)
            .first
        let displayEvent = CalendarEvent(
            id: canonical.id,
            title: canonical.title,
            meetingDescription: meetingDescription,
            startDate: canonical.startDate,
            endDate: endDate,
            timeZoneIdentifier: canonical.timeZoneIdentifier,
            isAllDay: canonical.isAllDay,
            isAccepted: canonical.isAccepted,
            calendarID: canonical.calendarID,
            accountID: canonical.accountID,
            recognizedMeetingLinks: meetingLinks,
            eventType: canonical.eventType
        )
        return MergedCommitment(
            representations: sortedRepresentations,
            displayEvent: displayEvent,
            endDate: endDate
        )
    }

    private func conflictGroup(containing commitment: CalendarEvent) -> MergedCommitment? {
        currentMergedCommitments.first { $0.contains(commitment) } ??
            mergedCommitment(containing: commitment)
    }

    private func strongAlertGroup(containing commitment: CalendarEvent) -> MergedCommitment? {
        if let group = strongAlertConflictMergedCommitments.first(where: { $0.contains(commitment) }) {
            return group
        }
        if let group = strongAlertMergedCommitment, group.contains(commitment) {
            return group
        }
        return conflictGroup(containing: commitment)
    }

    private func hasActiveTimeConflict(
        _ left: MergedCommitment,
        _ right: MergedCommitment
    ) -> Bool {
        guard let leftStart = left.displayEvent.startDate,
              let rightStart = right.displayEvent.startDate else {
            return false
        }
        return leftStart < right.endDate && rightStart < left.endDate
    }

    private func conflictGroups(
        for commitment: MergedCommitment,
        among commitments: [MergedCommitment]
    ) -> [MergedCommitment]? {
        guard let anchorIndex = commitments.firstIndex(where: {
            $0.occurrences == commitment.occurrences
        }) else {
            return nil
        }

        var includedIndices = [anchorIndex]
        var nextIndex = 0
        while nextIndex < includedIndices.count {
            let includedCommitment = commitments[includedIndices[nextIndex]]
            for candidateIndex in commitments.indices where !includedIndices.contains(candidateIndex) {
                let candidate = commitments[candidateIndex]
                guard hasActiveTimeConflict(includedCommitment, candidate) else { continue }
                includedIndices.append(candidateIndex)
            }
            nextIndex += 1
        }

        let groups = includedIndices.map { commitments[$0] }
        return groups.count > 1 ? groups : nil
    }

    private func displayedConflictGroups(containing commitment: MergedCommitment) -> [MergedCommitment]? {
        let displayedConflicts = [
            upcomingConflictMergedCommitments,
            earlyReminderConflictMergedCommitments,
            strongAlertConflictMergedCommitments
        ]
        return displayedConflicts.first { groups in
            groups.count > 1 && groups.contains { $0.occurrences == commitment.occurrences }
        }
    }

    private func hasSelectedPrimary(in commitment: MergedCommitment) -> Bool {
        selectedPrimaryOccurrences.contains { selectedOccurrence in
            commitment.occurrences.contains { selectedOccurrence.matches($0) }
        }
    }

    private func areSameStart(_ commitments: [MergedCommitment]) -> Bool {
        let startDates = Set(commitments.compactMap { $0.displayEvent.startDate })
        return commitments.count > 1 && startDates.count == 1
    }

    private func primaryCommitment(for commitments: [MergedCommitment]) -> MergedCommitment? {
        guard !commitments.isEmpty else { return nil }

        if areSameStart(commitments) {
            if let selected = commitments.first(where: { group in
                hasSelectedPrimary(in: group)
            }) {
                return selected
            }
            return nil
        }

        return commitments.min { left, right in
            guard let leftStart = left.displayEvent.startDate,
                  let rightStart = right.displayEvent.startDate else {
                return left.displayEvent.id < right.displayEvent.id
            }
            return leftStart == rightStart
                ? left.displayEvent.id < right.displayEvent.id
                : leftStart < rightStart
        }
    }

    private func publicConflict(
        from commitments: [MergedCommitment],
        primary: MergedCommitment?
    ) -> CommitmentConflict {
        let sortedCommitments = commitments.sorted { left, right in
            guard let leftStart = left.displayEvent.startDate,
                  let rightStart = right.displayEvent.startDate else {
                return left.displayEvent.id < right.displayEvent.id
            }
            return leftStart == rightStart
                ? left.displayEvent.id < right.displayEvent.id
                : leftStart < rightStart
        }
        let identifiers = sortedCommitments.map {
            "\($0.displayEvent.accountID)/\($0.displayEvent.calendarID)/\($0.displayEvent.id)/\($0.displayEvent.startDate?.timeIntervalSince1970 ?? 0)"
        }
        return CommitmentConflict(
            id: identifiers.joined(separator: "|"),
            primaryCommitment: primary?.displayEvent,
            commitments: sortedCommitments.map(\.displayEvent)
        )
    }

    private func mergedCommitment(containing commitment: CalendarEvent) -> MergedCommitment? {
        currentMergedCommitments.first { $0.contains(commitment) } ??
            [strongAlertMergedCommitment, earlyReminderMergedCommitment, upcomingMergedCommitment]
                .compactMap { $0 }
                .first { $0.contains(commitment) }
    }

    private func currentMergedCommitment(
        containing commitment: CalendarEvent,
        at date: Date
    ) -> MergedCommitment? {
        let currentEvents = accountRecords.values
            .flatMap(\.lastFreshEvents)
            .filter { event in
                isEventEligibleForProtection(event) &&
                    (event.endDate ?? .distantPast) > date
            }
        return mergedCommitments(from: currentEvents).first { $0.contains(commitment) }
    }

    private func hasEnabledProtectionWindow(_ event: CalendarEvent) -> Bool {
        guard !event.isAllDay, event.startDate != nil, event.endDate != nil else {
            return false
        }
        return event.eventType != .outOfOffice || isOutOfOfficeProtectionEnabled
    }

    private func isEventEligibleForProtection(_ event: CalendarEvent) -> Bool {
        event.isAccepted && hasEnabledProtectionWindow(event)
    }

    private func isUpcoming(_ commitment: MergedCommitment, at date: Date) -> Bool {
        guard let startDate = commitment.displayEvent.startDate else { return false }
        return startDate > date
    }

    private func isProtectionAvailable(for commitment: MergedCommitment, at date: Date) -> Bool {
        guard !commitment.representations.contains(where: isDecisionActive) else {
            return false
        }
        let allRepresentationsSuppressed = commitment.representations.allSatisfy {
            suppressedPostStartAcceptanceOccurrences.contains(OccurrenceIdentity($0)) ||
                suppressedUntrackedPastOccurrences.contains(OccurrenceIdentity($0))
        }
        return !allRepresentationsSuppressed && !isSnoozed(commitment, at: date)
    }

    private func isSnoozed(_ commitment: MergedCommitment, at date: Date) -> Bool {
        guard let snoozedUntil, date < snoozedUntil else { return false }
        return !snoozedOccurrences.isDisjoint(with: commitment.occurrences)
    }

    private func isCleared(_ commitment: MergedCommitment) -> Bool {
        !clearedEarlyReminderOccurrences.isDisjoint(with: commitment.occurrences)
    }

    private func reconcileCalendarSnapshot(
        _ events: [CalendarEvent],
        at currentDate: Date,
        isCompleteSnapshot: Bool = true
    ) {
        guard !isAppManagedDataResetInProgress else { return }
        updateTemporaryLifecycleState(at: currentDate)
        recordAcceptanceMutations(
            in: events,
            at: currentDate,
            pruneMissingOccurrences: isCompleteSnapshot
        )
        let eligibleEvents = events
            .filter { event in
                guard isEventEligibleForProtection(event),
                      event.startDate != nil,
                      let endDate = event.endDate else {
                    return false
                }
                return endDate > currentDate
            }
            .sorted { left, right in
                guard let leftStart = left.startDate,
                      let rightStart = right.startDate else {
                    return left.id < right.id
                }
                return leftStart == rightStart ? left.id < right.id : leftStart < rightStart
            }

        // A successful calendar refresh replaces the visible snapshot. This is what removes
        // canceled commitments and updates changed occurrences, links, times, and time zones.
        updateLocalState(for: eligibleEvents, at: currentDate)
        saveConfiguration()
        let commitments = mergedCommitments(from: eligibleEvents)
        currentMergedCommitments = commitments
        let nextCommitment = commitments.first {
            isUpcoming($0, at: currentDate)
        }
        let protectedCommitments = isPaused(at: currentDate)
            ? []
            : commitments.filter {
                isProtectionAvailable(for: $0, at: currentDate)
            }
        let upcomingProtectedCommitments = protectedCommitments.filter {
            isUpcoming($0, at: currentDate)
        }
        let nextProtectedCandidate = upcomingProtectedCommitments.first
        let nextConflictGroups = nextProtectedCandidate.flatMap {
            conflictGroups(for: $0, among: upcomingProtectedCommitments)
        }
        let nextConflictPrimary = nextConflictGroups.flatMap { primaryCommitment(for: $0) }
        let nextProtectedCommitment = nextConflictPrimary ?? nextProtectedCandidate
        let activeProtectedCandidate = protectedCommitments.first {
            !isUpcoming($0, at: currentDate)
        }
        let activeConflictGroups = activeProtectedCandidate.flatMap {
            conflictGroups(for: $0, among: protectedCommitments)
        }
        let activeConflictPrimary = activeConflictGroups.flatMap { primaryCommitment(for: $0) }
        let activeProtectedCommitment = activeConflictPrimary ?? activeProtectedCandidate
        upcomingMergedCommitment = nextCommitment
        upcomingCommitment = nextCommitment?.displayEvent
        upcomingConflictMergedCommitments = nextConflictGroups ?? []
        upcomingConflict = nextConflictGroups.map {
            publicConflict(from: $0, primary: nextConflictPrimary)
        }
        if let nextProtectedCommitment, !isCleared(nextProtectedCommitment) {
            clearedEarlyReminderOccurrences = []
        }

        if let activeProtectedCommitment {
            updateStrongAlert(
                for: activeProtectedCommitment,
                conflictGroups: activeConflictGroups ?? [activeProtectedCommitment],
                at: currentDate
            )
        } else {
            clearStrongAlertState()
        }

        if isPaused(at: currentDate) {
            earlyReminderMergedCommitment = nil
            earlyReminderCommitment = nil
            earlyReminderConflictMergedCommitments = []
            earlyReminderConflict = nil
            return
        }

        guard isEarlyReminderEnabled else {
            earlyReminderMergedCommitment = nil
            earlyReminderCommitment = nil
            earlyReminderConflictMergedCommitments = []
            earlyReminderConflict = nil
            return
        }

        guard let nextProtectedCommitment,
              let startDate = nextProtectedCommitment.displayEvent.startDate,
              currentDate >= startDate.addingTimeInterval(-Double(earlyReminderLeadTimeMinutes) * 60),
              !isCleared(nextProtectedCommitment) else {
            earlyReminderMergedCommitment = nil
            earlyReminderCommitment = nil
            earlyReminderConflictMergedCommitments = []
            earlyReminderConflict = nil
            return
        }

        let isExistingEarlyReminder = earlyReminderMergedCommitment?.sharesOccurrence(
            with: nextProtectedCommitment
        ) == true
        guard isExistingEarlyReminder ||
            startDate.timeIntervalSince(currentDate) >= Self.minimumEarlyReminderPresentationLeadTime
        else {
            earlyReminderMergedCommitment = nil
            earlyReminderCommitment = nil
            earlyReminderConflictMergedCommitments = []
            earlyReminderConflict = nil
            return
        }

        let isNewEarlyReminder = !isExistingEarlyReminder
        earlyReminderMergedCommitment = nextProtectedCommitment
        earlyReminderCommitment = nextProtectedCommitment.displayEvent
        earlyReminderConflictMergedCommitments = nextConflictGroups ?? []
        earlyReminderConflict = nextConflictGroups.map {
            publicConflict(from: $0, primary: nextConflictPrimary)
        }
        if isNewEarlyReminder {
            recordActivity(
                .earlyReminderShown,
                actor: .system,
                title: "Early Reminder shown",
                detail: "Protection is active for \(nextProtectedCommitment.displayEvent.title).",
                commitment: nextProtectedCommitment.displayEvent,
                commitmentGroup: nextProtectedCommitment,
                at: currentDate
            )
        }
    }

    private func updateTemporaryLifecycleState(at currentDate: Date) {
        var didChange = false
        if let pauseUntil, pauseUntil <= currentDate {
            self.pauseUntil = nil
            stateStore.removeObject(forKey: Self.pauseUntilKey)
            recordActivity(
                .pauseEnded,
                actor: .system,
                title: "Protection resumed",
                detail: "The pause expired and protection resumed.",
                at: currentDate
            )
            didChange = true
        }
        if didChange {
            saveConfiguration()
        }
    }

    private func recordAcceptanceMutations(
        in events: [CalendarEvent],
        at currentDate: Date,
        pruneMissingOccurrences: Bool = true
    ) {
        let trackedEvents = events.filter { event in
            guard hasEnabledProtectionWindow(event),
                  let endDate = event.endDate else {
                return false
            }
            return endDate > currentDate
        }
        let trackedOccurrences = Set(trackedEvents.map(OccurrenceIdentity.init))
        var didChange = false

        if pruneMissingOccurrences {
            let retainedUnacceptedOccurrences = observedUnacceptedOccurrences.intersection(trackedOccurrences)
            if retainedUnacceptedOccurrences != observedUnacceptedOccurrences {
                observedUnacceptedOccurrences = retainedUnacceptedOccurrences
                didChange = true
            }
            let retainedSuppressedOccurrences = suppressedPostStartAcceptanceOccurrences.intersection(trackedOccurrences)
            if retainedSuppressedOccurrences != suppressedPostStartAcceptanceOccurrences {
                suppressedPostStartAcceptanceOccurrences = retainedSuppressedOccurrences
                didChange = true
            }
            let retainedUntrackedPastOccurrences = suppressedUntrackedPastOccurrences.intersection(trackedOccurrences)
            if retainedUntrackedPastOccurrences != suppressedUntrackedPastOccurrences {
                suppressedUntrackedPastOccurrences = retainedUntrackedPastOccurrences
                didChange = true
            }
        }

        for event in trackedEvents {
            let occurrence = OccurrenceIdentity(event)
            if event.isAccepted {
                if let startDate = event.startDate,
                   startDate <= currentDate,
                   observedUnacceptedOccurrences.contains(occurrence),
                   suppressedPostStartAcceptanceOccurrences.insert(occurrence).inserted {
                    didChange = true
                }
                if observedUnacceptedOccurrences.remove(occurrence) != nil {
                    didChange = true
                }
            } else {
                if observedUnacceptedOccurrences.insert(occurrence).inserted {
                    didChange = true
                }
                if suppressedPostStartAcceptanceOccurrences.remove(occurrence) != nil {
                    didChange = true
                }
            }
        }

        if didChange {
            saveConfiguration()
        }
    }

    private func suppressUntrackedPastOccurrences(
        in events: [CalendarEvent],
        previouslyTracked: Set<OccurrenceIdentity>,
        at date: Date
    ) {
        var didChange = false
        for event in events {
            guard let startDate = event.startDate,
                  startDate <= date,
                  !previouslyTracked.contains(OccurrenceIdentity(event)),
                  suppressedUntrackedPastOccurrences.insert(OccurrenceIdentity(event)).inserted else {
                continue
            }
            didChange = true
        }

        if didChange {
            saveConfiguration()
        }
    }

    private func recordDecision(
        _ decision: CommitmentProtectionDecision,
        for commitment: CalendarEvent,
        group: MergedCommitment? = nil,
        message: String
    ) {
        guard !isAppManagedDataResetInProgress else { return }
        let effectiveGroup = group ?? mergedCommitment(containing: commitment)
        let occurrence = OccurrenceIdentity(commitment)
        decisionOccurrence = OccurrenceIdentity(commitment)
        decisionOccurrences = effectiveGroup?.occurrences ?? [occurrence]
        for occurrence in decisionOccurrences {
            localDecisions[occurrence] = decision
        }
        currentCommitmentDecision = decision
        decisionCommitment = effectiveGroup?.displayEvent ?? commitment
        if let earlyReminderMergedCommitment,
           (effectiveGroup?.sharesOccurrence(with: earlyReminderMergedCommitment) == true ||
            effectiveGroup.map { group in
                earlyReminderConflictMergedCommitments.contains { $0.sharesOccurrence(with: group) }
            } == true) {
            self.earlyReminderMergedCommitment = nil
            self.earlyReminderCommitment = nil
        }
        if let strongAlertMergedCommitment,
           (effectiveGroup?.sharesOccurrence(with: strongAlertMergedCommitment) == true ||
            (areSameStart(strongAlertConflictMergedCommitments) &&
                effectiveGroup.map { group in
                    strongAlertConflictMergedCommitments.contains { $0.sharesOccurrence(with: group) }
                } == true)) {
            clearStrongAlertState()
        }
        lastActionMessage = message
        lastActionOccurrence = occurrence
        let activityKind: ProtectionActivityKind
        switch decision {
        case .handled:
            activityKind = .handled
        case .dismissed:
            activityKind = .dismissed
        case .joined:
            activityKind = .joined
        }
        recordActivity(
            activityKind,
            actor: .user,
            title: activityKind.activityTitle,
            detail: message,
            commitment: effectiveGroup?.displayEvent ?? commitment,
            commitmentGroup: effectiveGroup
        )

        if !currentMergedCommitments.isEmpty {
            let snapshot = accountRecords.values.flatMap { $0.lastFreshEvents }
            reconcileCalendarSnapshot(snapshot, at: now())
        }
    }

    private func updateLocalState(for eligibleEvents: [CalendarEvent], at date: Date) {
        if let lastActionOccurrence,
           !eligibleEvents.contains(where: { lastActionOccurrence.matches($0) }) {
            clearLastActionMessage()
        }

        let eligibleOccurrences = Set(eligibleEvents.map(OccurrenceIdentity.init))
        let retainedDecisions = localDecisions.filter { entry in
            eligibleOccurrences.contains { entry.key.matches($0) }
        }
        if retainedDecisions.count != localDecisions.count {
            localDecisions = retainedDecisions
            saveConfiguration()
        }
        let retainedPrimaryOccurrences = selectedPrimaryOccurrences.filter { selectedOccurrence in
            eligibleOccurrences.contains { selectedOccurrence.matches($0) }
        }
        if retainedPrimaryOccurrences != selectedPrimaryOccurrences {
            selectedPrimaryOccurrences = retainedPrimaryOccurrences
            saveConfiguration()
        }

        let activeDecisionOccurrences = decisionOccurrences.isEmpty
            ? decisionOccurrence.map { [$0] } ?? []
            : Array(decisionOccurrences)
        if !activeDecisionOccurrences.isEmpty {
            let retainedOccurrences = Set(activeDecisionOccurrences.filter { storedOccurrence in
                eligibleOccurrences.contains { storedOccurrence.matches($0) }
            })
            if let matchingCommitment = eligibleEvents.first(where: { event in
                retainedOccurrences.contains { occurrence in occurrence.matches(event) }
            }), !retainedOccurrences.isEmpty {
                decisionCommitment = matchingCommitment
                decisionOccurrences = retainedOccurrences
                if matchingCommitment.endDate ?? .distantPast <= date {
                    clearCurrentDecisionProjection()
                    saveConfiguration()
                }
            } else {
                clearCurrentDecisionProjection()
                saveConfiguration()
            }
        }

        let activeSnoozedOccurrences = snoozedOccurrences.isEmpty
            ? snoozedOccurrence.map { [$0] } ?? []
            : Array(snoozedOccurrences)
        if !activeSnoozedOccurrences.isEmpty,
           !eligibleEvents.contains(where: { event in
               activeSnoozedOccurrences.contains { $0.matches(event) }
           }) {
            self.snoozedOccurrence = nil
            snoozedOccurrences = []
            snoozedUntil = nil
            saveConfiguration()
        }
    }

    private func isSnoozed(_ commitment: CalendarEvent, at date: Date) -> Bool {
        guard let snoozedUntil, date < snoozedUntil else {
            return false
        }
        if !snoozedOccurrences.isEmpty {
            return snoozedOccurrences.contains { $0.matches(commitment) }
        }
        return snoozedOccurrence?.matches(commitment) == true
    }

    private func isDecisionActive(_ commitment: CalendarEvent) -> Bool {
        isDecisionActive(for: OccurrenceIdentity(commitment))
    }

    private func isDecisionActive(for occurrence: OccurrenceIdentity) -> Bool {
        if localDecisions.keys.contains(where: { $0.matches(occurrence) }) {
            return true
        }
        guard currentCommitmentDecision != nil else { return false }
        if !decisionOccurrences.isEmpty {
            return decisionOccurrences.contains { $0.matches(occurrence) }
        }
        return decisionOccurrence?.matches(occurrence) == true
    }

    private func isUpcoming(_ commitment: CalendarEvent, at date: Date) -> Bool {
        guard let startDate = commitment.startDate else { return false }
        return startDate > date
    }

    private func isProtectionAvailable(for commitment: CalendarEvent, at date: Date) -> Bool {
        !isDecisionActive(commitment) &&
            !isSnoozed(commitment, at: date) &&
            !suppressedPostStartAcceptanceOccurrences.contains(OccurrenceIdentity(commitment)) &&
            !suppressedUntrackedPastOccurrences.contains(OccurrenceIdentity(commitment))
    }

    private func restoreDisplayedProtection(for commitment: CalendarEvent, at date: Date) {
        let group = mergedCommitment(containing: commitment) ?? makeMergedCommitment(from: [commitment])
        restoreDisplayedProtection(for: group, at: date)
    }

    private func restoreDisplayedProtection(for commitment: MergedCommitment, at date: Date) {
        guard let startDate = commitment.displayEvent.startDate,
              commitment.endDate > date,
              !isSnoozed(commitment, at: date) else {
            return
        }

        if startDate > date {
            guard isEarlyReminderEnabled else { return }
            guard date >= startDate.addingTimeInterval(-Double(earlyReminderLeadTimeMinutes) * 60),
                  startDate.timeIntervalSince(date) >= Self.minimumEarlyReminderPresentationLeadTime,
                  !isCleared(commitment),
                  !isSnoozed(commitment, at: date) else {
                return
            }
            let conflict = conflictGroups(for: commitment, among: currentMergedCommitments)
            let primary = conflict.flatMap { primaryCommitment(for: $0) } ?? commitment
            upcomingMergedCommitment = primary
            upcomingCommitment = primary.displayEvent
            earlyReminderMergedCommitment = primary
            earlyReminderCommitment = primary.displayEvent
            earlyReminderConflictMergedCommitments = conflict ?? []
            earlyReminderConflict = conflict.map {
                publicConflict(
                    from: $0,
                    primary: primaryCommitment(for: $0)
                )
            }
            recordActivity(
                .earlyReminderShown,
                actor: .system,
                title: "Early Reminder shown",
                detail: "Protection is active for \(primary.displayEvent.title).",
                commitment: primary.displayEvent,
                commitmentGroup: primary,
                at: date
            )
            return
        }

        let conflict = conflictGroups(for: commitment, among: currentMergedCommitments)
        let primary = conflict.flatMap { primaryCommitment(for: $0) } ?? commitment
        updateStrongAlert(
            for: primary,
            conflictGroups: conflict ?? [primary],
            at: date
        )
    }

    private func updateStrongAlert(for commitment: MergedCommitment, at date: Date) {
        updateStrongAlert(for: commitment, conflictGroups: [commitment], at: date)
    }

    private func updateStrongAlert(
        for commitment: MergedCommitment,
        conflictGroups: [MergedCommitment],
        at date: Date
    ) {
        if commitment.representations.contains(where: isDecisionActive) {
            clearStrongAlertState()
            return
        }

        let conflictOccurrences = conflictGroups.reduce(into: Set<OccurrenceIdentity>()) { occurrences, group in
            occurrences.formUnion(group.occurrences)
        }
        if strongAlertOccurrences.isEmpty || strongAlertOccurrences != conflictOccurrences {
            strongAlertOccurrences = conflictOccurrences
            strongAlertNextPresentationDate = date
            isStrongAlertPresented = false
        }

        strongAlertMergedCommitment = commitment
        strongAlertCommitment = commitment.displayEvent
        strongAlertConflictMergedCommitments = conflictGroups
        let selectedConflictPrimary = conflictGroups.first(where: { hasSelectedPrimary(in: $0) })
        strongAlertConflict = conflictGroups.count > 1
            ? publicConflict(from: conflictGroups, primary: areSameStart(conflictGroups) &&
                selectedConflictPrimary == nil
                ? nil
                : commitment)
            : nil
        guard let nextPresentationDate = strongAlertNextPresentationDate,
              date >= nextPresentationDate else {
            return
        }

        let wasPresented = isStrongAlertPresented
        if !wasPresented {
            clearLastActionMessage()
        }
        isStrongAlertPresented = true
        strongAlertNextPresentationDate = date.addingTimeInterval(
            Double(strongAlertRepeatIntervalMinutes) * 60
        )
        let activityKind: ProtectionActivityKind = wasPresented ? .strongAlertRepeated : .strongAlertShown
        recordActivity(
            activityKind,
            actor: .system,
            title: activityKind.activityTitle,
            detail: wasPresented
                ? "\(commitment.displayEvent.title) is still awaiting an explicit action."
                : "\(commitment.displayEvent.title) needs attention now.",
            commitment: commitment.displayEvent,
            commitmentGroup: commitment,
            at: date
        )
    }

    private func monitoringSleepIntervalNanoseconds() -> UInt64 {
        let currentDate = now()
        var interval = 30.0
        if let startDate = upcomingCommitment?.startDate,
           startDate > currentDate {
            interval = min(interval, startDate.timeIntervalSince(currentDate))
        }
        if let nextPresentationDate = strongAlertNextPresentationDate,
           nextPresentationDate > currentDate {
            interval = min(interval, nextPresentationDate.timeIntervalSince(currentDate))
        }
        if let snoozedUntil,
           snoozedUntil > currentDate {
            interval = min(interval, snoozedUntil.timeIntervalSince(currentDate))
        }
        if let pauseUntil,
           pauseUntil > currentDate {
            interval = min(interval, pauseUntil.timeIntervalSince(currentDate))
        }
        return UInt64(max(interval, 0.25) * 1_000_000_000)
    }

    private func coverageHealth(for record: AccountRecord, at date: Date) -> CoverageHealth {
        if let persistenceError = persistenceCoverageErrors[record.connection.account.id] {
            return .unavailable(persistenceError)
        }
        switch record.connectionState {
        case .connected:
            guard record.hasConfiguredProtection else {
                return .noCoverage
            }
            guard let lastSuccessfulRefreshAt = record.lastSuccessfulRefreshAt else {
                return .checking
            }
            return date.timeIntervalSince(lastSuccessfulRefreshAt) <= Self.coverageFreshnessInterval
                ? .fresh
                : .stale
        case .reconnectRequired:
            return .reconnectRequired
        case .failed(let message):
            if let lastSuccessfulRefreshAt = record.lastSuccessfulRefreshAt,
               date.timeIntervalSince(lastSuccessfulRefreshAt) > Self.coverageFreshnessInterval {
                return .stale
            }
            return .unavailable(message)
        case .connecting:
            return .unavailable("Coverage is still connecting.")
        case .notConnected:
            return .unavailable("The account is not connected.")
        }
    }

    private var hasConfiguredProtection: Bool {
        accountRecords.values.contains(where: \.hasConfiguredProtection)
    }

    private var coverageEvaluationDate: Date {
        max(lastEvaluatedCoverageDate ?? .distantPast, now())
    }

    private func markPendingCalendarsAsNewlySelected() {
        for record in accountRecords.values where !record.confirmedCalendarIDs.isEmpty {
            let pendingCalendarIDs = record.selectedCalendarIDs.subtracting(record.confirmedCalendarIDs)
            for calendarID in pendingCalendarIDs {
                newlySelectedCalendars.insert(
                    CalendarSelectionIdentity(
                        calendarID: calendarID,
                        accountID: record.connection.account.id
                    )
                )
            }
        }
    }

    private func syncCoverageAndActiveAccountProjection() {
        accountCoverages = accountRecords.values
            .map { record in
                AccountCoverage(
                    account: record.connection.account,
                    calendars: record.connection.calendars,
                    selectedCalendarIDs: record.selectedCalendarIDs,
                    confirmedCalendarIDs: record.confirmedCalendarIDs,
                    isProtectionConfirmed: record.isProtectionConfirmed,
                    connectionState: record.connectionState,
                    health: coverageHealth(for: record, at: coverageEvaluationDate),
                    lastSuccessfulRefreshAt: record.lastSuccessfulRefreshAt
                )
            }
            .sorted {
                $0.account.protectionDisplayLabel.localizedCaseInsensitiveCompare(
                    $1.account.protectionDisplayLabel
                ) == .orderedAscending
            }

        guard let activeAccountID, let record = accountRecords[activeAccountID] else {
            connectedAccount = nil
            availableCalendars = []
            selectedCalendarIDs = []
            connectionState = accountConnectionError.map(ConnectionState.failed) ?? .notConnected
            isProtectionConfirmed = false
            return
        }

        connectedAccount = record.connection.account
        availableCalendars = record.connection.calendars
        selectedCalendarIDs = record.selectedCalendarIDs
        connectionState = record.connectionState
        isProtectionConfirmed = record.isProtectionConfirmed
        isEarlyReminderUnverified = earlyReminderMergedCommitment.map(isUnverified) == true ||
            earlyReminderConflictMergedCommitments.contains(where: isUnverified)
        isStrongAlertUnverified = strongAlertMergedCommitment.map(isUnverified) == true ||
            strongAlertConflictMergedCommitments.contains(where: isUnverified)
    }

    private func isUnverified(_ commitment: MergedCommitment) -> Bool {
        commitment.representations.contains(where: isUnverified)
    }

    private func isUnverified(_ commitment: CalendarEvent) -> Bool {
        if unverifiedAccountIDs.contains(commitment.accountID) {
            return true
        }
        guard let record = accountRecords[commitment.accountID] else { return false }
        return coverageHealth(for: record, at: coverageEvaluationDate) == .stale
    }

    private func account(for commitment: CalendarEvent) -> GoogleAccount? {
        accountRecords[commitment.accountID]?.connection.account
    }

    private func restoredFreshEvents(
        from savedAccount: SavedAccountConfiguration,
        accountID: String,
        calendars: [CalendarOption]
    ) -> [CalendarEvent] {
        guard savedAccount.lastFreshEventsSchemaVersion == Self.freshEventsSchemaVersion else {
            return []
        }
        let confirmedCalendarIDs = savedAccount.resolvedConfirmedCalendarIDs
        return savedAccount.lastFreshEvents.filter { event in
            event.accountID == accountID &&
                confirmedCalendarIDs.contains(event.calendarID) &&
                calendars.contains { calendar in calendar.id == event.calendarID }
        }
    }

    private func protectedAccountIDs() throws -> [String] {
        if let encryptedGoogleVault {
            return encryptedGoogleVault.accountIDs()
        }
        if recoverEncryptedGoogleStorage != nil {
            throw unavailableProtectedStorageError()
        }
        return volatileGoogleDataStore.accountIDs
    }

    private func loadProtectedData(
        _ kind: EncryptedGoogleVaultRecordKind,
        accountID: String
    ) throws -> Data? {
        if let encryptedGoogleVault {
            do {
                return try encryptedGoogleVault.loadData(as: kind, for: accountID)
            } catch EncryptedGoogleVaultError.accountNotFound {
                return nil
            }
        }
        if recoverEncryptedGoogleStorage != nil {
            throw unavailableProtectedStorageError()
        }
        return volatileGoogleDataStore.load(kind, accountID: accountID)
    }

    private func storeProtectedData(
        _ data: Data,
        kind: EncryptedGoogleVaultRecordKind,
        accountID: String
    ) throws {
        if let encryptedGoogleVault {
            try encryptedGoogleVault.storeData(data, as: kind, for: accountID)
        } else if recoverEncryptedGoogleStorage != nil {
            throw unavailableProtectedStorageError()
        } else {
            volatileGoogleDataStore.store(data, kind: kind, accountID: accountID)
        }
    }

    private func removeProtectedRecord(
        _ kind: EncryptedGoogleVaultRecordKind,
        accountID: String
    ) throws {
        if let encryptedGoogleVault {
            do {
                try encryptedGoogleVault.removeRecord(kind, for: accountID)
            } catch EncryptedGoogleVaultError.accountNotFound {
                return
            }
        } else if recoverEncryptedGoogleStorage != nil {
            throw unavailableProtectedStorageError()
        } else {
            volatileGoogleDataStore.remove(kind, accountID: accountID)
        }
    }

    private func removeProtectedAccount(_ accountID: String) throws {
        if let encryptedGoogleVault {
            do {
                try encryptedGoogleVault.removeAccount(accountID)
            } catch EncryptedGoogleVaultError.accountNotFound {
                return
            }
        } else if recoverEncryptedGoogleStorage != nil {
            throw unavailableProtectedStorageError()
        } else {
            volatileGoogleDataStore.removeAccount(accountID)
        }
    }

    private func unavailableProtectedStorageError() -> ProtectionPersistenceError {
        .protectedStorageUnavailable(
            encryptedStorageError ??
                EncryptedGoogleVaultError.secureEnclaveUnavailable.localizedDescription
        )
    }

    private func loadConfiguration() -> SavedConfiguration? {
        if let legacyData = legacyConfigurationData,
           let legacy = try? JSONDecoder().decode(SavedConfiguration.self, from: legacyData) {
            didUseLegacyConfiguration = true
            // The old OAuth identity was an OIDC subject. The new Calendar-only
            // identity is the primary CalendarList id (normally the account email).
            // Preserve only user-selected configuration; legacy Google snapshots,
            // decisions, and activity remain plaintext and are intentionally dropped.
            let migratedAccounts = legacy.accounts.compactMap { saved -> SavedAccountConfiguration? in
                let primaryCalendarID = saved.account.email.trimmingCharacters(in: .whitespacesAndNewlines)
                let migratedID = primaryCalendarID.isEmpty ? saved.account.id : primaryCalendarID
                guard !migratedID.isEmpty else { return nil }
                let selectedIDs = Set(saved.selectedCalendarIDs)
                let selectedCalendars = saved.calendars.compactMap { calendar -> CalendarOption? in
                    guard selectedIDs.contains(calendar.id) else { return nil }
                    return CalendarOption(id: calendar.id, name: calendar.name, accountID: migratedID)
                }
                return SavedAccountConfiguration(
                    account: GoogleAccount(id: migratedID, email: migratedID, displayName: ""),
                    calendars: selectedCalendars,
                    selectedCalendarIDs: saved.selectedCalendarIDs,
                    isProtectionConfirmed: saved.isProtectionConfirmed,
                    confirmedCalendarIDs: saved.resolvedConfirmedCalendarIDs.sorted(),
                    lastSuccessfulRefreshAt: nil,
                    lastFreshEvents: [],
                    lastFreshEventsSchemaVersion: nil
                )
            }
            activityLog = []
            return SavedConfiguration(
                accounts: migratedAccounts,
                decisionOccurrence: nil,
                decisionOccurrences: [],
                decisions: [],
                currentCommitmentDecision: nil,
                selectedPrimaryOccurrences: [],
                snoozedOccurrence: nil,
                snoozedOccurrences: [],
                snoozedUntil: nil,
                pauseUntil: pauseUntil,
                observedUnacceptedOccurrences: [],
                suppressedPostStartAcceptanceOccurrences: [],
                suppressedUntrackedPastOccurrences: []
            )
        }

        let accountIDs: [String]
        do {
            accountIDs = try protectedAccountIDs()
        } catch {
            handleProtectedStorageError(error)
            return nil
        }

        var savedConfigurations: [SavedConfiguration] = []
        for accountID in accountIDs {
            let configuration: SavedConfiguration
            do {
                guard let configurationData = try loadProtectedData(.configuration, accountID: accountID) else {
                    // OAuth writes the protected credential before account choices. A process
                    // interruption in that narrow window must still leave a visible account
                    // that the user can reconnect, disconnect, or remove.
                    savedConfigurations.append(emptySavedConfiguration(accountID: accountID))
                    continue
                }
                configuration = try decodeProtectedRecord(
                    SavedConfiguration.self,
                    from: configurationData,
                    kind: .configuration
                )
                guard configuration.accounts.count == 1,
                      configuration.accounts.first?.account.id == accountID else {
                    throw EncryptedGoogleVaultError.recordCorrupted(.configuration)
                }
            } catch {
                markProtectedAccountStorageFailure(accountID, error: error)
                savedConfigurations.append(emptySavedConfiguration(accountID: accountID))
                continue
            }

            guard var savedAccount = configuration.accounts.first else { continue }
            do {
                if let snapshotData = try loadProtectedData(.eventSnapshot, accountID: accountID) {
                    let snapshot = try decodeProtectedRecord(
                        SavedEventSnapshot.self,
                        from: snapshotData,
                        kind: .eventSnapshot
                    )
                    let expiration = snapshot.capturedAt.addingTimeInterval(Self.eventRetentionInterval)
                    if snapshot.schemaVersion == Self.freshEventsSchemaVersion, expiration > now() {
                        let horizon = now().addingTimeInterval(Self.eventRetentionInterval)
                        let confirmedCalendarIDs = savedAccount.resolvedConfirmedCalendarIDs
                        let retainedEvents = snapshot.events.filter { event in
                            event.accountID == accountID &&
                                confirmedCalendarIDs.contains(event.calendarID) &&
                                isEventEligibleForProtection(event) &&
                                (event.endDate ?? .distantPast) > now() &&
                                (event.startDate ?? .distantFuture) <= horizon
                        }
                        savedAccount = SavedAccountConfiguration(
                            account: savedAccount.account,
                            calendars: savedAccount.calendars,
                            selectedCalendarIDs: savedAccount.selectedCalendarIDs,
                            isProtectionConfirmed: savedAccount.isProtectionConfirmed,
                            confirmedCalendarIDs: savedAccount.confirmedCalendarIDs,
                            lastSuccessfulRefreshAt: snapshot.lastSuccessfulRefreshAt,
                            lastFreshEvents: retainedEvents,
                            lastFreshEventsSchemaVersion: snapshot.schemaVersion
                        )
                    } else {
                        try removeProtectedRecord(.eventSnapshot, accountID: accountID)
                    }
                }
            } catch {
                markProtectedAccountStorageFailure(accountID, error: error)
                savedAccount = SavedAccountConfiguration(
                    account: savedAccount.account,
                    calendars: savedAccount.calendars,
                    selectedCalendarIDs: savedAccount.selectedCalendarIDs,
                    isProtectionConfirmed: savedAccount.isProtectionConfirmed,
                    confirmedCalendarIDs: savedAccount.confirmedCalendarIDs,
                    lastSuccessfulRefreshAt: nil,
                    lastFreshEvents: [],
                    lastFreshEventsSchemaVersion: nil
                )
            }

            savedConfigurations.append(
                SavedConfiguration(
                    accounts: [savedAccount],
                    decisionOccurrence: configuration.decisionOccurrence,
                    decisionOccurrences: configuration.decisionOccurrences,
                    decisions: configuration.decisions,
                    currentCommitmentDecision: configuration.currentCommitmentDecision,
                    selectedPrimaryOccurrences: configuration.selectedPrimaryOccurrences,
                    snoozedOccurrence: configuration.snoozedOccurrence,
                    snoozedOccurrences: configuration.snoozedOccurrences,
                    snoozedUntil: configuration.snoozedUntil,
                    pauseUntil: nil,
                    observedUnacceptedOccurrences: configuration.observedUnacceptedOccurrences,
                    suppressedPostStartAcceptanceOccurrences: configuration.suppressedPostStartAcceptanceOccurrences,
                    suppressedUntrackedPastOccurrences: configuration.suppressedUntrackedPastOccurrences
                )
            )
        }
        guard !savedConfigurations.isEmpty else { return nil }
        return mergeSavedConfigurations(savedConfigurations)
    }

    private func emptySavedConfiguration(accountID: String) -> SavedConfiguration {
        SavedConfiguration(
            accounts: [
                SavedAccountConfiguration(
                    account: GoogleAccount(id: accountID, email: accountID, displayName: ""),
                    calendars: [],
                    selectedCalendarIDs: [],
                    isProtectionConfirmed: false,
                    confirmedCalendarIDs: [],
                    lastSuccessfulRefreshAt: nil,
                    lastFreshEvents: [],
                    lastFreshEventsSchemaVersion: nil
                )
            ],
            decisionOccurrence: nil,
            decisionOccurrences: [],
            decisions: [],
            currentCommitmentDecision: nil,
            selectedPrimaryOccurrences: [],
            snoozedOccurrence: nil,
            snoozedOccurrences: [],
            snoozedUntil: nil,
            pauseUntil: nil,
            observedUnacceptedOccurrences: [],
            suppressedPostStartAcceptanceOccurrences: [],
            suppressedUntrackedPastOccurrences: []
        )
    }

    private func decodeProtectedRecord<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        kind: EncryptedGoogleVaultRecordKind
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw EncryptedGoogleVaultError.decodingFailed(kind)
        }
    }

    private func mergeSavedConfigurations(_ configurations: [SavedConfiguration]) -> SavedConfiguration {
        SavedConfiguration(
            accounts: configurations.flatMap(\.accounts).sorted { $0.account.id < $1.account.id },
            decisionOccurrence: configurations.compactMap(\.decisionOccurrence).first,
            decisionOccurrences: configurations.flatMap(\.decisionOccurrences),
            decisions: configurations.flatMap(\.decisions),
            currentCommitmentDecision: configurations.compactMap(\.currentCommitmentDecision).first,
            selectedPrimaryOccurrences: configurations.flatMap(\.selectedPrimaryOccurrences),
            snoozedOccurrence: configurations.compactMap(\.snoozedOccurrence).first,
            snoozedOccurrences: configurations.flatMap(\.snoozedOccurrences),
            snoozedUntil: configurations.compactMap(\.snoozedUntil).max(),
            pauseUntil: pauseUntil,
            observedUnacceptedOccurrences: configurations.flatMap(\.observedUnacceptedOccurrences),
            suppressedPostStartAcceptanceOccurrences: configurations.flatMap(\.suppressedPostStartAcceptanceOccurrences),
            suppressedUntrackedPastOccurrences: configurations.flatMap(\.suppressedUntrackedPastOccurrences)
        )
    }

    private func loadActivityLog() -> [ProtectionActivity] {
        if didUseLegacyConfiguration {
            return []
        }
        let accountIDs: [String]
        do {
            accountIDs = try protectedAccountIDs()
        } catch {
            handleProtectedStorageError(error)
            return []
        }

        let protectedAccountIDSet = Set(accountIDs)
        var activitiesByID: [UUID: ProtectionActivity] = [:]
        for accountID in accountIDs {
            do {
                guard let data = try loadProtectedData(.activity, accountID: accountID) else { continue }
                let activities = try decodeProtectedRecord(
                    [ProtectionActivity].self,
                    from: data,
                    kind: .activity
                )
                let retainedActivities = activities.filter { activity in
                    isActivityFromSameLocalDay(activity, as: now()) &&
                        activity.protectedSourceAccountIDs.isSubset(of: protectedAccountIDSet)
                }
                if retainedActivities.count != activities.count {
                    if retainedActivities.isEmpty {
                        try removeProtectedRecord(.activity, accountID: accountID)
                    } else {
                        let retainedData = try JSONEncoder().encode(retainedActivities)
                        try storeProtectedData(retainedData, kind: .activity, accountID: accountID)
                    }
                }
                for activity in retainedActivities {
                    activitiesByID[activity.id] = activity
                }
            } catch {
                markProtectedAccountStorageFailure(accountID, error: error)
            }
        }
        return globallyBoundedActivities(
            activitiesByID.values.sorted { $0.occurredAt > $1.occurredAt }
        )
    }

    private func restoreLocalState(from configuration: SavedConfiguration) {
        decisionOccurrence = configuration.decisionOccurrence?.identity
        currentCommitmentDecision = configuration.currentCommitmentDecision
        decisionOccurrences = Set(configuration.decisionOccurrences.map(\.identity))
        if decisionOccurrences.isEmpty, let decisionOccurrence {
            decisionOccurrences = [decisionOccurrence]
        }
        localDecisions = Dictionary(
            uniqueKeysWithValues: configuration.decisions.map {
                ($0.occurrence.identity, $0.decision)
            }
        )
        if localDecisions.isEmpty, let currentCommitmentDecision {
            for occurrence in decisionOccurrences {
                localDecisions[occurrence] = currentCommitmentDecision
            }
        }
        selectedPrimaryOccurrences = Set(configuration.selectedPrimaryOccurrences.map(\.identity))
        snoozedOccurrence = configuration.snoozedOccurrence?.identity
        snoozedUntil = configuration.snoozedUntil
        snoozedOccurrences = Set(configuration.snoozedOccurrences.map(\.identity))
        if snoozedOccurrences.isEmpty, let snoozedOccurrence {
            snoozedOccurrences = [snoozedOccurrence]
        }
        pauseUntil = configuration.pauseUntil ?? pauseUntil
        observedUnacceptedOccurrences = Set(configuration.observedUnacceptedOccurrences.map(\.identity))
        suppressedPostStartAcceptanceOccurrences = Set(
            configuration.suppressedPostStartAcceptanceOccurrences.map(\.identity)
        )
        suppressedUntrackedPastOccurrences = Set(
            configuration.suppressedUntrackedPastOccurrences.map(\.identity)
        )
    }

    private func saveConfiguration() {
        guard !isAppManagedDataResetInProgress else { return }
        guard !accountRecords.isEmpty else {
            stateStore.removeObject(forKey: Self.stateKey)
            return
        }

        var didPersistEveryAccount = true
        for accountID in accountRecords.keys.sorted() {
            guard let record = accountRecords[accountID] else { continue }
            guard !corruptedProtectedAccountIDs.contains(accountID) else {
                didPersistEveryAccount = false
                continue
            }
            do {
                let configuration = savedConfiguration(for: accountID, record: record)
                let configurationData = try JSONEncoder().encode(configuration)
                try storeProtectedData(configurationData, kind: .configuration, accountID: accountID)
                try saveEventSnapshot(for: accountID, record: record)
                persistenceCoverageErrors[accountID] = nil
            } catch {
                didPersistEveryAccount = false
                let safeErrorDescription = Self.privacySafeProtectedStorageErrorDescription(error)
                let message = "Protected calendar data could not be saved. \(safeErrorDescription)"
                persistenceCoverageErrors[accountID] = message
                handleProtectedStorageError(error)
            }
        }
        if didPersistEveryAccount {
            stateStore.removeObject(forKey: Self.stateKey)
            stateStore.removeObject(forKey: Self.activityLogKey)
            if activityPersistenceErrorAccountIDs.isEmpty, !requiresEncryptedStorageReset {
                encryptedStorageError = nil
            }
        }
    }

    private func savedConfiguration(
        for accountID: String,
        record: AccountRecord
    ) -> SavedConfiguration {
        let referenceDate = now()
        let horizon = referenceDate.addingTimeInterval(Self.eventRetentionInterval)
        let hasRetainedSnapshot = record.lastSuccessfulRefreshAt.map {
            $0.addingTimeInterval(Self.eventRetentionInterval) > referenceDate
        } == true
        let retainedOccurrences = Set(
            hasRetainedSnapshot
                ? record.lastFreshEvents.compactMap { event -> OccurrenceIdentity? in
                    guard event.accountID == accountID,
                          record.confirmedCalendarIDs.contains(event.calendarID),
                          isEventEligibleForProtection(event),
                          (event.endDate ?? .distantPast) > referenceDate,
                          (event.startDate ?? .distantFuture) <= horizon else {
                        return nil
                    }
                    return OccurrenceIdentity(event)
                }
                : []
        )

        func belongsToAccount(_ occurrence: OccurrenceIdentity) -> Bool {
            occurrence.accountID == accountID && retainedOccurrences.contains(occurrence)
        }

        let accountDecisionOccurrence = decisionOccurrence.flatMap {
            belongsToAccount($0) ? $0 : nil
        }
        let selectedCalendars = record.selectedCalendars.map {
            CalendarOption(id: $0.id, name: $0.name, accountID: accountID)
        }
        let savedAccount = SavedAccountConfiguration(
            account: GoogleAccount(
                id: record.connection.account.id,
                email: record.connection.account.email,
                displayName: ""
            ),
            calendars: selectedCalendars,
            selectedCalendarIDs: record.selectedCalendarIDs.sorted(),
            isProtectionConfirmed: record.isProtectionConfirmed,
            confirmedCalendarIDs: record.confirmedCalendarIDs.sorted(),
            lastSuccessfulRefreshAt: nil,
            lastFreshEvents: [],
            lastFreshEventsSchemaVersion: nil
        )
        return SavedConfiguration(
            accounts: [savedAccount],
            decisionOccurrence: accountDecisionOccurrence.map(SavedOccurrence.init),
            decisionOccurrences: decisionOccurrences.filter(belongsToAccount).map(SavedOccurrence.init),
            decisions: localDecisions.compactMap { occurrence, decision in
                guard belongsToAccount(occurrence) else { return nil }
                return SavedDecision(occurrence: SavedOccurrence(occurrence), decision: decision)
            },
            currentCommitmentDecision: accountDecisionOccurrence == nil ? nil : currentCommitmentDecision,
            selectedPrimaryOccurrences: selectedPrimaryOccurrences
                .filter(belongsToAccount)
                .map(SavedOccurrence.init),
            snoozedOccurrence: snoozedOccurrence.flatMap {
                belongsToAccount($0) ? SavedOccurrence($0) : nil
            },
            snoozedOccurrences: snoozedOccurrences.filter(belongsToAccount).map(SavedOccurrence.init),
            snoozedUntil: snoozedOccurrence.map(belongsToAccount) == true ? snoozedUntil : nil,
            pauseUntil: nil,
            observedUnacceptedOccurrences: observedUnacceptedOccurrences
                .filter(belongsToAccount)
                .map(SavedOccurrence.init),
            suppressedPostStartAcceptanceOccurrences: suppressedPostStartAcceptanceOccurrences
                .filter(belongsToAccount)
                .map(SavedOccurrence.init),
            suppressedUntrackedPastOccurrences: suppressedUntrackedPastOccurrences
                .filter(belongsToAccount)
                .map(SavedOccurrence.init)
        )
    }

    private func saveEventSnapshot(for accountID: String, record: AccountRecord) throws {
        guard let lastSuccessfulRefreshAt = record.lastSuccessfulRefreshAt,
              lastSuccessfulRefreshAt.addingTimeInterval(Self.eventRetentionInterval) > now() else {
            try removeProtectedRecord(.eventSnapshot, accountID: accountID)
            return
        }

        let horizon = now().addingTimeInterval(Self.eventRetentionInterval)
        let retainedEvents = record.lastFreshEvents.filter { event in
            event.accountID == accountID &&
                record.confirmedCalendarIDs.contains(event.calendarID) &&
                isEventEligibleForProtection(event) &&
                (event.endDate ?? .distantPast) > now() &&
                (event.startDate ?? .distantFuture) <= horizon
        }
        guard retainedEvents.count <= Self.maximumPersistedEventsPerAccount else {
            try removeProtectedRecord(.eventSnapshot, accountID: accountID)
            throw ProtectionPersistenceError.eventSnapshotLimitExceeded
        }
        let snapshot = SavedEventSnapshot(
            schemaVersion: Self.freshEventsSchemaVersion,
            capturedAt: lastSuccessfulRefreshAt,
            lastSuccessfulRefreshAt: lastSuccessfulRefreshAt,
            events: retainedEvents
        )
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= Self.maximumEventSnapshotBytes else {
            try removeProtectedRecord(.eventSnapshot, accountID: accountID)
            throw ProtectionPersistenceError.eventSnapshotLimitExceeded
        }
        try storeProtectedData(data, kind: .eventSnapshot, accountID: accountID)
    }

    private nonisolated static func privacySafeProtectedStorageErrorDescription(_ error: Error) -> String {
        if let persistenceError = error as? ProtectionPersistenceError {
            switch persistenceError {
            case .eventSnapshotLimitExceeded:
                return ProtectionPersistenceError.eventSnapshotLimitExceededDescription
            case .protectedStorageUnavailable:
                return "Protected storage operation failed."
            }
        }
        guard let vaultError = error as? EncryptedGoogleVaultError else {
            return "Protected storage operation failed."
        }
        switch vaultError {
        case .secureEnclaveUnavailable:
            return "Secure Enclave is unavailable on this Mac. Protected Google data cannot be stored."
        case .invalidApplicationIdentifier:
            return "The application identifier cannot be used for protected storage."
        case .invalidAccountIdentifier:
            return "The Google account identifier is invalid."
        case .accountNotFound:
            return "The protected Google account was not found."
        case .keyMaterialCorrupted:
            return "The Secure Enclave key material cannot be restored."
        case .indexCorrupted:
            return "The protected account index is damaged or cannot be authenticated."
        case .accountKeyCorrupted:
            return "The protected account key is damaged or cannot be authenticated."
        case .recordCorrupted:
            return "The protected account record is damaged or cannot be authenticated."
        case .encodingFailed:
            return "The account record could not be encoded for protected storage."
        case .decodingFailed:
            return "The protected account record could not be decoded."
        case .storageFailed:
            return "Protected storage operation failed."
        }
    }

    private nonisolated static func privacySafeUserFacingErrorDescription(_ error: Error) -> String {
        guard error is EncryptedGoogleVaultError else {
            return error.localizedDescription
        }
        return privacySafeProtectedStorageErrorDescription(error)
    }

    private func handleProtectedStorageError(_ error: Error) {
        encryptedStorageError = Self.privacySafeProtectedStorageErrorDescription(error)
        guard let vaultError = error as? EncryptedGoogleVaultError else { return }
        switch vaultError {
        case .keyMaterialCorrupted,
             .indexCorrupted,
             .accountKeyCorrupted,
             .recordCorrupted,
             .decodingFailed:
            requiresEncryptedStorageReset = true
        case .secureEnclaveUnavailable,
             .invalidApplicationIdentifier,
             .invalidAccountIdentifier,
             .accountNotFound,
             .encodingFailed,
             .storageFailed:
            break
        }
    }

    private func markProtectedAccountStorageFailure(_ accountID: String, error: Error) {
        let safeErrorDescription = Self.privacySafeProtectedStorageErrorDescription(error)
        let message = "Protected Google data for \(accountID) could not be read. \(safeErrorDescription)"
        persistenceCoverageErrors[accountID] = message
        if let vaultError = error as? EncryptedGoogleVaultError {
            switch vaultError {
            case .keyMaterialCorrupted,
                 .indexCorrupted,
                 .accountKeyCorrupted,
                 .recordCorrupted,
                 .decodingFailed:
                corruptedProtectedAccountIDs.insert(accountID)
            case .secureEnclaveUnavailable,
                 .invalidApplicationIdentifier,
                 .invalidAccountIdentifier,
                 .accountNotFound,
                 .encodingFailed,
                 .storageFailed:
                break
            }
        }
        handleProtectedStorageError(error)
    }

    private func isPermanentlyUnreadableCredential(_ error: Error) -> Bool {
        guard let vaultError = error as? EncryptedGoogleVaultError else { return false }
        switch vaultError {
        case .recordCorrupted(.credential),
             .decodingFailed(.credential),
             .accountKeyCorrupted:
            return true
        case .secureEnclaveUnavailable,
             .invalidApplicationIdentifier,
             .invalidAccountIdentifier,
             .accountNotFound,
             .keyMaterialCorrupted,
             .indexCorrupted,
             .recordCorrupted,
             .encodingFailed,
             .decodingFailed,
             .storageFailed:
            return false
        }
    }

    private func invalidateRefreshes() {
        refreshGeneration &+= 1
        refreshCoordinator.invalidate()
    }

    private func beginRefresh() -> Int {
        refreshGeneration &+= 1
        return refreshGeneration
    }

    private func reconcileCachedProtectionAfterConfigurationChange(at date: Date) {
        let cachedEvents = accountRecords.values
            .filter {
                $0.connectionState != .reconnectRequired &&
                    $0.hasConfiguredProtection &&
                    !corruptedProtectedAccountIDs.contains($0.connection.account.id) &&
                    !$0.confirmedCalendarIDs.isEmpty
            }
            .flatMap { record in
                record.lastFreshEvents.filter { event in
                    record.confirmedCalendarIDs.contains(event.calendarID)
                }
            }
        // `lastFreshEvents` intentionally stores only eligible accepted events, so
        // this is not a complete acceptance snapshot. Preserve unaccepted-event
        // history used to suppress commitments accepted after they have started.
        reconcileCalendarSnapshot(cachedEvents, at: date, isCompleteSnapshot: false)
    }

    private func clearLocalState(forAccountID accountID: String) {
        func belongsToAccount(_ occurrence: OccurrenceIdentity) -> Bool {
            occurrence.accountID == accountID
        }

        localDecisions = localDecisions.filter { !belongsToAccount($0.key) }
        selectedPrimaryOccurrences = selectedPrimaryOccurrences.filter { !belongsToAccount($0) }
        decisionOccurrences = decisionOccurrences.filter { !belongsToAccount($0) }
        snoozedOccurrences = snoozedOccurrences.filter { !belongsToAccount($0) }
        observedUnacceptedOccurrences = observedUnacceptedOccurrences.filter { !belongsToAccount($0) }
        suppressedPostStartAcceptanceOccurrences = suppressedPostStartAcceptanceOccurrences
            .filter { !belongsToAccount($0) }
        suppressedUntrackedPastOccurrences = suppressedUntrackedPastOccurrences
            .filter { !belongsToAccount($0) }
        strongAlertOccurrences = strongAlertOccurrences.filter { !belongsToAccount($0) }
        clearedEarlyReminderOccurrences = clearedEarlyReminderOccurrences
            .filter { !belongsToAccount($0) }
        newlySelectedCalendars = newlySelectedCalendars.filter { $0.accountID != accountID }
        accountsRequiringUntrackedPastSuppression.remove(accountID)

        if decisionOccurrence.map(belongsToAccount) == true || decisionCommitment?.accountID == accountID {
            clearCurrentDecisionProjection()
        }
        if snoozedOccurrence.map(belongsToAccount) == true {
            snoozedOccurrence = nil
            snoozedUntil = nil
        }
        if lastActionOccurrence.map(belongsToAccount) == true {
            clearLastActionMessage()
        }
        if meetingLinkOpenFailure.map({ belongsToAccount($0.occurrence) }) == true {
            meetingLinkOpenFailure = nil
        }
    }

    private func clearProtectionState() {
        clearDisplayedProtectionState()
        currentMergedCommitments = []
        selectedPrimaryOccurrences = []
        clearedEarlyReminderOccurrences = []
        snoozedOccurrence = nil
        snoozedOccurrences = []
        snoozedUntil = nil
        pauseUntil = nil
        stateStore.removeObject(forKey: Self.pauseUntilKey)
        observedUnacceptedOccurrences = []
        suppressedPostStartAcceptanceOccurrences = []
        suppressedUntrackedPastOccurrences = []
        clearAllLocalDecisions()
        clearLastActionMessage()
    }

    private func clearDisplayedProtectionState() {
        upcomingCommitment = nil
        upcomingMergedCommitment = nil
        upcomingConflict = nil
        upcomingConflictMergedCommitments = []
        earlyReminderCommitment = nil
        earlyReminderMergedCommitment = nil
        earlyReminderConflictMergedCommitments = []
        earlyReminderConflict = nil
        isEarlyReminderUnverified = false
        clearStrongAlertState()
    }

    private func clearStrongAlertState() {
        isStrongAlertPresented = false
        strongAlertCommitment = nil
        strongAlertMergedCommitment = nil
        strongAlertConflictMergedCommitments = []
        strongAlertConflict = nil
        strongAlertOccurrences = []
        strongAlertNextPresentationDate = nil
    }

    private func clearLocalDecision() {
        let occurrences = decisionOccurrences.isEmpty
            ? decisionOccurrence.map { [$0] } ?? []
            : Array(decisionOccurrences)
        for storedOccurrence in Array(localDecisions.keys)
            where occurrences.contains(where: { $0.matches(storedOccurrence) }) {
            localDecisions.removeValue(forKey: storedOccurrence)
        }
        clearCurrentDecisionProjection()
    }

    private func clearAllLocalDecisions() {
        localDecisions = [:]
        clearCurrentDecisionProjection()
    }

    private func clearCurrentDecisionProjection() {
        currentCommitmentDecision = nil
        decisionCommitment = nil
        decisionOccurrence = nil
        decisionOccurrences = []
    }

    private func clearLastActionMessage() {
        lastActionMessage = nil
        lastActionOccurrence = nil
    }

    @discardableResult
    private func pruneActivityLog(at date: Date) -> Bool {
        let retainedActivities = activityLog.filter {
            isActivityFromSameLocalDay($0, as: date)
        }
        guard retainedActivities != activityLog else { return false }
        activityLog = retainedActivities
        return true
    }

    private func migrateLegacyActivityCalendarContext(with events: [CalendarEvent]) {
        guard !activityLog.isEmpty else { return }

        var didChange = false
        let migratedActivities = activityLog.map { activity in
            guard activity.calendarID == nil,
                  let accountID = activity.accountID,
                  let calendar = calendarForLegacyActivity(activity, accountID: accountID, events: events) else {
                return activity
            }
            didChange = true
            return activity.withCalendarContext(calendarID: calendar.id, calendarName: calendar.name)
        }
        guard didChange else { return }

        activityLog = migratedActivities
        saveActivityLog()
    }

    private func calendarForLegacyActivity(
        _ activity: ProtectionActivity,
        accountID: String,
        events: [CalendarEvent]
    ) -> (id: String, name: String?)? {
        if let commitmentID = activity.commitmentID {
            guard let commitmentStartDate = activity.commitmentStartDate else {
                return nil
            }
            let matchingCommitments = events.filter { event in
                event.id == commitmentID &&
                    event.accountID == accountID &&
                    event.startDate == commitmentStartDate
            }
            if matchingCommitments.count == 1,
               let commitment = matchingCommitments.first {
                return (
                    id: commitment.calendarID,
                    name: calendarName(for: commitment)
                )
            }
            return nil
        }

        guard activity.kind == .configurationChanged,
              activity.title == "Calendar selection changed",
              let record = accountRecords[accountID] else {
            return nil
        }

        let prefixes = ["Monitoring ", "Stopped monitoring "]
        guard let prefix = prefixes.first(where: { activity.detail.hasPrefix($0) }),
              activity.detail.hasSuffix(".") else {
            return nil
        }
        let calendarName = String(activity.detail.dropFirst(prefix.count).dropLast())
        let matchingCalendars = record.connection.calendars.filter { $0.name == calendarName }
        guard matchingCalendars.count == 1,
              let calendar = matchingCalendars.first else {
            return nil
        }
        return (id: calendar.id, name: calendar.name)
    }

    private func recordActivity(
        _ kind: ProtectionActivityKind,
        actor: ProtectionActivityActor,
        title: String,
        detail: String,
        commitment: CalendarEvent? = nil,
        commitmentGroup: MergedCommitment? = nil,
        account: GoogleAccount? = nil,
        calendar: CalendarOption? = nil,
        at date: Date? = nil
    ) {
        guard !isAppManagedDataResetInProgress else { return }
        let occurredAt = date ?? now()
        let activityAccount = account ?? commitment.flatMap { self.account(for: $0) } ??
            calendar.flatMap { accountRecords[$0.accountID]?.connection.account } ?? connectedAccount
        let activityCalendarID = calendar?.id ?? commitment?.calendarID
        let activityCalendarName = calendar?.name ?? commitment.flatMap { calendarName(for: $0) }
        let provenanceSources: [ProtectionProvenanceSource]? = if let commitmentGroup {
            commitmentGroup.representations.map(provenanceSource(for:))
        } else if let commitment {
            [provenanceSource(for: commitment)]
        } else if let activityAccount, let calendar {
            [provenanceSource(account: activityAccount, calendar: calendar)]
        } else if let activityAccount {
            [provenanceSource(account: activityAccount)]
        } else {
            nil
        }
        let sourceAccountIDs = Set(
            (commitmentGroup?.representations.map(\.accountID) ?? []) +
                (activityAccount.map { [$0.id] } ?? [])
        ).sorted()
        _ = pruneActivityLog(at: occurredAt)
        activityLog.insert(
            ProtectionActivity(
                occurredAt: occurredAt,
                actor: actor,
                kind: kind,
                title: title,
                detail: detail,
                commitmentTitle: commitment?.title,
                commitmentID: commitment?.id,
                commitmentStartDate: commitment?.startDate,
                accountID: activityAccount?.id,
                accountEmail: activityAccount?.email,
                calendarID: activityCalendarID,
                calendarName: activityCalendarName,
                sourceAccountIDs: sourceAccountIDs,
                provenanceSources: provenanceSources
            ),
            at: 0
        )
        activityLog = globallyBoundedActivities(activityLog)
        saveActivityLog()
        saveConfiguration()
    }

    private func calendarName(for commitment: CalendarEvent) -> String? {
        accountRecords[commitment.accountID]?.connection.calendars
            .first(where: { $0.id == commitment.calendarID })?.name
    }

    private func provenanceSource(for commitment: CalendarEvent) -> ProtectionProvenanceSource {
        let account = account(for: commitment)
        return ProtectionProvenanceSource(
            accountID: commitment.accountID,
            accountEmail: account?.email ?? "",
            accountDisplayName: account?.displayName ?? "",
            calendarID: commitment.calendarID,
            calendarName: calendarName(for: commitment)
        )
    }

    private func provenanceSource(
        account: GoogleAccount,
        calendar: CalendarOption
    ) -> ProtectionProvenanceSource {
        ProtectionProvenanceSource(
            accountID: account.id,
            accountEmail: account.email,
            accountDisplayName: account.displayName,
            calendarID: calendar.id,
            calendarName: calendar.name
        )
    }

    private func provenanceSource(account: GoogleAccount) -> ProtectionProvenanceSource {
        ProtectionProvenanceSource(
            accountID: account.id,
            accountEmail: account.email,
            accountDisplayName: account.displayName
        )
    }

    private func saveActivityLog() {
        guard !isAppManagedDataResetInProgress else { return }
        var currentDayActivities = globallyBoundedActivities(
            activityLog.filter { isActivityFromSameLocalDay($0, as: now()) }
        )
        let payloads: [String: Data]
        do {
            var candidatePayloads = try encodedActivityPayloads(for: currentDayActivities)
            while candidatePayloads.values.reduce(0, { $0 + $1.count }) >
                Self.maximumActivityBytesAcrossAccounts,
                !currentDayActivities.isEmpty {
                currentDayActivities.removeLast()
                candidatePayloads = try encodedActivityPayloads(for: currentDayActivities)
            }
            payloads = candidatePayloads
        } catch {
            activityPersistenceErrorAccountIDs.formUnion(accountRecords.keys)
            handleProtectedStorageError(error)
            return
        }
        activityLog = currentDayActivities
        for accountID in accountRecords.keys.sorted() {
            guard !corruptedProtectedAccountIDs.contains(accountID) else {
                activityPersistenceErrorAccountIDs.insert(accountID)
                continue
            }
            do {
                if let data = payloads[accountID] {
                    try storeProtectedData(data, kind: .activity, accountID: accountID)
                } else {
                    try removeProtectedRecord(.activity, accountID: accountID)
                }
                activityPersistenceErrorAccountIDs.remove(accountID)
            } catch {
                activityPersistenceErrorAccountIDs.insert(accountID)
                handleProtectedStorageError(error)
            }
        }
    }

    private func encodedActivityPayloads(
        for activities: [ProtectionActivity]
    ) throws -> [String: Data] {
        var payloads: [String: Data] = [:]
        for accountID in accountRecords.keys.sorted() {
            let accountActivities = activities.filter { activity in
                activity.accountID == accountID ||
                    (activity.accountID == nil && accountID == activeAccountID)
            }
            do {
                let data = try JSONEncoder().encode(accountActivities)
                if !accountActivities.isEmpty {
                    payloads[accountID] = data
                }
            } catch {
                throw EncryptedGoogleVaultError.encodingFailed
            }
        }
        return payloads
    }

    private func globallyBoundedActivities(
        _ activities: [ProtectionActivity]
    ) -> [ProtectionActivity] {
        var bounded = Array(activities.prefix(Self.maximumActivitiesAcrossAccounts))
        while !bounded.isEmpty {
            guard let data = try? JSONEncoder().encode(bounded) else {
                return []
            }
            guard data.count > Self.maximumActivityBytesAcrossAccounts else {
                return bounded
            }
            bounded.removeLast()
        }
        return []
    }

    private func isActivityFromSameLocalDay(_ activity: ProtectionActivity, as date: Date) -> Bool {
        Calendar.current.isDate(activity.occurredAt, inSameDayAs: date)
    }
}

private enum ProtectionFlowError: LocalizedError {
    case restoredAccountMismatch
    case localCredentialMissingForRevocation

    var errorDescription: String? {
        switch self {
        case .restoredAccountMismatch:
            return "Google returned a different account than the one that was saved. Reconnect the original account."
        case .localCredentialMissingForRevocation:
            return "The local Google credential is missing, so remote access could not be revoked. Remove the account locally, then review Google Account access."
        }
    }
}

private enum ProtectionPersistenceError: LocalizedError {
    case eventSnapshotLimitExceeded
    case protectedStorageUnavailable(String)

    static let eventSnapshotLimitExceededDescription =
        "The next 24 hours contain more calendar data than Meeting Incoming can safely retain as Protected Calendar Data. Narrow the Monitored Calendars, then retry."

    var errorDescription: String? {
        switch self {
        case .eventSnapshotLimitExceeded:
            return Self.eventSnapshotLimitExceededDescription
        case .protectedStorageUnavailable(let message):
            return message
        }
    }
}
