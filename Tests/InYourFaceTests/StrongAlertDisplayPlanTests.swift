import XCTest
@testable import InYourFace

final class StrongAlertDisplayPlanTests: XCTestCase {
    func testAlertPresentationVariantsShareFlowActionsAndDisplaySharingVisibility() {
        let normal = AlertPresentationContract(variant: .earlyReminderNormal)
        let fallback = AlertPresentationContract(variant: .earlyReminderFallback)
        let strongAlert = AlertPresentationContract(variant: .strongAlert)
        let conflict = AlertPresentationContract(variant: .strongAlertConflict)

        XCTAssertEqual(normal.actionSource, fallback.actionSource)
        XCTAssertEqual(strongAlert.actionSource, conflict.actionSource)
        XCTAssertTrue(normal.preservesProtectionWhenSurfaceCloses)
        XCTAssertTrue(fallback.preservesProtectionWhenSurfaceCloses)
        XCTAssertTrue(strongAlert.preservesProtectionWhenSurfaceCloses)
        XCTAssertTrue(conflict.preservesProtectionWhenSurfaceCloses)
        XCTAssertTrue(normal.remainsVisibleDuringDisplaySharing)
        XCTAssertTrue(fallback.remainsVisibleDuringDisplaySharing)
        XCTAssertTrue(strongAlert.remainsVisibleDuringDisplaySharing)
        XCTAssertTrue(conflict.remainsVisibleDuringDisplaySharing)
    }

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
