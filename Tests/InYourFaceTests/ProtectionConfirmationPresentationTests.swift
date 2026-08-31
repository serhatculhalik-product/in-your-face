import CommitmentProtection
import Foundation
import XCTest
@testable import InYourFace

final class ProtectionConfirmationPresentationTests: XCTestCase {
    func testEmptyAccountHasNoProtectionOrConfirmationAction() {
        let presentation = ProtectionConfirmationPresentation.account(
            makeCoverage(
                id: "work",
                calendars: [("work-primary", "Work")],
                selectedCalendarIDs: [],
                confirmedCalendarIDs: []
            ),
            locale: englishLocale
        )

        XCTAssertEqual(presentation.state, .empty)
        XCTAssertEqual(presentation.selectedCount, 0)
        XCTAssertEqual(presentation.confirmedCount, 0)
        XCTAssertEqual(presentation.pendingCount, 0)
        XCTAssertEqual(presentation.pendingAccountCount, 0)
        XCTAssertEqual(presentation.title, "No Monitored Calendars selected")
        XCTAssertEqual(presentation.detail, "Select at least one calendar to begin protection.")
        XCTAssertNil(presentation.actionTitle)
        XCTAssertEqual(presentation.systemImage, "shield.slash")
    }

    func testInitialSelectionNeedsConfirmationBeforeProtectionBegins() {
        let presentation = ProtectionConfirmationPresentation.account(
            makeCoverage(
                id: "work",
                calendars: [
                    ("work-primary", "Work"),
                    ("work-team", "Team")
                ],
                selectedCalendarIDs: ["work-primary", "work-team"],
                confirmedCalendarIDs: []
            ),
            locale: englishLocale
        )

        XCTAssertEqual(presentation.state, .pendingInitialSelection)
        XCTAssertEqual(presentation.selectedCount, 2)
        XCTAssertEqual(presentation.confirmedCount, 0)
        XCTAssertEqual(presentation.pendingCount, 2)
        XCTAssertEqual(presentation.pendingAccountCount, 1)
        XCTAssertEqual(presentation.title, "Calendar selection needs confirmation")
        XCTAssertEqual(
            presentation.detail,
            "Protection is pending for 2 selected calendars."
        )
        XCTAssertEqual(presentation.actionTitle, "Protect Selected Calendars")
        XCTAssertEqual(presentation.systemImage, "calendar.badge.plus")
    }

    func testConfirmedAccountIsAQuietSettledState() {
        let presentation = ProtectionConfirmationPresentation.account(
            makeCoverage(
                id: "personal",
                calendars: [("personal-primary", "Personal")],
                selectedCalendarIDs: ["personal-primary"],
                confirmedCalendarIDs: ["personal-primary"]
            ),
            locale: englishLocale
        )

        XCTAssertEqual(presentation.state, .confirmed)
        XCTAssertEqual(presentation.selectedCount, 1)
        XCTAssertEqual(presentation.confirmedCount, 1)
        XCTAssertEqual(presentation.pendingCount, 0)
        XCTAssertEqual(presentation.pendingAccountCount, 0)
        XCTAssertEqual(presentation.title, "1 Monitored Calendar confirmed for protection")
        XCTAssertNil(presentation.detail)
        XCTAssertNil(presentation.actionTitle)
        XCTAssertEqual(presentation.systemImage, "checkmark.circle")
    }

    func testPendingAdditionKeepsConfirmedCalendarsInProtectedScope() {
        let presentation = ProtectionConfirmationPresentation.account(
            makeCoverage(
                id: "work",
                calendars: [
                    ("work-primary", "Work"),
                    ("work-team", "Team"),
                    ("work-project", "Project")
                ],
                selectedCalendarIDs: ["work-primary", "work-team", "work-project"],
                confirmedCalendarIDs: ["work-primary", "work-team"]
            ),
            locale: englishLocale
        )

        XCTAssertEqual(presentation.state, .pendingAdditions)
        XCTAssertEqual(presentation.selectedCount, 3)
        XCTAssertEqual(presentation.confirmedCount, 2)
        XCTAssertEqual(presentation.pendingCount, 1)
        XCTAssertEqual(presentation.pendingAccountCount, 1)
        XCTAssertEqual(presentation.title, "Calendar changes need confirmation")
        XCTAssertEqual(
            presentation.detail,
            "Protection is pending for 1 new calendar. " +
                "Existing confirmation already includes 2 calendars."
        )
        XCTAssertEqual(presentation.actionTitle, "Confirm Calendar Changes")
        XCTAssertEqual(presentation.systemImage, "calendar.badge.plus")
    }

    func testGlobalPresentationAggregatesPendingScopeAcrossAccounts() {
        let presentation = ProtectionConfirmationPresentation.global(
            [
                makeCoverage(
                    id: "work",
                    calendars: [
                        ("work-primary", "Work"),
                        ("work-project", "Project")
                    ],
                    selectedCalendarIDs: ["work-primary", "work-project"],
                    confirmedCalendarIDs: ["work-primary"]
                ),
                makeCoverage(
                    id: "personal",
                    calendars: [
                        ("personal-primary", "Personal"),
                        ("personal-shared", "Family")
                    ],
                    selectedCalendarIDs: ["personal-primary", "personal-shared"],
                    confirmedCalendarIDs: ["personal-primary"]
                )
            ],
            locale: englishLocale
        )

        XCTAssertEqual(presentation.state, .pendingAdditions)
        XCTAssertEqual(presentation.selectedCount, 4)
        XCTAssertEqual(presentation.confirmedCount, 2)
        XCTAssertEqual(presentation.pendingCount, 2)
        XCTAssertEqual(presentation.pendingAccountCount, 2)
        XCTAssertEqual(
            presentation.detail,
            "Protection is pending for 2 new calendars across 2 Google Accounts. " +
                "Existing confirmation already includes 2 calendars."
        )
    }

    func testGlobalInitialSelectionNamesTheMultiAccountScope() {
        let presentation = ProtectionConfirmationPresentation.global(
            [
                makeCoverage(
                    id: "work",
                    calendars: [("work-primary", "Work")],
                    selectedCalendarIDs: ["work-primary"],
                    confirmedCalendarIDs: []
                ),
                makeCoverage(
                    id: "personal",
                    calendars: [("personal-primary", "Personal")],
                    selectedCalendarIDs: ["personal-primary"],
                    confirmedCalendarIDs: []
                )
            ],
            locale: englishLocale
        )

        XCTAssertEqual(presentation.state, .pendingInitialSelection)
        XCTAssertEqual(presentation.selectedCount, 2)
        XCTAssertEqual(presentation.confirmedCount, 0)
        XCTAssertEqual(presentation.pendingCount, 2)
        XCTAssertEqual(presentation.pendingAccountCount, 2)
        XCTAssertEqual(
            presentation.detail,
            "Protection is pending for 2 selected calendars across 2 Google Accounts."
        )
    }

    func testGlobalEmptyAndSettledStatesIgnoreConfirmationOutsideSelection() {
        let empty = ProtectionConfirmationPresentation.global(
            [
                makeCoverage(
                    id: "empty",
                    calendars: [("available", "Available")],
                    selectedCalendarIDs: [],
                    confirmedCalendarIDs: ["orphaned-confirmation"]
                )
            ],
            locale: englishLocale
        )
        XCTAssertEqual(empty.state, .empty)
        XCTAssertEqual(empty.selectedCount, 0)
        XCTAssertEqual(empty.confirmedCount, 0)
        XCTAssertEqual(empty.pendingCount, 0)
        XCTAssertFalse(empty.showsAction)

        let settled = ProtectionConfirmationPresentation.global(
            [
                makeCoverage(
                    id: "work",
                    calendars: [("work", "Work")],
                    selectedCalendarIDs: ["work"],
                    confirmedCalendarIDs: ["work", "orphaned-confirmation"]
                ),
                makeCoverage(
                    id: "personal",
                    calendars: [("personal", "Personal")],
                    selectedCalendarIDs: ["personal"],
                    confirmedCalendarIDs: ["personal"]
                )
            ],
            locale: englishLocale
        )
        XCTAssertEqual(settled.state, .confirmed)
        XCTAssertEqual(settled.selectedCount, 2)
        XCTAssertEqual(settled.confirmedCount, 2)
        XCTAssertEqual(settled.pendingCount, 0)
        XCTAssertEqual(
            settled.title,
            "2 Monitored Calendars confirmed for protection"
        )
        XCTAssertFalse(settled.showsAction)
    }

    func testGlobalCountsDoNotCollapseCalendarIDsSharedByDifferentAccounts() {
        let presentation = ProtectionConfirmationPresentation.global(
            [
                makeCoverage(
                    id: "work",
                    calendars: [("primary", "Work")],
                    selectedCalendarIDs: ["primary"],
                    confirmedCalendarIDs: ["primary"]
                ),
                makeCoverage(
                    id: "personal",
                    calendars: [("primary", "Personal")],
                    selectedCalendarIDs: ["primary"],
                    confirmedCalendarIDs: []
                )
            ],
            locale: englishLocale
        )

        XCTAssertEqual(presentation.state, .pendingAdditions)
        XCTAssertEqual(presentation.selectedCount, 2)
        XCTAssertEqual(presentation.confirmedCount, 1)
        XCTAssertEqual(presentation.pendingCount, 1)
        XCTAssertEqual(presentation.pendingAccountCount, 1)
        XCTAssertEqual(
            presentation.detail,
            "Protection is pending for 1 new calendar in 1 Google Account. " +
                "Existing confirmation already includes 1 calendar."
        )
    }

    func testSettingsSummaryKeepsGlobalStatusTruthWhileDisclosingPendingScope() {
        let pendingAddition = ProtectionConfirmationPresentation.account(
            makeCoverage(
                id: "work",
                calendars: [
                    ("confirmed", "Confirmed"),
                    ("pending", "Pending")
                ],
                selectedCalendarIDs: ["confirmed", "pending"],
                confirmedCalendarIDs: ["confirmed"]
            ),
            locale: englishLocale
        )
        XCTAssertEqual(
            settingsProtectionStatusDetail(
                statusPresentation: ProtectionCoveragePresentation(
                    state: .activeProtection
                ),
                confirmationPresentation: pendingAddition,
                pauseDetail: "Paused",
                reconnectAccountLabels: []
            ),
            "Protection is pending for 1 new calendar. " +
                "Existing confirmation already includes 1 calendar. " +
                "Confirm the calendar changes in Calendars."
        )

        let pendingInitialSelection = ProtectionConfirmationPresentation.account(
            makeCoverage(
                id: "personal",
                calendars: [("pending", "Pending")],
                selectedCalendarIDs: ["pending"],
                confirmedCalendarIDs: []
            ),
            locale: englishLocale
        )
        XCTAssertEqual(
            settingsProtectionStatusDetail(
                statusPresentation: ProtectionCoveragePresentation(
                    state: .noCoverage
                ),
                confirmationPresentation: pendingInitialSelection,
                pauseDetail: "Paused",
                reconnectAccountLabels: []
            ),
            "Protection is pending for 1 selected calendar. " +
                "Confirm the calendar selection in Calendars to start protection."
        )
    }

    func testSettingsSummaryRecoveryStateDoesNotClaimPendingAvailability() {
        let pendingAddition = ProtectionConfirmationPresentation.account(
            makeCoverage(
                id: "work",
                calendars: [
                    ("confirmed", "Confirmed"),
                    ("pending", "Pending")
                ],
                selectedCalendarIDs: ["confirmed", "pending"],
                confirmedCalendarIDs: ["confirmed"]
            ),
            locale: englishLocale
        )

        XCTAssertEqual(
            settingsProtectionStatusDetail(
                statusPresentation: ProtectionCoveragePresentation(
                    state: .protectionPaused
                ),
                confirmationPresentation: pendingAddition,
                pauseDetail: "All protection paused",
                reconnectAccountLabels: []
            ),
            "All protection paused"
        )
        XCTAssertEqual(
            settingsProtectionStatusDetail(
                statusPresentation: ProtectionCoveragePresentation(
                    state: .reconnectRequired
                ),
                confirmationPresentation: pendingAddition,
                pauseDetail: "Paused",
                reconnectAccountLabels: ["person@example.com"]
            ),
            "Reconnect person@example.com to resume protection. " +
                "Routine relaunches keep valid authorization."
        )
        XCTAssertEqual(
            settingsProtectionStatusDetail(
                statusPresentation: ProtectionCoveragePresentation(
                    state: .coverageNeedsAttention
                ),
                confirmationPresentation: pendingAddition,
                pauseDetail: "Paused",
                reconnectAccountLabels: []
            ),
            "Calendar coverage needs attention."
        )
    }

    func testEnglishCopyInflectsSingularAndPluralCounts() {
        let cases: [(selectedCount: Int, expectedDetail: String)] = [
            (1, "Protection is pending for 1 selected calendar."),
            (2, "Protection is pending for 2 selected calendars.")
        ]

        for testCase in cases {
            let calendars = (1 ... testCase.selectedCount).map {
                (id: "calendar-\($0)", name: "Calendar \($0)")
            }
            let presentation = ProtectionConfirmationPresentation.account(
                makeCoverage(
                    id: "work",
                    calendars: calendars,
                    selectedCalendarIDs: Set(calendars.map(\.id)),
                    confirmedCalendarIDs: []
                ),
                locale: englishLocale
            )

            XCTAssertEqual(
                presentation.detail,
                testCase.expectedDetail,
                "selected count: \(testCase.selectedCount)"
            )
        }

        let confirmedCases: [(confirmedCount: Int, expectedTitle: String)] = [
            (1, "1 Monitored Calendar confirmed for protection"),
            (2, "2 Monitored Calendars confirmed for protection")
        ]

        for testCase in confirmedCases {
            let calendars = (1 ... testCase.confirmedCount).map {
                (id: "calendar-\($0)", name: "Calendar \($0)")
            }
            let selectedIDs = Set(calendars.map(\.id))
            let presentation = ProtectionConfirmationPresentation.account(
                makeCoverage(
                    id: "work",
                    calendars: calendars,
                    selectedCalendarIDs: selectedIDs,
                    confirmedCalendarIDs: selectedIDs
                ),
                locale: englishLocale
            )

            XCTAssertEqual(
                presentation.title,
                testCase.expectedTitle,
                "confirmed count: \(testCase.confirmedCount)"
            )
        }
    }

    func testOnlyPendingStatesExposeAnAction() {
        let cases: [(
            name: String,
            coverage: AccountCoverage,
            expectedIsPending: Bool,
            expectedShowsAction: Bool
        )] = [
            (
                "empty",
                makeCoverage(
                    id: "empty",
                    calendars: [("calendar", "Calendar")],
                    selectedCalendarIDs: [],
                    confirmedCalendarIDs: []
                ),
                false,
                false
            ),
            (
                "initial selection",
                makeCoverage(
                    id: "initial",
                    calendars: [("calendar", "Calendar")],
                    selectedCalendarIDs: ["calendar"],
                    confirmedCalendarIDs: []
                ),
                true,
                true
            ),
            (
                "addition",
                makeCoverage(
                    id: "addition",
                    calendars: [
                        ("confirmed", "Confirmed"),
                        ("pending", "Pending")
                    ],
                    selectedCalendarIDs: ["confirmed", "pending"],
                    confirmedCalendarIDs: ["confirmed"]
                ),
                true,
                true
            ),
            (
                "confirmed",
                makeCoverage(
                    id: "confirmed",
                    calendars: [("calendar", "Calendar")],
                    selectedCalendarIDs: ["calendar"],
                    confirmedCalendarIDs: ["calendar"]
                ),
                false,
                false
            )
        ]

        for testCase in cases {
            let presentation = ProtectionConfirmationPresentation.account(
                testCase.coverage,
                locale: englishLocale
            )

            XCTAssertEqual(
                presentation.isPending,
                testCase.expectedIsPending,
                testCase.name
            )
            XCTAssertEqual(
                presentation.showsAction,
                testCase.expectedShowsAction,
                testCase.name
            )
            XCTAssertEqual(
                presentation.actionTitle != nil,
                testCase.expectedShowsAction,
                testCase.name
            )
        }
    }

    private var englishLocale: Locale {
        Locale(identifier: "en_US")
    }

    private func makeCoverage(
        id: String,
        calendars: [(id: String, name: String)],
        selectedCalendarIDs: Set<String>,
        confirmedCalendarIDs: Set<String>
    ) -> AccountCoverage {
        AccountCoverage(
            account: GoogleAccount(
                id: id,
                email: "\(id)@example.com",
                displayName: id.capitalized
            ),
            calendars: calendars.map {
                CalendarOption(id: $0.id, name: $0.name, accountID: id)
            },
            selectedCalendarIDs: selectedCalendarIDs,
            confirmedCalendarIDs: confirmedCalendarIDs,
            isProtectionConfirmed: !selectedCalendarIDs.isEmpty &&
                selectedCalendarIDs == confirmedCalendarIDs,
            connectionState: .connected,
            health: confirmedCalendarIDs.isEmpty ? .noCoverage : .fresh,
            lastSuccessfulRefreshAt: confirmedCalendarIDs.isEmpty
                ? nil
                : Date(timeIntervalSince1970: 1_777_545_600)
        )
    }
}
