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
}
