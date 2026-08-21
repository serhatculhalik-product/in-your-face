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
        recognizedMeetingLink: URL? = nil
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
    }

    public var isEligibleForProtection: Bool {
        isAccepted && !isAllDay && startDate != nil && endDate != nil
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
        accountEmail: String? = nil
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
    }
}

public enum ConnectionState: Equatable, Sendable {
    case notConnected
    case connecting
    case connected
    case failed(String)
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
    private var clearedEarlyReminderEventID: String?
    private var clearedEarlyReminderEventStartDate: Date?
    private struct OccurrenceIdentity: Hashable, Sendable {
        let eventID: String
        let startDate: Date?

        init(_ commitment: CalendarEvent) {
            eventID = commitment.id
            startDate = commitment.startDate
        }

        init(eventID: String, startDate: Date?) {
            self.eventID = eventID
            self.startDate = startDate
        }
    }

    private var snoozedOccurrence: OccurrenceIdentity?
    private var snoozedUntil: Date?
    private var observedUnacceptedOccurrences: Set<OccurrenceIdentity> = []
    private var suppressedPostStartAcceptanceOccurrences: Set<OccurrenceIdentity> = []
    private var decisionOccurrence: OccurrenceIdentity?
    private var lastActionOccurrence: OccurrenceIdentity?
    private var strongAlertEventID: String?
    private var strongAlertEventStartDate: Date?
    private var strongAlertNextPresentationDate: Date?
    private var monitoringTask: Task<Void, Never>?
    private var refreshGeneration = 0

    private struct SavedOccurrence: Codable {
        let eventID: String
        let startDate: Date?

        init(_ occurrence: OccurrenceIdentity) {
            eventID = occurrence.eventID
            startDate = occurrence.startDate
        }

        var identity: OccurrenceIdentity {
            OccurrenceIdentity(eventID: eventID, startDate: startDate)
        }
    }

    private struct SavedConfiguration: Codable {
        let accountID: String
        let selectedCalendarIDs: [String]
        let isProtectionConfirmed: Bool
        let decisionOccurrence: SavedOccurrence?
        let currentCommitmentDecision: CommitmentProtectionDecision?
        let snoozedOccurrence: SavedOccurrence?
        let snoozedUntil: Date?
        let pauseUntil: Date?
        let observedUnacceptedOccurrences: [SavedOccurrence]
        let suppressedPostStartAcceptanceOccurrences: [SavedOccurrence]

        private enum CodingKeys: String, CodingKey {
            case accountID
            case selectedCalendarIDs
            case isProtectionConfirmed
            case decisionOccurrence
            case currentCommitmentDecision
            case snoozedOccurrence
            case snoozedUntil
            case pauseUntil
            case observedUnacceptedOccurrences
            case suppressedPostStartAcceptanceOccurrences
        }

        init(
            accountID: String,
            selectedCalendarIDs: [String],
            isProtectionConfirmed: Bool,
            decisionOccurrence: SavedOccurrence?,
            currentCommitmentDecision: CommitmentProtectionDecision?,
            snoozedOccurrence: SavedOccurrence?,
            snoozedUntil: Date?,
            pauseUntil: Date?,
            observedUnacceptedOccurrences: [SavedOccurrence],
            suppressedPostStartAcceptanceOccurrences: [SavedOccurrence]
        ) {
            self.accountID = accountID
            self.selectedCalendarIDs = selectedCalendarIDs
            self.isProtectionConfirmed = isProtectionConfirmed
            self.decisionOccurrence = decisionOccurrence
            self.currentCommitmentDecision = currentCommitmentDecision
            self.snoozedOccurrence = snoozedOccurrence
            self.snoozedUntil = snoozedUntil
            self.pauseUntil = pauseUntil
            self.observedUnacceptedOccurrences = observedUnacceptedOccurrences
            self.suppressedPostStartAcceptanceOccurrences = suppressedPostStartAcceptanceOccurrences
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accountID = try container.decode(String.self, forKey: .accountID)
            selectedCalendarIDs = try container.decode([String].self, forKey: .selectedCalendarIDs)
            isProtectionConfirmed = try container.decodeIfPresent(Bool.self, forKey: .isProtectionConfirmed) ?? false
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

    public var status: ProtectionStatus {
        guard let connectedAccount else { return .noCoverage }

        let selectedCalendars = availableCalendars.filter {
            $0.accountID == connectedAccount.id && selectedCalendarIDs.contains($0.id)
        }
        guard !selectedCalendars.isEmpty else { return .noCoverage }
        guard isProtectionConfirmed else { return .noCoverage }
        if case .failed = connectionState {
            return .unavailable
        }
        guard connectionState == .connected else { return .noCoverage }
        return .active
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
        guard connectedAccount != nil,
              isProtectionConfirmed,
              !selectedCalendarIDs.isEmpty else {
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
        guard lastActionOccurrence == OccurrenceIdentity(commitment) else { return nil }
        return lastActionMessage
    }

    public func connectGoogleAccount() async {
        invalidateRefreshes()
        clearProtectionState()
        connectionState = .connecting

        do {
            let connection = try await calendarConnector.connect()
            let shouldPreserveSelection = connectedAccount?.id == connection.account.id
            let shouldPreserveConfirmation = shouldPreserveSelection && isProtectionConfirmed

            connectedAccount = connection.account
            availableCalendars = connection.calendars
            selectedCalendarIDs = shouldPreserveSelection
                ? selectedCalendarIDs.intersection(Set(connection.calendars.map(\.id)))
                : []
            isProtectionConfirmed = shouldPreserveConfirmation
            connectionState = .connected
            recordActivity(
                .accountConnected,
                actor: .user,
                title: "Google Calendar connected",
                detail: "Connected \(connection.account.email)."
            )
            await refreshCommitmentProtection()
        } catch {
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
        invalidateRefreshes()
        let accountID = connectedAccount?.id ?? loadConfiguration()?.accountID
        if let accountID {
            do {
                try calendarConnector.disconnect(accountID: accountID)
            } catch {
                connectionState = .failed(error.localizedDescription)
                recordActivity(
                    .accountDisconnectFailed,
                    actor: .system,
                    title: "Google Calendar disconnect failed",
                    detail: "The account could not be disconnected: \(error.localizedDescription)."
                )
                return false
            }
        }

        recordActivity(
            .accountDisconnected,
            actor: .user,
            title: "Google Calendar disconnected",
            detail: "Disconnected the Google Calendar account."
        )
        connectedAccount = nil
        availableCalendars = []
        selectedCalendarIDs = []
        isProtectionConfirmed = false
        upcomingCommitment = nil
        earlyReminderCommitment = nil
        clearStrongAlertState()
        clearedEarlyReminderEventID = nil
        clearedEarlyReminderEventStartDate = nil
        snoozedOccurrence = nil
        snoozedUntil = nil
        pauseUntil = nil
        clearLocalDecision()
        lastActionMessage = nil
        connectionState = .notConnected
        stateStore.removeObject(forKey: Self.stateKey)
        return true
    }

    public func restoreSavedConnection() async {
        guard let savedConfiguration = loadConfiguration() else { return }

        invalidateRefreshes()
        isRestoringConnection = true
        defer { isRestoringConnection = false }

        do {
            guard let connection = try await calendarConnector.restore(accountID: savedConfiguration.accountID) else {
                stateStore.removeObject(forKey: Self.stateKey)
                return
            }
            guard connection.account.id == savedConfiguration.accountID else {
                throw ProtectionFlowError.restoredAccountMismatch
            }

            connectedAccount = connection.account
            availableCalendars = connection.calendars
            selectedCalendarIDs = Set(savedConfiguration.selectedCalendarIDs)
                .intersection(Set(connection.calendars.map(\.id)))
            isProtectionConfirmed = savedConfiguration.isProtectionConfirmed
            restoreLocalState(from: savedConfiguration)
            saveActivityLog()
            connectionState = .connected
            saveConfiguration()
            await refreshCommitmentProtection()
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    public func setCalendarSelected(_ isSelected: Bool, calendarID: String) {
        guard let connectedAccount,
              availableCalendars.contains(where: {
                  $0.id == calendarID && $0.accountID == connectedAccount.id
              }) else { return }

        if isSelected {
            selectedCalendarIDs.insert(calendarID)
        } else {
            selectedCalendarIDs.remove(calendarID)
        }
        isProtectionConfirmed = false
        let calendarName = availableCalendars.first(where: { $0.id == calendarID })?.name ?? calendarID
        invalidateRefreshes()
        clearProtectionState()
        recordActivity(
            .configurationChanged,
            actor: .user,
            title: "Calendar selection changed",
            detail: isSelected ? "Monitoring \(calendarName)." : "Stopped monitoring \(calendarName)."
        )
        Task { await refreshCommitmentProtection() }
    }

    @discardableResult
    public func confirmProtection() -> Bool {
        guard connectedAccount != nil, !selectedCalendarIDs.isEmpty else { return false }
        isProtectionConfirmed = true
        invalidateRefreshes()
        recordActivity(
            .configurationChanged,
            actor: .user,
            title: "Protection confirmed",
            detail: "Protection is enabled for the selected calendars."
        )
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
        invalidateRefreshes()
        clearProtectionState()
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
        invalidateRefreshes()
        clearProtectionState()
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
        if pruneActivityLog(at: currentDate) {
            saveActivityLog()
            saveConfiguration()
        }
        let generation = beginRefresh()
        guard let connectedAccount, isProtectionConfirmed else {
            clearProtectionState()
            return
        }

        let selectedCalendars = availableCalendars.filter {
            $0.accountID == connectedAccount.id && selectedCalendarIDs.contains($0.id)
        }
        guard !selectedCalendars.isEmpty else {
            clearProtectionState()
            return
        }
        let startDate = Calendar.current.startOfDay(for: currentDate)
        let endDate = currentDate.addingTimeInterval(24 * 60 * 60)

        do {
            var events: [CalendarEvent] = []
            for calendar in selectedCalendars {
                events += try await calendarConnector.loadEvents(
                    accountID: connectedAccount.id,
                    calendarID: calendar.id,
                    from: startDate,
                    to: endDate
                )
            }

            guard generation == refreshGeneration else { return }
            let wasUnavailable: Bool
            if case .failed = connectionState {
                wasUnavailable = true
            } else {
                wasUnavailable = false
            }
            connectionState = .connected
            if wasUnavailable {
                recordActivity(
                    .coverageRestored,
                    actor: .system,
                    title: "Calendar coverage restored",
                    detail: "Calendar protection is available again.",
                    at: currentDate
                )
            }

            reconcileCalendarSnapshot(events, at: currentDate)
        } catch {
            guard generation == refreshGeneration else { return }
            clearDisplayedProtectionState()
            let wasUnavailable: Bool
            if case .failed = connectionState {
                wasUnavailable = true
            } else {
                wasUnavailable = false
            }
            connectionState = .failed(error.localizedDescription)
            if !wasUnavailable {
                recordActivity(
                    .coverageUnavailable,
                    actor: .system,
                    title: "Calendar coverage unavailable",
                    detail: "Calendar events could not be refreshed: \(error.localizedDescription).",
                    at: currentDate
                )
            }
        }
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
        let calendarName = availableCalendars.first(where: { $0.id == commitment.calendarID })?.name
            ?? commitment.calendarID
        let accountName = connectedAccount?.id == commitment.accountID
            ? connectedAccount?.email ?? commitment.accountID
            : commitment.accountID
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
        return earlyReminderCommitment.id == commitment.id &&
            earlyReminderCommitment.startDate == commitment.startDate
    }

    public func localStartTimeText(for commitment: CalendarEvent) -> String {
        guard let startDate = commitment.startDate else { return "Time unavailable" }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        formatter.timeZone = .current
        var text = formatter.string(from: startDate)

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
        let occurrence = OccurrenceIdentity(commitment)
        return [strongAlertCommitment, earlyReminderCommitment, upcomingCommitment]
            .compactMap { $0 }
            .contains { OccurrenceIdentity($0) == occurrence }
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
        if clearedEarlyReminderEventID != nextProtectedCommitment?.id ||
            clearedEarlyReminderEventStartDate != nextProtectedCommitment?.startDate {
            clearedEarlyReminderEventID = nil
            clearedEarlyReminderEventStartDate = nil
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
                clearedEarlyReminderEventStartDate == startDate) else {
            earlyReminderCommitment = nil
            return
        }

        let isNewEarlyReminder = earlyReminderCommitment?.id != nextProtectedCommitment.id ||
            earlyReminderCommitment?.startDate != startDate
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
            guard !event.isAllDay,
                  event.startDate != nil,
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

    private func recordDecision(
        _ decision: CommitmentProtectionDecision,
        for commitment: CalendarEvent,
        message: String
    ) {
        decisionOccurrence = OccurrenceIdentity(commitment)
        currentCommitmentDecision = decision
        decisionCommitment = commitment
        if let earlyReminderCommitment,
           OccurrenceIdentity(earlyReminderCommitment) == decisionOccurrence {
            self.earlyReminderCommitment = nil
        }
        if let strongAlertCommitment,
           OccurrenceIdentity(strongAlertCommitment) == decisionOccurrence {
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
           !eligibleEvents.contains(where: { OccurrenceIdentity($0) == lastActionOccurrence }) {
            clearLastActionMessage()
        }

        if let decisionOccurrence {
            if let matchingCommitment = eligibleEvents.first(where: {
                OccurrenceIdentity($0) == decisionOccurrence
            }) {
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
           !eligibleEvents.contains(where: { OccurrenceIdentity($0) == snoozedOccurrence }) {
            self.snoozedOccurrence = nil
            snoozedUntil = nil
            saveConfiguration()
        }
    }

    private func isSnoozed(_ commitment: CalendarEvent, at date: Date) -> Bool {
        guard snoozedOccurrence == OccurrenceIdentity(commitment),
              let snoozedUntil else {
            return false
        }
        return date < snoozedUntil
    }

    private func isDecisionActive(_ commitment: CalendarEvent) -> Bool {
        isDecisionActive(for: OccurrenceIdentity(commitment))
    }

    private func isDecisionActive(for occurrence: OccurrenceIdentity) -> Bool {
        decisionOccurrence == occurrence && currentCommitmentDecision != nil
    }

    private func isUpcoming(_ commitment: CalendarEvent, at date: Date) -> Bool {
        guard let startDate = commitment.startDate else { return false }
        return startDate > date
    }

    private func isProtectionAvailable(for commitment: CalendarEvent, at date: Date) -> Bool {
        !isDecisionActive(commitment) &&
            !isSnoozed(commitment, at: date) &&
            !suppressedPostStartAcceptanceOccurrences.contains(OccurrenceIdentity(commitment))
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
                    clearedEarlyReminderEventStartDate == startDate),
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
        if decisionOccurrence == OccurrenceIdentity(commitment),
           currentCommitmentDecision != nil {
            clearStrongAlertState()
            return
        }

        if strongAlertEventID != commitment.id ||
            strongAlertEventStartDate != commitment.startDate {
            strongAlertEventID = commitment.id
            strongAlertEventStartDate = commitment.startDate
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
    }

    private func saveConfiguration() {
        guard let connectedAccount else { return }

        let configuration = SavedConfiguration(
            accountID: connectedAccount.id,
            selectedCalendarIDs: selectedCalendarIDs.sorted(),
            isProtectionConfirmed: isProtectionConfirmed,
            decisionOccurrence: decisionOccurrence.map(SavedOccurrence.init),
            currentCommitmentDecision: currentCommitmentDecision,
            snoozedOccurrence: snoozedOccurrence.map(SavedOccurrence.init),
            snoozedUntil: snoozedUntil,
            pauseUntil: pauseUntil,
            observedUnacceptedOccurrences: observedUnacceptedOccurrences.map(SavedOccurrence.init),
            suppressedPostStartAcceptanceOccurrences: suppressedPostStartAcceptanceOccurrences.map(SavedOccurrence.init)
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
        snoozedOccurrence = nil
        snoozedUntil = nil
        pauseUntil = nil
        observedUnacceptedOccurrences = []
        suppressedPostStartAcceptanceOccurrences = []
        clearLocalDecision()
        clearLastActionMessage()
    }

    private func clearDisplayedProtectionState() {
        upcomingCommitment = nil
        earlyReminderCommitment = nil
        clearStrongAlertState()
    }

    private func clearStrongAlertState() {
        isStrongAlertPresented = false
        strongAlertCommitment = nil
        strongAlertEventID = nil
        strongAlertEventStartDate = nil
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

    private func recordActivity(
        _ kind: ProtectionActivityKind,
        actor: ProtectionActivityActor,
        title: String,
        detail: String,
        commitment: CalendarEvent? = nil,
        at date: Date? = nil
    ) {
        let occurredAt = date ?? now()
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
                accountID: connectedAccount?.id,
                accountEmail: connectedAccount?.email
            ),
            at: 0
        )
        saveActivityLog()
        saveConfiguration()
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

    var errorDescription: String? {
        "The saved Google account could not be restored safely. Connect it again."
    }
}
