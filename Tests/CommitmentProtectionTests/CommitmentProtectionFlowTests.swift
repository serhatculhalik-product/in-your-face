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

    func testStrongAlertUsesHandledWhenNoRecognizedMeetingLink() async {
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

        XCTAssertEqual(flow.strongAlertPrimaryActionTitle, "Handled")
        flow.handleStrongAlert()
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
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: TestLaunchAtLoginController(),
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

    private func makeFlow(
        connection: GoogleCalendarConnection = GoogleCalendarConnection(
            account: GoogleAccount(id: "default-account", email: "user@example.com", displayName: "User"),
            calendars: []
        ),
        events: [CalendarEvent] = [],
        now: Date = Date()
    ) -> CommitmentProtectionFlow {
        CommitmentProtectionFlow(
            calendarConnector: TestGoogleCalendarConnector(connection: connection, events: events),
            launchAtLogin: TestLaunchAtLoginController(),
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
    let connection: GoogleCalendarConnection
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
