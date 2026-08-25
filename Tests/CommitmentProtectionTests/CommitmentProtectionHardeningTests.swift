import Foundation
import XCTest
@testable import CommitmentProtection

@MainActor
final class CommitmentProtectionHardeningTests: XCTestCase {
    func testConfirmedCoverageIsCheckingUntilItsFirstRefreshSucceeds() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let account = GoogleAccount(id: "checking-account", email: "checking@example.com", displayName: "Checking")
        let calendar = CalendarOption(id: "checking-calendar", name: "Work", accountID: account.id)
        let state = FirstRefreshGate()
        let flow = makeFlow(
            connector: FirstRefreshCheckingConnector(
                connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
                state: state
            ),
            now: now
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await waitUntil { await state.hasStarted }

        XCTAssertEqual(flow.coverage(for: account.id), .checking)

        await state.release()
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.coverage(for: account.id), .fresh)
    }

    func testOverlappingRefreshTriggersCoalesceIntoOneLatestRerun() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let account = GoogleAccount(id: "coalescing-account", email: "coalescing@example.com", displayName: "Coalescing")
        let calendar = CalendarOption(id: "coalescing-calendar", name: "Work", accountID: account.id)
        let state = CoalescingRefreshState()
        let flow = makeFlow(
            connector: CoalescingRefreshConnector(
                connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
                state: state
            ),
            now: now
        )
        await activateProtection(flow, calendarID: calendar.id, at: now)
        await state.prepareToHoldNextLoad()

        let firstDate = now.addingTimeInterval(60)
        let supersededDate = now.addingTimeInterval(120)
        let latestDate = now.addingTimeInterval(180)
        let firstRefresh = Task { @MainActor in
            await flow.refreshCommitmentProtection(at: firstDate)
        }
        await waitUntil { await state.callCount == 1 }
        XCTAssertTrue(flow.isRefreshingCoverage)

        let supersededRefresh = Task { @MainActor in
            await flow.refreshCommitmentProtection(at: supersededDate)
        }
        let latestRefresh = Task { @MainActor in
            await flow.refreshCommitmentProtection(at: latestDate)
        }
        for _ in 0..<10 {
            await Task.yield()
        }
        await state.releaseHeldLoad()

        await firstRefresh.value
        await supersededRefresh.value
        await latestRefresh.value
        XCTAssertFalse(flow.isRefreshingCoverage)

        let callCount = await state.callCount
        let lastRequestedEndDate = await state.lastRequestedEndDate
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(
            lastRequestedEndDate,
            latestDate.addingTimeInterval(24 * 60 * 60)
        )
    }

    func testDelayedFailingAccountDoesNotDelayHealthyAccountsStrongAlert() async {
        let baseline = Date(timeIntervalSince1970: 1_000_000)
        let alertDate = baseline.addingTimeInterval(10 * 60)
        let delayedAccount = GoogleAccount(id: "a-delayed", email: "delayed@example.com", displayName: "Delayed")
        let delayedCalendar = CalendarOption(id: "delayed-calendar", name: "Delayed", accountID: delayedAccount.id)
        let healthyAccount = GoogleAccount(id: "z-healthy", email: "healthy@example.com", displayName: "Healthy")
        let healthyCalendar = CalendarOption(id: "healthy-calendar", name: "Healthy", accountID: healthyAccount.id)
        let healthyCommitment = CalendarEvent(
            id: "healthy-commitment",
            title: "Healthy account commitment",
            startDate: alertDate,
            endDate: alertDate.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: healthyCalendar.id,
            accountID: healthyAccount.id
        )
        let state = AccountIsolationRefreshState(
            connections: [
                GoogleCalendarConnection(account: delayedAccount, calendars: [delayedCalendar]),
                GoogleCalendarConnection(account: healthyAccount, calendars: [healthyCalendar])
            ],
            events: [healthyCommitment],
            delayedAccountID: delayedAccount.id
        )
        let flow = makeFlow(
            connector: AccountIsolationRefreshConnector(state: state),
            now: baseline
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: delayedCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await flow.refreshCommitmentProtection(at: baseline)
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: healthyCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await flow.refreshCommitmentProtection(at: baseline)
        XCTAssertFalse(flow.isStrongAlertPresented)

        await state.delayAndFailNextRefresh()
        let refresh = Task { @MainActor in
            await flow.refreshCommitmentProtection(at: alertDate)
        }
        await waitUntil { await state.delayedLoadHasStarted }
        for _ in 0..<100 where !flow.isStrongAlertPresented {
            await Task.yield()
        }

        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertEqual(flow.strongAlertCommitment, healthyCommitment)

        await state.releaseDelayedFailure()
        await refresh.value
        if case .unavailable = flow.coverage(for: delayedAccount.id) {
            // The delayed failure is isolated after healthy protection is already visible.
        } else {
            XCTFail("Expected delayed account coverage to become unavailable.")
        }
    }

    func testFailedMeetingLinkOpenKeepsStrongAlertActiveAndAllowsRetry() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let account = GoogleAccount(id: "join-account", email: "join@example.com", displayName: "Join")
        let calendar = CalendarOption(id: "join-calendar", name: "Work", accountID: account.id)
        let meetingLink = URL(string: "https://meet.google.com/abc-defg-hij")!
        let commitment = CalendarEvent(
            id: "join-event",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: meetingLink
        )
        let flow = makeFlow(
            connector: StaticHardeningConnector(
                connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
                events: [commitment]
            ),
            now: now
        )

        await activateProtection(flow, calendarID: calendar.id, at: now)

        XCTAssertFalse(flow.openStrongAlertMeetingLink(using: meetingLink) { _ in false })
        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertEqual(flow.strongAlertCommitment, commitment)
        XCTAssertNil(flow.currentCommitmentDecision)
        XCTAssertTrue(flow.lastActionMessage?.contains("Protection remains active") == true)
        XCTAssertEqual(
            flow.meetingLinkOpenFailureMessage(for: commitment),
            flow.lastActionMessage
        )

        XCTAssertTrue(flow.openStrongAlertMeetingLink(using: meetingLink) { $0 == meetingLink })
        XCTAssertFalse(flow.isStrongAlertPresented)
        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertEqual(flow.currentCommitmentDecision, .joined)
        XCTAssertEqual(
            flow.lastActionMessage,
            "Meeting link opened. Reminders stopped for this occurrence."
        )
        XCTAssertNil(flow.meetingLinkOpenFailureMessage(for: commitment))

        var staleActionOpenedLink = false
        XCTAssertFalse(flow.openStrongAlertMeetingLink(using: meetingLink) { _ in
            staleActionOpenedLink = true
            return true
        })
        XCTAssertFalse(staleActionOpenedLink)
        XCTAssertEqual(
            flow.activityLog.filter { $0.kind == .joined }.count,
            1
        )
    }

    private func makeFlow(
        connector: any GoogleCalendarConnecting,
        now: Date
    ) -> CommitmentProtectionFlow {
        let suiteName = "CommitmentProtectionHardeningTests.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            stateStore.removePersistentDomain(forName: suiteName)
        }
        return CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: HardeningLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<100 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for the test condition.")
    }

    private func activateProtection(
        _ flow: CommitmentProtectionFlow,
        calendarID: String,
        at date: Date
    ) async {
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendarID)
        XCTAssertTrue(flow.confirmProtection())
        await flow.refreshCommitmentProtection(at: date)
    }
}

private struct StaticHardeningConnector: GoogleCalendarConnecting {
    let connection: GoogleCalendarConnection
    let events: [CalendarEvent]

    func connect() async throws -> GoogleCalendarConnection {
        connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        accountID == connection.account.id ? connection : nil
    }

    func disconnect(accountID: String) throws {}

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

private actor FirstRefreshGate {
    private(set) var hasStarted = false
    private var shouldHold = true
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        guard shouldHold else { return }
        hasStarted = true
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        shouldHold = false
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor CoalescingRefreshState {
    private(set) var callCount = 0
    private(set) var lastRequestedEndDate: Date?
    private var shouldHoldNextLoad = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func prepareToHoldNextLoad() {
        callCount = 0
        lastRequestedEndDate = nil
        shouldHoldNextLoad = true
    }

    func load(until endDate: Date) async {
        callCount += 1
        lastRequestedEndDate = endDate
        guard shouldHoldNextLoad else { return }
        shouldHoldNextLoad = false
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func releaseHeldLoad() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor AccountIsolationRefreshState {
    private var connections: [GoogleCalendarConnection]
    private let allConnections: [GoogleCalendarConnection]
    private let events: [CalendarEvent]
    private let delayedAccountID: String
    private var shouldDelayAndFail = false
    private(set) var delayedLoadHasStarted = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(
        connections: [GoogleCalendarConnection],
        events: [CalendarEvent],
        delayedAccountID: String
    ) {
        self.connections = connections
        allConnections = connections
        self.events = events
        self.delayedAccountID = delayedAccountID
    }

    func connect() throws -> GoogleCalendarConnection {
        guard !connections.isEmpty else { throw AccountIsolationError.unavailable }
        return connections.removeFirst()
    }

    func restore(accountID: String) -> GoogleCalendarConnection? {
        allConnections.first { $0.account.id == accountID }
    }

    func delayAndFailNextRefresh() {
        shouldDelayAndFail = true
        delayedLoadHasStarted = false
    }

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        if accountID == delayedAccountID, shouldDelayAndFail {
            shouldDelayAndFail = false
            delayedLoadHasStarted = true
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
            throw AccountIsolationError.unavailable
        }
        return events.filter {
            $0.accountID == accountID &&
                $0.calendarID == calendarID &&
                ($0.startDate ?? .distantPast) < endDate &&
                ($0.endDate ?? .distantFuture) > startDate
        }
    }

    func releaseDelayedFailure() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private struct FirstRefreshCheckingConnector: GoogleCalendarConnecting {
    let connection: GoogleCalendarConnection
    let state: FirstRefreshGate

    func connect() async throws -> GoogleCalendarConnection {
        connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        accountID == connection.account.id ? connection : nil
    }

    func disconnect(accountID: String) throws {}

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        await state.waitForRelease()
        return []
    }
}

private struct CoalescingRefreshConnector: GoogleCalendarConnecting {
    let connection: GoogleCalendarConnection
    let state: CoalescingRefreshState

    func connect() async throws -> GoogleCalendarConnection {
        connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        accountID == connection.account.id ? connection : nil
    }

    func disconnect(accountID: String) throws {}

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        await state.load(until: endDate)
        return []
    }
}

private struct AccountIsolationRefreshConnector: GoogleCalendarConnecting {
    let state: AccountIsolationRefreshState

    func connect() async throws -> GoogleCalendarConnection {
        try await state.connect()
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        await state.restore(accountID: accountID)
    }

    func disconnect(accountID: String) throws {}

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        try await state.loadEvents(
            accountID: accountID,
            calendarID: calendarID,
            from: startDate,
            to: endDate
        )
    }
}

private enum AccountIsolationError: LocalizedError, Sendable {
    case unavailable

    var errorDescription: String? {
        "The delayed account is unavailable."
    }
}

@MainActor
private final class HardeningLaunchAtLoginController: LaunchAtLoginControlling {
    private(set) var isEnabled = true

    func enable() throws {
        isEnabled = true
    }
}
