import CommitmentProtection
import Foundation
import XCTest
@testable import InYourFace

@MainActor
final class OnboardingReminderPreferencesTests: XCTestCase {
    func testCommitAppliesTheDraftAndReconfirmsSelectedCalendars() async {
        let suiteName = "OnboardingReminderPreferencesTests.\(UUID().uuidString)"
        guard let stateStore = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        stateStore.removePersistentDomain(forName: suiteName)
        defer { stateStore.removePersistentDomain(forName: suiteName) }

        let account = GoogleAccount(
            id: "account-1",
            email: "alex@example.com",
            displayName: "Alex"
        )
        let calendar = CalendarOption(
            id: "calendar-1",
            name: "Work",
            accountID: account.id
        )
        let flow = CommitmentProtectionFlow(
            calendarConnector: OnboardingCalendarConnector(
                connection: GoogleCalendarConnection(
                    account: account,
                    calendars: [calendar]
                )
            ),
            launchAtLogin: OnboardingLaunchAtLoginController(),
            stateStore: stateStore
        )

        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmAllProtection())

        var draft = OnboardingReminderPreferences(flow: flow)
        draft.isEarlyReminderEnabled = false
        draft.earlyReminderLeadTimeMinutes = 20

        XCTAssertTrue(flow.isEarlyReminderEnabled)
        XCTAssertEqual(flow.earlyReminderLeadTimeMinutes, 10)
        XCTAssertTrue(draft.commit(to: flow))

        XCTAssertFalse(flow.isEarlyReminderEnabled)
        XCTAssertEqual(flow.earlyReminderLeadTimeMinutes, 20)
        XCTAssertFalse(flow.isProtectionConfirmationRequired)
        XCTAssertTrue(flow.isProtectionConfirmed(for: account.id))
    }
}

private struct OnboardingCalendarConnector: GoogleCalendarConnecting {
    let connection: GoogleCalendarConnection

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
        []
    }
}

@MainActor
private final class OnboardingLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled = false

    func enable() throws {
        isEnabled = true
    }
}
