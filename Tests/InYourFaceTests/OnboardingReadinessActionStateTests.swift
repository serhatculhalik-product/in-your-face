import CommitmentProtection
import XCTest
@testable import InYourFace

final class OnboardingReadinessActionStateTests: XCTestCase {
    func testOnlyFinishableReadinessStatesOfferFinishSetup() {
        let cases: [Case] = [
            Case(
                name: "active",
                expectedAction: .finishSetup,
                expectedCanFinishSetup: true,
                status: .active
            ),
            Case(
                name: "pending confirmation",
                expectedAction: .finishSetup,
                expectedCanFinishSetup: true,
                status: .noCoverage,
                isProtectionConfirmationRequired: true
            ),
            Case(
                name: "reconnect required",
                expectedAction: .reconnect,
                expectedCanFinishSetup: false,
                requiresReconnect: true,
                status: .active
            ),
            Case(
                name: "checking coverage",
                expectedAction: .checkingCoverage,
                expectedCanFinishSetup: false,
                isCheckingCoverage: true,
                status: .active
            ),
            Case(
                name: "refreshing coverage",
                expectedAction: .checkingCoverage,
                expectedCanFinishSetup: false,
                isRefreshingCoverage: true,
                status: .active
            ),
            Case(
                name: "review calendars",
                expectedAction: .reviewCalendars,
                expectedCanFinishSetup: false,
                status: .noCoverage
            ),
            Case(
                name: "retry calendar access",
                expectedAction: .retryCalendarAccess,
                expectedCanFinishSetup: false,
                status: .unavailable
            ),
            Case(
                name: "account operation in progress",
                expectedAction: .finishSetup,
                expectedCanFinishSetup: false,
                isGoogleAccountOperationInProgress: true,
                status: .active
            ),
        ]

        for testCase in cases {
            let state = OnboardingReadinessActionState.make(
                requiresReconnect: testCase.requiresReconnect,
                isGoogleAccountOperationInProgress: testCase.isGoogleAccountOperationInProgress,
                isCheckingCoverage: testCase.isCheckingCoverage,
                isRefreshingCoverage: testCase.isRefreshingCoverage,
                status: testCase.status,
                isProtectionConfirmationRequired: testCase.isProtectionConfirmationRequired
            )

            XCTAssertEqual(
                state.primaryAction,
                testCase.expectedAction,
                testCase.name
            )
            XCTAssertEqual(
                state.canFinishSetup,
                testCase.expectedCanFinishSetup,
                testCase.name
            )
        }
    }
}

private struct Case {
    let name: String
    let expectedAction: OnboardingReadinessActionState.PrimaryAction
    let expectedCanFinishSetup: Bool
    var requiresReconnect = false
    var isGoogleAccountOperationInProgress = false
    var isCheckingCoverage = false
    var isRefreshingCoverage = false
    let status: ProtectionStatus
    var isProtectionConfirmationRequired = false
}
