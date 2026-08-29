import AppKit
import SwiftUI
import XCTest
@testable import InYourFace

@MainActor
final class StrongAlertViewLayoutTests: XCTestCase {
    func testStandardAlertUsesItsNaturalContentHeight() {
        _ = NSApplication.shared
        let view = StrongAlertView(
            title: "Customer review",
            timing: "Starting now",
            detail: "alex@example.com · work@example.com",
            repeatConsequence: "Closes this alert now. Protection stays active and Strong Alert returns in 1 minute unless you Join, choose I joined another way, Stop reminders, or Pause All Protection.",
            primaryActionTitle: "Join",
            primaryAction: {},
            secondaryActionTitle: "Stop reminders",
            secondaryAction: {},
            handledActionTitle: "I joined another way",
            handledAction: {},
            tertiaryActionTitle: "Got it",
            tertiaryAction: {},
            pauseAction: { _ in true }
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = [.intrinsicContentSize]

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThanOrEqual(hostingView.fittingSize.height, 300)
        XCTAssertLessThan(
            hostingView.fittingSize.height,
            559,
            "A standard alert should fit its content instead of inheriting the old fixed 560-point ideal height."
        )
    }

    func testOversizedAlertClampsToTheScrollableHeightLimit() {
        _ = NSApplication.shared
        let view = StrongAlertView(
            title: "Customer review",
            timing: "Starting now",
            detail: "alex@example.com · work@example.com",
            supportingContent: AnyView(
                Color.clear.frame(width: 500, height: 900)
            ),
            primaryActionTitle: "Join",
            primaryAction: {},
            tertiaryActionTitle: "Got it",
            tertiaryAction: {}
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = [.intrinsicContentSize]

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(hostingView.fittingSize.height, 680, accuracy: 0.5)
    }
}
