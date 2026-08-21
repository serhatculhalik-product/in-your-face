import XCTest
@testable import InYourFace

final class StrongAlertDisplayPlanTests: XCTestCase {
    func testStrongAlertCoversThePrimaryAndEveryAdditionalDisplay() {
        let plan = StrongAlertDisplayPlan(displayCount: 3, primaryIndex: 1)

        XCTAssertEqual(plan?.primaryIndex, 1)
        XCTAssertEqual(Set(plan?.allDisplayIndices ?? []), Set(0..<3))
        XCTAssertEqual(plan?.additionalIndices, [0, 2])
    }

    func testStrongAlertFallsBackToTheFirstDisplayWhenPrimaryIsUnavailable() {
        let plan = StrongAlertDisplayPlan(displayCount: 2, primaryIndex: nil)

        XCTAssertEqual(plan?.primaryIndex, 0)
        XCTAssertEqual(plan?.additionalIndices, [1])
    }

    func testStrongAlertRebuildsCoverageWhenDisplayTopologyChanges() {
        let beforeChange = StrongAlertDisplayPlan(displayCount: 2, primaryIndex: 0)
        let afterChange = StrongAlertDisplayPlan(displayCount: 3, primaryIndex: 1)

        XCTAssertEqual(Set(beforeChange?.allDisplayIndices ?? []), Set(0..<2))
        XCTAssertEqual(Set(afterChange?.allDisplayIndices ?? []), Set(0..<3))
        XCTAssertNotEqual(beforeChange, afterChange)
    }

    func testStrongAlertHasNoDisplayPlanWhenNoDisplaysAreAvailable() {
        XCTAssertNil(StrongAlertDisplayPlan(displayCount: 0, primaryIndex: nil))
    }
}
