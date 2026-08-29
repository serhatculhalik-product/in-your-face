import AppKit
import CommitmentProtection
import Foundation

/// A deterministic Google Calendar adapter used only by the public Test First Run profile.
///
/// It intentionally never opens a browser or creates a Google grant. The connection looks
/// realistic enough to exercise account and Monitored Calendar onboarding while every value
/// remains clearly synthetic.
struct TestFirstRunCalendarConnector: GoogleCalendarConnecting, Sendable {
    static let account = GoogleAccount(
        id: "test-first-run-account",
        email: "test.user@example.invalid",
        displayName: "Test User"
    )

    static let calendars = [
        CalendarOption(
            id: "test-first-run-work",
            name: "Work (Simulated)",
            accountID: account.id
        ),
        CalendarOption(
            id: "test-first-run-personal",
            name: "Personal (Simulated)",
            accountID: account.id
        )
    ]

    private static let connection = GoogleCalendarConnection(
        account: account,
        calendars: calendars
    )

    func connect() async throws -> GoogleCalendarConnection {
        Self.connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        accountID == Self.account.id ? Self.connection : nil
    }

    func disconnect(accountID: String) throws {}

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        []
    }
}

@MainActor
final class SimulatedLaunchAtLoginController: LaunchAtLoginControlling {
    private static let enabledKey = "test-first-run.launch-at-login-enabled"
    private let stateStore: UserDefaults

    init(stateStore: UserDefaults) {
        self.stateStore = stateStore
    }

    var isEnabled: Bool {
        stateStore.bool(forKey: Self.enabledKey)
    }

    func enable() throws {
        stateStore.set(true, forKey: Self.enabledKey)
    }

    func disable() throws {
        stateStore.set(false, forKey: Self.enabledKey)
    }
}

enum BlockingPermissionKind: String, Identifiable, Sendable {
    case accessibility
    case inputMonitoring

    var id: String { rawValue }
}

@MainActor
final class BlockingPermissionController: ObservableObject {
    enum Mode {
        case system
        case simulated(UserDefaults)
    }

    private static let accessibilityKey = "test-first-run.permission.accessibility"
    private static let inputMonitoringKey = "test-first-run.permission.input-monitoring"

    let mode: Mode
    @Published private(set) var simulatedAccessibilityPermission = false
    @Published private(set) var simulatedInputMonitoringPermission = false
    @Published var pendingSimulation: BlockingPermissionKind?

    init(mode: Mode) {
        self.mode = mode
        if case .simulated(let stateStore) = mode {
            simulatedAccessibilityPermission = stateStore.bool(forKey: Self.accessibilityKey)
            simulatedInputMonitoringPermission = stateStore.bool(forKey: Self.inputMonitoringKey)
        }
    }

    var isSimulated: Bool {
        if case .simulated = mode { return true }
        return false
    }

    var hasAccessibilityPermission: Bool {
        switch mode {
        case .system:
            return AXIsProcessTrusted()
        case .simulated:
            return simulatedAccessibilityPermission
        }
    }

    var hasInputMonitoringPermission: Bool {
        switch mode {
        case .system:
            return CGPreflightListenEventAccess()
        case .simulated:
            return simulatedInputMonitoringPermission
        }
    }

    func request(_ permission: BlockingPermissionKind) {
        switch mode {
        case .system:
            openSystemSettings(for: permission)
        case .simulated:
            pendingSimulation = permission
        }
    }

    func resolveSimulation(allowed: Bool) {
        guard case .simulated(let stateStore) = mode,
              let permission = pendingSimulation else {
            pendingSimulation = nil
            return
        }

        if allowed {
            switch permission {
            case .accessibility:
                simulatedAccessibilityPermission = true
                stateStore.set(true, forKey: Self.accessibilityKey)
            case .inputMonitoring:
                simulatedInputMonitoringPermission = true
                stateStore.set(true, forKey: Self.inputMonitoringKey)
            }
        }
        pendingSimulation = nil
    }

    private func openSystemSettings(for permission: BlockingPermissionKind) {
        let section: String
        switch permission {
        case .accessibility:
            section = "Privacy_Accessibility"
        case .inputMonitoring:
            section = "Privacy_ListenEvent"
        }
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(section)"
        ) else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }
}
