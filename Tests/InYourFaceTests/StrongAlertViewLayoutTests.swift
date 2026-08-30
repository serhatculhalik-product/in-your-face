import AppKit
import CommitmentProtection
import SwiftUI
import XCTest
@testable import InYourFace

@MainActor
final class StrongAlertViewLayoutTests: XCTestCase {
    func testHostedSharedProvenanceRendererPreservesUrgentAndFullSemantics() throws {
        _ = NSApplication.shared
        struct Case {
            let name: String
            let sources: [ProtectionProvenanceSource]
            let expected: ExpectedProvenanceSemantics
        }
        let cases = [
            Case(
                name: "one source",
                sources: [source(accountID: "account-1", email: "alex@example.com", calendarID: "work", calendarName: "Work")],
                expected: ExpectedProvenanceSemantics(
                    primaryText: "Work",
                    secondaryText: "Account: alex@example.com",
                    help: "Monitored Calendar Work, Google Account alex@example.com",
                    accessibilityLabel: "Monitored Calendar Work, Google Account alex@example.com"
                )
            ),
            Case(
                name: "same visible names",
                sources: [
                    source(accountID: "z-account", email: "same@example.com", calendarID: "z-calendar", calendarName: "Work"),
                    source(accountID: "a-account", email: "same@example.com", calendarID: "a-calendar", calendarName: "Work"),
                ],
                expected: ExpectedProvenanceSemantics(
                    primaryText: "2 calendar sources",
                    secondaryText: "Across 2 accounts",
                    help: "Monitored Calendar Work, Google Account same@example.com, 2 of 2 and Monitored Calendar Work, Google Account same@example.com, 1 of 2",
                    accessibilityLabel: "Monitored Calendar Work, Google Account same@example.com, 2 of 2 and Monitored Calendar Work, Google Account same@example.com, 1 of 2"
                )
            ),
            Case(
                name: "merged sources",
                sources: [
                    source(accountID: "account-1", email: "alex@example.com", calendarID: "work", calendarName: "Work"),
                    source(accountID: "account-1", email: "alex@example.com", calendarID: "personal", calendarName: "Personal"),
                    source(accountID: "account-2", email: "sam@example.com", calendarID: "shared", calendarName: "Shared"),
                ],
                expected: ExpectedProvenanceSemantics(
                    primaryText: "3 calendar sources",
                    secondaryText: "Across 2 accounts",
                    help: "Monitored Calendar Work, Google Account alex@example.com, Monitored Calendar Personal, Google Account alex@example.com, and Monitored Calendar Shared, Google Account sam@example.com",
                    accessibilityLabel: "Monitored Calendar Work, Google Account alex@example.com, Monitored Calendar Personal, Google Account alex@example.com, and Monitored Calendar Shared, Google Account sam@example.com"
                )
            ),
        ]

        for testCase in cases {
            let presentation = ProvenancePresentation(
                sources: testCase.sources,
                locale: Locale(identifier: "en_US")
            )
            let renderer = strongAlertProvenanceRenderer(presentation)
            let semantics = try XCTUnwrap(renderer.semantics, testCase.name)

            assertSemantics(semantics, equalTo: testCase.expected, testCase.name)

            let hostingView = NSHostingView(
                rootView: renderer.frame(width: 320)
            )
            hostingView.sizingOptions = [.intrinsicContentSize]
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertGreaterThan(hostingView.fittingSize.height, 10, testCase.name)
            XCTAssertLessThan(
                hostingView.fittingSize.height,
                90,
                "Urgent provenance should stay secondary to the alert decision: \(testCase.name)."
            )
        }
    }

    func testStartingNowAndOverdueAlertsComposeTheHostedSharedRenderer() throws {
        _ = NSApplication.shared
        let expected = ExpectedProvenanceSemantics(
            primaryText: "Work",
            secondaryText: "Account: alex@example.com",
            help: "Monitored Calendar Work, Google Account alex@example.com",
            accessibilityLabel: "Monitored Calendar Work, Google Account alex@example.com"
        )

        for timing in ["Starting now", "Started 12 minutes ago"] {
            let view = alert(timing: timing)

            let semantics = try XCTUnwrap(view.provenanceRenderer.semantics, timing)
            assertSemantics(semantics, equalTo: expected, timing)

            let hostingView = NSHostingView(rootView: view)
            hostingView.sizingOptions = [.intrinsicContentSize]
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertGreaterThan(hostingView.fittingSize.height, 300, timing)
            XCTAssertLessThan(hostingView.fittingSize.height, 559, timing)
        }
    }

    func testNormalAndUnresolvedConflictCompositionsShareTheRendererSeam() {
        let normalAlert = alert(timing: "Starting now")
        let unresolvedConflictRenderer = strongAlertProvenanceRenderer(testProvenance)

        XCTAssertEqual(
            normalAlert.provenanceRenderer.semantics,
            unresolvedConflictRenderer.semantics
        )
        XCTAssertEqual(
            unresolvedConflictRenderer.semantics?.accessibilityLabel,
            "Monitored Calendar Work, Google Account alex@example.com"
        )
    }

    func testStandardAlertUsesItsNaturalContentHeight() {
        _ = NSApplication.shared
        let view = StrongAlertView(
            title: "Customer review",
            timing: "Starting now",
            provenance: testProvenance,
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
            provenance: testProvenance,
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
            provenance: testProvenance,
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
            provenance: testProvenance,
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

    private struct ExpectedProvenanceSemantics {
        let primaryText: String
        let secondaryText: String?
        let help: String
        let accessibilityLabel: String
    }

    private func assertSemantics(
        _ actual: StrongAlertProvenanceSemantics,
        equalTo expected: ExpectedProvenanceSemantics,
        _ message: String
    ) {
        XCTAssertEqual(actual.primaryText, expected.primaryText, message)
        XCTAssertEqual(actual.secondaryText, expected.secondaryText, message)
        XCTAssertEqual(actual.help, expected.help, message)
        XCTAssertEqual(actual.accessibilityLabel, expected.accessibilityLabel, message)
    }

    private var testProvenance: ProvenancePresentation {
        ProvenancePresentation(
            sources: [
                ProtectionProvenanceSource(
                    accountID: "account-1",
                    accountEmail: "alex@example.com",
                    accountDisplayName: "Alex",
                    calendarID: "calendar-1",
                    calendarName: "Work"
                )
            ],
            locale: Locale(identifier: "en_US")
        )
    }

    private func source(
        accountID: String,
        email: String,
        calendarID: String,
        calendarName: String
    ) -> ProtectionProvenanceSource {
        ProtectionProvenanceSource(
            accountID: accountID,
            accountEmail: email,
            accountDisplayName: "",
            calendarID: calendarID,
            calendarName: calendarName
        )
    }

    private func alert(timing: String) -> StrongAlertView {
        StrongAlertView(
            title: "Customer review",
            timing: timing,
            provenance: testProvenance,
            primaryActionTitle: "Join",
            primaryAction: {},
            secondaryActionTitle: "Stop reminders",
            secondaryAction: {},
            handledActionTitle: "I joined another way",
            handledAction: {},
            tertiaryActionTitle: "Got it",
            tertiaryAction: {}
        )
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
