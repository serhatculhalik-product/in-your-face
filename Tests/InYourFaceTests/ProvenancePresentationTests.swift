import CommitmentProtection
import Foundation
import XCTest
@testable import InYourFace

final class ProvenancePresentationTests: XCTestCase {
    func testOneSourceHasExplicitCompactStandardUrgentAndAccessibleForms() throws {
        let presentation = ProvenancePresentation(
            sources: [
                ProtectionProvenanceSource(
                    accountID: "account-1",
                    accountEmail: "alex@example.com",
                    accountDisplayName: "Alex",
                    calendarID: "calendar-1",
                    calendarName: "Work"
                )
            ],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            presentation.compactItems.map(\.label),
            ["Calendar: Work · Account: alex@example.com"]
        )
        let compactItem = try XCTUnwrap(presentation.compactItems.first)
        XCTAssertEqual(compactItem.accountLabel, "alex@example.com")
        XCTAssertEqual(compactItem.calendarLabel, "Work")
        XCTAssertEqual(
            compactItem.help,
            "Monitored Calendar Work, Google Account alex@example.com"
        )
        XCTAssertEqual(compactItem.accessibilityDescription, compactItem.help)
        XCTAssertEqual(
            presentation.standardGroups.map(\.accountText),
            ["Google Account: alex@example.com"]
        )
        XCTAssertEqual(
            presentation.standardGroups.map(\.calendarsText),
            ["Monitored Calendar: Work"]
        )
        let standardGroup = try XCTUnwrap(presentation.standardGroups.first)
        let calendarItem = try XCTUnwrap(standardGroup.calendars?.first)
        XCTAssertEqual(calendarItem.calendarLabel, "Work")
        XCTAssertNil(calendarItem.ordinal)
        XCTAssertEqual(calendarItem.label, "Work")
        XCTAssertEqual(calendarItem.text, "Monitored Calendar: Work")
        XCTAssertEqual(calendarItem.help, compactItem.help)
        XCTAssertEqual(
            calendarItem.accessibilityDescription,
            compactItem.accessibilityDescription
        )
        XCTAssertEqual(standardGroup.help, compactItem.help)
        XCTAssertEqual(
            standardGroup.accessibilityDescription,
            compactItem.accessibilityDescription
        )
        let urgent = try XCTUnwrap(presentation.urgent)
        XCTAssertEqual(urgent.primaryText, "Work")
        XCTAssertEqual(urgent.secondaryText, "Account: alex@example.com")
        XCTAssertEqual(urgent.help, compactItem.help)
        XCTAssertEqual(urgent.accessibilityDescription, compactItem.accessibilityDescription)
        XCTAssertEqual(presentation.fullDescription, compactItem.help)
        XCTAssertEqual(
            presentation.accessibilityDescription,
            "Monitored Calendar Work, Google Account alex@example.com"
        )
    }

    func testMultipleSourcesDeduplicateByIdentityAndGroupAccounts() throws {
        let duplicateWork = ProtectionProvenanceSource(
            accountID: "account-1",
            accountEmail: "alex@example.com",
            accountDisplayName: "Alex",
            calendarID: "work",
            calendarName: "Work"
        )
        let presentation = ProvenancePresentation(
            sources: [
                duplicateWork,
                ProtectionProvenanceSource(
                    accountID: "account-1",
                    accountEmail: "alex@example.com",
                    accountDisplayName: "Alex",
                    calendarID: "personal",
                    calendarName: "Personal"
                ),
                duplicateWork,
                ProtectionProvenanceSource(
                    accountID: "account-2",
                    accountEmail: "sam@example.com",
                    accountDisplayName: "Sam",
                    calendarID: "work",
                    calendarName: "Work"
                )
            ],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            presentation.compactItems.map(\.label),
            [
                "Calendar: Work · Account: alex@example.com",
                "Calendar: Personal · Account: alex@example.com",
                "Calendar: Work · Account: sam@example.com",
            ]
        )
        XCTAssertEqual(
            presentation.standardGroups.map(\.accountText),
            [
                "Google Account: alex@example.com",
                "Google Account: sam@example.com",
            ]
        )
        XCTAssertEqual(
            presentation.standardGroups.map(\.calendarsText),
            [
                "Monitored Calendars: Work and Personal",
                "Monitored Calendar: Work",
            ]
        )
        let urgent = try XCTUnwrap(presentation.urgent)
        XCTAssertEqual(urgent.primaryText, "3 calendar sources")
        XCTAssertEqual(urgent.secondaryText, "Across 2 accounts")
        XCTAssertEqual(
            presentation.accessibilityDescription,
            "Monitored Calendar Work, Google Account alex@example.com, " +
                "Monitored Calendar Personal, Google Account alex@example.com, and " +
                "Monitored Calendar Work, Google Account sam@example.com"
        )
        XCTAssertEqual(urgent.help, presentation.fullDescription)
        XCTAssertEqual(urgent.accessibilityDescription, presentation.accessibilityDescription)
    }

    func testEmptyAndAccountOnlySourcesProduceOnlyMeaningfulForms() throws {
        let empty = ProvenancePresentation(
            sources: [],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertTrue(empty.compactItems.isEmpty)
        XCTAssertTrue(empty.standardGroups.isEmpty)
        XCTAssertNil(empty.urgent)
        XCTAssertEqual(empty.fullDescription, "")
        XCTAssertEqual(empty.accessibilityDescription, "")

        let accountOnly = ProvenancePresentation(
            sources: [
                ProtectionProvenanceSource(
                    accountID: "account-1",
                    accountEmail: " ",
                    accountDisplayName: " Alex ",
                    calendarID: nil,
                    calendarName: nil
                )
            ],
            locale: Locale(identifier: "en_US")
        )

        let item = try XCTUnwrap(accountOnly.compactItems.first)
        XCTAssertEqual(item.accountLabel, "Alex")
        XCTAssertNil(item.calendarLabel)
        XCTAssertEqual(item.label, "Account: Alex")
        XCTAssertEqual(item.help, "Google Account Alex")
        XCTAssertEqual(item.accessibilityDescription, "Google Account Alex")

        let group = try XCTUnwrap(accountOnly.standardGroups.first)
        XCTAssertEqual(group.accountLabel, "Alex")
        XCTAssertEqual(group.accountText, "Google Account: Alex")
        XCTAssertNil(group.calendars)
        XCTAssertNil(group.calendarsText)
        XCTAssertEqual(group.help, "Google Account Alex")
        XCTAssertEqual(group.accessibilityDescription, "Google Account Alex")
        XCTAssertNil(accountOnly.urgent)
        XCTAssertEqual(accountOnly.fullDescription, "Google Account Alex")
        XCTAssertEqual(accountOnly.accessibilityDescription, "Google Account Alex")
    }

    func testNormalizationTableCoversFallbacksAndFirstCanonicalValueForExactIdentities() {
        struct Expectation {
            let name: String
            let sources: [ProtectionProvenanceSource]
            let accountLabels: [String]
            let calendarLabels: [String?]
            let compactLabels: [String]
        }

        let cases = [
            Expectation(
                name: "missing calendar metadata and blank account identity",
                sources: [
                    ProtectionProvenanceSource(
                        accountID: "account-1",
                        accountEmail: "  ",
                        accountDisplayName: "\n",
                        calendarID: "calendar-1",
                        calendarName: nil
                    )
                ],
                accountLabels: ["Google Account"],
                calendarLabels: ["Unavailable calendar"],
                compactLabels: [
                    "Calendar: Unavailable calendar · Account: Google Account"
                ]
            ),
            Expectation(
                name: "blank calendar name",
                sources: [
                    ProtectionProvenanceSource(
                        accountID: "account-1",
                        accountEmail: " alex@example.com ",
                        accountDisplayName: "Alex",
                        calendarID: "calendar-1",
                        calendarName: " \n "
                    )
                ],
                accountLabels: ["alex@example.com"],
                calendarLabels: ["Unnamed calendar"],
                compactLabels: [
                    "Calendar: Unnamed calendar · Account: alex@example.com"
                ]
            ),
            Expectation(
                name: "repeated stable pair keeps its first canonical labels",
                sources: [
                    ProtectionProvenanceSource(
                        accountID: "account-1",
                        accountEmail: "first@example.com",
                        accountDisplayName: "First",
                        calendarID: "calendar-1",
                        calendarName: "First calendar"
                    ),
                    ProtectionProvenanceSource(
                        accountID: "account-1",
                        accountEmail: "replacement@example.com",
                        accountDisplayName: "Replacement",
                        calendarID: "calendar-1",
                        calendarName: "Replacement calendar"
                    )
                ],
                accountLabels: ["first@example.com"],
                calendarLabels: ["First calendar"],
                compactLabels: [
                    "Calendar: First calendar · Account: first@example.com"
                ]
            ),
        ]

        for expectation in cases {
            let presentation = ProvenancePresentation(
                sources: expectation.sources,
                locale: Locale(identifier: "en_US")
            )

            XCTAssertEqual(
                presentation.compactItems.map(\.accountLabel),
                expectation.accountLabels,
                expectation.name
            )
            XCTAssertEqual(
                presentation.compactItems.map(\.calendarLabel),
                expectation.calendarLabels,
                expectation.name
            )
            XCTAssertEqual(
                presentation.compactItems.map(\.label),
                expectation.compactLabels,
                expectation.name
            )
        }
    }

    func testFullyIdenticalVisibleLabelsUseStableIDOrdinalsWithoutReorderingSources() throws {
        let presentation = ProvenancePresentation(
            sources: [
                ProtectionProvenanceSource(
                    accountID: "z-account",
                    accountEmail: "same@example.com",
                    accountDisplayName: "Same",
                    calendarID: "z-calendar",
                    calendarName: "Work"
                ),
                ProtectionProvenanceSource(
                    accountID: "a-account",
                    accountEmail: "same@example.com",
                    accountDisplayName: "Same",
                    calendarID: "a-calendar",
                    calendarName: "Work"
                )
            ],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            presentation.compactItems.map(\.id),
            [
                .init(accountID: "z-account", calendarID: "z-calendar"),
                .init(accountID: "a-account", calendarID: "a-calendar"),
            ],
            "Presentation order must remain the canonical input order."
        )
        XCTAssertEqual(presentation.compactItems.map(\.ordinal), ["2 of 2", "1 of 2"])
        XCTAssertEqual(
            presentation.compactItems.map(\.label),
            [
                "Calendar: Work · Account: same@example.com (2 of 2)",
                "Calendar: Work · Account: same@example.com (1 of 2)",
            ]
        )
        XCTAssertEqual(
            presentation.standardGroups.map(\.id),
            ["z-account", "a-account"]
        )
        XCTAssertEqual(
            presentation.standardGroups.map(\.calendarsText),
            [
                "Monitored Calendar: Work (2 of 2)",
                "Monitored Calendar: Work (1 of 2)",
            ]
        )
        XCTAssertEqual(
            presentation.accessibilityDescription,
            "Monitored Calendar Work, Google Account same@example.com, 2 of 2 and " +
                "Monitored Calendar Work, Google Account same@example.com, 1 of 2"
        )
        let urgent = try XCTUnwrap(presentation.urgent)
        XCTAssertEqual(urgent.primaryText, "2 calendar sources")
        XCTAssertEqual(urgent.secondaryText, "Across 2 accounts")
        XCTAssertEqual(urgent.help, presentation.fullDescription)
        XCTAssertEqual(urgent.accessibilityDescription, presentation.accessibilityDescription)
    }

    func testLongMixedDirectionValuesRemainCompleteAndBidirectionallyIsolated() throws {
        let calendarLabel = "تقويم العمل " + String(repeating: "計画", count: 80)
        let accountLabel = String(repeating: "very.long.account.", count: 30) + "@example.com"
        let presentation = ProvenancePresentation(
            sources: [
                ProtectionProvenanceSource(
                    accountID: "account-1",
                    accountEmail: " \(accountLabel) ",
                    accountDisplayName: "",
                    calendarID: "calendar-1",
                    calendarName: " \(calendarLabel) "
                )
            ],
            locale: Locale(identifier: "en_US")
        )

        let item = try XCTUnwrap(presentation.compactItems.first)
        XCTAssertEqual(item.accountLabel, accountLabel)
        XCTAssertEqual(item.calendarLabel, calendarLabel)
        XCTAssertTrue(item.label.contains("\u{2068}\(calendarLabel)\u{2069}"))
        XCTAssertTrue(item.label.contains("\u{2068}\(accountLabel)\u{2069}"))
        XCTAssertTrue(item.help.contains(calendarLabel))
        XCTAssertTrue(item.help.contains(accountLabel))

        let urgent = try XCTUnwrap(presentation.urgent)
        XCTAssertEqual(urgent.primaryText, calendarLabel)
        XCTAssertTrue(urgent.secondaryText?.contains(accountLabel) == true)
        XCTAssertEqual(urgent.help, presentation.fullDescription)
        XCTAssertEqual(urgent.accessibilityDescription, presentation.accessibilityDescription)
        XCTAssertTrue(presentation.fullDescription.contains(calendarLabel))
        XCTAssertTrue(presentation.accessibilityDescription.contains(accountLabel))
    }

    func testStandardCalendarListsUseTheRequestedLocale() throws {
        let presentation = ProvenancePresentation(
            sources: [
                ProtectionProvenanceSource(
                    accountID: "account-1",
                    accountEmail: "alex@example.com",
                    accountDisplayName: "Alex",
                    calendarID: "work",
                    calendarName: "Arbeit"
                ),
                ProtectionProvenanceSource(
                    accountID: "account-1",
                    accountEmail: "alex@example.com",
                    accountDisplayName: "Alex",
                    calendarID: "personal",
                    calendarName: "Privat"
                )
            ],
            locale: Locale(identifier: "de_DE")
        )

        XCTAssertEqual(
            try XCTUnwrap(presentation.standardGroups.first?.calendarsText),
            "Monitored Calendars: Arbeit und Privat"
        )
    }
}
