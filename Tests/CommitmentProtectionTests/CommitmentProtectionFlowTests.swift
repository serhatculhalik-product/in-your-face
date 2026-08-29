import Foundation
import XCTest
@testable import CommitmentProtection

@MainActor
final class CommitmentProtectionFlowTests: XCTestCase {
    func testEarlyReminderStaysVisualUntilBlockingModeIsExplicitlyEnabled() {
        var mode = EarlyReminderBlockingMode()

        XCTAssertFalse(mode.shouldAttemptBlocking)

        mode.enableBlocking()

        XCTAssertTrue(mode.shouldAttemptBlocking)

        mode.disableBlocking()

        XCTAssertFalse(mode.shouldAttemptBlocking)
    }

    func testStartsWithNoCoverageAndLeavesLaunchAtLoginOff() {
        let launchAtLogin = TestLaunchAtLoginController(shouldEnable: false)
        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(),
            launchAtLogin: launchAtLogin
        )

        XCTAssertEqual(flow.status, .noCoverage)
        XCTAssertFalse(flow.isLaunchAtLoginEnabled)
        XCTAssertFalse(launchAtLogin.enableWasCalled)
        XCTAssertEqual(flow.menuBarTitle, "No Coverage")
    }

    func testLaunchAtLoginFailureCanBeRetried() {
        let launchAtLogin = TestLaunchAtLoginController(shouldEnable: false)
        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(),
            launchAtLogin: launchAtLogin
        )

        XCTAssertFalse(flow.isLaunchAtLoginEnabled)
        flow.requestLaunchAtLogin()
        XCTAssertNotNil(flow.launchAtLoginError)

        launchAtLogin.allowEnabling()
        flow.requestLaunchAtLogin()

        XCTAssertTrue(flow.isLaunchAtLoginEnabled)
        XCTAssertNil(flow.launchAtLoginError)
        XCTAssertEqual(launchAtLogin.enableCallCount, 2)
    }

    func testAppManagedDataResetLockBlocksAccountCalendarConfirmationAndLoginMutations() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let connectorState = TestGoogleCalendarConnectorState()
        let launchAtLogin = TestLaunchAtLoginController(shouldEnable: false)
        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(
                connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
                state: connectorState
            ),
            launchAtLogin: launchAtLogin
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertEqual(connectorState.connectCallCount, 1)
        XCTAssertFalse(flow.isProtectionConfirmed)

        flow.lockMutationsForAppManagedDataReset()

        await flow.connectGoogleAccount()
        await flow.reconnectGoogleAccount(accountID: account.id)
        flow.setCalendarSelected(false, calendarID: calendar.id)
        XCTAssertFalse(flow.confirmProtection())
        let didDisconnect = await flow.disconnectGoogleAccount(accountID: account.id)
        let didRemove = await flow.removeGoogleAccount(accountID: account.id)
        flow.requestLaunchAtLogin()

        XCTAssertFalse(didDisconnect)
        XCTAssertFalse(didRemove)
        XCTAssertTrue(flow.isAppManagedDataResetInProgress)
        XCTAssertTrue(flow.isGoogleAccountOperationInProgress)
        XCTAssertEqual(connectorState.connectCallCount, 1)
        XCTAssertFalse(connectorState.disconnectWasCalled)
        XCTAssertEqual(flow.selectedCalendarIDs(for: account.id), [calendar.id])
        XCTAssertFalse(flow.isProtectionConfirmed(for: account.id))
        XCTAssertEqual(launchAtLogin.enableCallCount, 0)
        XCTAssertFalse(flow.isLaunchAtLoginEnabled)
    }

    func testAppManagedDataResetLockBlocksPreferenceAndStorageMutations() async {
        let suiteName = "CommitmentProtectionFlowTests.resetPreferenceLock.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(
                connection: GoogleCalendarConnection(account: account, calendars: [calendar])
            ),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        let persistentStateBeforeLock = stateStore.persistentDomain(forName: suiteName)
        let activityBeforeLock = flow.activityLog

        flow.lockMutationsForAppManagedDataReset()

        XCTAssertFalse(flow.pause(for: .oneHour))
        flow.setEarlyReminderEnabled(false)
        flow.setOutOfOfficeProtectionEnabled(true)
        flow.setBlockingModeEnabled(true)
        flow.setStrongAlertRepeatInterval(minutes: 5)
        flow.setEarlyReminderLeadTime(minutes: 30)
        flow.setBlockingAvailability(false)
        XCTAssertFalse(flow.resetEncryptedGoogleData())

        XCTAssertNil(flow.pauseUntil)
        XCTAssertTrue(flow.isEarlyReminderEnabled)
        XCTAssertFalse(flow.isOutOfOfficeProtectionEnabled)
        XCTAssertFalse(flow.isBlockingModeEnabled)
        XCTAssertEqual(flow.strongAlertRepeatIntervalMinutes, 1)
        XCTAssertEqual(flow.earlyReminderLeadTimeMinutes, 10)
        XCTAssertTrue(flow.isBlockingAvailable)
        XCTAssertEqual(flow.activityLog, activityBeforeLock)
        XCTAssertTrue(
            NSDictionary(
                dictionary: stateStore.persistentDomain(forName: suiteName) ?? [:]
            ).isEqual(to: persistentStateBeforeLock ?? [:])
        )
        XCTAssertEqual(flow.connectedAccount, account)
    }

    func testAppManagedDataResetMutationGateRemainsClosedUntilEveryOwnerUnlocks() {
        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(),
            launchAtLogin: TestLaunchAtLoginController()
        )

        flow.lockMutationsForAppManagedDataReset()
        flow.lockMutationsForAppManagedDataReset()
        flow.unlockMutationsForAppManagedDataReset()

        XCTAssertTrue(flow.isAppManagedDataResetInProgress)

        flow.unlockMutationsForAppManagedDataReset()

        XCTAssertFalse(flow.isAppManagedDataResetInProgress)
    }

    func testAppManagedDataResetLockBlocksJoinAndPreservesStrongAlert() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let meetingURL = URL(string: "https://meet.google.com/abc-defg-hij")!
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: meetingURL
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )
        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        let activityBeforeLock = flow.activityLog
        var didOpenMeetingLink = false

        flow.lockMutationsForAppManagedDataReset()

        let didJoin = flow.openStrongAlertMeetingLink { _ in
            didOpenMeetingLink = true
            return true
        }
        flow.closeStrongAlertSurface(at: now)

        XCTAssertFalse(didJoin)
        XCTAssertFalse(didOpenMeetingLink)
        XCTAssertNil(flow.currentCommitmentDecision)
        XCTAssertEqual(flow.strongAlertCommitment, commitment)
        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertEqual(flow.activityLog, activityBeforeLock)
    }

    func testAppManagedDataResetLockBlocksSnoozeAndPreservesEarlyReminder() async {
        let fixture = makeRefreshTerminationFixture(testName: #function)
        defer { fixture.cleanUp() }
        await fixture.flow.connectGoogleAccount()
        fixture.flow.setCalendarSelected(true, calendarID: fixture.calendar.id)
        XCTAssertTrue(fixture.flow.confirmProtection())
        await settleScheduledRefreshes()
        await fixture.flow.refreshCommitmentProtection(at: fixture.now)
        XCTAssertEqual(fixture.flow.earlyReminderCommitment, fixture.commitment)
        let activityBeforeLock = fixture.flow.activityLog

        fixture.flow.lockMutationsForAppManagedDataReset()

        XCTAssertFalse(fixture.flow.snoozeEarlyReminder(minutes: 5, at: fixture.now))
        XCTAssertFalse(fixture.flow.clearEarlyReminder(for: fixture.commitment))
        XCTAssertEqual(fixture.flow.earlyReminderCommitment, fixture.commitment)
        XCTAssertEqual(fixture.flow.activityLog, activityBeforeLock)
    }

    func testAppManagedDataResetLockBlocksHandledAndDismissedDecisions() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )

        let handledFlow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )
        await activateProtection(for: handledFlow, calendarID: calendar.id)
        await handledFlow.refreshCommitmentProtection(at: now)
        let handledActivityBeforeLock = handledFlow.activityLog
        handledFlow.lockMutationsForAppManagedDataReset()

        XCTAssertFalse(handledFlow.handleCommitment(for: commitment, at: now))
        XCTAssertNil(handledFlow.currentCommitmentDecision)
        XCTAssertEqual(handledFlow.strongAlertCommitment, commitment)
        XCTAssertEqual(handledFlow.activityLog, handledActivityBeforeLock)

        let dismissedFlow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )
        await activateProtection(for: dismissedFlow, calendarID: calendar.id)
        await dismissedFlow.refreshCommitmentProtection(at: now)
        let dismissedActivityBeforeLock = dismissedFlow.activityLog
        dismissedFlow.lockMutationsForAppManagedDataReset()

        XCTAssertFalse(dismissedFlow.dismissCommitment(for: commitment, at: now))
        XCTAssertNil(dismissedFlow.currentCommitmentDecision)
        XCTAssertEqual(dismissedFlow.strongAlertCommitment, commitment)
        XCTAssertEqual(dismissedFlow.activityLog, dismissedActivityBeforeLock)
    }

    func testAppManagedDataResetLockBlocksRestoringProtection() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )
        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertTrue(flow.dismissCommitment(for: commitment, at: now))
        XCTAssertEqual(flow.currentCommitmentDecision, .dismissed)
        let activityBeforeLock = flow.activityLog

        flow.lockMutationsForAppManagedDataReset()

        XCTAssertFalse(flow.restoreProtection(at: now))
        XCTAssertEqual(flow.currentCommitmentDecision, .dismissed)
        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertEqual(flow.activityLog, activityBeforeLock)
    }

    func testAppManagedDataResetLockBlocksConflictPrimarySelection() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstCommitment = CalendarEvent(
            id: "event-a",
            title: "First review",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(65 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let secondCommitment = CalendarEvent(
            id: "event-b",
            title: "Second review",
            startDate: firstCommitment.startDate,
            endDate: now.addingTimeInterval(75 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstCommitment, secondCommitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertTrue(flow.upcomingConflict?.requiresPrimarySelection == true)
        XCTAssertNil(flow.upcomingConflict?.primaryCommitment)
        let activityBeforeLock = flow.activityLog

        flow.lockMutationsForAppManagedDataReset()

        XCTAssertFalse(flow.selectPrimary(for: secondCommitment))
        XCTAssertNil(flow.upcomingConflict?.primaryCommitment)
        XCTAssertNil(flow.earlyReminderConflict?.primaryCommitment)
        XCTAssertEqual(flow.earlyReminderCommitment, firstCommitment)
        XCTAssertEqual(flow.activityLog, activityBeforeLock)
    }

    func testAppManagedDataResetLockStopsInFlightSavedConnectionRestore() async {
        let suiteName = "CommitmentProtectionFlowTests.resetRestoreRace.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let (account, calendar) = makeTestAccountAndCalendar()
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])
        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(connection: connection),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(firstLaunch.confirmProtection())
        await settleScheduledRefreshes()

        let connectorState = RefreshRaceConnectorState(holdNextLoad: false)
        let relaunch = CommitmentProtectionFlow(
            calendarConnector: RefreshRaceTestConnector(
                connection: connection,
                events: [],
                state: connectorState
            ),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )
        await connectorState.armNextRestore()
        let restoreTask = Task { @MainActor in
            await relaunch.restoreSavedConnection()
        }
        for _ in 0..<20 {
            if await connectorState.hasRestoreStarted() { break }
            await Task.yield()
        }
        let restoreStarted = await connectorState.hasRestoreStarted()
        XCTAssertTrue(restoreStarted)
        let activityBeforeLock = relaunch.activityLog

        relaunch.lockMutationsForAppManagedDataReset()
        await connectorState.releaseRestore()
        await restoreTask.value

        XCTAssertTrue(relaunch.isAppManagedDataResetInProgress)
        XCTAssertTrue(relaunch.accountCoverages.isEmpty)
        XCTAssertNil(relaunch.connectedAccount)
        XCTAssertEqual(relaunch.status, .noCoverage)
        XCTAssertEqual(relaunch.activityLog, activityBeforeLock)
    }

    func testConnectingLoadsCalendarsAndConfirmationActivatesProtection() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
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

        XCTAssertEqual(flow.status, .noCoverage)
        XCTAssertTrue(flow.confirmProtection())
        XCTAssertEqual(flow.coverage(for: account.id), .checking)
        XCTAssertEqual(flow.status, .unavailable)
        XCTAssertEqual(flow.menuBarTitle, "Checking Coverage")
    }

    func testConnectStorageFailureDoesNotExposeVaultPayload() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let sensitivePayload = "writing /Users/alice/Library/Application Support/Meeting Incoming/private-token"
        let state = TestGoogleCalendarConnectorState()
        state.connectError = EncryptedGoogleVaultError.storageFailed(sensitivePayload)
        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(
                connection: GoogleCalendarConnection(account: account, calendars: []),
                state: state
            ),
            launchAtLogin: TestLaunchAtLoginController()
        )

        await flow.connectGoogleAccount()

        XCTAssertEqual(flow.accountConnectionError, "Protected storage operation failed.")
        XCTAssertEqual(flow.connectionState, .failed("Protected storage operation failed."))
        let failureActivity = flow.activityLog.last { $0.kind == .accountConnectionFailed }
        XCTAssertFalse(failureActivity?.detail.contains(sensitivePayload) == true)
    }

    func testMultipleConnectedAccountsKeepHealthyCoverageWhenOneAccountFails() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstAccount = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let firstCalendar = CalendarOption(id: "calendar-1", name: "Work", accountID: firstAccount.id)
        let secondAccount = GoogleAccount(id: "account-2", email: "sam@example.com", displayName: "Sam")
        let secondCalendar = CalendarOption(id: "calendar-2", name: "Personal", accountID: secondAccount.id)
        let firstCommitment = CalendarEvent(
            id: "event-1",
            title: "Work review",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(65 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: firstCalendar.id,
            accountID: firstAccount.id
        )
        let connector = MultiAccountTestGoogleCalendarConnector(
            connections: [
                GoogleCalendarConnection(account: firstAccount, calendars: [firstCalendar]),
                GoogleCalendarConnection(account: secondAccount, calendars: [secondCalendar])
            ],
            events: [firstCommitment]
        )
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            now: { now }
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: firstCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: secondCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await flow.refreshCommitmentProtection(at: now)

        await connector.setFailingAccountIDs([secondAccount.id])
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(16 * 60))

        XCTAssertEqual(flow.accountCoverages.count, 2)
        XCTAssertEqual(flow.coverage(for: firstAccount.id), .fresh)
        if case .stale = flow.coverage(for: secondAccount.id) {
            // The affected account is isolated without disabling healthy coverage.
        } else {
            XCTFail("Expected the second account to retain stale cached coverage.")
        }
        XCTAssertEqual(flow.strongAlertCommitment, firstCommitment)
        XCTAssertTrue(flow.isStrongAlertUnverified == false)
        XCTAssertEqual(flow.status, .active)
    }

    func testKnownReminderContinuesAsUnverifiedWhenItsAccountBecomesStale() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connector = MultiAccountTestGoogleCalendarConnector(
            connections: [GoogleCalendarConnection(account: account, calendars: [calendar])],
            events: [commitment]
        )
        let suiteName = "CommitmentProtectionFlowTests.staleCoverage.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.status, .active)
        XCTAssertEqual(flow.selectedCalendarIDs, [calendar.id])
        XCTAssertEqual(flow.accountCoverages.count, 1)
        XCTAssertEqual(flow.accountCoverages.first?.lastSuccessfulRefreshAt, now)
        XCTAssertEqual(flow.earlyReminderCommitment, commitment)
        XCTAssertFalse(flow.isEarlyReminderUnverified)

        await connector.setFailingAccountIDs([account.id])
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(16 * 60))

        XCTAssertEqual(flow.strongAlertCommitment, commitment)
        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertTrue(flow.isStrongAlertUnverified)
        XCTAssertEqual(flow.accountCoverages.first?.lastSuccessfulRefreshAt, now)
        XCTAssertEqual(flow.coverage(for: account.id), .stale)
        XCTAssertTrue(flow.coverageWarning(for: account.id)?.contains("hasn’t refreshed") == true)
    }

    func testFreshCoverageAllowsNewReminderAfterStaleSnapshotRecovery() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let knownCommitment = CalendarEvent(
            id: "known-event",
            title: "Known review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let newlyDiscoveredCommitment = CalendarEvent(
            id: "new-event",
            title: "New review",
            startDate: now.addingTimeInterval(20 * 60),
            endDate: now.addingTimeInterval(80 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [knownCommitment]
        )
        let suiteName = "CommitmentProtectionFlowTests.staleRecovery.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        connector.events = [knownCommitment, newlyDiscoveredCommitment]
        connector.loadEventsError = TestCalendarLoadError.unavailable
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(16 * 60))

        XCTAssertEqual(flow.strongAlertCommitment, knownCommitment)
        XCTAssertTrue(flow.isStrongAlertUnverified)
        XCTAssertNil(flow.earlyReminderCommitment)

        connector.loadEventsError = nil
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(16 * 60))

        XCTAssertEqual(flow.strongAlertCommitment, knownCommitment)
        XCTAssertFalse(flow.isStrongAlertUnverified)
        XCTAssertEqual(flow.earlyReminderCommitment, newlyDiscoveredCommitment)
        XCTAssertEqual(flow.coverage(for: account.id), .fresh)
    }

    func testDisconnectingOneAccountKeepsTheOtherAccountProtected() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstAccount = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let firstCalendar = CalendarOption(id: "calendar-1", name: "Work", accountID: firstAccount.id)
        let secondAccount = GoogleAccount(id: "account-2", email: "sam@example.com", displayName: "Sam")
        let secondCalendar = CalendarOption(id: "calendar-2", name: "Personal", accountID: secondAccount.id)
        let firstCommitment = CalendarEvent(
            id: "event-1",
            title: "Work review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: firstCalendar.id,
            accountID: firstAccount.id
        )
        let connector = MultiAccountTestGoogleCalendarConnector(
            connections: [
                GoogleCalendarConnection(account: firstAccount, calendars: [firstCalendar]),
                GoogleCalendarConnection(account: secondAccount, calendars: [secondCalendar])
            ],
            events: [firstCommitment]
        )
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            now: { now }
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: firstCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: secondCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.strongAlertCommitment, firstCommitment)

        let didDisconnect = await flow.disconnectGoogleAccount(accountID: secondAccount.id)
        XCTAssertTrue(didDisconnect)

        XCTAssertEqual(flow.accountCoverages.map(\.account.id), [firstAccount.id, secondAccount.id])
        XCTAssertEqual(
            flow.accountCoverages.first { $0.account.id == secondAccount.id }?.connectionState,
            .reconnectRequired
        )
        XCTAssertEqual(flow.status, .active)
        XCTAssertEqual(flow.strongAlertCommitment, firstCommitment)
        XCTAssertTrue(flow.activityLog.contains {
            $0.kind == .accountDisconnected && $0.accountID == secondAccount.id
        })
    }

    func testDisconnectingDisplayedConflictAccountImmediatelySurfacesRemainingCommitment() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstAccount = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let firstCalendar = CalendarOption(id: "calendar-1", name: "Work", accountID: firstAccount.id)
        let secondAccount = GoogleAccount(id: "account-2", email: "sam@example.com", displayName: "Sam")
        let secondCalendar = CalendarOption(id: "calendar-2", name: "Personal", accountID: secondAccount.id)
        let firstCommitment = CalendarEvent(
            id: "event-1",
            title: "Work review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: firstCalendar.id,
            accountID: firstAccount.id
        )
        let secondCommitment = CalendarEvent(
            id: "event-2",
            title: "Personal appointment",
            startDate: now,
            endDate: now.addingTimeInterval(45 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: secondCalendar.id,
            accountID: secondAccount.id
        )
        let connector = MultiAccountTestGoogleCalendarConnector(
            connections: [
                GoogleCalendarConnection(account: firstAccount, calendars: [firstCalendar]),
                GoogleCalendarConnection(account: secondAccount, calendars: [secondCalendar])
            ],
            events: [firstCommitment, secondCommitment]
        )
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            now: { now }
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: firstCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await flow.refreshCommitmentProtection(at: now)
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: secondCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.strongAlertConflict?.commitments.count, 2)

        let didDisconnect = await flow.disconnectGoogleAccount(accountID: firstAccount.id)
        XCTAssertTrue(didDisconnect)

        XCTAssertEqual(flow.strongAlertCommitment, secondCommitment)
        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertNil(flow.strongAlertConflict)
    }

    func testMultipleAccountSelectionsAndConfirmationRestoreAfterRelaunch() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstAccount = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let firstCalendar = CalendarOption(id: "calendar-1", name: "Work", accountID: firstAccount.id)
        let secondAccount = GoogleAccount(id: "account-2", email: "sam@example.com", displayName: "Sam")
        let secondCalendar = CalendarOption(id: "calendar-2", name: "Personal", accountID: secondAccount.id)
        let connections = [
            GoogleCalendarConnection(account: firstAccount, calendars: [firstCalendar]),
            GoogleCalendarConnection(account: secondAccount, calendars: [secondCalendar])
        ]
        let suiteName = "CommitmentProtectionFlowTests.multipleAccountRelaunch.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstConnector = MultiAccountTestGoogleCalendarConnector(connections: connections, events: [])
        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: firstConnector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: firstCalendar.id)
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: secondCalendar.id)
        XCTAssertTrue(firstLaunch.isProtectionConfirmationRequired)
        XCTAssertTrue(firstLaunch.confirmAllProtection())
        XCTAssertFalse(firstLaunch.isProtectionConfirmationRequired)
        await firstLaunch.refreshCommitmentProtection(at: now)

        let relaunch = CommitmentProtectionFlow(
            calendarConnector: MultiAccountTestGoogleCalendarConnector(connections: connections, events: []),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await relaunch.restoreSavedConnection()

        XCTAssertEqual(Set(relaunch.accountCoverages.map(\.account.id)), Set(connections.map(\.account.id)))
        XCTAssertEqual(relaunch.selectedCalendarIDs(for: firstAccount.id), [firstCalendar.id])
        XCTAssertEqual(relaunch.selectedCalendarIDs(for: secondAccount.id), [secondCalendar.id])
        XCTAssertTrue(relaunch.isProtectionConfirmed(for: firstAccount.id))
        XCTAssertTrue(relaunch.isProtectionConfirmed(for: secondAccount.id))
        XCTAssertEqual(relaunch.status, .active)
    }

    func testAdditionalAccountConnectionFailureRemainsVisibleBesideExistingCoverage() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let connector = MultiAccountTestGoogleCalendarConnector(
            connections: [GoogleCalendarConnection(account: account, calendars: [calendar])],
            events: []
        )
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController()
        )

        await flow.connectGoogleAccount()
        XCTAssertNil(flow.accountConnectionError)

        await flow.connectGoogleAccount()

        XCTAssertFalse(flow.isConnectingAccount)
        XCTAssertEqual(flow.accountConnectionError, "The test calendar is unavailable.")
        XCTAssertEqual(flow.accountCoverages.map(\.account.id), [account.id])
    }

    func testSelectedCalendarProtectionRestoresAfterRelaunch() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
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
        XCTAssertTrue(firstLaunch.confirmProtection())

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

    func testSelectedCalendarRemainsActiveWhileLoginNeedsAttention() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(
                connection: GoogleCalendarConnection(account: account, calendars: [calendar])
            ),
            launchAtLogin: TestLaunchAtLoginController(shouldEnable: false)
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())

        XCTAssertEqual(flow.coverage(for: account.id), .checking)
        XCTAssertEqual(flow.status, .unavailable)
        XCTAssertEqual(flow.menuBarTitle, "Checking Coverage")
    }

    func testRemovingAccountClearsConnectionAndProtectionConfiguration() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let suiteName = "CommitmentProtectionFlowTests.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let connector = TestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar])
        )
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        XCTAssertEqual(flow.coverage(for: account.id), .checking)
        XCTAssertEqual(flow.status, .unavailable)

        let didRemove = await flow.removeGoogleAccount(accountID: account.id)
        XCTAssertTrue(didRemove)

        XCTAssertFalse(flow.activityLog.contains { $0.accountID == account.id })
        XCTAssertNil(flow.connectedAccount)
        XCTAssertTrue(flow.availableCalendars.isEmpty)
        XCTAssertTrue(flow.selectedCalendarIDs.isEmpty)
        XCTAssertEqual(flow.connectionState, .notConnected)
        XCTAssertEqual(flow.status, .noCoverage)
        XCTAssertTrue(connector.state.disconnectWasCalled)

        let relaunchedFlow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )
        await relaunchedFlow.restoreSavedConnection()
        XCTAssertNil(relaunchedFlow.connectedAccount)
        XCTAssertTrue(relaunchedFlow.activityLog.isEmpty)
    }

    func testDisconnectFailureKeepsAccountAndExposesRetryableError() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let connector = TestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [])
        )
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController()
        )
        await flow.connectGoogleAccount()
        connector.state.disconnectError = TestCalendarError.unavailable

        let firstAttempt = await flow.disconnectGoogleAccount(accountID: account.id)
        XCTAssertFalse(firstAttempt)

        XCTAssertEqual(flow.connectedAccount, account)
        XCTAssertEqual(flow.failedAccountDisconnectionID, account.id)
        XCTAssertEqual(
            flow.accountDisconnectionError,
            "Couldn’t disconnect alex@example.com. The test calendar is unavailable."
        )
        XCTAssertFalse(flow.activityLog.contains { $0.kind == .accountDisconnectFailed })

        connector.state.disconnectError = nil
        let retry = await flow.disconnectGoogleAccount(accountID: account.id)
        XCTAssertTrue(retry)
        XCTAssertNil(flow.accountDisconnectionError)
        XCTAssertNil(flow.failedAccountDisconnectionID)
        XCTAssertEqual(flow.connectionState, .reconnectRequired)
    }

    func testDisconnectWithMissingLocalCredentialPreservesAccountAndGuidesGoogleAccessReview() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(30 * 60),
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connector = MissingLocalCredentialRevocationConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment]
        )
        let suiteName = "CommitmentProtectionFlowTests.missing-credential-disconnect.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)
        let activityIDs = flow.activityLog.map(\.id)

        let didDisconnect = await flow.disconnectGoogleAccount(accountID: account.id)

        XCTAssertFalse(didDisconnect)
        XCTAssertEqual(flow.connectedAccount, account)
        XCTAssertEqual(flow.connectionState, .connected)
        XCTAssertEqual(flow.coverage(for: account.id), .fresh)
        XCTAssertEqual(flow.selectedCalendarIDs(for: account.id), [calendar.id])
        XCTAssertTrue(flow.isProtectionConfirmed(for: account.id))
        XCTAssertEqual(flow.upcomingCommitment, commitment)
        XCTAssertEqual(flow.activityLog.map(\.id), activityIDs)
        XCTAssertEqual(flow.failedAccountDisconnectionID, account.id)
        XCTAssertTrue(
            flow.accountDisconnectionError?.contains("Google Account access") == true
        )
    }

    func testRemoveWithMissingLocalCredentialDeletesLocallyAndGuidesGoogleAccessReview() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let connector = MissingLocalCredentialRevocationConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar])
        )
        let suiteName = "CommitmentProtectionFlowTests.missing-credential-remove.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()

        let didRemove = await flow.removeGoogleAccount(accountID: account.id)

        XCTAssertTrue(didRemove)
        XCTAssertNil(flow.coverage(for: account.id))
        XCTAssertTrue(flow.accountCoverages.isEmpty)
        XCTAssertNil(flow.connectedAccount)
        XCTAssertFalse(flow.activityLog.contains { $0.accountID == account.id })
        XCTAssertNil(flow.accountDisconnectionError)
        XCTAssertTrue(
            flow.googleAccessReviewNotice?.contains("Review Google Account access") == true
        )
        XCTAssertTrue(flow.googleAccessReviewNotice?.contains("local credential was missing") == true)
    }

    func testStrongAlertUsesJoinAndEndsProtectionWithoutAttendanceVerification() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let meetingURL = URL(string: "https://meet.google.com/abc-defg-hij")!
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: "Europe/Istanbul",
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: meetingURL
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.strongAlertCommitment, commitment)
        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertEqual(flow.strongAlertPrimaryActionTitle, "Join")
        XCTAssertTrue(flow.openStrongAlertMeetingLink { $0 == meetingURL })
        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testStrongAlertUsesStopRemindersWhenNoRecognizedMeetingLink() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "On-site review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.strongAlertPrimaryActionTitle, "Stop reminders")
        XCTAssertTrue(flow.dismissCommitment(at: now))
        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testSharedMeetingLinkRepresentationsProduceOneProtectionLifecycle() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let workCalendar = CalendarOption(id: "calendar-work", name: "Work", accountID: account.id)
        let personalCalendar = CalendarOption(id: "calendar-personal", name: "Personal", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let meetingURL = URL(string: "https://meet.google.com/shared-room")!
        let workRepresentation = CalendarEvent(
            id: "event-work",
            title: "Customer review",
            meetingDescription: "Work calendar details",
            startDate: now,
            endDate: now.addingTimeInterval(45 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: workCalendar.id,
            accountID: account.id,
            recognizedMeetingLink: meetingURL
        )
        let personalRepresentation = CalendarEvent(
            id: "event-personal",
            title: "Customer review (personal copy)",
            meetingDescription: "Personal calendar details",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: personalCalendar.id,
            accountID: account.id,
            recognizedMeetingLink: meetingURL
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(
                account: account,
                calendars: [workCalendar, personalCalendar]
            ),
            events: [workRepresentation, personalRepresentation],
            now: now
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: workCalendar.id)
        flow.setCalendarSelected(true, calendarID: personalCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.strongAlertCommitment?.recognizedMeetingLink, meetingURL)
        XCTAssertEqual(
            flow.strongAlertCommitment?.meetingDescription,
            "Personal calendar details"
        )
        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertTrue(flow.openStrongAlertMeetingLink { $0 == meetingURL })

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(1))

        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testMergedCommitmentProducesOneEarlyReminderLifecycle() async throws {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let meetingURL = URL(string: "https://meet.google.com/shared-early-lifecycle")!
        let firstRepresentation = CalendarEvent(
            id: "event-a",
            title: "Customer review",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: meetingURL
        )
        let secondRepresentation = CalendarEvent(
            id: "event-b",
            title: "Customer review copy",
            meetingDescription: "Details from the secondary representation",
            startDate: firstRepresentation.startDate,
            endDate: firstRepresentation.endDate,
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: meetingURL
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstRepresentation, secondRepresentation],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(1))

        XCTAssertEqual(flow.earlyReminderCommitment?.id, firstRepresentation.id)
        XCTAssertEqual(
            flow.earlyReminderCommitment?.meetingDescription,
            "Details from the secondary representation"
        )
        XCTAssertEqual(
            flow.activityLog.filter { $0.kind == .earlyReminderShown }.count,
            1
        )
        let encodedActivity = try JSONEncoder().encode(flow.activityLog)
        XCTAssertFalse(
            String(decoding: encodedActivity, as: UTF8.self)
                .contains("Details from the secondary representation")
        )
    }

    func testDesignatedMeetingLinkIsPreferredForJoin() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let primaryLink = URL(string: "https://meet.google.com/primary-room")!
        let secondaryLink = URL(string: "https://zoom.us/j/123456789")!
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLinks: [
                RecognizedMeetingLink(url: primaryLink, isPrimary: true),
                RecognizedMeetingLink(url: secondaryLink, isPrimary: false)
            ]
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.strongAlertMeetingLinkOptions, [primaryLink, secondaryLink])
        XCTAssertTrue(flow.openStrongAlertMeetingLink { $0 == primaryLink })
    }

    func testMultipleUndesignatedMeetingLinksCanBeChosenForJoin() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstLink = URL(string: "https://zoom.us/j/123456789")!
        let secondLink = URL(string: "https://teams.microsoft.com/l/meetup-join/abc")!
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLinks: [
                RecognizedMeetingLink(url: firstLink, isPrimary: false),
                RecognizedMeetingLink(url: secondLink, isPrimary: false)
            ]
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.strongAlertMeetingLinkOptions, [firstLink, secondLink])
        XCTAssertTrue(flow.openStrongAlertMeetingLink(using: secondLink) { $0 == secondLink })
        XCTAssertNil(flow.strongAlertCommitment)
    }

    func testSharedMeetingLinkCanMergeRepresentationsAcrossConnectedAccounts() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstAccount = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let firstCalendar = CalendarOption(id: "calendar-work", name: "Work", accountID: firstAccount.id)
        let secondAccount = GoogleAccount(id: "account-2", email: "sam@example.com", displayName: "Sam")
        let secondCalendar = CalendarOption(id: "calendar-personal", name: "Personal", accountID: secondAccount.id)
        let meetingURL = URL(string: "https://meet.google.com/cross-account")!
        let firstRepresentation = CalendarEvent(
            id: "event-work",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(45 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: firstCalendar.id,
            accountID: firstAccount.id,
            recognizedMeetingLink: meetingURL
        )
        let secondRepresentation = CalendarEvent(
            id: "event-personal",
            title: "Customer review copy",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: secondCalendar.id,
            accountID: secondAccount.id,
            recognizedMeetingLink: meetingURL
        )
        let connector = MultiAccountTestGoogleCalendarConnector(
            connections: [
                GoogleCalendarConnection(account: firstAccount, calendars: [firstCalendar]),
                GoogleCalendarConnection(account: secondAccount, calendars: [secondCalendar])
            ],
            events: [firstRepresentation, secondRepresentation]
        )
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            now: { now }
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: firstCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: secondCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.strongAlertMeetingLinkOptions, [meetingURL])
        XCTAssertTrue(flow.openStrongAlertMeetingLink { $0 == meetingURL })
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(1))
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testEquivalentMeetingLinkRepresentationsMergeIntoOneCommitment() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstLink = URL(string: "https://meet.google.com/normalized-room")!
        let equivalentLink = URL(string: "HTTPS://MEET.GOOGLE.COM/normalized-room/")!
        let firstRepresentation = CalendarEvent(
            id: "event-a",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(45 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: firstLink
        )
        let secondRepresentation = CalendarEvent(
            id: "event-b",
            title: "Customer review copy",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: equivalentLink
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstRepresentation, secondRepresentation],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.strongAlertMeetingLinkOptions, [firstLink])
        XCTAssertTrue(flow.openStrongAlertMeetingLink { $0 == firstLink })
    }

    func testConflictingDesignatedLinksRequireAnExplicitChoice() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstLink = URL(string: "https://meet.google.com/first-room")!
        let sharedLink = URL(string: "https://zoom.us/j/shared-room")!
        let secondLink = URL(string: "https://teams.microsoft.com/l/meetup-join/second")!
        let firstRepresentation = CalendarEvent(
            id: "event-a",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(45 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLinks: [
                RecognizedMeetingLink(url: firstLink, isPrimary: true),
                RecognizedMeetingLink(url: sharedLink, isPrimary: false)
            ]
        )
        let secondRepresentation = CalendarEvent(
            id: "event-b",
            title: "Customer review copy",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLinks: [
                RecognizedMeetingLink(url: secondLink, isPrimary: true),
                RecognizedMeetingLink(url: sharedLink, isPrimary: false)
            ]
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstRepresentation, secondRepresentation],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertNil(flow.strongAlertPrimaryMeetingLink)
        XCTAssertEqual(flow.strongAlertPrimaryActionTitle, "Choose link")
        XCTAssertFalse(flow.openStrongAlertMeetingLink { _ in true })
        XCTAssertTrue(flow.openStrongAlertMeetingLink(using: secondLink) { $0 == secondLink })
    }

    func testMergedReminderBecomesUnverifiedWhenAnySourceAccountIsStale() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstAccount = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let firstCalendar = CalendarOption(id: "calendar-work", name: "Work", accountID: firstAccount.id)
        let secondAccount = GoogleAccount(id: "account-2", email: "sam@example.com", displayName: "Sam")
        let secondCalendar = CalendarOption(id: "calendar-personal", name: "Personal", accountID: secondAccount.id)
        let meetingURL = URL(string: "https://meet.google.com/shared-stale-room")!
        let firstRepresentation = CalendarEvent(
            id: "event-work",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: firstCalendar.id,
            accountID: firstAccount.id,
            recognizedMeetingLink: meetingURL
        )
        let secondRepresentation = CalendarEvent(
            id: "event-personal",
            title: "Customer review copy",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: secondCalendar.id,
            accountID: secondAccount.id,
            recognizedMeetingLink: meetingURL
        )
        let connector = MultiAccountTestGoogleCalendarConnector(
            connections: [
                GoogleCalendarConnection(account: firstAccount, calendars: [firstCalendar]),
                GoogleCalendarConnection(account: secondAccount, calendars: [secondCalendar])
            ],
            events: [firstRepresentation, secondRepresentation]
        )
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            now: { now }
        )

        await flow.connectGoogleAccount()
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: firstCalendar.id, accountID: firstAccount.id)
        flow.setCalendarSelected(true, calendarID: secondCalendar.id, accountID: secondAccount.id)
        XCTAssertTrue(flow.confirmAllProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertFalse(flow.isStrongAlertUnverified)

        await connector.setFailingAccountIDs([secondAccount.id])
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(16 * 60))

        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertTrue(flow.isStrongAlertUnverified)
        let strongAlertActivity = flow.activityLog.first { $0.kind == .strongAlertShown }
        XCTAssertTrue(strongAlertActivity?.detail.contains(firstAccount.email) == true)
        XCTAssertTrue(strongAlertActivity?.detail.contains(secondAccount.email) == true)
    }

    func testSimilarCommitmentsWithoutSharedMeetingLinkRemainSeparate() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstCommitment = CalendarEvent(
            id: "event-a",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(45 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let secondCommitment = CalendarEvent(
            id: "event-b",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstCommitment, secondCommitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.strongAlertCommitment?.id, firstCommitment.id)
        XCTAssertTrue(flow.dismissCommitment(at: now))
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(1))

        XCTAssertEqual(flow.strongAlertCommitment?.id, secondCommitment.id)
        XCTAssertTrue(flow.isStrongAlertPresented)
    }

    func testCommitmentConflictExposesAnAutomaticPrimaryAndConflictList() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstCommitment = CalendarEvent(
            id: "event-a",
            title: "First review",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(65 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let secondCommitment = CalendarEvent(
            id: "event-b",
            title: "Second review",
            startDate: now.addingTimeInterval(15 * 60),
            endDate: now.addingTimeInterval(75 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstCommitment, secondCommitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.upcomingConflict?.commitments.map(\.id), [firstCommitment.id, secondCommitment.id])
        XCTAssertEqual(flow.upcomingConflict?.primaryCommitment, firstCommitment)
        XCTAssertEqual(flow.earlyReminderCommitment, firstCommitment)
        XCTAssertEqual(flow.earlyReminderConflict?.commitments.count, 2)
    }

    func testCommitmentsTouchingAtAnEndBoundaryDoNotConflict() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstCommitment = CalendarEvent(
            id: "event-a",
            title: "First review",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(15 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let secondCommitment = CalendarEvent(
            id: "event-b",
            title: "Second review",
            startDate: firstCommitment.endDate,
            endDate: now.addingTimeInterval(25 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstCommitment, secondCommitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertNil(flow.upcomingConflict)
    }

    func testSameStartConflictRemainsEqualAndExposesAllStrongAlertActions() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstCommitment = CalendarEvent(
            id: "event-a",
            title: "First review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let secondCommitment = CalendarEvent(
            id: "event-b",
            title: "Second review",
            startDate: now,
            endDate: now.addingTimeInterval(90 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstCommitment, secondCommitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertTrue(flow.strongAlertConflict?.requiresPrimarySelection == true)
        XCTAssertNil(flow.strongAlertConflict?.primaryCommitment)
        XCTAssertEqual(flow.strongAlertActionCommitments.map(\.id), [firstCommitment.id, secondCommitment.id])

        XCTAssertTrue(flow.handleCommitment(for: firstCommitment, at: now))
        XCTAssertEqual(flow.currentCommitmentDecision, .handled)
        XCTAssertEqual(flow.decisionCommitment, firstCommitment)
        XCTAssertEqual(flow.strongAlertCommitment, secondCommitment)
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(1))
        XCTAssertEqual(flow.strongAlertCommitment, secondCommitment)
        XCTAssertNil(flow.strongAlertConflict)

        XCTAssertTrue(flow.dismissCommitment(for: secondCommitment, at: now.addingTimeInterval(1)))
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(2))
        XCTAssertFalse(flow.isStrongAlertPresented)
        XCTAssertNil(flow.strongAlertCommitment)
    }

    func testSameStartPrimarySelectionPersistsAcrossRefreshes() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstCommitment = CalendarEvent(
            id: "event-a",
            title: "First review",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(65 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let secondCommitment = CalendarEvent(
            id: "event-b",
            title: "Second review",
            startDate: firstCommitment.startDate,
            endDate: now.addingTimeInterval(75 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstCommitment, secondCommitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertTrue(flow.selectPrimary(for: secondCommitment))
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.upcomingConflict?.primaryCommitment, secondCommitment)
        XCTAssertEqual(flow.earlyReminderConflict?.primaryCommitment, secondCommitment)
        XCTAssertEqual(flow.earlyReminderCommitment, secondCommitment)
    }

    func testSameStartPrimarySelectionSurvivesRelaunch() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstCommitment = CalendarEvent(
            id: "event-a",
            title: "First review",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(65 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let secondCommitment = CalendarEvent(
            id: "event-b",
            title: "Second review",
            startDate: firstCommitment.startDate,
            endDate: now.addingTimeInterval(75 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])
        let suiteName = "CommitmentProtectionFlowTests.conflictPrimaryPersistence.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(connection: connection, events: [firstCommitment, secondCommitment]),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await activateProtection(for: firstLaunch, calendarID: calendar.id)
        await firstLaunch.refreshCommitmentProtection(at: now)
        XCTAssertTrue(firstLaunch.selectPrimary(for: secondCommitment))
        await firstLaunch.refreshCommitmentProtection(at: now)

        let relaunch = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(connection: connection, events: [firstCommitment, secondCommitment]),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await relaunch.restoreSavedConnection()

        XCTAssertEqual(relaunch.upcomingConflict?.primaryCommitment, secondCommitment)
        XCTAssertEqual(relaunch.earlyReminderConflict?.primaryCommitment, secondCommitment)
        XCTAssertEqual(relaunch.earlyReminderCommitment, secondCommitment)
    }

    func testSharedSecondaryMeetingLinkMergesRepresentationsAndOffersAllLinks() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstLink = URL(string: "https://meet.google.com/first-room")!
        let sharedLink = URL(string: "https://zoom.us/j/shared-room")!
        let secondLink = URL(string: "https://teams.microsoft.com/l/meetup-join/second")!
        let firstCommitment = CalendarEvent(
            id: "event-a",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(45 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLinks: [
                RecognizedMeetingLink(url: firstLink, isPrimary: false),
                RecognizedMeetingLink(url: sharedLink, isPrimary: false)
            ]
        )
        let secondCommitment = CalendarEvent(
            id: "event-b",
            title: "Customer review copy",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLinks: [
                RecognizedMeetingLink(url: sharedLink, isPrimary: false),
                RecognizedMeetingLink(url: secondLink, isPrimary: false)
            ]
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstCommitment, secondCommitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.strongAlertMeetingLinkOptions, [firstLink, sharedLink, secondLink])
        XCTAssertTrue(flow.openStrongAlertMeetingLink(using: secondLink) { $0 == secondLink })
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(1))
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testMeetingLinkChainDoesNotMergeWithoutOneSharedLinkAcrossTheGroup() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstLink = URL(string: "https://meet.google.com/first-chain-room")!
        let bridgeLink = URL(string: "https://zoom.us/j/bridge-chain-room")!
        let lastLink = URL(string: "https://teams.microsoft.com/l/last-chain-room")!
        let firstRepresentation = CalendarEvent(
            id: "event-a",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLinks: [
                RecognizedMeetingLink(url: firstLink, isPrimary: false),
                RecognizedMeetingLink(url: bridgeLink, isPrimary: false)
            ]
        )
        let bridgeRepresentation = CalendarEvent(
            id: "event-b",
            title: "Customer review copy",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLinks: [
                RecognizedMeetingLink(url: bridgeLink, isPrimary: false),
                RecognizedMeetingLink(url: lastLink, isPrimary: false)
            ]
        )
        let lastRepresentation = CalendarEvent(
            id: "event-c",
            title: "Customer review third copy",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: lastLink
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstRepresentation, bridgeRepresentation, lastRepresentation],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.strongAlertMeetingLinkOptions, [firstLink, bridgeLink, lastLink])

        XCTAssertTrue(flow.dismissCommitment(at: now))
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(1))

        XCTAssertEqual(flow.strongAlertCommitment?.id, lastRepresentation.id)
        XCTAssertTrue(flow.isStrongAlertPresented)
    }

    func testMeetingLinkFragmentsRemainDifferentRecognizedLinks() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstLink = URL(string: "https://meet.google.com/same-room#first")!
        let secondLink = URL(string: "https://meet.google.com/same-room#second")!
        let firstRepresentation = CalendarEvent(
            id: "event-a",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: firstLink
        )
        let secondRepresentation = CalendarEvent(
            id: "event-b",
            title: "Customer review copy",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: secondLink
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstRepresentation, secondRepresentation],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.strongAlertMeetingLinkOptions, [firstLink])
        XCTAssertTrue(flow.dismissCommitment(at: now))
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(1))
        XCTAssertEqual(flow.strongAlertMeetingLinkOptions, [secondLink])
    }

    func testClearedMergedEarlyReminderStaysClearedWhenOneRepresentationDisappears() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let meetingURL = URL(string: "https://meet.google.com/early-shared-room")!
        let firstRepresentation = CalendarEvent(
            id: "event-a",
            title: "Customer review",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: meetingURL
        )
        let secondRepresentation = CalendarEvent(
            id: "event-b",
            title: "Customer review copy",
            startDate: firstRepresentation.startDate,
            endDate: firstRepresentation.endDate,
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: meetingURL
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstRepresentation, secondRepresentation]
        )
        let flow = makeMutableFlow(connector: connector, now: now)

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        flow.clearEarlyReminder()

        connector.events = [secondRepresentation]
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(1))

        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertEqual(flow.upcomingCommitment, secondRepresentation)
    }

    func testMergedDecisionSurvivesWhenOnlyAnotherRepresentationRemains() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let meetingURL = URL(string: "https://meet.google.com/decision-shared-room")!
        let firstRepresentation = CalendarEvent(
            id: "event-a",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: meetingURL
        )
        let secondRepresentation = CalendarEvent(
            id: "event-b",
            title: "Customer review copy",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: meetingURL
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstRepresentation, secondRepresentation]
        )
        let flow = makeMutableFlow(connector: connector, now: now)

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertTrue(flow.dismissCommitment(at: now))

        connector.events = [secondRepresentation]
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(1))

        XCTAssertEqual(flow.currentCommitmentDecision, .dismissed)
        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testStrongAlertTimingAndContextDescribeTheActiveCommitment() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(-2 * 60),
            endDate: now.addingTimeInterval(30 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(
            flow.strongAlertTimingText(for: commitment, at: now),
            "Overdue · started 2 minutes ago"
        )
        XCTAssertEqual(flow.strongAlertContextText(for: commitment), "Work · alex@example.com")
    }

    func testOverdueStrongAlertRepeatsAfterSurfaceCloseUntilCommitmentEnds() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(-5 * 60),
            endDate: now.addingTimeInterval(5 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertTrue(flow.isStrongAlertPresented)

        flow.closeStrongAlertSurface(at: now.addingTimeInterval(1))
        XCTAssertFalse(flow.isStrongAlertPresented)

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(60))
        XCTAssertFalse(flow.isStrongAlertPresented)

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(61))
        XCTAssertTrue(flow.isStrongAlertPresented)

        flow.closeStrongAlertSurface(at: now.addingTimeInterval(62))
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(5 * 60))
        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testRepeatIntervalDefaultsToOneMinuteAndPersistsWithinConfiguration() {
        let suiteName = "CommitmentProtectionFlowTests.repeat.(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )

        XCTAssertEqual(flow.strongAlertRepeatIntervalMinutes, 1)
        flow.setStrongAlertRepeatInterval(minutes: 5)

        let relaunchedFlow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )
        XCTAssertEqual(relaunchedFlow.strongAlertRepeatIntervalMinutes, 5)

        flow.setStrongAlertRepeatInterval(minutes: 0)
        XCTAssertEqual(flow.strongAlertRepeatIntervalMinutes, 1)
        flow.setStrongAlertRepeatInterval(minutes: 10)
        XCTAssertEqual(flow.strongAlertRepeatIntervalMinutes, 5)
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

    func testTokenExchangeFailureExplainsGoogleOAuthReason() {
        let error = GoogleCalendarConnectorError.tokenExchangeFailed(
            400,
            "invalid_grant: Bad Request"
        )

        XCTAssertEqual(
            error.errorDescription,
            "Google sign-in couldn’t be completed. Try again."
        )
    }

    func testOAuthCallbackRejectsDuplicateQueryValues() {
        let callbackURL = URL(string: "http://127.0.0.1/oauth/callback?state=first&state=second")!

        XCTAssertThrowsError(try callbackValues(from: callbackURL)) { error in
            XCTAssertEqual(error as? GoogleCalendarConnectorError, .invalidCallback)
        }
    }

    func testOAuthCallbackRejectsDuplicateValuesWhenOneValueIsMissing() {
        let callbackURL = URL(string: "http://127.0.0.1/oauth/callback?state&state=valid")!

        XCTAssertThrowsError(try callbackValues(from: callbackURL)) { error in
            XCTAssertEqual(error as? GoogleCalendarConnectorError, .invalidCallback)
        }
    }

    func testSelectingCalendarRequiresConfirmationBeforeProtectionActivates() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar])
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)

        XCTAssertFalse(flow.isProtectionConfirmed)
        XCTAssertEqual(flow.status, .noCoverage)

        XCTAssertTrue(flow.confirmProtection())
        XCTAssertTrue(flow.isProtectionConfirmed)
        XCTAssertEqual(flow.coverage(for: account.id), .checking)
        XCTAssertEqual(flow.status, .unavailable)
    }

    func testLegacySavedConfigurationRequiresExplicitConfirmation() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let suiteName = "CommitmentProtectionFlowTests.legacy.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let legacyConfiguration = try! JSONSerialization.data(withJSONObject: [
            "accountID": account.id,
            "selectedCalendarIDs": [calendar.id]
        ])
        stateStore.set(legacyConfiguration, forKey: "commitment-protection.configuration")

        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(
                connection: GoogleCalendarConnection(account: account, calendars: [calendar])
            ),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )

        await flow.restoreSavedConnection()

        XCTAssertEqual(flow.selectedCalendarIDs, [calendar.id])
        XCTAssertFalse(flow.isProtectionConfirmed)
        XCTAssertEqual(flow.status, .noCoverage)
        XCTAssertTrue(flow.confirmProtection())
        XCTAssertEqual(flow.coverage(for: account.id), .checking)
        XCTAssertEqual(flow.status, .unavailable)
    }

    func testDeselectingCalendarImmediatelyClearsItsProtectionState() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.earlyReminderCommitment, commitment)

        flow.setCalendarSelected(false, calendarID: calendar.id)

        XCTAssertNil(flow.upcomingCommitment)
        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertEqual(flow.status, .noCoverage)
    }

    func testImminentCalendarDeselectionProvidesAnAccountSpecificWarning() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
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
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)

        let warning = flow.calendarDeselectionWarning(
            for: calendar.id,
            accountID: account.id,
            at: now
        )

        XCTAssertTrue(warning?.contains(account.email) == true)
        XCTAssertTrue(warning?.contains(calendar.name) == true)
        XCTAssertTrue(warning?.contains("imminent") == true)
    }

    func testDeselectingOneCalendarKeepsTheAccountsOtherSelectedCalendarsProtected() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let workCalendar = CalendarOption(id: "calendar-work", name: "Work", accountID: account.id)
        let personalCalendar = CalendarOption(id: "calendar-personal", name: "Personal", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let workCommitment = CalendarEvent(
            id: "work-event",
            title: "Work review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: workCalendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(
                account: account,
                calendars: [workCalendar, personalCalendar]
            ),
            events: [workCommitment],
            now: now
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: workCalendar.id)
        flow.setCalendarSelected(true, calendarID: personalCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        flow.setCalendarSelected(false, calendarID: personalCalendar.id)

        XCTAssertEqual(flow.selectedCalendarIDs, [workCalendar.id])
        XCTAssertTrue(flow.isProtectionConfirmed)
        XCTAssertEqual(flow.status, .active)
        XCTAssertEqual(flow.strongAlertCommitment, workCommitment)
    }

    func testCalendarRequestFailureExplainsGoogleOAuthReason() {
        let error = GoogleCalendarConnectorError.calendarRequestFailed(
            403,
            "insufficientPermissions: Insufficient Permission"
        )

        XCTAssertEqual(
            error.errorDescription,
            "Google Calendar access was denied. Reconnect the account and approve read-only calendar access."
        )
    }

    func testCalendarAPIErrorResponseExplainsRealisticFailure() {
        let data = Data(#"""
        {
            "error": {
                "errors": [
                    {
                        "domain": "global",
                        "reason": "insufficientPermissions",
                        "message": "Insufficient Permission"
                    }
                ],
                "code": 403,
                "message": "Request had insufficient authentication scopes."
            }
        }
        """#.utf8)

        XCTAssertEqual(
            googleFailureReason(from: data),
            "403: Request had insufficient authentication scopes."
        )
    }

    func testAcceptedTimedEventFromSelectedCalendarProducesEarlyReminder() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.upcomingCommitment, commitment)
        XCTAssertEqual(flow.earlyReminderCommitment, commitment)
        XCTAssertEqual(flow.earlyReminderLeadTimeMinutes, 10)
    }

    func testUnacceptedAndAllDayEventsDoNotProduceEarlyReminders() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let unacceptedEvent = CalendarEvent(
            id: "event-unaccepted",
            title: "Optional review",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(65 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: false,
            calendarID: calendar.id,
            accountID: account.id
        )
        let allDayEvent = CalendarEvent(
            id: "event-all-day",
            title: "Company holiday",
            startDate: nil,
            endDate: nil,
            timeZoneIdentifier: nil,
            isAllDay: true,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [unacceptedEvent, allDayEvent],
            now: now
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertNil(flow.upcomingCommitment)
        XCTAssertNil(flow.earlyReminderCommitment)
    }

    func testClosingEarlyReminderForNowStillShowsStrongAlertAtStart() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)
        flow.clearEarlyReminder()
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.upcomingCommitment, commitment)
        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertNil(flow.currentCommitmentDecision)
        XCTAssertFalse(flow.canRestoreProtection)
        XCTAssertTrue(flow.activityLog.contains { activity in
            activity.kind == .earlyReminderCleared && activity.commitmentID == commitment.id
        })

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(10 * 60))

        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertEqual(flow.strongAlertCommitment, commitment)
    }

    func testSnoozeOptionsSuppressAllRemindersAcrossCommitmentStart() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(4 * 60),
            endDate: now.addingTimeInterval(64 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.snoozeOptionsMinutes, [5, 10, 15, 30])
        XCTAssertTrue(flow.canSnoozeEarlyReminder)
        XCTAssertFalse(flow.snoozeEarlyReminder(minutes: 60, at: now))
        XCTAssertTrue(flow.snoozeEarlyReminder(minutes: 5, at: now))
        XCTAssertEqual(flow.lastActionMessage, "Reminders for this occurrence snoozed for 5 minutes. Protection remains active.")
        XCTAssertNil(flow.earlyReminderCommitment)

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(4 * 60))

        XCTAssertFalse(flow.isStrongAlertPresented)
        XCTAssertNil(flow.strongAlertCommitment)

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(5 * 60))

        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertFalse(flow.canSnoozeEarlyReminder)
        XCTAssertFalse(flow.snoozeEarlyReminder(minutes: 5, at: now.addingTimeInterval(8 * 60)))
    }

    func testEarlyReminderActionsAreBoundToTheirDisplayedOccurrence() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let displayedCommitment = CalendarEvent(
            id: "displayed-event",
            title: "Displayed commitment",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let newerCommitment = CalendarEvent(
            id: "newer-event",
            title: "Newer commitment",
            startDate: now.addingTimeInterval(20 * 60),
            endDate: now.addingTimeInterval(80 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [displayedCommitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertFalse(flow.clearEarlyReminder(for: newerCommitment))
        XCTAssertFalse(flow.snoozeEarlyReminder(minutes: 5, for: newerCommitment, at: now))
        XCTAssertEqual(flow.earlyReminderCommitment, displayedCommitment)

        XCTAssertTrue(flow.clearEarlyReminder(for: displayedCommitment))
        XCTAssertNil(flow.earlyReminderCommitment)
    }

    func testSnoozeDoesNotShowAnAlertAfterTheCommitmentEnds() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(1 * 60),
            endDate: now.addingTimeInterval(3 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertTrue(flow.snoozeEarlyReminder(minutes: 30, at: now))

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(2 * 60))
        XCTAssertFalse(flow.isStrongAlertPresented)

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(3 * 60))
        XCTAssertNil(flow.upcomingCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testSnoozeReturnsOnceButCannotBeUsedAgain() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertTrue(flow.snoozeEarlyReminder(minutes: 5, at: now))

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(5 * 60))

        XCTAssertEqual(flow.earlyReminderCommitment, commitment)
        XCTAssertFalse(flow.canSnoozeEarlyReminder)
        XCTAssertFalse(flow.snoozeEarlyReminder(minutes: 10, at: now.addingTimeInterval(5 * 60)))
    }

    func testDismissStopsTheOccurrenceAndRestoreProtectionReactivatesIt() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertTrue(flow.dismissCommitment(at: now))

        await flow.refreshCommitmentProtection(at: now)

        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertEqual(flow.upcomingCommitment, commitment)
        XCTAssertEqual(flow.currentCommitmentDecision, .dismissed)
        XCTAssertTrue(flow.canRestoreProtection)
        XCTAssertEqual(flow.lastActionMessage, "Reminders stopped for this occurrence. Google Calendar RSVP unchanged.")
        XCTAssertTrue(flow.restoreProtection(at: now))
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertNil(flow.currentCommitmentDecision)
        XCTAssertFalse(flow.canRestoreProtection)
        XCTAssertEqual(flow.earlyReminderCommitment, commitment)
        XCTAssertEqual(flow.lastActionMessage, "Protection restored for this occurrence.")
    }

    func testDismissedOccurrenceDoesNotHideTheNextRecurringOccurrence() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstOccurrence = CalendarEvent(
            id: "weekly-review",
            title: "Weekly review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(12 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let nextOccurrence = CalendarEvent(
            id: firstOccurrence.id,
            title: firstOccurrence.title,
            startDate: now.addingTimeInterval(15 * 60),
            endDate: now.addingTimeInterval(17 * 60),
            timeZoneIdentifier: firstOccurrence.timeZoneIdentifier,
            isAllDay: firstOccurrence.isAllDay,
            isAccepted: firstOccurrence.isAccepted,
            calendarID: firstOccurrence.calendarID,
            accountID: firstOccurrence.accountID
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstOccurrence, nextOccurrence]
        )
        let flow = makeMutableFlow(connector: connector, now: now)

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.earlyReminderCommitment, firstOccurrence)
        XCTAssertTrue(flow.dismissCommitment(at: now))

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(5 * 60))

        XCTAssertEqual(flow.upcomingCommitment, firstOccurrence)
        XCTAssertEqual(flow.earlyReminderCommitment, nextOccurrence)
        XCTAssertEqual(flow.currentCommitmentDecision, .dismissed)
    }

    func testHandledDecisionCanBeRestoredAfterStrongAlertIsCleared() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "On-site review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        flow.handleStrongAlert()
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertFalse(flow.isStrongAlertPresented)
        XCTAssertEqual(flow.currentCommitmentDecision, .handled)
        XCTAssertTrue(flow.canRestoreProtection)
        XCTAssertEqual(flow.lastActionMessage, "Handled for this occurrence. Protection is off until it ends.")
        XCTAssertTrue(flow.restoreProtection(at: now))
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertNil(flow.currentCommitmentDecision)
    }

    func testDismissedDecisionSurvivesRelaunchForTheCurrentOccurrence() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])
        let suiteName = "CommitmentProtectionFlowTests.decisionPersistence.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(connection: connection, events: [commitment]),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await activateProtection(for: firstLaunch, calendarID: calendar.id)
        await firstLaunch.refreshCommitmentProtection(at: now)
        XCTAssertTrue(firstLaunch.dismissCommitment(at: now))

        let relaunch = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(connection: connection, events: [commitment]),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await relaunch.restoreSavedConnection()

        XCTAssertEqual(relaunch.currentCommitmentDecision, .dismissed)
        XCTAssertEqual(relaunch.decisionCommitment, commitment)
        XCTAssertNil(relaunch.earlyReminderCommitment)
        XCTAssertTrue(relaunch.canRestoreProtection)
    }

    func testSnoozeUsageSurvivesRelaunchForTheCurrentOccurrence() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])
        let suiteName = "CommitmentProtectionFlowTests.snoozePersistence.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(connection: connection, events: [commitment]),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await activateProtection(for: firstLaunch, calendarID: calendar.id)
        await firstLaunch.refreshCommitmentProtection(at: now)
        XCTAssertTrue(firstLaunch.snoozeEarlyReminder(minutes: 5, at: now))

        let relaunch = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(connection: connection, events: [commitment]),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await relaunch.restoreSavedConnection()

        XCTAssertNil(relaunch.earlyReminderCommitment)
        XCTAssertFalse(relaunch.canSnoozeEarlyReminder)

        await relaunch.refreshCommitmentProtection(at: now.addingTimeInterval(5 * 60))

        XCTAssertEqual(relaunch.earlyReminderCommitment, commitment)
        XCTAssertFalse(relaunch.canSnoozeEarlyReminder)
    }

    func testEarlyActionTargetsItsOccurrenceWhenAnotherCommitmentIsActive() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let activeCommitment = CalendarEvent(
            id: "active-event",
            title: "Current review",
            startDate: now.addingTimeInterval(-2 * 60),
            endDate: now.addingTimeInterval(30 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let upcomingCommitment = CalendarEvent(
            id: "upcoming-event",
            title: "Next review",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(65 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [activeCommitment, upcomingCommitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.strongAlertCommitment, activeCommitment)
        XCTAssertEqual(flow.earlyReminderCommitment, upcomingCommitment)
        XCTAssertTrue(flow.dismissCommitment(for: upcomingCommitment, at: now))

        XCTAssertEqual(flow.currentCommitmentDecision, .dismissed)
        XCTAssertEqual(flow.decisionCommitment, upcomingCommitment)
        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertEqual(flow.strongAlertCommitment, activeCommitment)
        XCTAssertTrue(flow.isStrongAlertPresented)
    }

    func testCancelingAProtectedCommitmentRemovesItsPendingProtection() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment]
        )
        let suiteName = "CommitmentProtectionFlowTests.cancelled.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.earlyReminderCommitment, commitment)

        connector.events = []
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(2 * 60))

        XCTAssertNil(flow.upcomingCommitment)
        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(10 * 60))

        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testReschedulingACommitmentIntoItsActiveWindowShowsAnOverdueStrongAlert() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let originalCommitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(20 * 60),
            endDate: now.addingTimeInterval(80 * 60),
            timeZoneIdentifier: "Europe/Istanbul",
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let rescheduledCommitment = CalendarEvent(
            id: originalCommitment.id,
            title: originalCommitment.title,
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(35 * 60),
            timeZoneIdentifier: originalCommitment.timeZoneIdentifier,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [originalCommitment]
        )
        let flow = makeMutableFlow(connector: connector, now: now)

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(10 * 60))
        XCTAssertEqual(flow.earlyReminderCommitment, originalCommitment)

        connector.events = [rescheduledCommitment]
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(15 * 60))

        XCTAssertNil(flow.upcomingCommitment)
        XCTAssertEqual(flow.strongAlertCommitment, rescheduledCommitment)
        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertEqual(
            flow.strongAlertTimingText(for: rescheduledCommitment, at: now.addingTimeInterval(15 * 60)),
            "Overdue · started 10 minutes ago"
        )
    }

    func testChangingTheMeetingLinkUpdatesTheJoinPathForAnActiveCommitment() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let oldLink = URL(string: "https://meet.google.com/old-link")!
        let newLink = URL(string: "https://meet.google.com/new-link")!
        let originalCommitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: oldLink
        )
        let updatedCommitment = CalendarEvent(
            id: originalCommitment.id,
            title: originalCommitment.title,
            startDate: originalCommitment.startDate,
            endDate: originalCommitment.endDate,
            timeZoneIdentifier: originalCommitment.timeZoneIdentifier,
            isAllDay: originalCommitment.isAllDay,
            isAccepted: originalCommitment.isAccepted,
            calendarID: originalCommitment.calendarID,
            accountID: originalCommitment.accountID,
            recognizedMeetingLink: newLink
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [originalCommitment]
        )
        let flow = makeMutableFlow(connector: connector, now: now)

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.strongAlertCommitment?.recognizedMeetingLink, oldLink)

        connector.events = [updatedCommitment]
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(1))

        XCTAssertEqual(flow.strongAlertCommitment, updatedCommitment)
        XCTAssertTrue(flow.openStrongAlertMeetingLink { $0 == newLink })
    }

    func testChangingACommitmentTimeZoneUpdatesTheDisplayedLocalTimeLabel() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let originalCommitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: "America/Los_Angeles",
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let updatedCommitment = CalendarEvent(
            id: originalCommitment.id,
            title: originalCommitment.title,
            startDate: originalCommitment.startDate,
            endDate: originalCommitment.endDate,
            timeZoneIdentifier: "Asia/Tokyo",
            isAllDay: originalCommitment.isAllDay,
            isAccepted: originalCommitment.isAccepted,
            calendarID: originalCommitment.calendarID,
            accountID: originalCommitment.accountID
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [originalCommitment]
        )
        let flow = makeMutableFlow(connector: connector, now: now)

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.earlyReminderCommitment, originalCommitment)

        connector.events = [updatedCommitment]
        await flow.refreshCommitmentProtection(at: now)

        let updatedZoneLabel = TimeZone(identifier: "Asia/Tokyo")!.abbreviation(for: now.addingTimeInterval(10 * 60))!
        XCTAssertEqual(flow.earlyReminderCommitment, updatedCommitment)
        XCTAssertTrue(flow.localStartTimeText(for: updatedCommitment).contains(updatedZoneLabel))
    }

    func testRecurringOccurrenceMutationLeavesUnchangedOccurrencesProtected() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstOccurrence = CalendarEvent(
            id: "series-occurrence-1",
            title: "Weekly review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(40 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let unchangedOccurrence = CalendarEvent(
            id: "series-occurrence-2",
            title: "Weekly review",
            startDate: now.addingTimeInterval(20 * 60),
            endDate: now.addingTimeInterval(50 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let rescheduledFirstOccurrence = CalendarEvent(
            id: firstOccurrence.id,
            title: firstOccurrence.title,
            startDate: now.addingTimeInterval(30 * 60),
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: firstOccurrence.timeZoneIdentifier,
            isAllDay: firstOccurrence.isAllDay,
            isAccepted: firstOccurrence.isAccepted,
            calendarID: firstOccurrence.calendarID,
            accountID: firstOccurrence.accountID
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [firstOccurrence, unchangedOccurrence]
        )
        let flow = makeMutableFlow(connector: connector, now: now)

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.earlyReminderCommitment, firstOccurrence)

        connector.events = [rescheduledFirstOccurrence, unchangedOccurrence]
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(10 * 60))

        XCTAssertEqual(flow.upcomingCommitment, unchangedOccurrence)
        XCTAssertEqual(flow.earlyReminderCommitment, unchangedOccurrence)
    }

    func testCommitmentAcceptedAfterItsStartDoesNotShowAnAlert() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(-5 * 60),
            endDate: now.addingTimeInterval(55 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let unacceptedCommitment = CalendarEvent(
            id: commitment.id,
            title: commitment.title,
            startDate: commitment.startDate,
            endDate: commitment.endDate,
            timeZoneIdentifier: commitment.timeZoneIdentifier,
            isAllDay: commitment.isAllDay,
            isAccepted: false,
            calendarID: commitment.calendarID,
            accountID: commitment.accountID
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [unacceptedCommitment]
        )
        let flow = makeMutableFlow(connector: connector, now: now)

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)

        connector.events = [commitment]
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertNil(flow.upcomingCommitment)
        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(1 * 60))

        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testConfigurationChangePreservesLateAcceptanceSuppression() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let workCalendar = CalendarOption(id: "calendar-work", name: "Work", accountID: account.id)
        let personalCalendar = CalendarOption(id: "calendar-personal", name: "Personal", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let acceptedCommitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(-5 * 60),
            endDate: now.addingTimeInterval(55 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: workCalendar.id,
            accountID: account.id
        )
        let unacceptedCommitment = CalendarEvent(
            id: acceptedCommitment.id,
            title: acceptedCommitment.title,
            startDate: acceptedCommitment.startDate,
            endDate: acceptedCommitment.endDate,
            timeZoneIdentifier: acceptedCommitment.timeZoneIdentifier,
            isAllDay: acceptedCommitment.isAllDay,
            isAccepted: false,
            calendarID: acceptedCommitment.calendarID,
            accountID: acceptedCommitment.accountID
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(
                account: account,
                calendars: [workCalendar, personalCalendar]
            ),
            events: [unacceptedCommitment]
        )
        let flow = makeMutableFlow(connector: connector, now: now)

        await activateProtection(for: flow, calendarID: workCalendar.id)
        await flow.refreshCommitmentProtection(at: now)

        flow.setCalendarSelected(true, calendarID: personalCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        connector.events = [acceptedCommitment]
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testLateAcceptanceSuppressionSurvivesRelaunch() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(-5 * 60),
            endDate: now.addingTimeInterval(55 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let unacceptedCommitment = CalendarEvent(
            id: commitment.id,
            title: commitment.title,
            startDate: commitment.startDate,
            endDate: commitment.endDate,
            timeZoneIdentifier: commitment.timeZoneIdentifier,
            isAllDay: commitment.isAllDay,
            isAccepted: false,
            calendarID: commitment.calendarID,
            accountID: commitment.accountID
        )
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])
        let connector = MutableTestGoogleCalendarConnector(connection: connection, events: [unacceptedCommitment])
        let suiteName = "CommitmentProtectionFlowTests.lateAcceptancePersistence.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        connector.events = [commitment]
        await flow.refreshCommitmentProtection(at: now)

        let relaunch = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(connection: connection, events: [commitment]),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await relaunch.restoreSavedConnection()

        XCTAssertNil(relaunch.earlyReminderCommitment)
        XCTAssertNil(relaunch.strongAlertCommitment)
        XCTAssertFalse(relaunch.isStrongAlertPresented)
    }

    func testDismissedOccurrenceDoesNotSuppressItsRescheduledSuccessor() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let originalCommitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let rescheduledCommitment = CalendarEvent(
            id: originalCommitment.id,
            title: originalCommitment.title,
            startDate: now.addingTimeInterval(30 * 60),
            endDate: now.addingTimeInterval(90 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [originalCommitment]
        )
        let suiteName = "CommitmentProtectionFlowTests.isolated.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertTrue(flow.dismissCommitment(at: now))

        connector.events = [rescheduledCommitment]
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(20 * 60))

        XCTAssertNil(flow.currentCommitmentDecision)
        XCTAssertEqual(flow.earlyReminderCommitment, rescheduledCommitment)
    }

    func testRescheduledEventGetsANewEarlyReminder() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let originalCommitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let rescheduledCommitment = CalendarEvent(
            id: originalCommitment.id,
            title: originalCommitment.title,
            startDate: now.addingTimeInterval(30 * 60),
            endDate: now.addingTimeInterval(90 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [originalCommitment]
        )
        let suiteName = "CommitmentProtectionFlowTests.isolated.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)
        flow.clearEarlyReminder()

        connector.events = [rescheduledCommitment]
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(20 * 60))

        XCTAssertEqual(flow.upcomingCommitment, rescheduledCommitment)
        XCTAssertEqual(flow.earlyReminderCommitment, rescheduledCommitment)
    }

    func testCalendarRefreshFailureRetainsKnownCommitmentWhileCoverageIsUnavailable() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let state = TestGoogleCalendarConnectorState()
        let suiteName = "CommitmentProtectionFlowTests.isolated.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(
                connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
                events: [commitment],
                state: state
            ),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.earlyReminderCommitment, commitment)
        flow.clearEarlyReminder()
        XCTAssertNil(flow.earlyReminderCommitment)

        state.loadEventsError = TestCalendarLoadError.unavailable
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.upcomingCommitment, commitment)
        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertEqual(flow.status, .unavailable)
        XCTAssertEqual(flow.connectionState, .failed("The test calendar is unavailable."))

        state.loadEventsError = nil
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.upcomingCommitment, commitment)
        XCTAssertNil(flow.earlyReminderCommitment)
    }

    func testInvalidCredentialDuringRefreshRequiresReconnectAndClearsCachedProtection() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let state = TestGoogleCalendarConnectorState()
        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(
                connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
                events: [commitment],
                state: state
            ),
            launchAtLogin: TestLaunchAtLoginController(),
            now: { now }
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.upcomingCommitment, commitment)

        state.loadEventsError = GoogleCalendarConnectorError.tokenExchangeFailed(
            400,
            "invalid_grant: token revoked"
        )
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.connectionState, .reconnectRequired)
        XCTAssertEqual(flow.coverage(for: account.id), .reconnectRequired)
        XCTAssertNil(flow.upcomingCommitment)
        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertNil(flow.strongAlertCommitment)
    }

    func testMissingBlockingPermissionKeepsVisualEarlyReminderActive() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        flow.setBlockingAvailability(false)

        XCTAssertEqual(flow.status, .active)
        XCTAssertFalse(flow.isBlockingAvailable)
        XCTAssertEqual(flow.upcomingCommitment, commitment)
        XCTAssertEqual(flow.earlyReminderCommitment, commitment)

        flow.setBlockingAvailability(true)

        XCTAssertEqual(flow.status, .active)
    }

    func testOlderRefreshCannotRestoreACommitmentAfterANewerRefreshClearsIt() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let state = RefreshRaceConnectorState(holdNextLoad: true)
        let connector = RefreshRaceTestConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            state: state
        )
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            now: { now }
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        for _ in 0..<20 {
            if await state.hasFirstLoadStarted() { break }
            await Task.yield()
        }
        let firstLoadStarted = await state.hasFirstLoadStarted()
        XCTAssertTrue(firstLoadStarted)

        connector.replaceEvents([])
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await state.releaseFirstLoad()
        await settleScheduledRefreshes()

        XCTAssertNil(flow.upcomingCommitment)
        XCTAssertNil(flow.earlyReminderCommitment)
    }

    func testAppManagedDataResetLockInvalidatesAnInFlightRefreshResponse() async {
        let fixture = makeRefreshTerminationFixture(testName: #function)
        defer { fixture.cleanUp() }

        await fixture.flow.connectGoogleAccount()
        fixture.flow.setCalendarSelected(true, calendarID: fixture.calendar.id)
        XCTAssertTrue(fixture.flow.confirmProtection())
        await settleScheduledRefreshes()
        await fixture.flow.refreshCommitmentProtection(at: fixture.now)
        XCTAssertEqual(fixture.flow.upcomingCommitment, fixture.commitment)

        let replacement = CalendarEvent(
            id: "replacement-event",
            title: "Replacement review",
            startDate: fixture.now.addingTimeInterval(20 * 60),
            endDate: fixture.now.addingTimeInterval(80 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: fixture.calendar.id,
            accountID: fixture.account.id
        )
        fixture.connector.replaceEvents([replacement])
        await fixture.state.armNextLoad()
        let refreshTask = Task { @MainActor in
            await fixture.flow.refreshCommitmentProtection(at: fixture.now)
        }
        for _ in 0..<20 {
            if await fixture.state.hasFirstLoadStarted() { break }
            await Task.yield()
        }
        let refreshStarted = await fixture.state.hasFirstLoadStarted()
        XCTAssertTrue(refreshStarted)

        fixture.flow.lockMutationsForAppManagedDataReset()
        await fixture.state.releaseFirstLoad()
        await refreshTask.value

        XCTAssertEqual(fixture.flow.upcomingCommitment, fixture.commitment)
        XCTAssertNotEqual(fixture.flow.upcomingCommitment, replacement)
        let loadCallCount = await fixture.state.loadCallCount()
        await fixture.flow.refreshCommitmentProtection(at: fixture.now)
        let loadCallCountAfterLock = await fixture.state.loadCallCount()
        XCTAssertEqual(loadCallCountAfterLock, loadCallCount)
    }

    func testDisconnectCannotBeResurrectedByInFlightRefresh() async {
        let fixture = makeRefreshTerminationFixture(testName: #function)
        defer { fixture.cleanUp() }

        await fixture.flow.connectGoogleAccount()
        fixture.flow.setCalendarSelected(true, calendarID: fixture.calendar.id)
        XCTAssertTrue(fixture.flow.confirmProtection())
        await settleScheduledRefreshes()
        await fixture.flow.refreshCommitmentProtection(at: fixture.now)
        XCTAssertEqual(fixture.flow.upcomingCommitment, fixture.commitment)

        await fixture.state.armNextLoad()
        let refreshTask = Task { @MainActor in
            await fixture.flow.refreshCommitmentProtection(at: fixture.now)
        }
        for _ in 0..<20 {
            if await fixture.state.hasFirstLoadStarted() { break }
            await Task.yield()
        }
        let refreshStarted = await fixture.state.hasFirstLoadStarted()
        XCTAssertTrue(refreshStarted)

        await fixture.state.armNextRevocation()
        let disconnectTask = Task { @MainActor in
            await fixture.flow.disconnectGoogleAccount(accountID: fixture.account.id)
        }
        for _ in 0..<20 {
            if await fixture.state.hasRevocationStarted() { break }
            await Task.yield()
        }
        let revocationStarted = await fixture.state.hasRevocationStarted()
        XCTAssertTrue(revocationStarted)

        await fixture.state.releaseFirstLoad()
        await refreshTask.value
        await fixture.state.releaseRevocation()
        let didDisconnect = await disconnectTask.value
        XCTAssertTrue(didDisconnect)

        XCTAssertEqual(fixture.flow.coverage(for: fixture.account.id), .reconnectRequired)
        XCTAssertEqual(
            fixture.flow.selectedCalendarIDs(for: fixture.account.id),
            [fixture.calendar.id]
        )
        XCTAssertNil(fixture.flow.upcomingCommitment)
        XCTAssertNil(fixture.flow.earlyReminderCommitment)
        XCTAssertNil(fixture.flow.strongAlertCommitment)
    }

    func testRemoveCannotBeResurrectedByInFlightRefresh() async {
        let fixture = makeRefreshTerminationFixture(testName: #function)
        defer { fixture.cleanUp() }

        await fixture.flow.connectGoogleAccount()
        fixture.flow.setCalendarSelected(true, calendarID: fixture.calendar.id)
        XCTAssertTrue(fixture.flow.confirmProtection())
        await settleScheduledRefreshes()
        await fixture.flow.refreshCommitmentProtection(at: fixture.now)
        XCTAssertEqual(fixture.flow.upcomingCommitment, fixture.commitment)

        await fixture.state.armNextLoad()
        let refreshTask = Task { @MainActor in
            await fixture.flow.refreshCommitmentProtection(at: fixture.now)
        }
        for _ in 0..<20 {
            if await fixture.state.hasFirstLoadStarted() { break }
            await Task.yield()
        }
        let refreshStarted = await fixture.state.hasFirstLoadStarted()
        XCTAssertTrue(refreshStarted)

        await fixture.state.armNextRevocation()
        let removeTask = Task { @MainActor in
            await fixture.flow.removeGoogleAccount(accountID: fixture.account.id)
        }
        for _ in 0..<20 {
            if await fixture.state.hasRevocationStarted() { break }
            await Task.yield()
        }
        let revocationStarted = await fixture.state.hasRevocationStarted()
        XCTAssertTrue(revocationStarted)

        await fixture.state.releaseFirstLoad()
        await refreshTask.value
        await fixture.state.releaseRevocation()
        let didRemove = await removeTask.value
        XCTAssertTrue(didRemove)

        XCTAssertNil(fixture.flow.coverage(for: fixture.account.id))
        XCTAssertTrue(fixture.flow.accountCoverages.isEmpty)
        XCTAssertFalse(fixture.flow.activityLog.contains { $0.accountID == fixture.account.id })
        XCTAssertNil(fixture.flow.upcomingCommitment)
        XCTAssertNil(fixture.flow.earlyReminderCommitment)
        XCTAssertNil(fixture.flow.strongAlertCommitment)
    }

    func testRefreshDuringTransientlyFailingDisconnectPreservesAccountState() async throws {
        let fixture = makeRefreshTerminationFixture(testName: #function)
        defer { fixture.cleanUp() }

        await fixture.flow.connectGoogleAccount()
        fixture.flow.setCalendarSelected(true, calendarID: fixture.calendar.id)
        XCTAssertTrue(fixture.flow.confirmProtection())
        await settleScheduledRefreshes()
        await fixture.flow.refreshCommitmentProtection(at: fixture.now)
        XCTAssertTrue(fixture.flow.dismissCommitment(at: fixture.now))
        XCTAssertTrue(fixture.flow.pause(for: .oneHour, at: fixture.now))

        let pauseUntil = try XCTUnwrap(fixture.flow.pauseUntil)
        let lastActionMessage = try XCTUnwrap(fixture.flow.lastActionMessage)
        let activityIDs = fixture.flow.activityLog.map(\.id)
        let loadCallCount = await fixture.state.loadCallCount()
        XCTAssertEqual(fixture.flow.upcomingCommitment, fixture.commitment)
        XCTAssertEqual(fixture.flow.currentCommitmentDecision, .dismissed)
        XCTAssertTrue(fixture.flow.canRestoreProtection)

        await fixture.state.armNextRevocation(error: .networkUnavailable)
        let disconnectTask = Task { @MainActor in
            await fixture.flow.disconnectGoogleAccount(accountID: fixture.account.id)
        }
        for _ in 0..<20 {
            if await fixture.state.hasRevocationStarted() { break }
            await Task.yield()
        }
        let revocationStarted = await fixture.state.hasRevocationStarted()
        XCTAssertTrue(revocationStarted)

        await fixture.flow.refreshCommitmentProtection(at: fixture.now.addingTimeInterval(60))

        let loadCallCountDuringRevocation = await fixture.state.loadCallCount()
        XCTAssertEqual(loadCallCountDuringRevocation, loadCallCount)
        assertProtectedAccountState(
            fixture,
            pauseUntil: pauseUntil,
            lastActionMessage: lastActionMessage,
            activityIDs: activityIDs
        )

        await fixture.state.releaseRevocation()
        let didDisconnect = await disconnectTask.value

        XCTAssertFalse(didDisconnect)
        XCTAssertNil(fixture.flow.terminatingAccountID)
        XCTAssertEqual(fixture.flow.failedAccountDisconnectionID, fixture.account.id)
        XCTAssertNotNil(fixture.flow.accountDisconnectionError)
        let loadCallCountAfterFailure = await fixture.state.loadCallCount()
        XCTAssertEqual(loadCallCountAfterFailure, loadCallCount)
        assertProtectedAccountState(
            fixture,
            pauseUntil: pauseUntil,
            lastActionMessage: lastActionMessage,
            activityIDs: activityIDs
        )
    }

    func testConnectAndReconnectAreBlockedWhileDisconnectAwaitsRevocation() async {
        await assertConnectionAttemptsAreBlocked(
            during: .disconnect,
            testName: #function
        )
    }

    func testConnectAndReconnectAreBlockedWhileRemoveAwaitsRevocation() async {
        await assertConnectionAttemptsAreBlocked(
            during: .remove,
            testName: #function
        )
    }

    func testLeadTimeIsGlobalAndPersistsWithinConfiguration() {
        let suiteName = "CommitmentProtectionFlowTests.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )
        XCTAssertEqual(flow.earlyReminderLeadTimeMinutes, 10)

        flow.setEarlyReminderLeadTime(minutes: 25)

        let relaunchedFlow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )
        XCTAssertEqual(relaunchedFlow.earlyReminderLeadTimeMinutes, 25)

        flow.setEarlyReminderLeadTime(minutes: 2)
        XCTAssertEqual(flow.earlyReminderLeadTimeMinutes, 5)
        flow.setEarlyReminderLeadTime(minutes: 60)
        XCTAssertEqual(flow.earlyReminderLeadTimeMinutes, 30)
    }

    func testEarlyReminderCanBeDisabledWithoutSuppressingStrongAlert() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let suiteName = "CommitmentProtectionFlowTests.earlyReminderToggle.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now,
            stateStore: stateStore
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.earlyReminderCommitment, commitment)

        flow.setEarlyReminderEnabled(false)
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.upcomingCommitment, commitment)
        XCTAssertNil(flow.earlyReminderCommitment)

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(10 * 60))
        XCTAssertTrue(flow.isStrongAlertPresented)
    }

    func testEarlyReminderAndBlockingSettingsPersistAcrossRelaunch() {
        let suiteName = "CommitmentProtectionFlowTests.reminderSettings.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let flow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )
        XCTAssertTrue(flow.isEarlyReminderEnabled)
        XCTAssertFalse(flow.isBlockingModeEnabled)
        XCTAssertFalse(flow.isOutOfOfficeProtectionEnabled)

        flow.setEarlyReminderEnabled(false)
        flow.setBlockingModeEnabled(true)
        flow.setOutOfOfficeProtectionEnabled(true)

        let relaunchedFlow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )
        XCTAssertFalse(relaunchedFlow.isEarlyReminderEnabled)
        XCTAssertTrue(relaunchedFlow.isBlockingModeEnabled)
        XCTAssertTrue(relaunchedFlow.isOutOfOfficeProtectionEnabled)
    }

    func testCountdownAndLocalTimeIncludeRelevantTimeZone() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: "America/Los_Angeles",
            isAllDay: false,
            isAccepted: true,
            calendarID: "calendar-1",
            accountID: "account-1"
        )
        let flow = makeFlow(now: now)
        let expectedZoneLabel = TimeZone(identifier: "America/Los_Angeles")!
            .abbreviation(for: commitment.startDate!)!

        XCTAssertEqual(flow.countdownText(for: commitment, at: now), "Starts in 10 minutes")
        XCTAssertTrue(flow.localStartTimeText(for: commitment).contains(expectedZoneLabel))
    }

    func testLocalStartTimeUsesTheCurrentLocale() {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let startDate = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: .current,
            year: 2026,
            month: 3,
            day: 2,
            hour: 14,
            minute: 30
        ))!
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let monitoredCalendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: monitoredCalendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [monitoredCalendar]),
            events: [commitment],
            now: startDate
        )

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        formatter.timeZone = .current

        XCTAssertEqual(
            flow.localStartTimeText(for: commitment),
            "\(formatter.string(from: startDate)) local time"
        )
    }

    func testGoogleEventResponseMapsAcceptanceAndAllDayState() throws {
        let data = Data(#"""
        {
            "items": [
                {
                    "id": "accepted-event",
                    "summary": "Accepted review",
                    "hangoutLink": "https://meet.google.com/abc-defg-hij",
                    "conferenceData": {
                        "entryPoints": [
                            {"entryPointType": "video", "uri": "https://zoom.us/j/123456789"}
                        ]
                    },
                    "start": {
                        "dateTime": "2026-08-20T10:00:00+03:00",
                        "timeZone": "Europe/Istanbul"
                    },
                    "end": {
                        "dateTime": "2026-08-20T11:00:00+03:00",
                        "timeZone": "Europe/Istanbul"
                    },
                    "attendees": [
                        {"email": "guest@example.com", "responseStatus": "accepted"},
                        {"self": true, "responseStatus": "accepted"}
                    ]
                },
                {
                    "id": "all-day-event",
                    "summary": "Company holiday",
                    "start": {"date": "2026-08-20"},
                    "end": {"date": "2026-08-21"},
                    "attendees": [{"self": true, "responseStatus": "accepted"}]
                },
                {
                    "id": "unaccepted-event",
                    "summary": "Optional review",
                    "start": {"dateTime": "2026-08-20T12:00:00+03:00"},
                    "end": {"dateTime": "2026-08-20T13:00:00+03:00"},
                    "attendees": [{"self": true, "responseStatus": "tentative"}]
                }
            ]
        }
        """#.utf8)

        let events = try decodeGoogleCalendarEvents(
            from: data,
            accountID: "account-1",
            calendarID: "calendar-1"
        )

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].title, "Accepted review")
        XCTAssertTrue(events[0].isAccepted)
        XCTAssertFalse(events[0].isAllDay)
        XCTAssertEqual(events[0].recognizedMeetingLink, URL(string: "https://meet.google.com/abc-defg-hij"))
        XCTAssertEqual(
            events[0].recognizedMeetingLinks.map(\.url),
            [
                URL(string: "https://meet.google.com/abc-defg-hij")!,
                URL(string: "https://zoom.us/j/123456789")!
            ]
        )
        XCTAssertEqual(events[0].primaryRecognizedMeetingLink, URL(string: "https://meet.google.com/abc-defg-hij"))
        XCTAssertTrue(events[1].isAllDay)
        XCTAssertTrue(events[1].isAccepted)
        XCTAssertFalse(events[2].isAccepted)
    }

    func testGoogleEventResponseMapsOutOfOfficeTypeAndNormalizesDescriptionToInertPlainText() throws {
        let data = Data(#"""
        {
            "items": [
                {
                    "id": "out-of-office-event",
                    "summary": "Out of office",
                    "description": "<p>Travel day</p><script>leak()</script><p>Back &amp; available tomorrow.</p><p>https://meet.google.com/not-a-join-action</p>",
                    "eventType": "outOfOffice",
                    "start": {"dateTime": "2026-08-20T10:00:00+03:00"},
                    "end": {"dateTime": "2026-08-20T18:00:00+03:00"},
                    "organizer": {"self": true}
                }
            ]
        }
        """#.utf8)

        let events = try decodeGoogleCalendarEvents(
            from: data,
            accountID: "account-1",
            calendarID: "calendar-1"
        )

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.eventType, .outOfOffice)
        XCTAssertEqual(
            event.meetingDescription,
            "Travel day\nBack & available tomorrow.\nhttps://meet.google.com/not-a-join-action"
        )
        XCTAssertTrue(event.recognizedMeetingLinks.isEmpty)
    }

    func testMeetingDescriptionIsBlankNormalizedAndLengthBounded() throws {
        let (account, calendar) = makeTestAccountAndCalendar()
        let longDescription = "<p>Agenda</p>" + String(repeating: "x", count: 2_500)
        let event = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            meetingDescription: longDescription,
            startDate: Date(timeIntervalSince1970: 1_000_000),
            endDate: Date(timeIntervalSince1970: 1_003_600),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let blankEvent = CalendarEvent(
            id: "event-2",
            title: "Customer review",
            meetingDescription: " <br> \n\t ",
            startDate: event.startDate,
            endDate: event.endDate,
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )

        let description = try XCTUnwrap(event.meetingDescription)
        XCTAssertEqual(description.count, CalendarEvent.maximumMeetingDescriptionCharacterCount)
        XCTAssertEqual(description.last, "…")
        XCTAssertFalse(description.contains("<"))
        XCTAssertNil(blankEvent.meetingDescription)
    }

    func testOutOfOfficeEventDoesNotCreateProtection() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let outOfOffice = CalendarEvent(
            id: "out-of-office-event",
            title: "Out of office",
            startDate: now,
            endDate: now.addingTimeInterval(24 * 60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            eventType: .outOfOffice
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [outOfOffice],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertFalse(flow.isStrongAlertPresented)
        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertNil(flow.earlyReminderCommitment)
    }

    func testOutOfOfficeOptInProducesEarlyReminderAndStrongAlert() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let outOfOffice = CalendarEvent(
            id: "out-of-office-event",
            title: "Out of office",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(8 * 60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            eventType: .outOfOffice
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [outOfOffice],
            now: now
        )

        XCTAssertFalse(flow.isOutOfOfficeProtectionEnabled)
        flow.setOutOfOfficeProtectionEnabled(true)
        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.earlyReminderCommitment, outOfOffice)
        XCTAssertFalse(flow.isStrongAlertPresented)

        await flow.refreshCommitmentProtection(at: outOfOffice.startDate!)

        XCTAssertEqual(flow.strongAlertCommitment, outOfOffice)
        XCTAssertTrue(flow.isStrongAlertPresented)
    }

    func testDisablingOutOfOfficeProtectionClearsItsActiveReminderAndAlert() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let outOfOffice = CalendarEvent(
            id: "out-of-office-event",
            title: "Out of office",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(8 * 60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            eventType: .outOfOffice
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [outOfOffice],
            now: now
        )

        flow.setOutOfOfficeProtectionEnabled(true)
        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.earlyReminderCommitment, outOfOffice)

        await flow.refreshCommitmentProtection(at: outOfOffice.startDate!)
        XCTAssertEqual(flow.strongAlertCommitment, outOfOffice)

        flow.setOutOfOfficeProtectionEnabled(false)

        XCTAssertNil(flow.upcomingCommitment)
        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testEnablingOutOfOfficeProtectionDoesNotAdoptAnAlreadyUnderwayEvent() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let outOfOffice = CalendarEvent(
            id: "out-of-office-event",
            title: "Out of office",
            startDate: now.addingTimeInterval(-5 * 60),
            endDate: now.addingTimeInterval(8 * 60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            eventType: .outOfOffice
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [outOfOffice],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        flow.setOutOfOfficeProtectionEnabled(true)
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertNil(flow.strongAlertCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testFirstEarlyReminderIsSuppressedWhenCommitmentIsLessThanOneMinuteAway() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "near-start-event",
            title: "Customer review",
            startDate: now.addingTimeInterval(20),
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertFalse(flow.isStrongAlertPresented)

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(20))

        XCTAssertEqual(flow.strongAlertCommitment, commitment)
        XCTAssertTrue(flow.isStrongAlertPresented)
    }

    func testFirstEarlyReminderAppearsAtExactlyOneMinuteBeforeStart() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "one-minute-event",
            title: "Customer review",
            startDate: now.addingTimeInterval(60),
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.earlyReminderCommitment, commitment)
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testVisibleEarlyReminderRemainsWhenCommitmentMovesInsideOneMinute() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "visible-reminder-event",
            title: "Customer review",
            startDate: now.addingTimeInterval(2 * 60),
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.earlyReminderCommitment, commitment)

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(90))

        XCTAssertEqual(flow.earlyReminderCommitment, commitment)
        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testPauseForOneHourSuppressesCurrentAndFutureProtectionAndShowsExpiration() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
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
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.earlyReminderCommitment, commitment)
        XCTAssertTrue(flow.pause(for: .oneHour, at: now))
        XCTAssertEqual(flow.pauseUntil, now.addingTimeInterval(60 * 60))
        XCTAssertTrue(flow.isPaused(at: now))
        XCTAssertTrue(flow.pauseExpirationText(at: now).contains("1 hour"))
        XCTAssertNil(flow.earlyReminderCommitment)

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(5 * 60))

        XCTAssertFalse(flow.isStrongAlertPresented)
        XCTAssertNil(flow.strongAlertCommitment)
    }

    func testActivityLogExplainsUserAndSystemProtectionActions() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        let earlyReminderActivity = flow.activityLog.first {
            $0.actor == .system &&
                $0.kind == .earlyReminderShown &&
                $0.commitmentTitle == commitment.title &&
                $0.commitmentID == commitment.id &&
                $0.commitmentStartDate == commitment.startDate &&
                $0.calendarID == calendar.id &&
                $0.calendarName == calendar.name &&
                $0.accountEmail == account.email
        }
        XCTAssertNotNil(earlyReminderActivity)

        XCTAssertTrue(flow.clearEarlyReminder(for: commitment))
        XCTAssertTrue(flow.activityLog.contains {
            $0.actor == .user && $0.kind == .earlyReminderCleared && $0.commitmentTitle == commitment.title
        })

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(10 * 60))
        XCTAssertTrue(flow.activityLog.contains {
            $0.actor == .system && $0.kind == .strongAlertShown && $0.commitmentTitle == commitment.title
        })

        flow.closeStrongAlertSurface(at: now.addingTimeInterval(10 * 60 + 1))
        XCTAssertTrue(flow.activityLog.contains {
            $0.actor == .user && $0.kind == .strongAlertClosed && $0.commitmentTitle == commitment.title
        })

        XCTAssertTrue(flow.dismissCommitment(for: commitment, at: now.addingTimeInterval(10 * 60 + 2)))
        XCTAssertTrue(flow.activityLog.contains {
            $0.actor == .user && $0.kind == .dismissed && $0.commitmentTitle == commitment.title
        })
    }

    func testProtectionActivityCanBeViewedPerCalendar() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let workCalendar = CalendarOption(id: "calendar-work", name: "Work", accountID: account.id)
        let personalCalendar = CalendarOption(id: "calendar-personal", name: "Personal", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let workCommitment = CalendarEvent(
            id: "work-event",
            title: "Work review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: workCalendar.id,
            accountID: account.id
        )
        let personalCommitment = CalendarEvent(
            id: "personal-event",
            title: "Personal appointment",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(65 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: personalCalendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(
                account: account,
                calendars: [workCalendar, personalCalendar]
            ),
            events: [workCommitment, personalCommitment],
            now: now
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: workCalendar.id)
        flow.setCalendarSelected(true, calendarID: personalCalendar.id)
        XCTAssertTrue(flow.confirmAllProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        let workActivities = flow.activities(forCalendarID: workCalendar.id, accountID: account.id)
        let personalActivities = flow.activities(forCalendarID: personalCalendar.id, accountID: account.id)

        XCTAssertTrue(workActivities.contains { $0.calendarID == workCalendar.id })
        XCTAssertTrue(workActivities.contains { $0.commitmentID == workCommitment.id })
        XCTAssertFalse(workActivities.contains { $0.calendarID == personalCalendar.id })
        XCTAssertTrue(personalActivities.contains { $0.calendarID == personalCalendar.id })
        XCTAssertTrue(personalActivities.contains { $0.commitmentID == personalCommitment.id })
        XCTAssertFalse(personalActivities.contains { $0.calendarID == workCalendar.id })
    }

    func testLegacyCalendarSelectionActivityIsAttributedAfterRelaunch() async throws {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let suiteName = "CommitmentProtectionFlowTests.legacyCalendarActivity.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])

        let firstLaunch = makeFlow(
            connection: connection,
            now: now,
            stateStore: stateStore
        )
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(firstLaunch.confirmProtection())
        await settleScheduledRefreshes()

        let legacyActivity = ProtectionActivity(
            occurredAt: now,
            actor: .user,
            kind: .configurationChanged,
            title: "Calendar selection changed",
            detail: "Monitoring Work.",
            accountID: account.id,
            accountEmail: account.email
        )
        stateStore.set(
            try JSONEncoder().encode([legacyActivity]),
            forKey: "commitment-protection.activity-log"
        )

        let relaunch = makeFlow(
            connection: connection,
            now: now,
            stateStore: stateStore
        )
        await relaunch.restoreSavedConnection()

        XCTAssertTrue(
            relaunch.activities(forCalendarID: calendar.id, accountID: account.id)
                .contains { $0.kind == .configurationChanged && $0.calendarName == calendar.name }
        )
    }

    func testPlaintextLegacyCommitmentActivityIsNotImportedAfterRelaunch() async throws {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
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
        let suiteName = "CommitmentProtectionFlowTests.legacyCommitmentActivity.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])

        let firstLaunch = makeFlow(
            connection: connection,
            events: [commitment],
            now: now,
            stateStore: stateStore
        )
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(firstLaunch.confirmProtection())
        await settleScheduledRefreshes()

        let legacyActivity = ProtectionActivity(
            occurredAt: now,
            actor: .user,
            kind: .dismissed,
            title: "Reminders stopped",
            detail: "Dismissed for this occurrence.",
            commitmentTitle: commitment.title,
            commitmentID: commitment.id,
            commitmentStartDate: commitment.startDate,
            accountID: account.id,
            accountEmail: account.email
        )
        stateStore.set(
            try JSONEncoder().encode([legacyActivity]),
            forKey: "commitment-protection.activity-log"
        )

        let relaunch = makeFlow(
            connection: connection,
            events: [commitment],
            now: now,
            stateStore: stateStore
        )
        await relaunch.restoreSavedConnection()

        XCTAssertFalse(
            relaunch.activities(forCalendarID: calendar.id, accountID: account.id)
                .contains { $0.id == legacyActivity.id && $0.calendarID == calendar.id }
        )
    }

    func testAmbiguousPlaintextLegacyCommitmentActivityIsNotImported() async throws {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
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
        let suiteName = "CommitmentProtectionFlowTests.ambiguousLegacyCommitmentActivity.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])

        let firstLaunch = makeFlow(
            connection: connection,
            events: [commitment],
            now: now,
            stateStore: stateStore
        )
        await firstLaunch.connectGoogleAccount()
        firstLaunch.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(firstLaunch.confirmProtection())
        await settleScheduledRefreshes()

        let legacyActivity = ProtectionActivity(
            occurredAt: now,
            actor: .user,
            kind: .dismissed,
            title: "Reminders stopped",
            detail: "Dismissed for this occurrence.",
            commitmentTitle: commitment.title,
            commitmentID: commitment.id,
            commitmentStartDate: nil,
            accountID: account.id,
            accountEmail: account.email
        )
        stateStore.set(
            try JSONEncoder().encode([legacyActivity]),
            forKey: "commitment-protection.activity-log"
        )

        let relaunch = makeFlow(
            connection: connection,
            events: [commitment],
            now: now,
            stateStore: stateStore
        )
        await relaunch.restoreSavedConnection()

        XCTAssertFalse(relaunch.activityLog.contains { $0.id == legacyActivity.id })
        XCTAssertFalse(
            relaunch.activities(forCalendarID: calendar.id, accountID: account.id)
                .contains { $0.id == legacyActivity.id }
        )
    }

    func testProtectionActivitySeparatesSameCalendarIDAcrossAccounts() async {
        let firstAccount = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let secondAccount = GoogleAccount(id: "account-2", email: "sam@example.com", displayName: "Sam")
        let firstCalendar = CalendarOption(id: "shared-calendar", name: "Work", accountID: firstAccount.id)
        let secondCalendar = CalendarOption(id: "shared-calendar", name: "Work", accountID: secondAccount.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstCommitment = CalendarEvent(
            id: "first-event",
            title: "Alex review",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: firstCalendar.id,
            accountID: firstAccount.id
        )
        let secondCommitment = CalendarEvent(
            id: "second-event",
            title: "Sam review",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(65 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: secondCalendar.id,
            accountID: secondAccount.id
        )
        let connector = MultiAccountTestGoogleCalendarConnector(
            connections: [
                GoogleCalendarConnection(account: firstAccount, calendars: [firstCalendar]),
                GoogleCalendarConnection(account: secondAccount, calendars: [secondCalendar])
            ],
            events: [firstCommitment, secondCommitment]
        )
        let suiteName = "CommitmentProtectionFlowTests.activityCalendarAccounts.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )

        await flow.connectGoogleAccount()
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: firstCalendar.id, accountID: firstAccount.id)
        flow.setCalendarSelected(true, calendarID: secondCalendar.id, accountID: secondAccount.id)
        XCTAssertTrue(flow.confirmAllProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        let firstActivities = flow.activities(forCalendarID: firstCalendar.id, accountID: firstAccount.id)
        let secondActivities = flow.activities(forCalendarID: secondCalendar.id, accountID: secondAccount.id)

        XCTAssertTrue(firstActivities.contains { $0.commitmentID == firstCommitment.id })
        XCTAssertFalse(firstActivities.contains { $0.commitmentID == secondCommitment.id })
        XCTAssertTrue(secondActivities.contains { $0.commitmentID == secondCommitment.id })
        XCTAssertFalse(secondActivities.contains { $0.commitmentID == firstCommitment.id })
    }

    func testActivityLogShowsPauseExpiryAsSystemAction() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
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
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertTrue(flow.pause(for: .oneHour, at: now))
        XCTAssertTrue(flow.activityLog.contains { $0.actor == .user && $0.kind == .pauseStarted })

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(70 * 60))

        XCTAssertTrue(flow.activityLog.contains { $0.actor == .system && $0.kind == .pauseEnded })
    }

    func testActivityLogPersistsAcrossSameDayRelaunch() async {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let now = calendar.date(byAdding: .hour, value: 10, to: day)!
        let (account, monitoredCalendar) = makeTestAccountAndCalendar()
        let suiteName = "CommitmentProtectionFlowTests.activityLog.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstLaunch = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [monitoredCalendar]),
            now: now,
            stateStore: stateStore
        )
        await activateProtection(for: firstLaunch, calendarID: monitoredCalendar.id)
        XCTAssertTrue(firstLaunch.pause(for: .oneHour, at: now))

        let relaunch = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [monitoredCalendar]),
            now: now,
            stateStore: stateStore
        )
        await relaunch.restoreSavedConnection()
        XCTAssertTrue(relaunch.activityLog.contains { $0.kind == .pauseStarted })
    }

    func testActivityLogRetainsAccountContextWhenConnectedAccountChanges() async {
        let firstAccount = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let firstCalendar = CalendarOption(id: "calendar-1", name: "Work", accountID: firstAccount.id)
        let secondAccount = GoogleAccount(id: "account-2", email: "sam@example.com", displayName: "Sam")
        let secondCalendar = CalendarOption(id: "calendar-2", name: "Personal", accountID: secondAccount.id)
        let connection = GoogleCalendarConnection(account: firstAccount, calendars: [firstCalendar])
        let connector = MutableTestGoogleCalendarConnector(connection: connection, events: [])
        let flow = makeMutableFlow(
            connector: connector,
            now: Date(timeIntervalSince1970: 1_000_000)
        )

        await activateProtection(for: flow, calendarID: firstCalendar.id)
        connector.connection = GoogleCalendarConnection(
            account: secondAccount,
            calendars: [secondCalendar]
        )
        await flow.connectGoogleAccount()

        let connectedAccountEmails = Set(
            flow.activityLog
                .filter { $0.kind == .accountConnected }
                .compactMap(\.accountEmail)
        )
        XCTAssertEqual(connectedAccountEmails, [firstAccount.email, secondAccount.email])
    }

    func testPlaintextLegacyActivityIsIntentionallyPurged() async throws {
        struct LegacyProtectionActivity: Encodable {
            let id: UUID
            let occurredAt: Date
            let actor: ProtectionActivityActor
            let kind: ProtectionActivityKind
            let title: String
            let detail: String
            let commitmentTitle: String?
            let commitmentID: String?
            let commitmentStartDate: Date?
            let accountID: String?
            let accountEmail: String?
        }

        let now = Date(timeIntervalSince1970: 1_000_000)
        let suiteName = "CommitmentProtectionFlowTests.legacyActivityLog.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let legacyActivity = LegacyProtectionActivity(
            id: UUID(),
            occurredAt: now.addingTimeInterval(-60),
            actor: .system,
            kind: .missedCommitment,
            title: "Missed Commitment",
            detail: "Legacy activity entry.",
            commitmentTitle: nil,
            commitmentID: nil,
            commitmentStartDate: nil,
            accountID: nil,
            accountEmail: nil
        )
        let currentActivity = LegacyProtectionActivity(
            id: UUID(),
            occurredAt: now,
            actor: .user,
            kind: .pauseStarted,
            title: "Protection paused",
            detail: "Protection paused for one hour.",
            commitmentTitle: nil,
            commitmentID: nil,
            commitmentStartDate: nil,
            accountID: nil,
            accountEmail: nil
        )
        stateStore.set(
            try JSONEncoder().encode([legacyActivity, currentActivity]),
            forKey: "commitment-protection.activity-log"
        )

        let flow = makeFlow(now: now, stateStore: stateStore)

        XCTAssertTrue(flow.activityLog.isEmpty)
        XCTAssertNil(stateStore.data(forKey: "commitment-protection.activity-log"))
    }

    func testActivityLogExpiresAtLocalDayBoundary() async {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let now = calendar.date(byAdding: .hour, value: 10, to: day)!
        let nextLocalDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let (account, monitoredCalendar) = makeTestAccountAndCalendar()
        let suiteName = "CommitmentProtectionFlowTests.activityLogExpiry.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstLaunch = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [monitoredCalendar]),
            now: now,
            stateStore: stateStore
        )
        await activateProtection(for: firstLaunch, calendarID: monitoredCalendar.id)
        XCTAssertTrue(firstLaunch.pause(for: .oneHour, at: now))

        let followingDayLaunch = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [monitoredCalendar]),
            now: nextLocalDay,
            stateStore: stateStore
        )
        await followingDayLaunch.restoreSavedConnection()
        XCTAssertEqual(followingDayLaunch.activityLog.map(\.kind), [.pauseEnded])
    }

    func testPauseSupportsEndOfDayAndCustomExpirationChoices() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)

        let expectedEndOfDay = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: now)
        )!
        XCTAssertTrue(flow.pause(for: .endOfDay, at: now))
        XCTAssertEqual(flow.pauseUntil, expectedEndOfDay)

        let customExpiration = now.addingTimeInterval(90 * 60)
        XCTAssertTrue(flow.pause(for: .custom(customExpiration), at: now))
        XCTAssertEqual(flow.pauseUntil, customExpiration)
        XCTAssertFalse(flow.pause(for: .custom(now), at: now))
    }

    func testPauseExpiryResumesStrongAlertForAnOngoingCommitment() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(-5 * 60),
            endDate: now.addingTimeInterval(2 * 60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertTrue(flow.isStrongAlertPresented)

        XCTAssertTrue(flow.pause(for: .oneHour, at: now))
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(60 * 60))

        XCTAssertFalse(flow.isPaused(at: now.addingTimeInterval(60 * 60)))
        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertEqual(flow.strongAlertCommitment, commitment)
    }

    func testCommitmentEndingWithoutAnExplicitDecisionStopsProtection() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(-5 * 60),
            endDate: now.addingTimeInterval(5 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertTrue(flow.isStrongAlertPresented)

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(5 * 60 + 1))

        XCTAssertFalse(flow.isStrongAlertPresented)
        XCTAssertNil(flow.strongAlertCommitment)
    }

    func testUnseenEndedCommitmentDoesNotCreateNewProtection() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(-20 * 60),
            endDate: now.addingTimeInterval(-5 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)

        XCTAssertFalse(flow.isStrongAlertPresented)
        XCTAssertNil(flow.strongAlertCommitment)
    }

    func testRescheduledCommitmentUsesTheCurrentCalendarSnapshot() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let originalCommitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(-20 * 60),
            endDate: now.addingTimeInterval(5 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let rescheduledCommitment = CalendarEvent(
            id: originalCommitment.id,
            title: originalCommitment.title,
            startDate: now.addingTimeInterval(30 * 60),
            endDate: now.addingTimeInterval(90 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [originalCommitment]
        )
        let flow = makeMutableFlow(connector: connector, now: now)

        await activateProtection(for: flow, calendarID: calendar.id)
        connector.events = [rescheduledCommitment]
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(10 * 60))

        XCTAssertEqual(flow.upcomingCommitment, rescheduledCommitment)
    }

    func testRecoveryAfterUnavailablePeriodShowsOverdueStrongAlertForAnOngoingCommitment() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: start.addingTimeInterval(-10 * 60),
            endDate: start.addingTimeInterval(50 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: start
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.recoverProtection(at: start)

        XCTAssertTrue(flow.isStrongAlertPresented)
        XCTAssertEqual(flow.strongAlertCommitment, commitment)
        XCTAssertEqual(
            flow.strongAlertTimingText(for: commitment, at: start),
            "Overdue · started 10 minutes ago"
        )
    }

    func testRelaunchRecoversAnOngoingCommitmentAsAnOverdueStrongAlert() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let start = Date(timeIntervalSince1970: 1_000_000)
        var currentDate = start
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: start.addingTimeInterval(10 * 60),
            endDate: start.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])
        let connector = MutableTestGoogleCalendarConnector(connection: connection, events: [commitment])
        let suiteName = "CommitmentProtectionFlowTests.recoveryRelaunch.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { currentDate }
        )
        await activateProtection(for: firstLaunch, calendarID: calendar.id)
        await firstLaunch.recoverProtection(at: start)

        currentDate = start.addingTimeInterval(15 * 60)
        let relaunch = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { currentDate }
        )
        await relaunch.restoreSavedConnection()

        XCTAssertTrue(relaunch.isStrongAlertPresented)
        XCTAssertEqual(relaunch.strongAlertCommitment, commitment)
        XCTAssertEqual(
            relaunch.strongAlertTimingText(for: commitment, at: currentDate),
            "Overdue · started 5 minutes ago"
        )
    }

    func testRelaunchDoesNotShowOverdueForCommitmentFirstSeenAfterAppWasClosed() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let currentDate = start
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: start.addingTimeInterval(-10 * 60),
            endDate: start.addingTimeInterval(50 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])
        let connector = MutableTestGoogleCalendarConnector(connection: connection, events: [])
        let suiteName = "CommitmentProtectionFlowTests.relaunchUntrackedOverdue.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { currentDate }
        )
        await activateProtection(for: firstLaunch, calendarID: calendar.id)

        connector.events = [commitment]
        let relaunch = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { currentDate }
        )
        await relaunch.restoreSavedConnection()

        XCTAssertFalse(relaunch.isStrongAlertPresented)
        XCTAssertNil(relaunch.strongAlertCommitment)
    }

    func testNewlySelectedCalendarDoesNotShowPastAcceptedCommitmentAsOverdue() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let firstCalendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let newCalendar = CalendarOption(id: "calendar-2", name: "Personal", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Personal appointment",
            startDate: now.addingTimeInterval(-10 * 60),
            endDate: now.addingTimeInterval(50 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: newCalendar.id,
            accountID: account.id
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(
                account: account,
                calendars: [firstCalendar, newCalendar]
            ),
            events: []
        )
        let flow = makeMutableFlow(connector: connector, now: now)

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: firstCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        connector.events = [commitment]
        flow.setCalendarSelected(true, calendarID: newCalendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertFalse(flow.isStrongAlertPresented)
        XCTAssertNil(flow.strongAlertCommitment)
    }

    func testReconnectingConnectedAccountDoesNotShowPastCommitmentAsOverdue() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(-10 * 60),
            endDate: now.addingTimeInterval(50 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: []
        )
        let flow = makeMutableFlow(connector: connector, now: now)

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: now)

        connector.events = [commitment]
        await flow.connectGoogleAccount()

        XCTAssertFalse(flow.isStrongAlertPresented)
        XCTAssertNil(flow.strongAlertCommitment)
    }

    func testRelaunchRespectsPersistedPauseUntilAnOngoingCommitmentResumes() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let start = Date(timeIntervalSince1970: 1_000_000)
        var currentDate = start
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: start.addingTimeInterval(-5 * 60),
            endDate: start.addingTimeInterval(3 * 60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])
        let connector = MutableTestGoogleCalendarConnector(connection: connection, events: [commitment])
        let suiteName = "CommitmentProtectionFlowTests.recoveryPause.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let firstLaunch = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { currentDate }
        )
        await activateProtection(for: firstLaunch, calendarID: calendar.id)
        await firstLaunch.recoverProtection(at: start)
        XCTAssertTrue(firstLaunch.pause(for: .oneHour, at: start))

        currentDate = start.addingTimeInterval(30 * 60)
        let relaunch = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { currentDate }
        )
        await relaunch.restoreSavedConnection()
        XCTAssertTrue(relaunch.isPaused(at: currentDate))
        XCTAssertFalse(relaunch.isStrongAlertPresented)

        currentDate = start.addingTimeInterval(61 * 60)
        await relaunch.recoverProtection()

        XCTAssertFalse(relaunch.isPaused(at: currentDate))
        XCTAssertTrue(relaunch.isStrongAlertPresented)
        XCTAssertEqual(relaunch.strongAlertCommitment, commitment)
    }

    func testRecoveryAfterUnavailablePeriodShowsNoAlertAfterCommitmentEnded() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: start.addingTimeInterval(-30 * 60),
            endDate: start.addingTimeInterval(-5 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: start
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.recoverProtection(at: start)

        XCTAssertFalse(flow.isStrongAlertPresented)
        XCTAssertNil(flow.strongAlertCommitment)
    }

    func testRecoveryUsesCurrentCalendarStateBeforeShowingProtection() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: start.addingTimeInterval(-10 * 60),
            endDate: start.addingTimeInterval(5 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment]
        )
        let flow = makeMutableFlow(connector: connector, now: start)

        await activateProtection(for: flow, calendarID: calendar.id)
        connector.events = []
        await flow.recoverProtection(at: start.addingTimeInterval(10 * 60))

        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testRecoveryDoesNotShowProtectionForAnUnacceptedEvent() async {
        let (account, calendar) = makeTestAccountAndCalendar()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let unacceptedEvent = CalendarEvent(
            id: "event-1",
            title: "Optional review",
            startDate: start.addingTimeInterval(-30 * 60),
            endDate: start.addingTimeInterval(-5 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: false,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [unacceptedEvent],
            now: start
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.recoverProtection(at: start)

        XCTAssertFalse(flow.isStrongAlertPresented)
    }

    func testPauseExpiryAfterCommitmentEndsDoesNotShowAnAlert() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(-5 * 60),
            endDate: now.addingTimeInterval(5 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertTrue(flow.pause(for: .oneHour, at: now))

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(60 * 60))

        XCTAssertFalse(flow.isStrongAlertPresented)
        XCTAssertFalse(flow.isPaused(at: now.addingTimeInterval(60 * 60)))
    }

    private func makeFlow(
        connection: GoogleCalendarConnection = GoogleCalendarConnection(
            account: GoogleAccount(id: "default-account", email: "user@example.com", displayName: "User"),
            calendars: []
        ),
        events: [CalendarEvent] = [],
        now: Date = Date(),
        stateStore: UserDefaults? = nil
    ) -> CommitmentProtectionFlow {
        CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(connection: connection, events: events),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore ?? UserDefaults(suiteName: "CommitmentProtectionFlowTests.\(UUID().uuidString)")!,
            now: { now }
        )
    }

    private func makeTestAccountAndCalendar() -> (GoogleAccount, CalendarOption) {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        return (account, calendar)
    }

    private func makeMutableFlow(
        connector: MutableTestGoogleCalendarConnector,
        now: Date
    ) -> CommitmentProtectionFlow {
        let suiteName = "CommitmentProtectionFlowTests.mutable.\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            stateStore.removePersistentDomain(forName: suiteName)
        }
        return CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
    }

    private func settleScheduledRefreshes() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    private func makeRefreshTerminationFixture(testName: String) -> RefreshTerminationFixture {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let state = RefreshRaceConnectorState(holdNextLoad: false)
        let connector = RefreshRaceTestConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment],
            state: state
        )
        let suiteName = "CommitmentProtectionFlowTests.\(testName).\(UUID().uuidString)"
        let stateStore = UserDefaults(suiteName: suiteName)!
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        return RefreshTerminationFixture(
            account: account,
            calendar: calendar,
            commitment: commitment,
            now: now,
            state: state,
            connector: connector,
            flow: flow,
            stateStore: stateStore,
            suiteName: suiteName
        )
    }

    private func assertProtectedAccountState(
        _ fixture: RefreshTerminationFixture,
        pauseUntil: Date,
        lastActionMessage: String,
        activityIDs: [UUID]
    ) {
        XCTAssertEqual(fixture.flow.connectedAccount, fixture.account)
        XCTAssertEqual(fixture.flow.connectionState, .connected)
        XCTAssertEqual(fixture.flow.coverage(for: fixture.account.id), .fresh)
        XCTAssertEqual(
            fixture.flow.selectedCalendarIDs(for: fixture.account.id),
            [fixture.calendar.id]
        )
        XCTAssertTrue(fixture.flow.isProtectionConfirmed(for: fixture.account.id))
        XCTAssertEqual(fixture.flow.upcomingCommitment, fixture.commitment)
        XCTAssertEqual(fixture.flow.currentCommitmentDecision, .dismissed)
        XCTAssertEqual(fixture.flow.decisionCommitment, fixture.commitment)
        XCTAssertTrue(fixture.flow.canRestoreProtection)
        XCTAssertEqual(fixture.flow.pauseUntil, pauseUntil)
        XCTAssertEqual(fixture.flow.lastActionMessage, lastActionMessage)
        XCTAssertEqual(fixture.flow.activityLog.map(\.id), activityIDs)
    }

    private func assertConnectionAttemptsAreBlocked(
        during operation: RefreshTerminationOperation,
        testName: String
    ) async {
        let fixture = makeRefreshTerminationFixture(testName: testName)
        defer { fixture.cleanUp() }

        await fixture.flow.connectGoogleAccount()
        fixture.flow.setCalendarSelected(true, calendarID: fixture.calendar.id)
        XCTAssertTrue(fixture.flow.confirmProtection())
        await settleScheduledRefreshes()
        await fixture.flow.refreshCommitmentProtection(at: fixture.now)

        let connectCallCount = await fixture.state.connectCallCount()
        let activityIDs = fixture.flow.activityLog.map(\.id)
        XCTAssertEqual(connectCallCount, 1)
        XCTAssertEqual(fixture.flow.upcomingCommitment, fixture.commitment)

        await fixture.state.armNextRevocation()
        let terminationTask = Task { @MainActor in
            switch operation {
            case .disconnect:
                return await fixture.flow.disconnectGoogleAccount(accountID: fixture.account.id)
            case .remove:
                return await fixture.flow.removeGoogleAccount(accountID: fixture.account.id)
            }
        }
        for _ in 0..<20 {
            if await fixture.state.hasRevocationStarted() { break }
            await Task.yield()
        }
        let revocationStarted = await fixture.state.hasRevocationStarted()
        XCTAssertTrue(revocationStarted)

        await fixture.flow.connectGoogleAccount()
        await fixture.flow.reconnectGoogleAccount(accountID: fixture.account.id)

        let connectCallCountDuringRevocation = await fixture.state.connectCallCount()
        XCTAssertEqual(connectCallCountDuringRevocation, connectCallCount)
        XCTAssertFalse(fixture.flow.isConnectingAccount)
        XCTAssertNil(fixture.flow.connectingAccountID)
        XCTAssertNil(fixture.flow.accountConnectionError)
        XCTAssertEqual(fixture.flow.connectedAccount, fixture.account)
        XCTAssertEqual(fixture.flow.connectionState, .connected)
        XCTAssertEqual(
            fixture.flow.selectedCalendarIDs(for: fixture.account.id),
            [fixture.calendar.id]
        )
        XCTAssertTrue(fixture.flow.isProtectionConfirmed(for: fixture.account.id))
        XCTAssertEqual(fixture.flow.upcomingCommitment, fixture.commitment)
        XCTAssertEqual(fixture.flow.activityLog.map(\.id), activityIDs)

        await fixture.state.releaseRevocation()
        let didTerminate = await terminationTask.value
        XCTAssertTrue(didTerminate)

        switch operation {
        case .disconnect:
            XCTAssertEqual(fixture.flow.coverage(for: fixture.account.id), .reconnectRequired)
        case .remove:
            XCTAssertNil(fixture.flow.coverage(for: fixture.account.id))
            XCTAssertTrue(fixture.flow.accountCoverages.isEmpty)
        }
    }

    private func activateProtection(
        for flow: CommitmentProtectionFlow,
        calendarID: String
    ) async {
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendarID)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
    }
}

private struct TestGoogleCalendarConnector: GoogleCalendarConnecting {
    let connection: GoogleCalendarConnection
    let events: [CalendarEvent]
    let state: TestGoogleCalendarConnectorState

    init(
        connection: GoogleCalendarConnection? = nil,
        events: [CalendarEvent] = [],
        state: TestGoogleCalendarConnectorState = TestGoogleCalendarConnectorState()
    ) {
        self.connection = connection ?? GoogleCalendarConnection(
            account: GoogleAccount(id: "default-account", email: "user@example.com", displayName: "User"),
            calendars: []
        )
        self.events = events
        self.state = state
    }

    func connect() async throws -> GoogleCalendarConnection {
        state.connectCallCount += 1
        if let error = state.connectError {
            throw error
        }
        return connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        connection.account.id == accountID ? connection : nil
    }

    func disconnect(accountID: String) throws {
        state.disconnectWasCalled = true
        if let error = state.disconnectError {
            throw error
        }
    }

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        if let error = state.loadEventsError {
            throw error
        }

        return events.filter {
            $0.accountID == accountID &&
            $0.calendarID == calendarID &&
            ($0.startDate ?? .distantPast) < endDate &&
            ($0.endDate ?? .distantFuture) > startDate
        }
    }
}

private final class TestGoogleCalendarConnectorState: @unchecked Sendable {
    var connectCallCount = 0
    var connectError: Error?
    var disconnectWasCalled = false
    var disconnectError: Error?
    var loadEventsError: Error?
}

private struct MissingLocalCredentialRevocationConnector:
    GoogleCalendarConnecting,
    GoogleAuthorizationRevoking
{
    let connection: GoogleCalendarConnection
    let events: [CalendarEvent]

    init(
        connection: GoogleCalendarConnection,
        events: [CalendarEvent] = []
    ) {
        self.connection = connection
        self.events = events
    }

    func connect() async throws -> GoogleCalendarConnection {
        connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        connection.account.id == accountID ? connection : nil
    }

    func disconnect(accountID: String) throws {}

    func revokeAuthorization(accountID: String) async throws -> GoogleAuthorizationRevocationResult {
        .localCredentialMissing
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

private actor RefreshRaceConnectorState {
    var holdNextLoad: Bool
    var firstLoadStarted = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var holdNextRestore = false
    private var restoreStarted = false
    private var releaseRestoreContinuation: CheckedContinuation<Void, Never>?
    private var holdNextRevocation = false
    private var revocationStarted = false
    private var releaseRevocationContinuation: CheckedContinuation<Void, Never>?
    private var nextRevocationError: GoogleCalendarConnectorError?
    private var storedConnectCallCount = 0
    private var storedLoadCallCount = 0

    init(holdNextLoad: Bool) {
        self.holdNextLoad = holdNextLoad
    }

    func armNextLoad() {
        holdNextLoad = true
        firstLoadStarted = false
    }

    func armNextRestore() {
        holdNextRestore = true
        restoreStarted = false
    }

    func armNextRevocation(error: GoogleCalendarConnectorError? = nil) {
        holdNextRevocation = true
        revocationStarted = false
        nextRevocationError = error
    }

    func waitForFirstLoadIfNeeded() async {
        storedLoadCallCount += 1
        guard holdNextLoad else { return }
        holdNextLoad = false
        firstLoadStarted = true
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func hasFirstLoadStarted() -> Bool {
        firstLoadStarted
    }

    func releaseFirstLoad() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func waitForRestoreIfNeeded() async {
        guard holdNextRestore else { return }
        holdNextRestore = false
        restoreStarted = true
        await withCheckedContinuation { continuation in
            releaseRestoreContinuation = continuation
        }
    }

    func hasRestoreStarted() -> Bool {
        restoreStarted
    }

    func releaseRestore() {
        releaseRestoreContinuation?.resume()
        releaseRestoreContinuation = nil
    }

    func recordConnect() {
        storedConnectCallCount += 1
    }

    func connectCallCount() -> Int {
        storedConnectCallCount
    }

    func loadCallCount() -> Int {
        storedLoadCallCount
    }

    func waitForRevocationIfNeeded() async throws {
        guard holdNextRevocation else { return }
        holdNextRevocation = false
        revocationStarted = true
        await withCheckedContinuation { continuation in
            releaseRevocationContinuation = continuation
        }
        if let nextRevocationError {
            self.nextRevocationError = nil
            throw nextRevocationError
        }
    }

    func hasRevocationStarted() -> Bool {
        revocationStarted
    }

    func releaseRevocation() {
        releaseRevocationContinuation?.resume()
        releaseRevocationContinuation = nil
    }
}

private final class RefreshRaceTestConnector:
    GoogleCalendarConnecting,
    GoogleAuthorizationRevoking,
    @unchecked Sendable
{
    let connection: GoogleCalendarConnection
    private let eventsLock = NSLock()
    private var events: [CalendarEvent]
    let state: RefreshRaceConnectorState

    init(
        connection: GoogleCalendarConnection,
        events: [CalendarEvent],
        state: RefreshRaceConnectorState
    ) {
        self.connection = connection
        self.events = events
        self.state = state
    }

    func replaceEvents(_ events: [CalendarEvent]) {
        eventsLock.lock()
        self.events = events
        eventsLock.unlock()
    }

    private func snapshotEvents() -> [CalendarEvent] {
        eventsLock.lock()
        defer { eventsLock.unlock() }
        return events
    }

    func connect() async throws -> GoogleCalendarConnection {
        await state.recordConnect()
        return connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        await state.waitForRestoreIfNeeded()
        return connection.account.id == accountID ? connection : nil
    }

    func disconnect(accountID: String) throws {}

    func revokeAuthorization(accountID: String) async throws -> GoogleAuthorizationRevocationResult {
        try await state.waitForRevocationIfNeeded()
        return .revoked
    }

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        let response = snapshotEvents()
        await state.waitForFirstLoadIfNeeded()
        return response.filter {
            $0.accountID == accountID &&
            $0.calendarID == calendarID &&
            ($0.startDate ?? .distantPast) < endDate &&
            ($0.endDate ?? .distantFuture) > startDate
        }
    }
}

@MainActor
private struct RefreshTerminationFixture {
    let account: GoogleAccount
    let calendar: CalendarOption
    let commitment: CalendarEvent
    let now: Date
    let state: RefreshRaceConnectorState
    let connector: RefreshRaceTestConnector
    let flow: CommitmentProtectionFlow
    let stateStore: UserDefaults
    let suiteName: String

    func cleanUp() {
        stateStore.removePersistentDomain(forName: suiteName)
    }
}

private enum RefreshTerminationOperation: Sendable {
    case disconnect
    case remove
}

private final class MutableTestGoogleCalendarConnector: GoogleCalendarConnecting, @unchecked Sendable {
    var connection: GoogleCalendarConnection
    var events: [CalendarEvent]
    var loadEventsError: Error?

    init(connection: GoogleCalendarConnection, events: [CalendarEvent], loadEventsError: Error? = nil) {
        self.connection = connection
        self.events = events
        self.loadEventsError = loadEventsError
    }

    func connect() async throws -> GoogleCalendarConnection {
        connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        connection.account.id == accountID ? connection : nil
    }

    func disconnect(accountID: String) throws {}

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        if let loadEventsError {
            throw loadEventsError
        }

        return events.filter {
            $0.accountID == accountID &&
            $0.calendarID == calendarID &&
            ($0.startDate ?? .distantPast) < endDate &&
            ($0.endDate ?? .distantFuture) > startDate
        }
    }
}

private final class MultiAccountTestGoogleCalendarConnector: GoogleCalendarConnecting, @unchecked Sendable {
    private let state: MultiAccountTestGoogleCalendarConnectorState
    private let events: [CalendarEvent]

    init(connections: [GoogleCalendarConnection], events: [CalendarEvent]) {
        state = MultiAccountTestGoogleCalendarConnectorState(connections: connections)
        self.events = events
    }

    func connect() async throws -> GoogleCalendarConnection {
        try await state.connect()
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        await state.restore(accountID: accountID)
    }

    func disconnect(accountID: String) throws {}

    func setFailingAccountIDs(_ accountIDs: Set<String>) async {
        await state.setFailingAccountIDs(accountIDs)
    }

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        let shouldFail = await state.shouldFail(accountID: accountID)

        if shouldFail {
            throw TestCalendarError.unavailable
        }

        return events.filter {
            $0.accountID == accountID &&
                $0.calendarID == calendarID &&
                ($0.startDate ?? .distantPast) < endDate &&
                ($0.endDate ?? .distantFuture) > startDate
        }
    }
}

private actor MultiAccountTestGoogleCalendarConnectorState {
    private var connections: [GoogleCalendarConnection]
    private let allConnections: [GoogleCalendarConnection]
    private var failingAccountIDs: Set<String> = []

    init(connections: [GoogleCalendarConnection]) {
        self.connections = connections
        allConnections = connections
    }

    func connect() throws -> GoogleCalendarConnection {
        guard !connections.isEmpty else { throw TestCalendarError.unavailable }
        return connections.removeFirst()
    }

    func restore(accountID: String) -> GoogleCalendarConnection? {
        allConnections.first { $0.account.id == accountID }
    }

    func setFailingAccountIDs(_ accountIDs: Set<String>) {
        failingAccountIDs = accountIDs
    }

    func shouldFail(accountID: String) -> Bool {
        failingAccountIDs.contains(accountID)
    }
}

private enum TestCalendarError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "The test calendar is unavailable."
    }
}

@MainActor
private final class TestLaunchAtLoginController: LaunchAtLoginControlling {
    private(set) var enableCallCount = 0
    private(set) var isEnabled: Bool

    private var shouldEnable: Bool

    var enableWasCalled: Bool {
        enableCallCount > 0
    }

    init(shouldEnable: Bool = true) {
        self.shouldEnable = shouldEnable
        isEnabled = shouldEnable
    }

    func enable() throws {
        enableCallCount += 1
        guard shouldEnable else {
            throw TestLaunchAtLoginError.registrationFailed
        }
        isEnabled = true
    }

    func allowEnabling() {
        shouldEnable = true
    }
}

private enum TestLaunchAtLoginError: Error {
    case registrationFailed
}

private enum TestCalendarLoadError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "The test calendar is unavailable."
    }
}
