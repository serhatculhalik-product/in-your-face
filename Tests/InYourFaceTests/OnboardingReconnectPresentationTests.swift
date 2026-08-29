import CommitmentProtection
import XCTest
@testable import InYourFace

final class OnboardingReconnectPresentationTests: XCTestCase {
    func testTwoSavedAccountsNeedingReconnectKeepSelectionsWithoutClaimingProtection() {
        let presentation = OnboardingReconnectPresentation.make(
            coverages: [
                makeCoverage(
                    id: "work",
                    email: "work@example.com",
                    selectedCalendarIDs: ["work-calendar"],
                    connectionState: .reconnectRequired,
                    health: .reconnectRequired
                ),
                makeCoverage(
                    id: "personal",
                    email: "personal@example.com",
                    selectedCalendarIDs: ["personal-calendar"],
                    connectionState: .reconnectRequired,
                    health: .reconnectRequired
                )
            ],
            preferredAccountID: "work",
            connectionError: "Google sign-in could not be completed."
        )

        XCTAssertEqual(presentation.connectedAccountCount, 0)
        XCTAssertEqual(presentation.savedAccountCount, 2)
        XCTAssertEqual(presentation.savedCalendarCount, 2)
        XCTAssertEqual(presentation.activelyProtectedCalendarCount, 0)
        XCTAssertEqual(presentation.currentTarget?.id, "work")
        XCTAssertEqual(presentation.currentTarget?.label, "work@example.com")
        XCTAssertEqual(presentation.connectionError, "Google sign-in could not be completed.")
    }

    func testFreshFirstAccountAdvancesReconnectTargetToTheRemainingAccount() {
        let presentation = OnboardingReconnectPresentation.make(
            coverages: [
                makeCoverage(
                    id: "work",
                    email: "work@example.com",
                    selectedCalendarIDs: ["work-calendar"],
                    connectionState: .connected,
                    health: .fresh
                ),
                makeCoverage(
                    id: "personal",
                    email: "personal@example.com",
                    selectedCalendarIDs: ["personal-calendar"],
                    connectionState: .reconnectRequired,
                    health: .reconnectRequired
                )
            ],
            preferredAccountID: "work",
            connectionError: nil
        )

        XCTAssertEqual(presentation.connectedAccountCount, 1)
        XCTAssertEqual(presentation.savedAccountCount, 2)
        XCTAssertEqual(presentation.activelyProtectedCalendarCount, 1)
        XCTAssertEqual(presentation.currentTarget?.id, "personal")
        XCTAssertEqual(presentation.currentTarget?.label, "personal@example.com")
    }

    func testAllFreshConnectedAccountsHaveNoReconnectTarget() {
        let presentation = OnboardingReconnectPresentation.make(
            coverages: [
                makeCoverage(
                    id: "work",
                    email: "work@example.com",
                    selectedCalendarIDs: ["work-calendar"],
                    connectionState: .connected,
                    health: .fresh
                ),
                makeCoverage(
                    id: "personal",
                    email: "personal@example.com",
                    selectedCalendarIDs: ["personal-calendar"],
                    connectionState: .connected,
                    health: .fresh
                )
            ],
            preferredAccountID: nil,
            connectionError: nil
        )

        XCTAssertEqual(presentation.connectedAccountCount, 2)
        XCTAssertEqual(presentation.savedAccountCount, 2)
        XCTAssertEqual(presentation.activelyProtectedCalendarCount, 2)
        XCTAssertNil(presentation.currentTarget)
        XCTAssertFalse(presentation.requiresReconnect)
    }

    private func makeCoverage(
        id: String,
        email: String,
        selectedCalendarIDs: Set<String>,
        connectionState: ConnectionState,
        health: CoverageHealth
    ) -> AccountCoverage {
        let account = GoogleAccount(id: id, email: email, displayName: "")
        let calendars = selectedCalendarIDs.map {
            CalendarOption(id: $0, name: $0, accountID: id)
        }
        return AccountCoverage(
            account: account,
            calendars: calendars,
            selectedCalendarIDs: selectedCalendarIDs,
            isProtectionConfirmed: true,
            connectionState: connectionState,
            health: health,
            lastSuccessfulRefreshAt: health == .fresh ? Date() : nil
        )
    }
}
