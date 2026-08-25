import Foundation
import XCTest
@testable import CommitmentProtection

@MainActor
final class GoogleCalendarCredentialSessionTests: XCTestCase {
    func testLegacyPersistedRefreshTokenIsDeletedWithoutRestoringAccount() async throws {
        let accountID = "legacy-session-\(UUID().uuidString)"
        let defaultsKey = "google.refreshToken.\(accountID)"
        let (legacyDefaults, suiteName) = makeIsolatedDefaults()
        legacyDefaults.set("persisted-refresh-token", forKey: defaultsKey)
        defer { legacyDefaults.removePersistentDomain(forName: suiteName) }

        let requests = RequestCounter()
        let credentialSession = GoogleSessionCredentialStore(legacyDefaults: legacyDefaults)
        let connector = GoogleCalendarConnector(
            configuration: GoogleCalendarOAuthConfiguration(clientID: "client-id"),
            requestExecutor: { request in
                await requests.record(request)
                throw URLError(.badServerResponse)
            },
            credentialSession: credentialSession
        )

        let connection = try await connector.restore(accountID: accountID)

        XCTAssertNil(connection)
        XCTAssertNil(legacyDefaults.string(forKey: defaultsKey))
        let requestCount = await requests.count
        XCTAssertEqual(requestCount, 0)
    }

    func testConnectorCopiesShareCurrentSessionButANewSessionHasNoCredential() async throws {
        let accountID = "current-session-\(UUID().uuidString)"
        let (legacyDefaults, suiteName) = makeIsolatedDefaults()
        defer { legacyDefaults.removePersistentDomain(forName: suiteName) }

        let requests = RequestCounter()
        let credentialSession = GoogleSessionCredentialStore(legacyDefaults: legacyDefaults)
        credentialSession.save(refreshToken: "refresh-token", accountID: accountID)
        let connector = makeConnector(
            accountID: accountID,
            credentialSession: credentialSession,
            requests: requests
        )
        let copiedConnector = connector

        let restored = try await copiedConnector.restore(accountID: accountID)
        XCTAssertEqual(restored?.account.id, accountID)
        let requestsAfterRestore = await requests.count
        XCTAssertEqual(requestsAfterRestore, 3)

        let newSession = GoogleSessionCredentialStore(legacyDefaults: legacyDefaults)
        let relaunchedConnector = makeConnector(
            accountID: accountID,
            credentialSession: newSession,
            requests: requests
        )

        let relaunchedConnection = try await relaunchedConnector.restore(accountID: accountID)
        XCTAssertNil(relaunchedConnection)
        let finalRequestCount = await requests.count
        XCTAssertEqual(finalRequestCount, requestsAfterRestore)
    }

    func testRelaunchPreservesConfigurationButRequiresReconnectBeforeRefreshing() async {
        let account = GoogleAccount(
            id: "account-1",
            email: "person@example.com",
            displayName: "Person"
        )
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])
        let (stateStore, suiteName) = makeIsolatedDefaults()
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstConnector = SessionLifecycleConnector(connection: connection, restoresConnection: true)
        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: firstConnector,
            launchAtLogin: SessionLaunchAtLoginController(),
            stateStore: stateStore
        )
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: calendar.id)
        let didConfirmProtection = firstLaunch.confirmProtection()
        XCTAssertTrue(didConfirmProtection)

        let relaunchedConnector = SessionLifecycleConnector(connection: connection, restoresConnection: false)
        let relaunch = CommitmentProtectionFlow(
            calendarConnector: relaunchedConnector,
            launchAtLogin: SessionLaunchAtLoginController(),
            stateStore: stateStore
        )

        await relaunch.restoreSavedConnection()

        let restoredConnectionState = relaunch.connectionState
        let restoredCoverage = relaunch.coverage(for: account.id)
        let restoredCalendarIDs = relaunch.selectedCalendarIDs
        let restoredConfirmation = relaunch.isProtectionConfirmed
        let loadCountBeforeReconnect = await relaunchedConnector.loadEventCount
        XCTAssertEqual(restoredConnectionState, .reconnectRequired)
        XCTAssertEqual(restoredCoverage, .reconnectRequired)
        XCTAssertEqual(restoredCalendarIDs, [calendar.id])
        XCTAssertTrue(restoredConfirmation)
        XCTAssertEqual(loadCountBeforeReconnect, 0)

        await relaunch.reconnectGoogleAccount(accountID: account.id)

        let reconnectedState = relaunch.connectionState
        let reconnectedCalendarIDs = relaunch.selectedCalendarIDs
        let reconnectedConfirmation = relaunch.isProtectionConfirmed
        let loadCountAfterReconnect = await relaunchedConnector.loadEventCount
        XCTAssertEqual(reconnectedState, .connected)
        XCTAssertEqual(reconnectedCalendarIDs, [calendar.id])
        XCTAssertTrue(reconnectedConfirmation)
        XCTAssertEqual(loadCountAfterReconnect, 1)
    }

    func testTargetedReconnectRejectsADifferentGoogleAccount() async {
        let savedAccount = GoogleAccount(
            id: "saved-account",
            email: "saved@example.com",
            displayName: "Saved"
        )
        let savedCalendar = CalendarOption(
            id: "calendar-1",
            name: "Work",
            accountID: savedAccount.id
        )
        let savedConnection = GoogleCalendarConnection(
            account: savedAccount,
            calendars: [savedCalendar]
        )
        let (stateStore, suiteName) = makeIsolatedDefaults()
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: SessionLifecycleConnector(
                connection: savedConnection,
                restoresConnection: true
            ),
            launchAtLogin: SessionLaunchAtLoginController(),
            stateStore: stateStore
        )
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: savedCalendar.id)
        XCTAssertTrue(firstLaunch.confirmProtection())

        let differentAccount = GoogleAccount(
            id: "different-account",
            email: "different@example.com",
            displayName: "Different"
        )
        let relaunch = CommitmentProtectionFlow(
            calendarConnector: SessionLifecycleConnector(
                connection: GoogleCalendarConnection(account: differentAccount, calendars: []),
                restoresConnection: false
            ),
            launchAtLogin: SessionLaunchAtLoginController(),
            stateStore: stateStore
        )
        await relaunch.restoreSavedConnection()

        await relaunch.reconnectGoogleAccount(accountID: savedAccount.id)

        XCTAssertEqual(relaunch.connectionState, .reconnectRequired)
        XCTAssertEqual(relaunch.accountCoverages.map(\.account.id), [savedAccount.id])
        XCTAssertEqual(
            relaunch.accountConnectionError,
            "That is a different Google account. Choose the account shown in In Your Face to reconnect it."
        )
    }

    func testRelaunchDoesNotPresentCachedReminderBeforeReconnect() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let account = GoogleAccount(
            id: "account-1",
            email: "person@example.com",
            displayName: "Person"
        )
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])
        let imminentCommitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(65 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let (stateStore, suiteName) = makeIsolatedDefaults()
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: SessionLifecycleConnector(
                connection: connection,
                restoresConnection: true,
                events: [imminentCommitment]
            ),
            launchAtLogin: SessionLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(firstLaunch.confirmProtection())
        await firstLaunch.refreshCommitmentProtection(at: now)
        XCTAssertEqual(firstLaunch.earlyReminderCommitment, imminentCommitment)

        let relaunch = CommitmentProtectionFlow(
            calendarConnector: SessionLifecycleConnector(
                connection: connection,
                restoresConnection: false,
                events: [imminentCommitment]
            ),
            launchAtLogin: SessionLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )

        await relaunch.restoreSavedConnection()

        XCTAssertEqual(relaunch.connectionState, .reconnectRequired)
        XCTAssertNil(relaunch.earlyReminderCommitment)
        XCTAssertNil(relaunch.strongAlertCommitment)
    }

    func testWrongAccountReconnectDoesNotDisableAnotherHealthyAccount() async {
        let firstAccount = GoogleAccount(
            id: "account-1",
            email: "first@example.com",
            displayName: "First"
        )
        let firstCalendar = CalendarOption(
            id: "calendar-1",
            name: "First Work",
            accountID: firstAccount.id
        )
        let secondAccount = GoogleAccount(
            id: "account-2",
            email: "second@example.com",
            displayName: "Second"
        )
        let secondCalendar = CalendarOption(
            id: "calendar-2",
            name: "Second Work",
            accountID: secondAccount.id
        )
        let firstConnection = GoogleCalendarConnection(
            account: firstAccount,
            calendars: [firstCalendar]
        )
        let secondConnection = GoogleCalendarConnection(
            account: secondAccount,
            calendars: [secondCalendar]
        )
        let (stateStore, suiteName) = makeIsolatedDefaults()
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: QueuedSessionLifecycleConnector(
                connections: [firstConnection, secondConnection]
            ),
            launchAtLogin: SessionLaunchAtLoginController(),
            stateStore: stateStore
        )
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: firstCalendar.id)
        XCTAssertTrue(firstLaunch.confirmProtection())
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: secondCalendar.id)
        XCTAssertTrue(firstLaunch.confirmProtection())

        let relaunchConnector = QueuedSessionLifecycleConnector(
            connections: [secondConnection, secondConnection]
        )
        let relaunch = CommitmentProtectionFlow(
            calendarConnector: relaunchConnector,
            launchAtLogin: SessionLaunchAtLoginController(),
            stateStore: stateStore
        )
        await relaunch.restoreSavedConnection()
        await relaunch.reconnectGoogleAccount(accountID: secondAccount.id)
        XCTAssertEqual(
            relaunch.accountCoverages.first { $0.account.id == secondAccount.id }?.connectionState,
            .connected
        )

        await relaunch.reconnectGoogleAccount(accountID: firstAccount.id)

        XCTAssertEqual(
            relaunch.accountCoverages.first { $0.account.id == firstAccount.id }?.connectionState,
            .reconnectRequired
        )
        XCTAssertEqual(
            relaunch.accountCoverages.first { $0.account.id == secondAccount.id }?.connectionState,
            .connected
        )
        XCTAssertTrue(relaunchConnector.disconnectedAccountIDs.isEmpty)
    }

    func testHealthyAccountRefreshDoesNotRestoreCachedReminderFromAccountAwaitingReconnect() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstAccount = GoogleAccount(
            id: "account-1",
            email: "first@example.com",
            displayName: "First"
        )
        let firstCalendar = CalendarOption(
            id: "calendar-1",
            name: "First Work",
            accountID: firstAccount.id
        )
        let secondAccount = GoogleAccount(
            id: "account-2",
            email: "second@example.com",
            displayName: "Second"
        )
        let secondCalendar = CalendarOption(
            id: "calendar-2",
            name: "Second Work",
            accountID: secondAccount.id
        )
        let firstConnection = GoogleCalendarConnection(
            account: firstAccount,
            calendars: [firstCalendar]
        )
        let secondConnection = GoogleCalendarConnection(
            account: secondAccount,
            calendars: [secondCalendar]
        )
        let firstCommitment = CalendarEvent(
            id: "event-1",
            title: "First account review",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(65 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: firstCalendar.id,
            accountID: firstAccount.id
        )
        let (stateStore, suiteName) = makeIsolatedDefaults()
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: QueuedSessionLifecycleConnector(
                connections: [firstConnection, secondConnection],
                events: [firstCommitment]
            ),
            launchAtLogin: SessionLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: firstCalendar.id)
        XCTAssertTrue(firstLaunch.confirmProtection())
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: secondCalendar.id)
        XCTAssertTrue(firstLaunch.confirmProtection())
        await firstLaunch.refreshCommitmentProtection(at: now)
        XCTAssertEqual(firstLaunch.earlyReminderCommitment, firstCommitment)

        let relaunch = CommitmentProtectionFlow(
            calendarConnector: QueuedSessionLifecycleConnector(
                connections: [secondConnection]
            ),
            launchAtLogin: SessionLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await relaunch.restoreSavedConnection()
        await relaunch.reconnectGoogleAccount(accountID: secondAccount.id)

        XCTAssertEqual(
            relaunch.accountCoverages.first { $0.account.id == firstAccount.id }?.connectionState,
            .reconnectRequired
        )
        XCTAssertEqual(
            relaunch.accountCoverages.first { $0.account.id == secondAccount.id }?.connectionState,
            .connected
        )
        XCTAssertNil(relaunch.earlyReminderCommitment)
        XCTAssertNil(relaunch.strongAlertCommitment)
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "GoogleCalendarCredentialSessionTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeConnector(
        accountID: String,
        credentialSession: GoogleSessionCredentialStore,
        requests: RequestCounter
    ) -> GoogleCalendarConnector {
        GoogleCalendarConnector(
            configuration: GoogleCalendarOAuthConfiguration(clientID: "client-id"),
            requestExecutor: { request in
                await requests.record(request)
                guard let url = request.url else { throw URLError(.badURL) }
                let body: String
                switch url.host {
                case "oauth2.googleapis.com":
                    body = #"{"access_token":"access-token"}"#
                case "openidconnect.googleapis.com":
                    body = #"{"sub":"\#(accountID)","email":"person@example.com"}"#
                case "www.googleapis.com":
                    body = #"{"items":[]}"#
                default:
                    throw URLError(.unsupportedURL)
                }
                return (
                    Data(body.utf8),
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            },
            credentialSession: credentialSession
        )
    }
}

private final class SessionLifecycleConnector: GoogleCalendarConnecting, @unchecked Sendable {
    private let connection: GoogleCalendarConnection
    private let restoresConnection: Bool
    private let events: [CalendarEvent]
    private let state = SessionLifecycleConnectorState()

    init(
        connection: GoogleCalendarConnection,
        restoresConnection: Bool,
        events: [CalendarEvent] = []
    ) {
        self.connection = connection
        self.restoresConnection = restoresConnection
        self.events = events
    }

    var loadEventCount: Int {
        get async { await state.loadEventCount }
    }

    func connect() async throws -> GoogleCalendarConnection {
        connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        restoresConnection && accountID == connection.account.id ? connection : nil
    }

    func disconnect(accountID: String) throws {}

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        await state.recordLoad()
        return events.filter {
            $0.accountID == accountID &&
                $0.calendarID == calendarID &&
                ($0.startDate ?? .distantPast) < endDate &&
                ($0.endDate ?? .distantFuture) > startDate
        }
    }
}

private actor SessionLifecycleConnectorState {
    private(set) var loadEventCount = 0

    func recordLoad() {
        loadEventCount += 1
    }
}

private final class QueuedSessionLifecycleConnector: GoogleCalendarConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [GoogleCalendarConnection]
    private let events: [CalendarEvent]
    private var disconnectedIDs: [String] = []

    init(connections: [GoogleCalendarConnection], events: [CalendarEvent] = []) {
        self.connections = connections
        self.events = events
    }

    var disconnectedAccountIDs: [String] {
        lock.withLock { disconnectedIDs }
    }

    func connect() async throws -> GoogleCalendarConnection {
        try lock.withLock {
            guard !connections.isEmpty else { throw URLError(.cannotConnectToHost) }
            return connections.removeFirst()
        }
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        nil
    }

    func disconnect(accountID: String) throws {
        lock.withLock {
            disconnectedIDs.append(accountID)
        }
    }

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        events.filter {
            $0.accountID == accountID &&
                $0.calendarID == calendarID &&
                ($0.startDate ?? .distantPast) < endDate &&
                ($0.endDate ?? .distantFuture) > startDate
        }
    }
}

@MainActor
private final class SessionLaunchAtLoginController: LaunchAtLoginControlling {
    private(set) var isEnabled = false

    func enable() throws {
        isEnabled = true
    }
}

private actor RequestCounter {
    private(set) var count = 0

    func record(_ request: URLRequest) {
        count += 1
    }
}
