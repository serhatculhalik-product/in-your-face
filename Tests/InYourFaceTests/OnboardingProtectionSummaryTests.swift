import CommitmentProtection
import XCTest
@testable import InYourFace

final class OnboardingProtectionSummaryTests: XCTestCase {
    func testDuplicateCalendarMetadataUsesTheLastValueWithoutCrashing() throws {
        let summary = OnboardingProtectionSummary.make(coverages: [
            makeCoverage(
                id: "work",
                calendars: [
                    ("calendar", "Old name"),
                    ("calendar", "Current name"),
                ],
                confirmedCalendarIDs: ["calendar"]
            )
        ])

        XCTAssertEqual(
            try XCTUnwrap(summary.accountGroups.first?.calendarsText),
            "Monitored Calendar: Current name"
        )
    }

    func testSameNamedCalendarsAcrossAccountsHaveVisibleAndAccessibleAccountQualification() throws {
        let summary = OnboardingProtectionSummary.make(coverages: [
            makeCoverage(
                id: "work-account",
                email: "work@example.com",
                calendars: [("work-calendar", "Team")],
                confirmedCalendarIDs: ["work-calendar"]
            ),
            makeCoverage(
                id: "personal-account",
                email: "personal@example.com",
                calendars: [("personal-calendar", "Team")],
                confirmedCalendarIDs: ["personal-calendar"]
            ),
        ])

        XCTAssertEqual(
            summary.accountGroups.map(\.accountText),
            [
                "Google Account: personal@example.com",
                "Google Account: work@example.com",
            ]
        )
        XCTAssertEqual(
            summary.accountGroups.map(\.calendarsText),
            [
                "Monitored Calendar: Team",
                "Monitored Calendar: Team",
            ]
        )
        XCTAssertEqual(
            summary.accountGroups.map(\.accessibilityDescription),
            [
                "Monitored Calendar Team, Google Account personal@example.com",
                "Monitored Calendar Team, Google Account work@example.com",
            ]
        )
    }

    func testIdenticalVisibleSourcesReceiveStableCrossAccountOrdinals() throws {
        let summary = OnboardingProtectionSummary.make(coverages: [
            makeCoverage(
                id: "z-account",
                email: "same@example.com",
                calendars: [("team", "Team")],
                confirmedCalendarIDs: ["team"]
            ),
            makeCoverage(
                id: "a-account",
                email: "same@example.com",
                calendars: [("team", "Team")],
                confirmedCalendarIDs: ["team"]
            ),
        ])

        XCTAssertEqual(summary.accountGroups.map(\.id), ["a-account", "z-account"])
        XCTAssertEqual(
            summary.accountGroups.map(\.calendarsText),
            [
                "Monitored Calendar: Team (1 of 2)",
                "Monitored Calendar: Team (2 of 2)",
            ]
        )
        XCTAssertEqual(
            summary.accountGroups.map(\.accessibilityDescription),
            [
                "Monitored Calendar Team, Google Account same@example.com, 1 of 2",
                "Monitored Calendar Team, Google Account same@example.com, 2 of 2",
            ]
        )
    }

    func testFreshAccountsGroupOnlyConfirmedCalendarsAndCountActiveProtection() throws {
        let summary = OnboardingProtectionSummary.make(coverages: [
            makeCoverage(
                id: "work",
                email: "work@example.com",
                calendars: [
                    ("work-primary", "Primary"),
                    ("work-shared", "Shared"),
                    ("work-unselected", "Unselected")
                ],
                confirmedCalendarIDs: ["work-primary", "work-shared"]
            ),
            makeCoverage(
                id: "personal",
                email: "personal@example.com",
                calendars: [
                    ("personal-main", "Personal"),
                    ("personal-unselected", "Unselected")
                ],
                confirmedCalendarIDs: ["personal-main"]
            )
        ])

        XCTAssertEqual(summary.activeCalendarCount, 3)
        XCTAssertEqual(summary.configuredCalendarCount, 3)
        XCTAssertEqual(summary.accountGroups.map(\.id), ["personal", "work"])
        XCTAssertEqual(
            try XCTUnwrap(summary.accountGroups.first { $0.id == "work" }).calendarIDs,
            ["work-primary", "work-shared"]
        )
        XCTAssertEqual(
            try XCTUnwrap(summary.accountGroups.first { $0.id == "personal" }).calendarIDs,
            ["personal-main"]
        )
    }

    func testPendingNewSelectionIsExcludedWhileOlderConfirmedCalendarRemains() throws {
        let summary = OnboardingProtectionSummary.make(coverages: [
            makeCoverage(
                id: "work",
                calendars: [
                    ("confirmed", "Existing"),
                    ("pending", "New selection")
                ],
                selectedCalendarIDs: ["confirmed", "pending"],
                confirmedCalendarIDs: ["confirmed"]
            )
        ])

        let group = try XCTUnwrap(summary.accountGroups.first)
        XCTAssertEqual(group.calendarIDs, ["confirmed"])
        XCTAssertEqual(group.calendarsText, "Monitored Calendar: Existing")
        XCTAssertEqual(summary.activeCalendarCount, 1)
    }

    func testGroupsAndCalendarsSortDeterministicallyWithoutCollapsingDuplicateNames() throws {
        let summary = OnboardingProtectionSummary.make(coverages: [
            makeCoverage(
                id: "z-account",
                email: "same@example.com",
                calendars: [
                    ("z-team", "Team"),
                    ("zulu", "Zulu"),
                    ("alpha", "Alpha"),
                    ("a-team", "Team")
                ],
                confirmedCalendarIDs: ["z-team", "zulu", "alpha", "a-team"]
            ),
            makeCoverage(
                id: "a-account",
                email: "same@example.com",
                calendars: [("main", "Main")],
                confirmedCalendarIDs: ["main"]
            )
        ])

        XCTAssertEqual(summary.accountGroups.map(\.id), ["a-account", "z-account"])
        let group = try XCTUnwrap(
            summary.accountGroups.first { $0.id == "z-account" }
        )
        XCTAssertEqual(group.calendarIDs, ["alpha", "a-team", "z-team", "zulu"])
        let calendars = try XCTUnwrap(group.standardPresentation.calendars)
        XCTAssertEqual(calendars.filter { $0.calendarLabel == "Team" }.count, 2)
    }

    func testNonFreshAndReconnectCoveragesKeepConfirmedGroupsButDoNotCountAsActive() throws {
        let summary = OnboardingProtectionSummary.make(coverages: [
            makeCoverage(id: "fresh", confirmedCalendarIDs: ["calendar"]),
            makeCoverage(
                id: "checking",
                confirmedCalendarIDs: ["calendar"],
                health: .checking
            ),
            makeCoverage(
                id: "stale",
                confirmedCalendarIDs: ["calendar"],
                health: .stale
            ),
            makeCoverage(
                id: "unavailable",
                confirmedCalendarIDs: ["calendar"],
                connectionState: .failed("Offline"),
                health: .unavailable("Offline")
            ),
            makeCoverage(
                id: "reconnect",
                confirmedCalendarIDs: ["calendar"],
                connectionState: .reconnectRequired,
                health: .reconnectRequired
            )
        ])

        XCTAssertEqual(Set(summary.accountGroups.map(\.id)), [
            "checking", "fresh", "reconnect", "stale", "unavailable"
        ])
        XCTAssertTrue(summary.accountGroups.allSatisfy { $0.calendarIDs.count == 1 })
        XCTAssertEqual(summary.activeCalendarCount, 1)
        XCTAssertEqual(
            try XCTUnwrap(summary.accountGroups.first { $0.id == "fresh" }).isActivelyProtected,
            true
        )
        XCTAssertTrue(
            summary.accountGroups
                .filter { $0.id != "fresh" }
                .allSatisfy { !$0.isActivelyProtected }
        )
    }

    func testOrphanConfirmedCalendarUsesExplicitUnavailablePlaceholder() throws {
        let summary = OnboardingProtectionSummary.make(coverages: [
            makeCoverage(
                id: "work",
                calendars: [("known", "Work")],
                confirmedCalendarIDs: ["known", "missing"],
                connectionState: .reconnectRequired,
                health: .reconnectRequired
            )
        ])

        let group = try XCTUnwrap(summary.accountGroups.first)
        let calendars = try XCTUnwrap(group.standardPresentation.calendars)
        let unavailable = try XCTUnwrap(
            calendars.first { $0.id.calendarID == "missing" }
        )
        XCTAssertEqual(unavailable.calendarLabel, "Unavailable calendar")
    }

    private func makeCoverage(
        id: String,
        email: String? = nil,
        calendars: [(id: String, name: String)] = [("calendar", "Calendar")],
        selectedCalendarIDs: Set<String>? = nil,
        confirmedCalendarIDs: Set<String>,
        connectionState: ConnectionState = .connected,
        health: CoverageHealth = .fresh
    ) -> AccountCoverage {
        let selectedCalendarIDs = selectedCalendarIDs ?? confirmedCalendarIDs
        return AccountCoverage(
            account: GoogleAccount(
                id: id,
                email: email ?? "\(id)@example.com",
                displayName: ""
            ),
            calendars: calendars.map {
                CalendarOption(id: $0.id, name: $0.name, accountID: id)
            },
            selectedCalendarIDs: selectedCalendarIDs,
            confirmedCalendarIDs: confirmedCalendarIDs,
            isProtectionConfirmed: !selectedCalendarIDs.isEmpty &&
                selectedCalendarIDs == confirmedCalendarIDs,
            connectionState: connectionState,
            health: health,
            lastSuccessfulRefreshAt: nil
        )
    }
}
