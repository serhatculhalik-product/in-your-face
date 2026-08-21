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

public struct GoogleCalendarConnection: Codable, Equatable, Sendable {
    public let account: GoogleAccount
    public let calendars: [CalendarOption]

    public init(account: GoogleAccount, calendars: [CalendarOption]) {
        self.account = account
        self.calendars = calendars
    }
}

public enum CalendarEventType: String, Codable, Equatable, Sendable {
    case outOfOffice
}

public struct CalendarEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date?
    public let endDate: Date?
    public let timeZoneIdentifier: String?
    public let isAllDay: Bool
    public let isAccepted: Bool
    public let calendarID: String
    public let accountID: String
    public let recognizedMeetingLink: URL?
    public let eventType: CalendarEventType?

    public init(
        id: String,
        title: String,
        startDate: Date?,
        endDate: Date?,
        timeZoneIdentifier: String?,
        isAllDay: Bool,
        isAccepted: Bool,
        calendarID: String,
        accountID: String,
        recognizedMeetingLink: URL? = nil,
        eventType: CalendarEventType? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isAllDay = isAllDay
        self.isAccepted = isAccepted
        self.calendarID = calendarID
        self.accountID = accountID
        self.recognizedMeetingLink = recognizedMeetingLink
        self.eventType = eventType
    }

    public var isProtectionTrackable: Bool {
        eventType != .outOfOffice && !isAllDay && startDate != nil && endDate != nil
    }

    public var isEligibleForProtection: Bool {
        isAccepted && isProtectionTrackable
    }
}

public protocol GoogleCalendarConnecting: Sendable {
    func connect() async throws -> GoogleCalendarConnection
    func restore(accountID: String) async throws -> GoogleCalendarConnection?
    func disconnect(accountID: String) throws
    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent]
}

@MainActor
public protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func enable() throws
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
            return "Joined commitment"
        case .handled:
            return "Commitment handled"
        case .dismissed:
            return "Reminders stopped"
        case .strongAlertShown:
            return "Strong Alert shown"
        case .strongAlertRepeated:
            return "Strong Alert repeated"
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
        calendarName: String? = nil
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
            calendarName: calendarName
        )
    }
}

public enum ConnectionState: Equatable, Sendable {
    case notConnected
    case connecting
    case connected
    case failed(String)
}

public enum CoverageHealth: Equatable, Sendable {
    case noCoverage
    case fresh
    case stale
    case unavailable(String)
}

public struct AccountCoverage: Equatable, Identifiable, Sendable {
    public let account: GoogleAccount
    public let calendars: [CalendarOption]
    public let selectedCalendarIDs: Set<String>
    public let isProtectionConfirmed: Bool
    public let connectionState: ConnectionState
    public let health: CoverageHealth
    public let lastSuccessfulRefreshAt: Date?

    public var id: String { account.id }

    public init(
        account: GoogleAccount,
        calendars: [CalendarOption],
        selectedCalendarIDs: Set<String>,
        isProtectionConfirmed: Bool = false,
        connectionState: ConnectionState,
        health: CoverageHealth,
        lastSuccessfulRefreshAt: Date?
    ) {
        self.account = account
        self.calendars = calendars
        self.selectedCalendarIDs = selectedCalendarIDs
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

@MainActor
public final class CommitmentProtectionFlow: ObservableObject {
    @Published public private(set) var connectedAccount: GoogleAccount?
    @Published public private(set) var availableCalendars: [CalendarOption] = []
    @Published public private(set) var selectedCalendarIDs: Set<String> = []
    @Published public private(set) var connectionState: ConnectionState = .notConnected
    @Published public private(set) var isRestoringConnection = false
    @Published public private(set) var isProtectionConfirmed = false
    @Published public private(set) var isBlockingAvailable = true
    @Published public private(set) var isTestAlertPresented = false
    @Published public private(set) var isStrongAlertPresented = false
    @Published public private(set) var isLaunchAtLoginEnabled = false
    @Published public private(set) var upcomingCommitment: CalendarEvent?
    @Published public private(set) var earlyReminderCommitment: CalendarEvent?
    @Published public private(set) var strongAlertCommitment: CalendarEvent?
    @Published public private(set) var pauseUntil: Date?
    @Published public private(set) var activityLog: [ProtectionActivity] = []
    @Published public private(set) var currentCommitmentDecision: CommitmentProtectionDecision?
    @Published public private(set) var decisionCommitment: CalendarEvent?
    @Published public private(set) var lastActionMessage: String?
    @Published public private(set) var isEarlyReminderEnabled: Bool
    @Published public private(set) var isBlockingModeEnabled: Bool
    @Published public private(set) var earlyReminderLeadTimeMinutes: Int
    @Published public private(set) var strongAlertRepeatIntervalMinutes: Int
    @Published public private(set) var accountCoverages: [AccountCoverage] = []
    @Published public private(set) var isEarlyReminderUnverified = false
    @Published public private(set) var isStrongAlertUnverified = false

    private let calendarConnector: any GoogleCalendarConnecting
    private let launchAtLogin: any LaunchAtLoginControlling
    private let stateStore: UserDefaults
    private let now: () -> Date
    private static let stateKey = "commitment-protection.configuration"
    private static let activityLogKey = "commitment-protection.activity-log"
    private static let earlyReminderEnabledKey = "commitment-protection.early-reminder-enabled"
    private static let blockingModeEnabledKey = "commitment-protection.blocking-mode-enabled"
    private static let earlyReminderLeadTimeKey = "commitment-protection.early-reminder-lead-time"
    private static let strongAlertRepeatIntervalKey = "commitment-protection.strong-alert-repeat-interval"
    private static let freshEventsSchemaVersion = 1
    private static let coverageFreshnessInterval: TimeInterval = 15 * 60
    private struct AccountRecord {
        var connection: GoogleCalendarConnection
        var selectedCalendarIDs: Set<String>
        var isProtectionConfirmed: Bool
        var connectionState: ConnectionState
        var lastSuccessfulRefreshAt: Date?
        var lastFreshEvents: [CalendarEvent]

        var selectedCalendars: [CalendarOption] {
            connection.calendars.filter { selectedCalendarIDs.contains($0.id) }
        }
    }

    private var accountRecords: [String: AccountRecord] = [:]
    private var activeAccountID: String?
    private var unverifiedAccountIDs: Set<String> = []
    private var lastConnectionError: String?
    private var lastEvaluatedCoverageDate: Date?
    private var clearedEarlyReminderEventID: String?
    private var clearedEarlyReminderEventStartDate: Date?
    private var clearedEarlyReminderEventCalendarID: String?
    private var clearedEarlyReminderEventAccountID: String?
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

    private struct CalendarSelectionIdentity: Hashable, Sendable {
        let calendarID: String
        let accountID: String
    }

    private var snoozedOccurrence: OccurrenceIdentity?
    private var snoozedUntil: Date?
    private var observedUnacceptedOccurrences: Set<OccurrenceIdentity> = []
    private var suppressedPostStartAcceptanceOccurrences: Set<OccurrenceIdentity> = []
    private var suppressedUntrackedPastOccurrences: Set<OccurrenceIdentity> = []
    private var decisionOccurrence: OccurrenceIdentity?
    private var lastActionOccurrence: OccurrenceIdentity?
    private var strongAlertEventID: String?
    private var strongAlertEventStartDate: Date?
    private var strongAlertEventCalendarID: String?
    private var strongAlertEventAccountID: String?
    private var strongAlertNextPresentationDate: Date?
    private var newlySelectedCalendars: Set<CalendarSelectionIdentity> = []
    private var shouldSuppressUntrackedPastOccurrencesOnNextRefresh = false
    private var monitoringTask: Task<Void, Never>?
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

    private struct SavedAccountConfiguration: Codable {
        let account: GoogleAccount
        let calendars: [CalendarOption]
        let selectedCalendarIDs: [String]
        let isProtectionConfirmed: Bool
        let lastSuccessfulRefreshAt: Date?
        let lastFreshEvents: [CalendarEvent]
        let lastFreshEventsSchemaVersion: Int?
    }

    private struct SavedConfiguration: Codable {
        let accounts: [SavedAccountConfiguration]
        let decisionOccurrence: SavedOccurrence?
        let currentCommitmentDecision: CommitmentProtectionDecision?
        let snoozedOccurrence: SavedOccurrence?
        let snoozedUntil: Date?
        let pauseUntil: Date?
        let observedUnacceptedOccurrences: [SavedOccurrence]
        let suppressedPostStartAcceptanceOccurrences: [SavedOccurrence]
        let suppressedUntrackedPastOccurrences: [SavedOccurrence]

        private enum CodingKeys: String, CodingKey {
            case accounts
            case decisionOccurrence
            case currentCommitmentDecision
            case snoozedOccurrence
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
            currentCommitmentDecision: CommitmentProtectionDecision?,
            snoozedOccurrence: SavedOccurrence?,
            snoozedUntil: Date?,
            pauseUntil: Date?,
            observedUnacceptedOccurrences: [SavedOccurrence],
            suppressedPostStartAcceptanceOccurrences: [SavedOccurrence],
            suppressedUntrackedPastOccurrences: [SavedOccurrence]
        ) {
            self.accounts = accounts
            self.decisionOccurrence = decisionOccurrence
            self.currentCommitmentDecision = currentCommitmentDecision
            self.snoozedOccurrence = snoozedOccurrence
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
                        lastSuccessfulRefreshAt: nil,
                        lastFreshEvents: [],
                        lastFreshEventsSchemaVersion: nil
                    )
                ]
            }
            decisionOccurrence = try container.decodeIfPresent(SavedOccurrence.self, forKey: .decisionOccurrence)
            currentCommitmentDecision = try container.decodeIfPresent(
                CommitmentProtectionDecision.self,
                forKey: .currentCommitmentDecision
            )
            snoozedOccurrence = try container.decodeIfPresent(SavedOccurrence.self, forKey: .snoozedOccurrence)
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

    public init(
        calendarConnector: any GoogleCalendarConnecting,
        launchAtLogin: any LaunchAtLoginControlling,
        stateStore: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.calendarConnector = calendarConnector
        self.launchAtLogin = launchAtLogin
        self.stateStore = stateStore
        self.now = now
        isEarlyReminderEnabled = stateStore.object(forKey: Self.earlyReminderEnabledKey) as? Bool ?? true
        isBlockingModeEnabled = stateStore.object(forKey: Self.blockingModeEnabledKey) as? Bool ?? false
        let savedLeadTime = stateStore.integer(forKey: Self.earlyReminderLeadTimeKey)
        earlyReminderLeadTimeMinutes = savedLeadTime == 0
            ? 10
            : Self.clampedEarlyReminderLeadTime(savedLeadTime)
        let savedRepeatInterval = stateStore.integer(forKey: Self.strongAlertRepeatIntervalKey)
        strongAlertRepeatIntervalMinutes = savedRepeatInterval == 0
            ? 1
            : Self.clampedStrongAlertRepeatInterval(savedRepeatInterval)
        pauseUntil = nil

        do {
            try launchAtLogin.enable()
        } catch {
            isLaunchAtLoginEnabled = launchAtLogin.isEnabled
        }
        isLaunchAtLoginEnabled = launchAtLogin.isEnabled
        activityLog = loadActivityLog()
        saveActivityLog()
    }

    public func refreshLaunchAtLoginStatus() {
        isLaunchAtLoginEnabled = launchAtLogin.isEnabled
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
        case .stale:
            return "Calendar coverage is stale for \(record.connection.account.email). Known reminders are unverified until coverage returns."
        case .unavailable(let message):
            return "Calendar coverage is unavailable for \(record.connection.account.email): \(message)"
        case .noCoverage, .fresh:
            return nil
        }
    }

    public func activities(forCalendarID calendarID: String, accountID: String) -> [ProtectionActivity] {
        activityLog.filter {
            $0.accountID == accountID && $0.calendarID == calendarID
        }
    }

    public func selectedCalendarIDs(for accountID: String) -> Set<String> {
        accountRecords[accountID]?.selectedCalendarIDs ?? []
    }

    public var isProtectionConfirmationRequired: Bool {
        accountRecords.values.contains {
            !$0.selectedCalendarIDs.isEmpty && !$0.isProtectionConfirmed
        }
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
                  event.isEligibleForProtection,
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
        return "\(calendarName) in \(record.connection.account.email) has an imminent commitment. Turning off this calendar removes its reminders."
    }

    public var status: ProtectionStatus {
        let configuredAccounts = accountRecords.values.filter {
            !$0.selectedCalendars.isEmpty && $0.isProtectionConfirmed
        }
        guard !configuredAccounts.isEmpty else { return .noCoverage }

        let hasFreshCoverage = configuredAccounts.contains { record in
            coverageHealth(for: record, at: coverageEvaluationDate) == .fresh
        }
        return hasFreshCoverage ? .active : .unavailable
    }

    public var menuBarTitle: String {
        switch status {
        case .noCoverage:
            return "No Coverage"
        case .active:
            if isPaused() {
                return "Protection Paused"
            }
            return isLaunchAtLoginEnabled
                ? "Active Protection"
                : "Active Protection · Login Needs Attention"
        case .unavailable:
            return "Coverage Needs Attention"
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

        let minutesRemaining = Int(ceil(pauseUntil.timeIntervalSince(currentDate) / 60))
        let relativeText: String
        if minutesRemaining >= 60 {
            let hours = minutesRemaining / 60
            let minutes = minutesRemaining % 60
            relativeText = minutes == 0
                ? "\(hours) hour\(hours == 1 ? "" : "s")"
                : "\(hours) hour\(hours == 1 ? "" : "s") \(minutes) min"
        } else {
            relativeText = "\(max(minutesRemaining, 1)) min"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = .current
        formatter.timeZone = .current
        return "Protection paused · ends in \(relativeText) (\(formatter.string(from: pauseUntil)))"
    }

    @discardableResult
    public func pause(for duration: PauseDuration, at date: Date? = nil) -> Bool {
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
        earlyReminderCommitment = nil
        clearStrongAlertState()
        lastActionMessage = pauseExpirationText(at: currentDate)
        recordActivity(
            .pauseStarted,
            actor: .user,
            title: "Protection paused",
            detail: lastActionMessage ?? "Protection paused.",
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

    public func connectGoogleAccount() async {
        invalidateRefreshes()
        lastConnectionError = nil
        if accountRecords.isEmpty {
            connectionState = .connecting
        }

        do {
            let connection = try await calendarConnector.connect()
            let existingRecord = accountRecords[connection.account.id]
            if existingRecord?.isProtectionConfirmed == true {
                shouldSuppressUntrackedPastOccurrencesOnNextRefresh = true
            }
            accountRecords[connection.account.id] = AccountRecord(
                connection: connection,
                selectedCalendarIDs: existingRecord?.selectedCalendarIDs.intersection(
                    Set(connection.calendars.map(\.id))
                ) ?? [],
                isProtectionConfirmed: existingRecord?.isProtectionConfirmed ?? false,
                connectionState: .connected,
                lastSuccessfulRefreshAt: existingRecord?.lastSuccessfulRefreshAt,
                lastFreshEvents: existingRecord?.lastFreshEvents.filter { event in
                    event.accountID == connection.account.id &&
                        connection.calendars.contains { calendar in calendar.id == event.calendarID }
                } ?? []
            )
            activeAccountID = connection.account.id
            syncCoverageAndActiveAccountProjection()
            recordActivity(
                .accountConnected,
                actor: .user,
                title: "Google Calendar connected",
                detail: "Connected \(connection.account.email)."
            )
            await refreshCommitmentProtection()
        } catch {
            lastConnectionError = error.localizedDescription
            connectionState = .failed(error.localizedDescription)
            recordActivity(
                .accountConnectionFailed,
                actor: .system,
                title: "Google Calendar connection failed",
                detail: "Connection could not be completed: \(error.localizedDescription)."
            )
        }
    }

    @discardableResult
    public func disconnectGoogleAccount() -> Bool {
        guard let accountID = activeAccountID ?? connectedAccount?.id else {
            return false
        }
        return disconnectGoogleAccount(accountID: accountID)
    }

    @discardableResult
    public func disconnectGoogleAccount(accountID: String) -> Bool {
        invalidateRefreshes()
        guard let record = accountRecords[accountID] else { return false }
        do {
            try calendarConnector.disconnect(accountID: accountID)
        } catch {
            accountRecords[accountID]?.connectionState = .failed(error.localizedDescription)
            syncCoverageAndActiveAccountProjection()
            recordActivity(
                .accountDisconnectFailed,
                actor: .system,
                title: "Google Calendar disconnect failed",
                detail: "The account could not be disconnected: \(error.localizedDescription).",
                account: record.connection.account
            )
            return false
        }

        recordActivity(
            .accountDisconnected,
            actor: .user,
            title: "Google Calendar disconnected",
            detail: "Disconnected the Google Calendar account.",
            account: record.connection.account
        )
        accountRecords.removeValue(forKey: accountID)
        unverifiedAccountIDs.remove(accountID)
        newlySelectedCalendars = newlySelectedCalendars.filter { $0.accountID != accountID }

        if decisionCommitment?.accountID == accountID {
            clearLocalDecision()
        }
        if [upcomingCommitment, earlyReminderCommitment, strongAlertCommitment]
            .compactMap({ $0 })
            .contains(where: { $0.accountID == accountID }) {
            clearDisplayedProtectionState()
            clearLastActionMessage()
        }

        if activeAccountID == accountID {
            activeAccountID = accountRecords.keys.sorted().first
        }
        if accountRecords.isEmpty {
            pauseUntil = nil
            clearDisplayedProtectionState()
            clearLastActionMessage()
            stateStore.removeObject(forKey: Self.stateKey)
        } else {
            saveConfiguration()
        }
        syncCoverageAndActiveAccountProjection()
        if !accountRecords.isEmpty {
            Task { await refreshCommitmentProtection() }
        }
        return true
    }

    public func restoreSavedConnection() async {
        guard let savedConfiguration = loadConfiguration() else { return }

        invalidateRefreshes()
        isRestoringConnection = true
        defer { isRestoringConnection = false }

        accountRecords = [:]
        unverifiedAccountIDs = []
        for savedAccount in savedConfiguration.accounts {
            do {
                guard let connection = try await calendarConnector.restore(accountID: savedAccount.account.id) else {
                    throw ProtectionFlowError.savedAccountUnavailable
                }
                guard connection.account.id == savedAccount.account.id else {
                    throw ProtectionFlowError.restoredAccountMismatch
                }
                accountRecords[connection.account.id] = AccountRecord(
                    connection: connection,
                    selectedCalendarIDs: Set(savedAccount.selectedCalendarIDs)
                        .intersection(Set(connection.calendars.map(\.id))),
                    isProtectionConfirmed: savedAccount.isProtectionConfirmed,
                    connectionState: .connected,
                    lastSuccessfulRefreshAt: savedAccount.lastSuccessfulRefreshAt,
                    lastFreshEvents: savedAccount.lastFreshEventsSchemaVersion == Self.freshEventsSchemaVersion
                        ? savedAccount.lastFreshEvents.filter { event in
                            event.accountID == connection.account.id &&
                                connection.calendars.contains { calendar in calendar.id == event.calendarID }
                        }
                        : []
                )
            } catch {
                guard !savedAccount.account.id.isEmpty else { continue }
                accountRecords[savedAccount.account.id] = AccountRecord(
                    connection: GoogleCalendarConnection(
                        account: savedAccount.account,
                        calendars: savedAccount.calendars
                    ),
                    selectedCalendarIDs: Set(savedAccount.selectedCalendarIDs),
                    isProtectionConfirmed: savedAccount.isProtectionConfirmed,
                    connectionState: .failed(error.localizedDescription),
                    lastSuccessfulRefreshAt: savedAccount.lastSuccessfulRefreshAt,
                    lastFreshEvents: savedAccount.lastFreshEventsSchemaVersion == Self.freshEventsSchemaVersion
                        ? savedAccount.lastFreshEvents.filter { event in
                            event.accountID == savedAccount.account.id &&
                                savedAccount.calendars.contains { calendar in calendar.id == event.calendarID }
                        }
                        : []
                )
            }
        }

        activeAccountID = accountRecords.keys.sorted().first
        restoreLocalState(from: savedConfiguration)
        syncCoverageAndActiveAccountProjection()
        saveActivityLog()
        saveConfiguration()
        if !accountRecords.isEmpty {
            shouldSuppressUntrackedPastOccurrencesOnNextRefresh = true
            await refreshCommitmentProtection()
        }
    }

    public func setCalendarSelected(_ isSelected: Bool, calendarID: String) {
        guard let accountID = activeAccountID else { return }
        setCalendarSelected(isSelected, calendarID: calendarID, accountID: accountID)
    }

    public func setCalendarSelected(_ isSelected: Bool, calendarID: String, accountID: String) {
        guard var record = accountRecords[accountID],
              record.connection.calendars.contains(where: { $0.id == calendarID }) else { return }

        if isSelected {
            let wasAlreadySelected = record.selectedCalendarIDs.contains(calendarID)
            let wasProtectionConfirmed = record.isProtectionConfirmed
            record.selectedCalendarIDs.insert(calendarID)
            record.isProtectionConfirmed = false
            if !wasAlreadySelected && wasProtectionConfirmed {
                newlySelectedCalendars.insert(
                    CalendarSelectionIdentity(calendarID: calendarID, accountID: accountID)
                )
            }
        } else {
            record.selectedCalendarIDs.remove(calendarID)
            record.lastFreshEvents.removeAll { $0.calendarID == calendarID }
            newlySelectedCalendars.remove(
                CalendarSelectionIdentity(calendarID: calendarID, accountID: accountID)
            )
            if record.selectedCalendarIDs.isEmpty {
                record.isProtectionConfirmed = false
            }
        }
        accountRecords[accountID] = record
        let selectedCalendar = record.connection.calendars.first(where: { $0.id == calendarID })
        let calendarName = selectedCalendar?.name ?? calendarID
        invalidateRefreshes()
        if !isSelected,
           [upcomingCommitment, earlyReminderCommitment, strongAlertCommitment]
            .compactMap({ $0 })
            .contains(where: { $0.accountID == accountID && $0.calendarID == calendarID }) {
            clearDisplayedProtectionState()
            clearLastActionMessage()
        }
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
        guard var record = accountRecords[accountID], !record.selectedCalendarIDs.isEmpty else {
            return false
        }
        record.isProtectionConfirmed = true
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
        let accountIDs = accountRecords.values
            .filter { !$0.selectedCalendarIDs.isEmpty }
            .map { $0.connection.account.id }
        guard !accountIDs.isEmpty else { return false }

        for accountID in accountIDs {
            accountRecords[accountID]?.isProtectionConfirmed = true
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
        isBlockingAvailable = isAvailable
    }

    public func setEarlyReminderEnabled(_ isEnabled: Bool) {
        guard isEnabled != isEarlyReminderEnabled else { return }

        isEarlyReminderEnabled = isEnabled
        stateStore.set(isEnabled, forKey: Self.earlyReminderEnabledKey)
        invalidateRefreshes()
        if !isEnabled {
            earlyReminderCommitment = nil
        }
        recordActivity(
            .configurationChanged,
            actor: .user,
            title: "Early Reminder setting changed",
            detail: isEnabled ? "Early Reminder enabled." : "Early Reminder disabled."
        )
        Task { await refreshCommitmentProtection() }
    }

    public func setBlockingModeEnabled(_ isEnabled: Bool) {
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
        let clampedMinutes = Self.clampedStrongAlertRepeatInterval(minutes)
        guard clampedMinutes != strongAlertRepeatIntervalMinutes else { return }

        strongAlertRepeatIntervalMinutes = clampedMinutes
        stateStore.set(clampedMinutes, forKey: Self.strongAlertRepeatIntervalKey)
        isProtectionConfirmed = false
        markAllAccountsProtectionUnconfirmed()
        invalidateRefreshes()
        clearProtectionState()
        syncCoverageAndActiveAccountProjection()
        recordActivity(
            .configurationChanged,
            actor: .user,
            title: "Strong Alert setting changed",
            detail: "Strong Alert repeats every \(clampedMinutes) minute\(clampedMinutes == 1 ? "" : "s")."
        )
        Task { await refreshCommitmentProtection() }
    }

    public func setEarlyReminderLeadTime(minutes: Int) {
        let clampedMinutes = Self.clampedEarlyReminderLeadTime(minutes)
        guard clampedMinutes != earlyReminderLeadTimeMinutes else { return }

        earlyReminderLeadTimeMinutes = clampedMinutes
        stateStore.set(clampedMinutes, forKey: Self.earlyReminderLeadTimeKey)
        isProtectionConfirmed = false
        markAllAccountsProtectionUnconfirmed()
        invalidateRefreshes()
        clearProtectionState()
        syncCoverageAndActiveAccountProjection()
        recordActivity(
            .configurationChanged,
            actor: .user,
            title: "Early Reminder setting changed",
            detail: "Early Reminder lead time is \(clampedMinutes) minutes."
        )
        Task { await refreshCommitmentProtection() }
    }

    public func startMonitoring() {
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

    public func refreshCommitmentProtection() async {
        await refreshCommitmentProtection(at: now())
    }

    public func recoverProtection(at currentDate: Date? = nil) async {
        await refreshCommitmentProtection(at: currentDate ?? now())
    }

    public func refreshCommitmentProtection(at currentDate: Date) async {
        lastEvaluatedCoverageDate = currentDate
        if pruneActivityLog(at: currentDate) {
            saveActivityLog()
            saveConfiguration()
        }
        migrateLegacyActivityCalendarContext(with: [])
        let generation = beginRefresh()
        let configuredAccountIDs = accountRecords.values
            .filter { !$0.selectedCalendars.isEmpty && $0.isProtectionConfirmed }
            .map { $0.connection.account.id }
            .sorted()
        guard !configuredAccountIDs.isEmpty else {
            clearProtectionState()
            syncCoverageAndActiveAccountProjection()
            return
        }

        let startDate = Calendar.current.startOfDay(for: currentDate)
        let endDate = currentDate.addingTimeInterval(24 * 60 * 60)
        var events: [CalendarEvent] = []
        var didRefreshAllConfiguredAccounts = true

        for accountID in configuredAccountIDs {
            guard var record = accountRecords[accountID] else { continue }
            let wasUnavailable = record.connectionState != .connected ||
                unverifiedAccountIDs.contains(accountID)
            let previouslyTrackedOccurrences = Set(record.lastFreshEvents.map(OccurrenceIdentity.init))
            let selectedNewCalendars = Set(record.selectedCalendars.map {
                CalendarSelectionIdentity(calendarID: $0.id, accountID: accountID)
            }).intersection(newlySelectedCalendars)
            do {
                var freshEvents: [CalendarEvent] = []
                for calendar in record.selectedCalendars {
                    freshEvents += try await calendarConnector.loadEvents(
                        accountID: accountID,
                        calendarID: calendar.id,
                        from: startDate,
                        to: endDate
                    )
                }

                guard generation == refreshGeneration else { return }
                let protectionEvents = freshEvents.filter { event in
                    event.isEligibleForProtection &&
                        (event.endDate ?? .distantPast) > currentDate
                }
                let eventsToSuppress = protectionEvents.filter { event in
                    shouldSuppressUntrackedPastOccurrencesOnNextRefresh ||
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
                newlySelectedCalendars.subtract(selectedNewCalendars)
                events += freshEvents
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
            } catch {
                guard generation == refreshGeneration else { return }
                didRefreshAllConfiguredAccounts = false
                let wasAlreadyUnavailable = record.connectionState == .failed(error.localizedDescription) ||
                    unverifiedAccountIDs.contains(accountID)
                record.connectionState = .failed(error.localizedDescription)
                accountRecords[accountID] = record
                unverifiedAccountIDs.insert(accountID)
                events += record.lastFreshEvents.filter {
                    $0.accountID == accountID && record.selectedCalendarIDs.contains($0.calendarID)
                }
                if !wasAlreadyUnavailable {
                    recordActivity(
                        .coverageUnavailable,
                        actor: .system,
                        title: "Calendar coverage unavailable",
                        detail: "Calendar events could not be refreshed: \(error.localizedDescription).",
                        account: record.connection.account,
                        at: currentDate
                    )
                }
            }
        }

        guard generation == refreshGeneration else { return }
        if didRefreshAllConfiguredAccounts {
            shouldSuppressUntrackedPastOccurrencesOnNextRefresh = false
        }
        syncCoverageAndActiveAccountProjection()
        migrateLegacyActivityCalendarContext(with: events)
        reconcileCalendarSnapshot(events, at: currentDate)
        syncCoverageAndActiveAccountProjection()
    }

    public func presentTestAlert() {
        guard !isTestAlertPresented else { return }
        isTestAlertPresented = true
        recordActivity(
            .testAlertShown,
            actor: .user,
            title: "Test Alert shown",
            detail: "The interruption experience was opened."
        )
    }

    public func dismissTestAlert() {
        guard isTestAlertPresented else { return }
        isTestAlertPresented = false
        recordActivity(
            .testAlertDismissed,
            actor: .user,
            title: "Test Alert dismissed",
            detail: "The interruption experience was closed."
        )
    }

    public var strongAlertPrimaryActionTitle: String {
        strongAlertCommitment?.recognizedMeetingLink == nil ? "Stop reminders" : "Join"
    }

    @discardableResult
    public func joinStrongAlert() -> URL? {
        guard let meetingLink = strongAlertCommitment?.recognizedMeetingLink else { return nil }
        guard let commitment = strongAlertCommitment else { return nil }
        recordDecision(
            .joined,
            for: commitment,
            message: "Joined. Protection ended for this occurrence."
        )
        return meetingLink
    }

    public func handleStrongAlert() {
        guard let commitment = strongAlertCommitment else { return }
        _ = handle(commitment, at: now())
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
        guard isActionable(commitment),
              let endDate = commitment.endDate,
              endDate > (date ?? now()) else {
            return false
        }
        recordDecision(
            .dismissed,
            for: commitment,
            message: "Dismissed for this occurrence. Protection is off until it ends."
        )
        return true
    }

    @discardableResult
    public func restoreProtection(at date: Date? = nil) -> Bool {
        let currentDate = date ?? now()
        guard currentCommitmentDecision?.isRestorable == true,
              let commitment = decisionCommitment,
              let endDate = commitment.endDate,
              endDate > currentDate else {
            return false
        }

        clearLocalDecision()
        lastActionMessage = "Protection restored for this occurrence."
        lastActionOccurrence = OccurrenceIdentity(commitment)
        recordActivity(
            .protectionRestored,
            actor: .user,
            title: "Protection restored",
            detail: lastActionMessage ?? "Protection restored for this occurrence.",
            commitment: commitment,
            at: currentDate
        )
        restoreDisplayedProtection(for: commitment, at: currentDate)
        return true
    }

    @discardableResult
    public func snoozeEarlyReminder(minutes: Int, at date: Date? = nil) -> Bool {
        let currentDate = date ?? now()
        guard snoozeOptionsMinutes.contains(minutes),
              let commitment = earlyReminderCommitment,
              let startDate = commitment.startDate,
              startDate > currentDate else {
            return false
        }

        let occurrence = OccurrenceIdentity(commitment)
        guard snoozedOccurrence != occurrence else { return false }

        snoozedOccurrence = occurrence
        let requestedSnoozeUntil = currentDate.addingTimeInterval(Double(minutes) * 60)
        let effectiveSnoozeUntil = min(
            commitment.endDate ?? requestedSnoozeUntil,
            requestedSnoozeUntil
        )
        snoozedUntil = effectiveSnoozeUntil
        earlyReminderCommitment = nil
        lastActionMessage = commitment.endDate == effectiveSnoozeUntil && requestedSnoozeUntil > effectiveSnoozeUntil
            ? "All reminders snoozed until the commitment ends. Protection remains active."
            : "All reminders snoozed for \(minutes) minutes. Protection remains active."
        lastActionOccurrence = occurrence
        recordActivity(
            .snoozed,
            actor: .user,
            title: "Reminders snoozed",
            detail: lastActionMessage ?? "Reminders snoozed.",
            commitment: commitment,
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
        guard isStrongAlertPresented,
              let commitment = strongAlertCommitment else { return }
        isStrongAlertPresented = false
        strongAlertNextPresentationDate = date.addingTimeInterval(
            Double(strongAlertRepeatIntervalMinutes) * 60
        )
        let interval = strongAlertRepeatIntervalMinutes == 1
            ? "1 minute"
            : "\(strongAlertRepeatIntervalMinutes) minutes"
        lastActionMessage = "Strong Alert closed. Protection remains active and will repeat in \(interval)."
        lastActionOccurrence = OccurrenceIdentity(commitment)
        recordActivity(
            .strongAlertClosed,
            actor: .user,
            title: "Strong Alert closed",
            detail: lastActionMessage ?? "Strong Alert closed.",
            commitment: commitment,
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
        return elapsedMinutes == 1
            ? "Overdue · started 1 min ago"
            : "Overdue · started \(elapsedMinutes) min ago"
    }

    public func strongAlertContextText(for commitment: CalendarEvent) -> String {
        let calendarName = calendarName(for: commitment) ?? commitment.calendarID
        let accountName = account(for: commitment)?.email ?? commitment.accountID
        return "\(calendarName) · \(accountName)"
    }

    public func clearEarlyReminder() {
        guard let earlyReminderCommitment else { return }
        _ = clearEarlyReminder(for: earlyReminderCommitment)
    }

    @discardableResult
    public func clearEarlyReminder(for commitment: CalendarEvent) -> Bool {
        guard isCurrentEarlyReminder(commitment),
              let earlyReminderCommitment else { return false }
        clearedEarlyReminderEventID = earlyReminderCommitment.id
        clearedEarlyReminderEventStartDate = earlyReminderCommitment.startDate
        clearedEarlyReminderEventCalendarID = earlyReminderCommitment.calendarID
        clearedEarlyReminderEventAccountID = earlyReminderCommitment.accountID
        self.earlyReminderCommitment = nil
        lastActionMessage = "Early Reminder cleared. Protection remains active."
        lastActionOccurrence = OccurrenceIdentity(earlyReminderCommitment)
        recordActivity(
            .earlyReminderCleared,
            actor: .user,
            title: "Early Reminder cleared",
            detail: lastActionMessage ?? "Early Reminder cleared.",
            commitment: earlyReminderCommitment
        )
        return true
    }

    private func isCurrentEarlyReminder(_ commitment: CalendarEvent) -> Bool {
        guard let earlyReminderCommitment else { return false }
        return OccurrenceIdentity(earlyReminderCommitment).matches(commitment)
    }

    public func localStartTimeText(for commitment: CalendarEvent) -> String {
        guard let startDate = commitment.startDate else { return "Time unavailable" }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        dateFormatter.locale = Locale(identifier: "tr_TR")
        dateFormatter.timeZone = .current

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        timeFormatter.locale = .current
        timeFormatter.timeZone = .current
        var text = "\(dateFormatter.string(from: startDate)), \(timeFormatter.string(from: startDate))"

        if let identifier = commitment.timeZoneIdentifier,
           let eventTimeZone = TimeZone(identifier: identifier),
           eventTimeZone != .current {
            let label = eventTimeZone.abbreviation(for: startDate) ?? identifier
            text += " (\(label))"
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
            return "Starts in \(totalMinutes) min"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0
            ? "Starts in \(hours) hr"
            : "Starts in \(hours) hr \(minutes) min"
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
        guard let endDate = commitment.endDate, endDate > date else { return false }
        recordDecision(
            .handled,
            for: commitment,
            message: "Handled for this occurrence. Protection is off until it ends."
        )
        return true
    }

    private func isActionable(_ commitment: CalendarEvent) -> Bool {
        return [strongAlertCommitment, earlyReminderCommitment, upcomingCommitment]
            .compactMap { $0 }
            .contains { OccurrenceIdentity(commitment).matches($0) }
    }

    private func reconcileCalendarSnapshot(_ events: [CalendarEvent], at currentDate: Date) {
        updateTemporaryLifecycleState(at: currentDate)
        recordAcceptanceMutations(in: events, at: currentDate)
        let eligibleEvents = events
            .filter { event in
                guard event.isEligibleForProtection,
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
        let nextCommitment = eligibleEvents.first {
            isUpcoming($0, at: currentDate)
        }
        let protectedEvents = isPaused(at: currentDate)
            ? []
            : eligibleEvents.filter {
                isProtectionAvailable(for: $0, at: currentDate)
            }
        let nextProtectedCommitment = protectedEvents.first {
            isUpcoming($0, at: currentDate)
        }
        let activeProtectedCommitment = protectedEvents.first {
            !isUpcoming($0, at: currentDate)
        }

        upcomingCommitment = nextCommitment
        if let nextProtectedCommitment,
           !(OccurrenceIdentity(
                eventID: clearedEarlyReminderEventID ?? "",
                startDate: clearedEarlyReminderEventStartDate,
                calendarID: clearedEarlyReminderEventCalendarID,
                accountID: clearedEarlyReminderEventAccountID
           ).matches(nextProtectedCommitment)) {
            clearedEarlyReminderEventID = nil
            clearedEarlyReminderEventStartDate = nil
            clearedEarlyReminderEventCalendarID = nil
            clearedEarlyReminderEventAccountID = nil
        }

        if let activeProtectedCommitment {
            updateStrongAlert(for: activeProtectedCommitment, at: currentDate)
        } else {
            clearStrongAlertState()
        }

        if isPaused(at: currentDate) {
            earlyReminderCommitment = nil
            return
        }

        guard isEarlyReminderEnabled else {
            earlyReminderCommitment = nil
            return
        }

        guard let nextProtectedCommitment,
              let startDate = nextProtectedCommitment.startDate,
              currentDate >= startDate.addingTimeInterval(-Double(earlyReminderLeadTimeMinutes) * 60),
              !(clearedEarlyReminderEventID == nextProtectedCommitment.id &&
                clearedEarlyReminderEventStartDate == startDate &&
                clearedEarlyReminderEventCalendarID == nextProtectedCommitment.calendarID &&
                clearedEarlyReminderEventAccountID == nextProtectedCommitment.accountID) else {
            earlyReminderCommitment = nil
            return
        }

        let isNewEarlyReminder = earlyReminderCommitment.map {
            !OccurrenceIdentity($0).matches(nextProtectedCommitment)
        } ?? true
        earlyReminderCommitment = nextProtectedCommitment
        if isNewEarlyReminder {
            recordActivity(
                .earlyReminderShown,
                actor: .system,
                title: "Early Reminder shown",
                detail: "Protection is active for \(nextProtectedCommitment.title).",
                commitment: nextProtectedCommitment,
                at: currentDate
            )
        }
    }

    private func updateTemporaryLifecycleState(at currentDate: Date) {
        var didChange = false
        if let pauseUntil, pauseUntil <= currentDate {
            self.pauseUntil = nil
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

    private func recordAcceptanceMutations(in events: [CalendarEvent], at currentDate: Date) {
        let trackedEvents = events.filter { event in
            guard event.isProtectionTrackable,
                  let endDate = event.endDate else {
                return false
            }
            return endDate > currentDate
        }
        let trackedOccurrences = Set(trackedEvents.map(OccurrenceIdentity.init))
        var didChange = false

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
        message: String
    ) {
        decisionOccurrence = OccurrenceIdentity(commitment)
        currentCommitmentDecision = decision
        decisionCommitment = commitment
        if let earlyReminderCommitment,
           decisionOccurrence?.matches(earlyReminderCommitment) == true {
            self.earlyReminderCommitment = nil
        }
        if let strongAlertCommitment,
           decisionOccurrence?.matches(strongAlertCommitment) == true {
            clearStrongAlertState()
        }
        lastActionMessage = message
        lastActionOccurrence = OccurrenceIdentity(commitment)
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
            commitment: commitment
        )
    }

    private func updateLocalState(for eligibleEvents: [CalendarEvent], at date: Date) {
        if let lastActionOccurrence,
           !eligibleEvents.contains(where: { lastActionOccurrence.matches($0) }) {
            clearLastActionMessage()
        }

        if let decisionOccurrence {
            if let matchingCommitment = eligibleEvents.first(where: { decisionOccurrence.matches($0) }) {
                decisionCommitment = matchingCommitment
                if matchingCommitment.endDate ?? .distantPast <= date {
                    clearLocalDecision()
                    saveConfiguration()
                }
            } else {
                clearLocalDecision()
                saveConfiguration()
            }
        }

        if let snoozedOccurrence,
           !eligibleEvents.contains(where: { snoozedOccurrence.matches($0) }) {
            self.snoozedOccurrence = nil
            snoozedUntil = nil
            saveConfiguration()
        }
    }

    private func isSnoozed(_ commitment: CalendarEvent, at date: Date) -> Bool {
        guard snoozedOccurrence?.matches(commitment) == true,
              let snoozedUntil else {
            return false
        }
        return date < snoozedUntil
    }

    private func isDecisionActive(_ commitment: CalendarEvent) -> Bool {
        isDecisionActive(for: OccurrenceIdentity(commitment))
    }

    private func isDecisionActive(for occurrence: OccurrenceIdentity) -> Bool {
        decisionOccurrence?.matches(occurrence) == true && currentCommitmentDecision != nil
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
        guard let startDate = commitment.startDate,
              let endDate = commitment.endDate,
              endDate > date,
              !isSnoozed(commitment, at: date) else {
            return
        }

        if startDate > date {
            guard isEarlyReminderEnabled else { return }
            guard date >= startDate.addingTimeInterval(-Double(earlyReminderLeadTimeMinutes) * 60),
                  !(clearedEarlyReminderEventID == commitment.id &&
                    clearedEarlyReminderEventStartDate == startDate &&
                    clearedEarlyReminderEventCalendarID == commitment.calendarID &&
                    clearedEarlyReminderEventAccountID == commitment.accountID),
                  !isSnoozed(commitment, at: date) else {
                return
            }
            upcomingCommitment = commitment
            earlyReminderCommitment = commitment
            recordActivity(
                .earlyReminderShown,
                actor: .system,
                title: "Early Reminder shown",
                detail: "Protection is active for \(commitment.title).",
                commitment: commitment,
                at: date
            )
            return
        }

        strongAlertEventID = commitment.id
        strongAlertEventStartDate = startDate
        strongAlertEventCalendarID = commitment.calendarID
        strongAlertEventAccountID = commitment.accountID
        strongAlertNextPresentationDate = date
        strongAlertCommitment = commitment
        isStrongAlertPresented = true
        strongAlertNextPresentationDate = date.addingTimeInterval(
            Double(strongAlertRepeatIntervalMinutes) * 60
        )
        recordActivity(
            .strongAlertShown,
            actor: .system,
            title: "Strong Alert shown",
            detail: "\(commitment.title) needs attention now.",
            commitment: commitment,
            at: date
        )
    }

    private func updateStrongAlert(for commitment: CalendarEvent, at date: Date) {
        if decisionOccurrence?.matches(commitment) == true,
           currentCommitmentDecision != nil {
            clearStrongAlertState()
            return
        }

        if strongAlertEventID != commitment.id ||
            strongAlertEventStartDate != commitment.startDate ||
            strongAlertEventCalendarID != commitment.calendarID ||
            strongAlertEventAccountID != commitment.accountID {
            strongAlertEventID = commitment.id
            strongAlertEventStartDate = commitment.startDate
            strongAlertEventCalendarID = commitment.calendarID
            strongAlertEventAccountID = commitment.accountID
            strongAlertNextPresentationDate = date
            isStrongAlertPresented = false
        }

        strongAlertCommitment = commitment
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
                ? "\(commitment.title) is still awaiting an explicit action."
                : "\(commitment.title) needs attention now.",
            commitment: commitment,
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
        guard !record.selectedCalendars.isEmpty, record.isProtectionConfirmed else {
            return .noCoverage
        }

        switch record.connectionState {
        case .connected:
            guard let lastSuccessfulRefreshAt = record.lastSuccessfulRefreshAt else {
                return .fresh
            }
            return date.timeIntervalSince(lastSuccessfulRefreshAt) <= Self.coverageFreshnessInterval
                ? .fresh
                : .stale
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
        accountRecords.values.contains {
            !$0.selectedCalendars.isEmpty && $0.isProtectionConfirmed
        }
    }

    private var coverageEvaluationDate: Date {
        max(lastEvaluatedCoverageDate ?? .distantPast, now())
    }

    private func markAllAccountsProtectionUnconfirmed() {
        for accountID in accountRecords.keys {
            accountRecords[accountID]?.isProtectionConfirmed = false
        }
    }

    private func syncCoverageAndActiveAccountProjection() {
        accountCoverages = accountRecords.values
            .map { record in
                AccountCoverage(
                    account: record.connection.account,
                    calendars: record.connection.calendars,
                    selectedCalendarIDs: record.selectedCalendarIDs,
                    isProtectionConfirmed: record.isProtectionConfirmed,
                    connectionState: record.connectionState,
                    health: coverageHealth(for: record, at: coverageEvaluationDate),
                    lastSuccessfulRefreshAt: record.lastSuccessfulRefreshAt
                )
            }
            .sorted { $0.account.email.localizedCaseInsensitiveCompare($1.account.email) == .orderedAscending }

        guard let activeAccountID, let record = accountRecords[activeAccountID] else {
            connectedAccount = nil
            availableCalendars = []
            selectedCalendarIDs = []
            connectionState = lastConnectionError.map(ConnectionState.failed) ?? .notConnected
            isProtectionConfirmed = false
            return
        }

        connectedAccount = record.connection.account
        availableCalendars = record.connection.calendars
        selectedCalendarIDs = record.selectedCalendarIDs
        connectionState = record.connectionState
        isProtectionConfirmed = record.isProtectionConfirmed
        isEarlyReminderUnverified = earlyReminderCommitment.map(isUnverified) ?? false
        isStrongAlertUnverified = strongAlertCommitment.map(isUnverified) ?? false
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

    private func loadConfiguration() -> SavedConfiguration? {
        guard let data = stateStore.data(forKey: Self.stateKey) else { return nil }
        return try? JSONDecoder().decode(SavedConfiguration.self, from: data)
    }

    private func loadActivityLog() -> [ProtectionActivity] {
        guard let data = stateStore.data(forKey: Self.activityLogKey),
              let activities = try? JSONDecoder().decode([ProtectionActivity].self, from: data) else {
            return []
        }
        return activities.filter {
            isActivityFromSameLocalDay($0, as: now())
        }
    }

    private func restoreLocalState(from configuration: SavedConfiguration) {
        decisionOccurrence = configuration.decisionOccurrence?.identity
        currentCommitmentDecision = configuration.currentCommitmentDecision
        snoozedOccurrence = configuration.snoozedOccurrence?.identity
        snoozedUntil = configuration.snoozedUntil
        pauseUntil = configuration.pauseUntil
        observedUnacceptedOccurrences = Set(configuration.observedUnacceptedOccurrences.map(\.identity))
        suppressedPostStartAcceptanceOccurrences = Set(
            configuration.suppressedPostStartAcceptanceOccurrences.map(\.identity)
        )
        suppressedUntrackedPastOccurrences = Set(
            configuration.suppressedUntrackedPastOccurrences.map(\.identity)
        )
    }

    private func saveConfiguration() {
        guard !accountRecords.isEmpty else {
            stateStore.removeObject(forKey: Self.stateKey)
            return
        }

        let configuration = SavedConfiguration(
            accounts: accountRecords.values.map { record in
                SavedAccountConfiguration(
                    account: record.connection.account,
                    calendars: record.connection.calendars,
                    selectedCalendarIDs: record.selectedCalendarIDs.sorted(),
                    isProtectionConfirmed: record.isProtectionConfirmed,
                    lastSuccessfulRefreshAt: record.lastSuccessfulRefreshAt,
                    lastFreshEvents: record.lastFreshEvents,
                    lastFreshEventsSchemaVersion: Self.freshEventsSchemaVersion
                )
            }.sorted { $0.account.id < $1.account.id },
            decisionOccurrence: decisionOccurrence.map(SavedOccurrence.init),
            currentCommitmentDecision: currentCommitmentDecision,
            snoozedOccurrence: snoozedOccurrence.map(SavedOccurrence.init),
            snoozedUntil: snoozedUntil,
            pauseUntil: pauseUntil,
            observedUnacceptedOccurrences: observedUnacceptedOccurrences.map(SavedOccurrence.init),
            suppressedPostStartAcceptanceOccurrences: suppressedPostStartAcceptanceOccurrences.map(SavedOccurrence.init),
            suppressedUntrackedPastOccurrences: suppressedUntrackedPastOccurrences.map(SavedOccurrence.init)
        )
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        stateStore.set(data, forKey: Self.stateKey)
    }

    private func invalidateRefreshes() {
        refreshGeneration &+= 1
    }

    private func beginRefresh() -> Int {
        invalidateRefreshes()
        return refreshGeneration
    }

    private func clearProtectionState() {
        clearDisplayedProtectionState()
        clearedEarlyReminderEventID = nil
        clearedEarlyReminderEventStartDate = nil
        clearedEarlyReminderEventCalendarID = nil
        clearedEarlyReminderEventAccountID = nil
        snoozedOccurrence = nil
        snoozedUntil = nil
        pauseUntil = nil
        observedUnacceptedOccurrences = []
        suppressedPostStartAcceptanceOccurrences = []
        suppressedUntrackedPastOccurrences = []
        clearLocalDecision()
        clearLastActionMessage()
    }

    private func clearDisplayedProtectionState() {
        upcomingCommitment = nil
        earlyReminderCommitment = nil
        isEarlyReminderUnverified = false
        clearStrongAlertState()
    }

    private func clearStrongAlertState() {
        isStrongAlertPresented = false
        strongAlertCommitment = nil
        strongAlertEventID = nil
        strongAlertEventStartDate = nil
        strongAlertEventCalendarID = nil
        strongAlertEventAccountID = nil
        strongAlertNextPresentationDate = nil
    }

    private func clearLocalDecision() {
        currentCommitmentDecision = nil
        decisionCommitment = nil
        decisionOccurrence = nil
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
    ) -> CalendarOption? {
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
                let name = calendarName(for: commitment) ?? commitment.calendarID
                return CalendarOption(id: commitment.calendarID, name: name, accountID: accountID)
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
        return matchingCalendars.count == 1 ? matchingCalendars.first : nil
    }

    private func recordActivity(
        _ kind: ProtectionActivityKind,
        actor: ProtectionActivityActor,
        title: String,
        detail: String,
        commitment: CalendarEvent? = nil,
        account: GoogleAccount? = nil,
        calendar: CalendarOption? = nil,
        at date: Date? = nil
    ) {
        let occurredAt = date ?? now()
        let activityAccount = account ?? commitment.flatMap { self.account(for: $0) } ??
            calendar.flatMap { accountRecords[$0.accountID]?.connection.account } ?? connectedAccount
        let activityCalendarID = calendar?.id ?? commitment?.calendarID
        let activityCalendarName = calendar?.name ?? commitment.flatMap { calendarName(for: $0) }
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
                calendarName: activityCalendarName
            ),
            at: 0
        )
        saveActivityLog()
        saveConfiguration()
    }

    private func calendarName(for commitment: CalendarEvent) -> String? {
        accountRecords[commitment.accountID]?.connection.calendars
            .first(where: { $0.id == commitment.calendarID })?.name
    }

    private func saveActivityLog() {
        guard let data = try? JSONEncoder().encode(activityLog) else { return }
        stateStore.set(data, forKey: Self.activityLogKey)
    }

    private func isActivityFromSameLocalDay(_ activity: ProtectionActivity, as date: Date) -> Bool {
        Calendar.current.isDate(activity.occurredAt, inSameDayAs: date)
    }
}

private enum ProtectionFlowError: LocalizedError {
    case restoredAccountMismatch
    case savedAccountUnavailable

    var errorDescription: String? {
        "The saved Google account could not be restored safely. Connect it again."
    }
}
