import Combine
import Foundation

public struct GoogleAccount: Equatable, Identifiable, Sendable {
    public let id: String
    public let email: String
    public let displayName: String

    public init(id: String, email: String, displayName: String) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }
}

public struct MonitoredCalendar: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let accountID: String

    public init(id: String, name: String, accountID: String) {
        self.id = id
        self.name = name
        self.accountID = accountID
    }
}

public struct GoogleCalendarConnection: Equatable, Sendable {
    public let account: GoogleAccount
    public let calendars: [MonitoredCalendar]

    public init(account: GoogleAccount, calendars: [MonitoredCalendar]) {
        self.account = account
        self.calendars = calendars
    }
}

public protocol GoogleCalendarConnecting: Sendable {
    func connect() async throws -> GoogleCalendarConnection
}

@MainActor
public protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func enable() throws
}

public enum ProtectionStatus: Equatable, Sendable {
    case noCoverage
    case active
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
    @Published public private(set) var isTestAlertPresented = false
    @Published public private(set) var isLaunchAtLoginEnabled = false

    private let calendarConnector: any GoogleCalendarConnecting
    private let launchAtLogin: any LaunchAtLoginControlling

    public init(
        calendarConnector: any GoogleCalendarConnecting,
        launchAtLogin: any LaunchAtLoginControlling
    ) {
        self.calendarConnector = calendarConnector
        self.launchAtLogin = launchAtLogin

        do {
            try launchAtLogin.enable()
        } catch {
            isLaunchAtLoginEnabled = launchAtLogin.isEnabled
        }
        isLaunchAtLoginEnabled = launchAtLogin.isEnabled
    }

    public var status: ProtectionStatus {
        selectedCalendarIDs.isEmpty ? .noCoverage : .active
    }

    public var menuBarTitle: String {
        switch status {
        case .noCoverage:
            return "No Coverage"
        case .active:
            let selectedNames = availableCalendars
                .filter { selectedCalendarIDs.contains($0.id) }
                .map(\.name)

            guard selectedNames.count == 1, let calendarName = selectedNames.first else {
                return "Active Protection"
            }
            return "Protected: \(calendarName)"
        }
    }

    public func connectGoogleAccount() async {
        connectionState = .connecting

        do {
            let connection = try await calendarConnector.connect()
            connectedAccount = connection.account
            availableCalendars = connection.calendars
            selectedCalendarIDs = selectedCalendarIDs.intersection(Set(connection.calendars.map(\.id)))
            connectionState = .connected
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    public func setCalendarSelected(_ isSelected: Bool, calendarID: String) {
        guard availableCalendars.contains(where: { $0.id == calendarID }) else { return }

        if isSelected {
            selectedCalendarIDs.insert(calendarID)
        } else {
            selectedCalendarIDs.remove(calendarID)
        }
    }

    public func presentTestAlert() {
        isTestAlertPresented = true
    }

    public func dismissTestAlert() {
        isTestAlertPresented = false
    }
}
