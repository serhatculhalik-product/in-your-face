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

    public init(
        id: String,
        title: String,
        startDate: Date?,
        endDate: Date?,
        timeZoneIdentifier: String?,
        isAllDay: Bool,
        isAccepted: Bool,
        calendarID: String,
        accountID: String
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

public enum ConnectionState: Equatable, Sendable {
    case notConnected
    case connecting
    case connected
    case failed(String)
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
    @Published public private(set) var isLaunchAtLoginEnabled = false
    @Published public private(set) var upcomingCommitment: CalendarEvent?
    @Published public private(set) var earlyReminderCommitment: CalendarEvent?
    @Published public private(set) var earlyReminderLeadTimeMinutes: Int

    private let calendarConnector: any GoogleCalendarConnecting
    private let launchAtLogin: any LaunchAtLoginControlling
    private let stateStore: UserDefaults
    private let now: () -> Date
    private static let stateKey = "commitment-protection.configuration"
    private static let earlyReminderLeadTimeKey = "commitment-protection.early-reminder-lead-time"
    private var clearedEarlyReminderEventID: String?
    private var clearedEarlyReminderEventStartDate: Date?
    private var monitoringTask: Task<Void, Never>?
    private var refreshGeneration = 0

    private struct SavedConfiguration: Codable {
        let accountID: String
        let selectedCalendarIDs: [String]
        let isProtectionConfirmed: Bool

        private enum CodingKeys: String, CodingKey {
            case accountID
            case selectedCalendarIDs
            case isProtectionConfirmed
        }

        init(accountID: String, selectedCalendarIDs: [String], isProtectionConfirmed: Bool) {
            self.accountID = accountID
            self.selectedCalendarIDs = selectedCalendarIDs
            self.isProtectionConfirmed = isProtectionConfirmed
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accountID = try container.decode(String.self, forKey: .accountID)
            selectedCalendarIDs = try container.decode([String].self, forKey: .selectedCalendarIDs)
            isProtectionConfirmed = try container.decodeIfPresent(Bool.self, forKey: .isProtectionConfirmed) ?? false
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
        let savedLeadTime = stateStore.integer(forKey: Self.earlyReminderLeadTimeKey)
        earlyReminderLeadTimeMinutes = savedLeadTime == 0
            ? 10
            : Self.clampedEarlyReminderLeadTime(savedLeadTime)

        do {
            try launchAtLogin.enable()
        } catch {
            isLaunchAtLoginEnabled = launchAtLogin.isEnabled
        }
        isLaunchAtLoginEnabled = launchAtLogin.isEnabled
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
        if earlyReminderCommitment != nil && !isBlockingAvailable {
            return .unavailable
        }
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
            return isLaunchAtLoginEnabled
                ? "Active Protection"
                : "Active Protection · Login Needs Attention"
        case .unavailable:
            return "Coverage Needs Attention"
        }
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
            saveConfiguration()
            await refreshCommitmentProtection()
        } catch {
            connectionState = .failed(error.localizedDescription)
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
                return false
            }
        }

        connectedAccount = nil
        availableCalendars = []
        selectedCalendarIDs = []
        isProtectionConfirmed = false
        upcomingCommitment = nil
        earlyReminderCommitment = nil
        clearedEarlyReminderEventID = nil
        clearedEarlyReminderEventStartDate = nil
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
        invalidateRefreshes()
        clearProtectionState()
        saveConfiguration()
        Task { await refreshCommitmentProtection() }
    }

    @discardableResult
    public func confirmProtection() -> Bool {
        guard connectedAccount != nil, !selectedCalendarIDs.isEmpty else { return false }
        isProtectionConfirmed = true
        invalidateRefreshes()
        saveConfiguration()
        Task { await refreshCommitmentProtection() }
        return true
    }

    public func setBlockingAvailability(_ isAvailable: Bool) {
        isBlockingAvailable = isAvailable
    }

    public func setEarlyReminderLeadTime(minutes: Int) {
        let clampedMinutes = Self.clampedEarlyReminderLeadTime(minutes)
        guard clampedMinutes != earlyReminderLeadTimeMinutes else { return }

        earlyReminderLeadTimeMinutes = clampedMinutes
        stateStore.set(clampedMinutes, forKey: Self.earlyReminderLeadTimeKey)
        isProtectionConfirmed = false
        invalidateRefreshes()
        clearProtectionState()
        saveConfiguration()
        Task { await refreshCommitmentProtection() }
    }

    public func startMonitoring() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshCommitmentProtection()
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    public func refreshCommitmentProtection() async {
        await refreshCommitmentProtection(at: now())
    }

    public func refreshCommitmentProtection(at currentDate: Date) async {
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
        let endDate = currentDate.addingTimeInterval(24 * 60 * 60)

        do {
            var events: [CalendarEvent] = []
            for calendar in selectedCalendars {
                events += try await calendarConnector.loadEvents(
                    accountID: connectedAccount.id,
                    calendarID: calendar.id,
                    from: currentDate,
                    to: endDate
                )
            }

            guard generation == refreshGeneration else { return }
            connectionState = .connected

            let nextCommitment = events
                .filter { event in
                    guard event.isEligibleForProtection,
                          let startDate = event.startDate,
                          let endDate = event.endDate else {
                        return false
                    }
                    return startDate > currentDate && endDate > currentDate
                }
                .sorted { left, right in
                    guard let leftStart = left.startDate,
                          let rightStart = right.startDate else {
                        return left.id < right.id
                    }
                    return leftStart == rightStart ? left.id < right.id : leftStart < rightStart
                }
                .first

            upcomingCommitment = nextCommitment
            if clearedEarlyReminderEventID != nextCommitment?.id ||
                clearedEarlyReminderEventStartDate != nextCommitment?.startDate {
                clearedEarlyReminderEventID = nil
                clearedEarlyReminderEventStartDate = nil
            }

            guard let nextCommitment,
                  let startDate = nextCommitment.startDate,
                  currentDate >= startDate.addingTimeInterval(-Double(earlyReminderLeadTimeMinutes) * 60),
                  !(clearedEarlyReminderEventID == nextCommitment.id &&
                    clearedEarlyReminderEventStartDate == startDate) else {
                earlyReminderCommitment = nil
                return
            }

            earlyReminderCommitment = nextCommitment
        } catch {
            guard generation == refreshGeneration else { return }
            clearDisplayedProtectionState()
            connectionState = .failed(error.localizedDescription)
        }
    }

    public func presentTestAlert() {
        isTestAlertPresented = true
    }

    public func dismissTestAlert() {
        isTestAlertPresented = false
    }

    public func clearEarlyReminder() {
        guard let earlyReminderCommitment else { return }
        clearedEarlyReminderEventID = earlyReminderCommitment.id
        clearedEarlyReminderEventStartDate = earlyReminderCommitment.startDate
        self.earlyReminderCommitment = nil
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

    private func loadConfiguration() -> SavedConfiguration? {
        guard let data = stateStore.data(forKey: Self.stateKey) else { return nil }
        return try? JSONDecoder().decode(SavedConfiguration.self, from: data)
    }

    private func saveConfiguration() {
        guard let connectedAccount else { return }

        let configuration = SavedConfiguration(
            accountID: connectedAccount.id,
            selectedCalendarIDs: selectedCalendarIDs.sorted(),
            isProtectionConfirmed: isProtectionConfirmed
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
    }

    private func clearDisplayedProtectionState() {
        upcomingCommitment = nil
        earlyReminderCommitment = nil
    }
}

private enum ProtectionFlowError: LocalizedError {
    case restoredAccountMismatch

    var errorDescription: String? {
        "The saved Google account could not be restored safely. Connect it again."
    }
}
