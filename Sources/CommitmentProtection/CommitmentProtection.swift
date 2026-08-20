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

public struct MonitoredCalendar: Codable, Equatable, Identifiable, Sendable {
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
    public let calendars: [MonitoredCalendar]

    public init(account: GoogleAccount, calendars: [MonitoredCalendar]) {
        self.account = account
        self.calendars = calendars
    }
}

public protocol GoogleCalendarConnecting: Sendable {
    func connect() async throws -> GoogleCalendarConnection
    func restore(accountID: String) async throws -> GoogleCalendarConnection?
}

@MainActor
public protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func enable() throws
}

public enum ProtectionStatus: Equatable, Sendable {
    case noCoverage
    case active
    case needsAttention
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
    @Published public private(set) var availableCalendars: [MonitoredCalendar] = []
    @Published public private(set) var selectedCalendarIDs: Set<String> = []
    @Published public private(set) var connectionState: ConnectionState = .notConnected
    @Published public private(set) var isRestoringConnection = false
    @Published public private(set) var isTestAlertPresented = false
    @Published public private(set) var isLaunchAtLoginEnabled = false

    private let calendarConnector: any GoogleCalendarConnecting
    private let stateStore: UserDefaults
    private static let stateKey = "commitment-protection.configuration"

    private struct SavedConfiguration: Codable {
        let accountID: String
        let selectedCalendarIDs: [String]
    }

    public init(
        calendarConnector: any GoogleCalendarConnecting,
        launchAtLogin: any LaunchAtLoginControlling,
        stateStore: UserDefaults = .standard
    ) {
        self.calendarConnector = calendarConnector
        self.stateStore = stateStore

        do {
            try launchAtLogin.enable()
        } catch {
            isLaunchAtLoginEnabled = launchAtLogin.isEnabled
        }
        isLaunchAtLoginEnabled = launchAtLogin.isEnabled
    }

    public var status: ProtectionStatus {
        guard let connectedAccount else { return .noCoverage }

        let selectedCalendars = availableCalendars.filter {
            $0.accountID == connectedAccount.id && selectedCalendarIDs.contains($0.id)
        }
        guard !selectedCalendars.isEmpty else { return .noCoverage }
        return isLaunchAtLoginEnabled ? .active : .needsAttention
    }

    public var menuBarTitle: String {
        switch status {
        case .noCoverage:
            return "No Coverage"
        case .active:
            let selectedNames = availableCalendars
                .filter {
                    $0.accountID == connectedAccount?.id && selectedCalendarIDs.contains($0.id)
                }
                .map(\.name)

            guard selectedNames.count == 1, let calendarName = selectedNames.first else {
                return "Active Protection"
            }
            return "Protected: \(calendarName)"
        case .needsAttention:
            return "Start at Login Needs Attention"
        }
    }

    public func connectGoogleAccount() async {
        connectionState = .connecting

        do {
            let connection = try await calendarConnector.connect()
            let shouldPreserveSelection = connectedAccount?.id == connection.account.id

            connectedAccount = connection.account
            availableCalendars = connection.calendars
            selectedCalendarIDs = shouldPreserveSelection
                ? selectedCalendarIDs.intersection(Set(connection.calendars.map(\.id)))
                : []
            connectionState = .connected
            saveConfiguration()
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    public func restoreSavedConnection() async {
        guard let savedConfiguration = loadConfiguration() else { return }

        isRestoringConnection = true
        defer { isRestoringConnection = false }

        do {
            guard let connection = try await calendarConnector.restore(accountID: savedConfiguration.accountID) else {
                return
            }
            guard connection.account.id == savedConfiguration.accountID else {
                throw ProtectionFlowError.restoredAccountMismatch
            }

            connectedAccount = connection.account
            availableCalendars = connection.calendars
            selectedCalendarIDs = Set(savedConfiguration.selectedCalendarIDs)
                .intersection(Set(connection.calendars.map(\.id)))
            connectionState = .connected
            saveConfiguration()
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
        saveConfiguration()
    }

    public func presentTestAlert() {
        isTestAlertPresented = true
    }

    public func dismissTestAlert() {
        isTestAlertPresented = false
    }

    private func loadConfiguration() -> SavedConfiguration? {
        guard let data = stateStore.data(forKey: Self.stateKey) else { return nil }
        return try? JSONDecoder().decode(SavedConfiguration.self, from: data)
    }

    private func saveConfiguration() {
        guard let connectedAccount else { return }

        let configuration = SavedConfiguration(
            accountID: connectedAccount.id,
            selectedCalendarIDs: selectedCalendarIDs.sorted()
        )
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        stateStore.set(data, forKey: Self.stateKey)
    }
}

private enum ProtectionFlowError: LocalizedError {
    case restoredAccountMismatch

    var errorDescription: String? {
        "The saved Google account could not be restored safely. Connect it again."
    }
}
