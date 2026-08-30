import CommitmentProtection
import XCTest
@testable import InYourFace

final class OnboardingAdditionalProtectionDestinationTests: XCTestCase {
    func testConnectedUnprotectedAccountRoutesToItsCalendarReview() {
        let destination = OnboardingAdditionalProtectionDestination.make(
            coverages: [
                makeCoverage(id: "first", selected: true, confirmed: true),
                makeCoverage(id: "second")
            ]
        )

        XCTAssertEqual(destination, .reviewCalendars(accountID: "second"))
    }

    func testConnectedAccountWithPendingSelectionRoutesToItsCalendarReview() {
        let destination = OnboardingAdditionalProtectionDestination.make(
            coverages: [
                makeCoverage(id: "first", selected: true, confirmed: true),
                makeCoverage(id: "second", selected: true, confirmed: false)
            ]
        )

        XCTAssertEqual(destination, .reviewCalendars(accountID: "second"))
    }

    func testAllConnectedAccountsConfirmedRoutesToAccountConnection() {
        let destination = OnboardingAdditionalProtectionDestination.make(
            coverages: [
                makeCoverage(id: "first", selected: true, confirmed: true),
                makeCoverage(id: "second", selected: true, confirmed: true)
            ]
        )

        XCTAssertEqual(destination, .connectAccount)
    }

    func testAccountsThatAreNotConnectedAreNeverChosenForCalendarReview() {
        let destination = OnboardingAdditionalProtectionDestination.make(
            coverages: [
                makeCoverage(id: "reconnect", connectionState: .reconnectRequired),
                makeCoverage(id: "disconnected", connectionState: .notConnected),
                makeCoverage(id: "protected", selected: true, confirmed: true)
            ]
        )

        XCTAssertEqual(destination, .connectAccount)
    }

    private func makeCoverage(
        id: String,
        selected: Bool = false,
        confirmed: Bool = false,
        connectionState: ConnectionState = .connected
    ) -> AccountCoverage {
        let calendarID = "\(id)-calendar"
        return AccountCoverage(
            account: GoogleAccount(id: id, email: "\(id)@example.com", displayName: ""),
            calendars: [CalendarOption(id: calendarID, name: "Calendar", accountID: id)],
            selectedCalendarIDs: selected ? [calendarID] : [],
            isProtectionConfirmed: confirmed,
            connectionState: connectionState,
            health: confirmed ? .fresh : .noCoverage,
            lastSuccessfulRefreshAt: nil
        )
    }
}
