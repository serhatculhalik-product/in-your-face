import XCTest
@testable import InYourFace

final class RuntimeSystemAdaptersTests: XCTestCase {
    func testFirstRunConnectorReturnsOnlySyntheticConnectionAndNoEvents() async throws {
        let connector = TestFirstRunCalendarConnector()

        let connection = try await connector.connect()
        let events = try await connector.loadEvents(
            accountID: connection.account.id,
            calendarID: connection.calendars[0].id,
            from: Date(),
            to: Date().addingTimeInterval(3_600)
        )

        XCTAssertEqual(connection.account.email, "test.user@example.invalid")
        XCTAssertTrue(connection.calendars.allSatisfy { $0.name.contains("Simulated") })
        XCTAssertTrue(events.isEmpty)
        let missingConnection = try await connector.restore(accountID: "unknown")
        XCTAssertNil(missingConnection)
    }

    @MainActor
    func testSimulatedLaunchAtLoginIsScopedToInjectedDefaults() throws {
        let suiteName = "RuntimeSystemAdaptersTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = SimulatedLaunchAtLoginController(stateStore: defaults)

        XCTAssertFalse(controller.isEnabled)
        try controller.enable()
        XCTAssertTrue(controller.isEnabled)
        try controller.disable()
        XCTAssertFalse(controller.isEnabled)
    }

    @MainActor
    func testSimulatedPermissionsNeverUseSystemPermissionState() throws {
        let suiteName = "RuntimeSystemAdaptersTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = BlockingPermissionController(mode: .simulated(defaults))

        XCTAssertFalse(controller.hasAccessibilityPermission)
        controller.request(.accessibility)
        controller.resolveSimulation(allowed: true)
        XCTAssertTrue(controller.hasAccessibilityPermission)

        controller.request(.inputMonitoring)
        controller.resolveSimulation(allowed: false)
        XCTAssertFalse(controller.hasInputMonitoringPermission)
    }
}
