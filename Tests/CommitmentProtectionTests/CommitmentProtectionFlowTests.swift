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
        XCTAssertEqual(flow.status, .active)
        XCTAssertEqual(flow.menuBarTitle, "Active Protection")
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

        XCTAssertEqual(flow.status, .active)
        XCTAssertEqual(flow.menuBarTitle, "Active Protection · Login Needs Attention")
    }

    func testLoggingOutClearsConnectionAndProtectionConfiguration() async {
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
        XCTAssertEqual(flow.status, .active)

        flow.disconnectGoogleAccount()

        XCTAssertTrue(flow.activityLog.contains { $0.kind == .accountDisconnected && $0.actor == .user })
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
        XCTAssertTrue(relaunchedFlow.activityLog.contains { $0.kind == .accountDisconnected })
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
        XCTAssertEqual(flow.joinStrongAlert(), meetingURL)
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
            "Overdue · started 2 min ago"
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
            "Google sign-in could not be completed (invalid_grant: Bad Request)."
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

    func testRefreshTokenStorePersistsInUserDefaults() {
        let accountID = "test-account-\(UUID().uuidString)"
        let defaultsKey = "google.refreshToken.\(accountID)"
        let refreshToken = "refresh-token-\(UUID().uuidString)"
        defer {
            GoogleRefreshTokenStore.remove(accountID: accountID)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }

        GoogleRefreshTokenStore.save(refreshToken: refreshToken, accountID: accountID)

        XCTAssertEqual(UserDefaults.standard.string(forKey: defaultsKey), refreshToken)
        XCTAssertEqual(GoogleRefreshTokenStore.load(accountID: accountID), refreshToken)
    }

    func testRefreshTokenStoreLoadsExistingUserDefaultsToken() {
        let accountID = "legacy-account-\(UUID().uuidString)"
        let defaultsKey = "google.refreshToken.\(accountID)"
        let refreshToken = "legacy-refresh-token-\(UUID().uuidString)"
        defer {
            GoogleRefreshTokenStore.remove(accountID: accountID)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
        UserDefaults.standard.set(refreshToken, forKey: defaultsKey)

        XCTAssertEqual(GoogleRefreshTokenStore.load(accountID: accountID), refreshToken)
        XCTAssertEqual(UserDefaults.standard.string(forKey: defaultsKey), refreshToken)
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
        XCTAssertEqual(flow.status, .active)
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
        XCTAssertEqual(flow.status, .active)
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

    func testCalendarRequestFailureExplainsGoogleOAuthReason() {
        let error = GoogleCalendarConnectorError.calendarRequestFailed(
            403,
            "insufficientPermissions: Insufficient Permission"
        )

        XCTAssertEqual(
            error.errorDescription,
            "The Google calendars could not be loaded (insufficientPermissions: Insufficient Permission)."
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

    func testClearingEarlyReminderLeavesCommitmentProtected() async {
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
        XCTAssertEqual(flow.lastActionMessage, "All reminders snoozed for 5 minutes. Protection remains active.")
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
        XCTAssertEqual(flow.lastActionMessage, "Dismissed for this occurrence. Protection is off until it ends.")
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
            "Overdue · started 10 min ago"
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
        XCTAssertEqual(flow.joinStrongAlert(), newLink)
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

    func testCalendarRefreshFailureClearsStaleProtection() async {
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

        XCTAssertNil(flow.upcomingCommitment)
        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertEqual(flow.status, .unavailable)
        XCTAssertEqual(flow.connectionState, .failed("The test calendar is unavailable."))

        state.loadEventsError = nil
        await flow.refreshCommitmentProtection(at: now)

        XCTAssertEqual(flow.upcomingCommitment, commitment)
        XCTAssertNil(flow.earlyReminderCommitment)
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

        flow.setEarlyReminderEnabled(false)
        flow.setBlockingModeEnabled(true)

        let relaunchedFlow = CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(),
            launchAtLogin: TestLaunchAtLoginController(),
            stateStore: stateStore
        )
        XCTAssertFalse(relaunchedFlow.isEarlyReminderEnabled)
        XCTAssertTrue(relaunchedFlow.isBlockingModeEnabled)
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

        XCTAssertEqual(flow.countdownText(for: commitment, at: now), "Starts in 10 min")
        XCTAssertTrue(flow.localStartTimeText(for: commitment).contains(expectedZoneLabel))
    }

    func testGoogleEventResponseMapsAcceptanceAndAllDayState() throws {
        let data = Data(#"""
        {
            "items": [
                {
                    "id": "accepted-event",
                    "summary": "Accepted review",
                    "hangoutLink": "https://meet.google.com/abc-defg-hij",
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
        XCTAssertTrue(events[1].isAllDay)
        XCTAssertTrue(events[1].isAccepted)
        XCTAssertFalse(events[2].isAccepted)
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
        XCTAssertTrue(flow.activityLog.contains {
            $0.actor == .system &&
                $0.kind == .earlyReminderShown &&
                $0.commitmentTitle == commitment.title &&
                $0.commitmentID == commitment.id &&
                $0.commitmentStartDate == commitment.startDate &&
                $0.accountEmail == account.email
        })

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

    func testActivityLogShowsPauseExpiryAndMissedCommitmentAsSystemActions() async {
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
        XCTAssertTrue(flow.pause(for: .oneHour, at: now))
        XCTAssertTrue(flow.activityLog.contains { $0.actor == .user && $0.kind == .pauseStarted })

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(70 * 60))

        XCTAssertTrue(flow.activityLog.contains { $0.actor == .system && $0.kind == .pauseEnded })
        XCTAssertTrue(flow.activityLog.contains {
            $0.actor == .system && $0.kind == .missedCommitment && $0.commitmentTitle == commitment.title
        })
    }

    func testActivityLogPersistsAcrossSameDayRelaunch() async {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let now = calendar.date(byAdding: .hour, value: 10, to: day)!
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let monitoredCalendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
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

    func testActivityLogExpiresAtLocalDayBoundary() async {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let now = calendar.date(byAdding: .hour, value: 10, to: day)!
        let nextLocalDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let monitoredCalendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
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

    func testCommitmentEndingWithoutAnExplicitDecisionBecomesMissed() async {
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
        XCTAssertEqual(flow.missedCommitment, commitment)
    }

    func testUnseenEndedCommitmentBecomesMissedAfterProtectionStarts() async {
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

        XCTAssertEqual(flow.missedCommitment, commitment)
    }

    func testRescheduledCommitmentDoesNotBecomeMissedFromAnOldSnapshot() async {
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

        XCTAssertNil(flow.missedCommitment)
        XCTAssertEqual(flow.upcomingCommitment, rescheduledCommitment)
    }

    func testRecoveryAfterUnavailablePeriodShowsOverdueStrongAlertForAnOngoingCommitment() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
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
            "Overdue · started 10 min ago"
        )
    }

    func testMultipleCommitmentsEndingTogetherRemainIndividuallyAcknowledgeable() async {
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstCommitment = CalendarEvent(
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
        let secondCommitment = CalendarEvent(
            id: "event-2",
            title: "Design review",
            startDate: now.addingTimeInterval(-30 * 60),
            endDate: now.addingTimeInterval(-10 * 60),
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

        XCTAssertEqual(
            Set(flow.missedCommitments.map(\.id)),
            Set([firstCommitment.id, secondCommitment.id])
        )
        XCTAssertTrue(flow.acknowledgeMissedCommitment(for: firstCommitment))
        XCTAssertEqual(flow.missedCommitments, [secondCommitment])
    }

    func testPauseExpiryAfterCommitmentEndsShowsPassiveMissedStatus() async {
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
        XCTAssertEqual(flow.missedCommitment, commitment)
        XCTAssertFalse(flow.isPaused(at: now.addingTimeInterval(60 * 60)))
    }

    func testMissedCommitmentRemainsUntilAcknowledgeAndAcknowledgeDoesNotChangeCalendar() async {
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
        let connector = MutableTestGoogleCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment]
        )
        let flow = makeMutableFlow(connector: connector, now: now)

        await activateProtection(for: flow, calendarID: calendar.id)
        await flow.refreshCommitmentProtection(at: now)
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(5 * 60 + 1))
        XCTAssertEqual(flow.missedCommitment, commitment)

        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(10 * 60))
        XCTAssertEqual(flow.missedCommitment, commitment)
        XCTAssertTrue(flow.acknowledgeMissedCommitment())
        XCTAssertNil(flow.missedCommitment)
        XCTAssertTrue(flow.activityLog.contains {
            $0.actor == .user &&
                $0.kind == .missedCommitmentAcknowledged &&
                $0.commitmentTitle == commitment.title
        })
        XCTAssertTrue(connector.events.contains(commitment))
    }

    func testMissedCommitmentExpiresAtTheEndOfTheUsersLocalDay() async {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let now = calendar.date(byAdding: .minute, value: 23 * 60 + 50, to: day)!
        let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
        let monitoredCalendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: now.addingTimeInterval(-5 * 60),
            endDate: now.addingTimeInterval(5 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: monitoredCalendar.id,
            accountID: account.id
        )
        let flow = makeFlow(
            connection: GoogleCalendarConnection(account: account, calendars: [monitoredCalendar]),
            events: [commitment],
            now: now
        )

        await activateProtection(for: flow, calendarID: monitoredCalendar.id)
        await flow.refreshCommitmentProtection(at: now)
        await flow.refreshCommitmentProtection(at: now.addingTimeInterval(5 * 60 + 1))
        XCTAssertEqual(flow.missedCommitment, commitment)

        let nextLocalDay = calendar.date(byAdding: .day, value: 1, to: day)!
        await flow.refreshCommitmentProtection(at: nextLocalDay)

        XCTAssertNil(flow.missedCommitment)
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
        connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        connection.account.id == accountID ? connection : nil
    }

    func disconnect(accountID: String) throws {
        state.disconnectWasCalled = true
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
    var disconnectWasCalled = false
    var loadEventsError: Error?
}

private actor RefreshRaceConnectorState {
    var holdNextLoad: Bool
    var firstLoadStarted = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(holdNextLoad: Bool) {
        self.holdNextLoad = holdNextLoad
    }

    func waitForFirstLoadIfNeeded() async {
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
}

private final class RefreshRaceTestConnector: GoogleCalendarConnecting, @unchecked Sendable {
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

private final class MutableTestGoogleCalendarConnector: GoogleCalendarConnecting, @unchecked Sendable {
    var connection: GoogleCalendarConnection
    var events: [CalendarEvent]

    init(connection: GoogleCalendarConnection, events: [CalendarEvent]) {
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
private final class TestLaunchAtLoginController: LaunchAtLoginControlling {
    private(set) var enableWasCalled = false
    private(set) var isEnabled: Bool

    private let shouldEnable: Bool

    init(shouldEnable: Bool = true) {
        self.shouldEnable = shouldEnable
        isEnabled = shouldEnable
    }

    func enable() throws {
        enableWasCalled = true
        guard shouldEnable else {
            throw TestLaunchAtLoginError.registrationFailed
        }
        isEnabled = true
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
