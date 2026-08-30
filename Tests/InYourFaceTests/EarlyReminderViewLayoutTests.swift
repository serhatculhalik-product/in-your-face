import AppKit
import SwiftUI
import XCTest
@testable import InYourFace

@MainActor
final class EarlyReminderViewLayoutTests: XCTestCase {
    func testStandardEarlyReminderUsesItsNaturalContentHeight() async {
        _ = NSApplication.shared
        let flow = await makeWindowFittingEarlyReminderFlow()
        let view = EarlyReminderContentView(
            flow: flow,
            variant: .normal,
            closingActionCompleted: { _ in }
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = [.intrinsicContentSize]

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostingView.fittingSize.height, 300)
        XCTAssertLessThan(
            hostingView.fittingSize.height,
            519,
            "A standard Early Reminder should fit its content instead of inheriting the old fixed 520-point ideal height."
        )
    }

    func testSmallEarlyReminderContentKeepsTheUsableMinimumHeight() {
        _ = NSApplication.shared
        let hostingView = NSHostingView(rootView: EarlyReminderViewport {
            Color.clear.frame(width: 360, height: 40)
        })
        hostingView.sizingOptions = [.intrinsicContentSize]

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(hostingView.fittingSize.height, 300, accuracy: 0.5)
    }

    func testMidSizedEarlyReminderContentUsesItsExactNaturalHeight() {
        _ = NSApplication.shared
        let hostingView = NSHostingView(rootView: EarlyReminderViewport(
            maximumContentHeight: 420
        ) {
            Color.clear.frame(width: 500, height: 360)
        })
        hostingView.sizingOptions = [.intrinsicContentSize]

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            hostingView.fittingSize.height,
            360,
            accuracy: 0.5,
            "Content between the minimum and maximum must not inherit a fixed window height."
        )
    }

    func testOversizedEarlyReminderContentUsesABoundedScrollableViewport() throws {
        _ = NSApplication.shared
        let hostingView = NSHostingView(rootView: EarlyReminderViewport(
            maximumContentHeight: 420
        ) {
            Color.clear.frame(width: 500, height: 900)
        })
        hostingView.sizingOptions = [.intrinsicContentSize]

        hostingView.layoutSubtreeIfNeeded()
        hostingView.frame.size = hostingView.fittingSize
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(hostingView.fittingSize.height, 420, accuracy: 0.5)
        let scrollView = try XCTUnwrap(firstScrollView(in: hostingView))
        XCTAssertEqual(scrollView.frame.height, 420, accuracy: 0.5)
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let scrollView = firstScrollView(in: child) { return scrollView }
        }
        return nil
    }
}
