import XCTest
@testable import InYourFace

final class WindowOwnershipTests: XCTestCase {
    func testChildWindowsBelongToTheReminderRoot() {
        final class WindowNode {
            var parent: WindowNode?
        }

        let root = WindowNode()
        let child = WindowNode()
        let unrelated = WindowNode()
        child.parent = root

        XCTAssertTrue(objectIsOwned(root, by: root, parent: \.parent))
        XCTAssertTrue(objectIsOwned(child, by: root, parent: \.parent))
        XCTAssertFalse(objectIsOwned(unrelated, by: root, parent: \.parent))
        XCTAssertFalse(objectIsOwned(nil, by: root, parent: \.parent))
    }

    func testPrimaryReplicaAndTheirChildrenBelongToOneReminderSurface() {
        final class WindowNode {
            var parent: WindowNode?
        }

        let primary = WindowNode()
        let replica = WindowNode()
        let replicaSheet = WindowNode()
        let unrelated = WindowNode()
        replicaSheet.parent = replica
        let reminderRoots = [primary, replica]

        XCTAssertTrue(objectIsOwned(primary, byAny: reminderRoots, parent: \.parent))
        XCTAssertTrue(objectIsOwned(replica, byAny: reminderRoots, parent: \.parent))
        XCTAssertTrue(objectIsOwned(replicaSheet, byAny: reminderRoots, parent: \.parent))
        XCTAssertFalse(objectIsOwned(unrelated, byAny: reminderRoots, parent: \.parent))
    }
}
