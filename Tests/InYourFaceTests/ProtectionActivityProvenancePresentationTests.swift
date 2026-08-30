import CommitmentProtection
import Foundation
import XCTest
@testable import InYourFace

final class ProtectionActivityProvenancePresentationTests: XCTestCase {
    func testScopesUseCompactRolesPairIdentityAndSearchEitherLabel() {
        let scopes = ProtectionActivityProvenancePresentation.scopes(
            sources: [
                source(
                    accountID: "sam-account",
                    email: "sam@example.com",
                    calendarID: "work",
                    calendarName: "Work"
                ),
                source(
                    accountID: "alex-account",
                    email: "alex@example.com",
                    calendarID: "personal",
                    calendarName: "Personal"
                ),
            ],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            scopes.map(\.id),
            [
                .init(accountID: "alex-account", calendarID: "personal"),
                .init(accountID: "sam-account", calendarID: "work"),
            ]
        )
        XCTAssertEqual(
            scopes.map(\.label),
            [
                "Calendar: Personal · Account: alex@example.com",
                "Calendar: Work · Account: sam@example.com",
            ]
        )
        XCTAssertEqual(
            ProtectionActivityProvenancePresentation.matchingScopes(
                scopes,
                query: " work "
            ).map(\.id),
            [.init(accountID: "sam-account", calendarID: "work")]
        )
        XCTAssertEqual(
            ProtectionActivityProvenancePresentation.matchingScopes(
                scopes,
                query: "ALEX@EXAMPLE"
            ).map(\.id),
            [.init(accountID: "alex-account", calendarID: "personal")]
        )
        XCTAssertTrue(
            ProtectionActivityProvenancePresentation.matchingScopes(
                scopes,
                query: "missing"
            ).isEmpty
        )
    }

    func testScopeOrderingUsesStablePairIDsWhenEveryVisibleLabelCollides() {
        let scopes = ProtectionActivityProvenancePresentation.scopes(
            sources: [
                source(
                    accountID: "z-account",
                    email: "same@example.com",
                    calendarID: "z-calendar",
                    calendarName: "Work"
                ),
                source(
                    accountID: "a-account",
                    email: "same@example.com",
                    calendarID: "a-calendar",
                    calendarName: "Work"
                ),
            ],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            scopes.map(\.id),
            [
                .init(accountID: "a-account", calendarID: "a-calendar"),
                .init(accountID: "z-account", calendarID: "z-calendar"),
            ]
        )
        XCTAssertEqual(
            scopes.map(\.label),
            [
                "Calendar: Work · Account: same@example.com (1 of 2)",
                "Calendar: Work · Account: same@example.com (2 of 2)",
            ]
        )
    }

    func testRowUsesStandardGroupsAndFullAccessibleSourceDescription() {
        let row = ProtectionActivityProvenancePresentation.row(
            sources: [
                source(
                    accountID: "alex-account",
                    email: "alex@example.com",
                    calendarID: "work",
                    calendarName: "Work"
                ),
                source(
                    accountID: "alex-account",
                    email: "alex@example.com",
                    calendarID: "personal",
                    calendarName: "Personal"
                ),
                source(
                    accountID: "sam-account",
                    email: "sam@example.com",
                    calendarID: "team",
                    calendarName: "Team"
                ),
            ],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            row.standardGroups.map(\.accountText),
            [
                "Google Account: alex@example.com",
                "Google Account: sam@example.com",
            ]
        )
        XCTAssertEqual(
            row.standardGroups.map(\.calendarsText),
            [
                "Monitored Calendars: Work and Personal",
                "Monitored Calendar: Team",
            ]
        )
        XCTAssertEqual(
            row.accessibilityDescription,
            "Monitored Calendar Work, Google Account alex@example.com, " +
                "Monitored Calendar Personal, Google Account alex@example.com, and " +
                "Monitored Calendar Team, Google Account sam@example.com"
        )
        XCTAssertEqual(row.help, row.accessibilityDescription)
    }

    private func source(
        accountID: String,
        email: String,
        calendarID: String,
        calendarName: String
    ) -> ProtectionProvenanceSource {
        ProtectionProvenanceSource(
            accountID: accountID,
            accountEmail: email,
            accountDisplayName: "",
            calendarID: calendarID,
            calendarName: calendarName
        )
    }
}
