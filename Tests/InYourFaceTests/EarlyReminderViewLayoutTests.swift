import AppKit
import SwiftUI
import XCTest
@testable import InYourFace

@MainActor
final class EarlyReminderViewLayoutTests: XCTestCase {
    func testNormalAndFallbackHostedCloseUseTheRealFlowAction() async throws {
        let cases: [(String, EarlyReminderContentVariant)] = [
            ("normal", .normal),
            ("fallback", .fallback),
        ]

        for (name, variant) in cases {
            let fixture = await makeEarlyReminderTestFlow()
            var completions: [Bool] = []
            let (window, hostingView) = host(
                EarlyReminderContentView(
                    flow: fixture.flow,
                    variant: variant,
                    closingActionCompleted: { completions.append($0) }
                ),
                width: 560,
                height: 680
            )
            defer { window.orderOut(nil) }
            let closeButton = try XCTUnwrap(
                descendants(in: hostingView)
                    .compactMap { $0 as? NSButton }
                    .first { $0.accessibilityLabel() == "Close for now" },
                name
            )

            closeButton.performClick(nil)
            settle(hostingView)

            XCTAssertNil(fixture.flow.earlyReminderCommitment, name)
            XCTAssertEqual(completions, [true], name)
        }
    }

    func testUnresolvedConflictOrdersAndDispatchesContextualHostedActions() async throws {
        let fixture = await makeEarlyReminderConflictTestFlow()
        let (window, hostingView) = host(
            EarlyReminderContentView(
                flow: fixture.flow,
                variant: .normal,
                closingActionCompleted: { _ in }
            ),
            width: 560,
            height: 680
        )
        defer { window.orderOut(nil) }

        let actionControls = descendants(in: hostingView)
            .compactMap { $0 as? NSButton }
            .filter { control in
                guard let label = control.accessibilityLabel() else { return false }
                return label.hasPrefix("Close ") ||
                    label.hasPrefix("Snooze ") ||
                    label.hasPrefix("Stop reminders for ") ||
                    label.hasPrefix("Make ")
            }
            .sorted {
                hostingView.convert($0.bounds, from: $0).midY <
                    hostingView.convert($1.bounds, from: $1).midY
            }
        let labels = actionControls.compactMap { $0.accessibilityLabel() }

        XCTAssertEqual(labels.count, 5)
        XCTAssertTrue(labels[0].hasPrefix("Close "))
        XCTAssertTrue(labels[1].hasPrefix("Snooze "))
        XCTAssertTrue(labels[2].hasPrefix("Stop reminders for "))
        XCTAssertTrue(labels[3].hasPrefix("Make "))
        XCTAssertTrue(labels[4].hasPrefix("Make "))
        XCTAssertTrue(labels.allSatisfy { $0.contains("Monitored Calendar Work") })
        XCTAssertTrue(labels.allSatisfy { $0.contains("option ") })

        let secondaryAction = try XCTUnwrap(
            zip(actionControls, labels).first { _, label in
                label.hasPrefix("Make ") && label.contains("Secondary review")
            }?.0
        )
        secondaryAction.performClick(nil)
        settle(hostingView)

        XCTAssertEqual(
            fixture.flow.lastActionMessage,
            "Primary commitment selected for this conflict."
        )
    }

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

    private func host<Content: View>(
        _ view: Content,
        width: CGFloat,
        height: CGFloat
    ) -> (NSWindow, NSHostingView<Content>) {
        _ = NSApplication.shared
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = [.intrinsicContentSize]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.frame = window.contentView?.bounds ?? .zero
        settle(hostingView)
        return (window, hostingView)
    }

    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        view.layoutSubtreeIfNeeded()
    }

    private func descendants(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
