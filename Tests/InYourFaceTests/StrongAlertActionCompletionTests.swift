import XCTest
@testable import InYourFace

@MainActor
final class StrongAlertActionCompletionTests: XCTestCase {
    func testCompletionClosesTheAlertControllerBeforeHidingTheApplication() {
        var actions: [String] = []

        StrongAlertActionCompletion.finish(
            hasRemainingAlert: false,
            closeAlertWindow: { actions.append("close") },
            hideApplication: { actions.append("hide") }
        )

        XCTAssertEqual(actions, ["close", "hide"])
    }

    func testCompletionLeavesTheApplicationVisibleWhenAnotherAlertRemains() {
        var actions: [String] = []

        StrongAlertActionCompletion.finish(
            hasRemainingAlert: true,
            closeAlertWindow: { actions.append("close") },
            hideApplication: { actions.append("hide") }
        )

        XCTAssertTrue(actions.isEmpty)
    }
}
