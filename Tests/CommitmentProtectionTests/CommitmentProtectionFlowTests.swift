import Foundation
import XCTest
@testable import CommitmentProtection

@MainActor
final class CommitmentProtectionFlowTests: XCTestCase {
    func testStartsWithNoCoverageAndEnablesLaunchAtLogin() {
        let launchAtLogin = TestLaunchAtLoginController()
        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(),
            launchAtLogin: launchAtLogin
        )

        XCTAssertEqual(flow.status, .noCoverage)
        XCTAssertTrue(flow.isLaunchAtLoginEnabled)
        XCTAssertTrue(launchAtLogin.enableWasCalled)
        XCTAssertEqual(flow.menuBarTitle, "No Coverage")
    }

    func testConnectingLoadsCalendarsButSelectionActivatesProtection() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = MonitoredCalendar(id: "calendar-1", name: "Work", accountID: account.id)
        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(
                connection: GoogleCalendarConnection(account: account, calendars: [calendar])
            ),
            launchAtLogin: TestLaunchAtLoginController()
        )

        await flow.connectGoogleAccount()

        XCTAssertEqual(flow.connectedAccount, account)
        XCTAssertEqual(flow.availableCalendars, [calendar])
        XCTAssertEqual(flow.status, .noCoverage)

        flow.setCalendarSelected(true, calendarID: calendar.id)

        XCTAssertEqual(flow.status, .active)
        XCTAssertEqual(flow.menuBarTitle, "Protected: Work")
    }

    func testSelectedCalendarProtectionRestoresAfterRelaunch() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = MonitoredCalendar(id: "calendar-1", name: "Work", accountID: account.id)
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])
        let suiteName = "CommitmentProtectionFlowTests.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(connection: connection),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: calendar.id)

        let relaunch = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(connection: connection),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )

        XCTAssertEqual(relaunch.status, .noCoverage)

        await relaunch.restoreSavedConnection()

        XCTAssertEqual(relaunch.connectedAccount, account)
        XCTAssertEqual(relaunch.availableCalendars, [calendar])
        XCTAssertEqual(relaunch.selectedCalendarIDs, [calendar.id])
        XCTAssertEqual(relaunch.status, .active)
    }

    func testTestAlertCanBePresentedAndDismissedWithoutACommitment() async {
        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(),
            launchAtLogin: TestLaunchAtLoginController()
        )

        XCTAssertFalse(flow.isTestAlertPresented)

        flow.presentTestAlert()
        XCTAssertTrue(flow.isTestAlertPresented)

        flow.dismissTestAlert()
        XCTAssertFalse(flow.isTestAlertPresented)
    }

    func testGoogleConnectionRequiresOAuthConfiguration() async {
        let connector = GoogleCalendarConnector(
            configuration: GoogleCalendarOAuthConfiguration(clientID: "")
        )

        do {
            _ = try await connector.connect()
            XCTFail("A missing OAuth client ID should prevent connection")
        } catch let error as GoogleCalendarConnectorError {
            XCTAssertEqual(error, .missingClientID)
        } catch {
            XCTFail("Unexpected connection error: \(error)")
        }
    }
}

private struct TestGoogleCalendarConnector: GoogleCalendarConnecting {
    let connection: GoogleCalendarConnection

    init(connection: GoogleCalendarConnection? = nil) {
        self.connection = connection ?? GoogleCalendarConnection(
            account: GoogleAccount(id: "default-account", email: "user@example.com", displayName: "User"),
            calendars: []
        )
    }

    func connect() async throws -> GoogleCalendarConnection {
        connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        connection.account.id == accountID ? connection : nil
    }
}

@MainActor
private final class TestLaunchAtLoginController: LaunchAtLoginControlling {
    private(set) var enableWasCalled = false
    private(set) var isEnabled = false

    func enable() throws {
        enableWasCalled = true
        isEnabled = true
    }
}
