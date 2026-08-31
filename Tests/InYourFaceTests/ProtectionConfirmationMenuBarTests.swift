import CommitmentProtection
import Foundation
import XCTest
@testable import InYourFace

final class ProtectionConfirmationMenuBarTests: XCTestCase {
    func testInitialPendingSelectionKeepsNoCoverageAndRoutesToCalendars() {
        let confirmation = ProtectionConfirmationPresentation.global(
            [
                makeCoverage(
                    selectedCalendarIDs: ["work", "team"],
                    confirmedCalendarIDs: []
                )
            ],
            locale: englishLocale
        )

        let presentation = makePresentation(
            status: .noCoverage,
            confirmation: confirmation
        )

        XCTAssertEqual(presentation.statusPresentation.state, .noCoverage)
        XCTAssertEqual(presentation.title, "No Coverage")
        XCTAssertEqual(presentation.primaryAction, .openSettings)
        XCTAssertEqual(
            presentation.detail,
            "Protection is pending for 2 selected calendars. " +
                "Open Calendars in Settings to confirm the selection and start reminders."
        )
    }

    func testPendingAdditionKeepsActiveProtectionAndExistingConfirmationVisible() {
        let confirmation = ProtectionConfirmationPresentation.global(
            [
                makeCoverage(
                    selectedCalendarIDs: ["work", "team", "project"],
                    confirmedCalendarIDs: ["work", "team"]
                )
            ],
            locale: englishLocale
        )

        let presentation = makePresentation(
            status: .active,
            confirmation: confirmation
        )

        XCTAssertEqual(presentation.statusPresentation.state, .activeProtection)
        XCTAssertEqual(presentation.title, "Active Protection")
        XCTAssertNil(presentation.primaryAction)
        XCTAssertEqual(
            presentation.detail,
            "Protection is pending for 1 new calendar. " +
                "Existing confirmation already includes 2 calendars. " +
                "Open Calendars in Settings to confirm the change."
        )
    }

    func testSettledActiveProtectionRetainsItsNormalDetail() {
        let confirmation = ProtectionConfirmationPresentation.global(
            [
                makeCoverage(
                    selectedCalendarIDs: ["work"],
                    confirmedCalendarIDs: ["work"]
                )
            ],
            locale: englishLocale
        )

        let presentation = makePresentation(
            status: .active,
            confirmation: confirmation
        )

        XCTAssertEqual(presentation.statusPresentation.state, .activeProtection)
        XCTAssertNil(presentation.primaryAction)
        XCTAssertEqual(
            presentation.detail,
            "No upcoming commitment needs your attention."
        )
    }

    func testPendingConfirmationDoesNotReplacePausedStaleOrReconnectPrecedence() {
        let pendingConfirmation = ProtectionConfirmationPresentation.global(
            [
                makeCoverage(
                    selectedCalendarIDs: ["work", "team"],
                    confirmedCalendarIDs: ["work"]
                )
            ],
            locale: englishLocale
        )
        let pauseDetail = "All protection paused · resumes in 1 hour (11:00 PM)"

        let paused = makePresentation(
            status: .active,
            isPaused: true,
            confirmation: pendingConfirmation
        )
        XCTAssertEqual(paused.statusPresentation.state, .protectionPaused)
        XCTAssertEqual(paused.detail, pauseDetail)
        XCTAssertNil(paused.primaryAction)

        let stale = makePresentation(
            status: .unavailable,
            accounts: [staleAccount],
            confirmation: pendingConfirmation
        )
        XCTAssertEqual(stale.statusPresentation.state, .coverageNeedsAttention)
        XCTAssertEqual(
            stale.detail,
            "Calendar data is out of date. " +
                "Known reminders stay unverified until refresh succeeds."
        )
        XCTAssertNil(stale.primaryAction)

        let reconnect = makePresentation(
            status: .unavailable,
            accounts: [reconnectAccount],
            confirmation: pendingConfirmation
        )
        XCTAssertEqual(reconnect.statusPresentation.state, .reconnectRequired)
        XCTAssertEqual(
            reconnect.detail,
            "Reconnect person@example.com to resume reminders. " +
                "Routine relaunches keep valid authorization."
        )
        XCTAssertEqual(
            reconnect.primaryAction,
            .reconnect(accountID: "account-1")
        )
    }

    private var englishLocale: Locale {
        Locale(identifier: "en_US")
    }

    private var staleAccount: MenuBarAccountPresentation {
        MenuBarAccountPresentation(
            id: "account-1",
            label: "person@example.com",
            connectionState: .connected,
            health: .stale
        )
    }

    private var reconnectAccount: MenuBarAccountPresentation {
        MenuBarAccountPresentation(
            id: "account-1",
            label: "person@example.com",
            connectionState: .reconnectRequired,
            health: .reconnectRequired
        )
    }

    private func makeCoverage(
        selectedCalendarIDs: Set<String>,
        confirmedCalendarIDs: Set<String>
    ) -> AccountCoverage {
        let account = GoogleAccount(
            id: "account-1",
            email: "person@example.com",
            displayName: "Person"
        )
        let calendars = selectedCalendarIDs.sorted().map {
            CalendarOption(id: $0, name: $0.capitalized, accountID: account.id)
        }
        return AccountCoverage(
            account: account,
            calendars: calendars,
            selectedCalendarIDs: selectedCalendarIDs,
            confirmedCalendarIDs: confirmedCalendarIDs,
            isProtectionConfirmed: !selectedCalendarIDs.isEmpty &&
                selectedCalendarIDs == confirmedCalendarIDs,
            connectionState: .connected,
            health: .fresh,
            lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makePresentation(
        status: ProtectionStatus,
        isPaused: Bool = false,
        accounts: [MenuBarAccountPresentation] = [],
        confirmation: ProtectionConfirmationPresentation
    ) -> MenuBarProtectionPresentation {
        MenuBarProtectionPresentation.make(
            isRestoringConnection: false,
            needsSetup: false,
            status: status,
            isCheckingCoverage: false,
            isPaused: isPaused,
            pauseDetail: "All protection paused · resumes in 1 hour (11:00 PM)",
            isLaunchAtLoginEnabled: true,
            hasUpcomingCommitment: false,
            accounts: accounts,
            confirmation: confirmation
        )
    }
}
