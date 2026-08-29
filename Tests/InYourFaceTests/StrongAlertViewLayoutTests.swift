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

        XCTAssertGreaterThan(hostingView.fittingSize.height, 300)
        XCTAssertLessThan(
            hostingView.fittingSize.height,
            559,
            "A standard alert should fit its content instead of inheriting the old fixed 560-point ideal height."
        )
    }

    func testOversizedAlertClampsToTheScrollableHeightLimit() throws {
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
        hostingView.frame.size = hostingView.fittingSize
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(hostingView.fittingSize.height, 680, accuracy: 0.5)
        let scrollView = try XCTUnwrap(firstScrollView(in: hostingView))
        XCTAssertEqual(scrollView.frame.height, 680, accuracy: 0.5)
    }

    func testCustomHeightLimitCreatesABoundedScrollableViewport() throws {
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
            tertiaryAction: {},
            maximumContentHeight: 420
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = [.intrinsicContentSize]

        hostingView.layoutSubtreeIfNeeded()
        hostingView.frame.size = hostingView.fittingSize
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(hostingView.fittingSize.height, 420, accuracy: 0.5)
        let scrollView = try XCTUnwrap(firstScrollView(in: hostingView))
        XCTAssertEqual(scrollView.frame.height, 420, accuracy: 0.5)
    }

    func testAlertContentIsMountedOnlyOnce() {
        _ = NSApplication.shared
        let counter = StrongAlertMountCounter()
        let view = StrongAlertView(
            title: "Customer review",
            timing: "Starting now",
            detail: "alex@example.com · work@example.com",
            supportingContent: AnyView(StrongAlertMountProbe(counter: counter)),
            primaryActionTitle: "Join",
            primaryAction: {},
            tertiaryActionTitle: "Got it",
            tertiaryAction: {}
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = [.intrinsicContentSize]

        hostingView.layoutSubtreeIfNeeded()
        hostingView.frame.size = hostingView.fittingSize
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(counter.mountCount, 1)
    }

    func testShortestDisplayDeterminesTheSafeContentHeight() {
        XCTAssertEqual(
            StrongAlertDisplayMetrics.maximumContentHeight(visibleFrameHeights: []),
            680
        )
        XCTAssertEqual(
            StrongAlertDisplayMetrics.maximumContentHeight(visibleFrameHeights: [1_440, 900]),
            680
        )
        XCTAssertEqual(
            StrongAlertDisplayMetrics.maximumContentHeight(visibleFrameHeights: [1_440, 700]),
            580
        )
        XCTAssertEqual(
            StrongAlertDisplayMetrics.maximumContentHeight(visibleFrameHeights: [350]),
            300
        )
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let scrollView = firstScrollView(in: child) { return scrollView }
        }
        return nil
    }
}

@MainActor
private final class StrongAlertMountCounter {
    var mountCount = 0
}

private struct StrongAlertMountProbe: NSViewRepresentable {
    let counter: StrongAlertMountCounter

    func makeNSView(context: Context) -> NSView {
        counter.mountCount += 1
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
