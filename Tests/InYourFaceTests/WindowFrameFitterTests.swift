import AppKit
import SwiftUI
import XCTest
@testable import InYourFace

@MainActor
final class WindowFrameFitterTests: XCTestCase {
    func testCentersWithinAnOffsetVisibleFrame() {
        let frame = WindowFrameFitter.centeredFrame(
            preferredSize: CGSize(width: 500, height: 400),
            minimumSize: CGSize(width: 360, height: 300),
            visibleFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_055)
        )

        XCTAssertEqual(frame.origin.x, -1_210, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 327.5, accuracy: 0.001)
        XCTAssertEqual(frame.size, CGSize(width: 500, height: 400))
    }

    func testUsesTheMinimumSizeWhenPreferredContentIsSmaller() {
        let frame = WindowFrameFitter.centeredFrame(
            preferredSize: CGSize(width: 200, height: 100),
            minimumSize: CGSize(width: 360, height: 300),
            visibleFrame: CGRect(x: 0, y: 80, width: 1_440, height: 780)
        )

        XCTAssertEqual(frame.origin.x, 540, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 320, accuracy: 0.001)
        XCTAssertEqual(frame.size, CGSize(width: 360, height: 300))
    }

    func testMarginsYieldBeforeMinimumAndDisplayWinsWhenNeeded() {
        let frame = WindowFrameFitter.centeredFrame(
            preferredSize: CGSize(width: 620, height: 680),
            minimumSize: CGSize(width: 360, height: 300),
            visibleFrame: CGRect(x: 100, y: 200, width: 380, height: 280)
        )

        XCTAssertEqual(frame, CGRect(x: 110, y: 200, width: 360, height: 280))
    }

    func testLargeContentIsCappedInsideTheVisibleFrameMargins() {
        let frame = WindowFrameFitter.centeredFrame(
            preferredSize: CGSize(width: 2_000, height: 1_500),
            minimumSize: CGSize(width: 360, height: 300),
            visibleFrame: CGRect(x: 0, y: 25, width: 1_024, height: 743)
        )

        XCTAssertEqual(frame, CGRect(x: 40, y: 65, width: 944, height: 663))
    }

    func testLivePanelIsRefittedAfterHostedContentGrows() {
        let visibleFrame = CGRect(x: -1_200, y: 40, width: 1_200, height: 760)
        let contentView = VariableFittingView()
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }
        panel.contentView = contentView

        contentView.targetFittingSize = CGSize(width: 500, height: 400)
        WindowFrameFitter.fit(
            panel,
            visibleFrame: visibleFrame,
            minimumContentSize: CGSize(width: 360, height: 300)
        )
        contentView.targetFittingSize = CGSize(
            width: visibleFrame.width * 2,
            height: visibleFrame.height * 2
        )
        WindowFrameFitter.fit(
            panel,
            visibleFrame: visibleFrame,
            minimumContentSize: CGSize(width: 360, height: 300)
        )

        let allowedFrame = visibleFrame.insetBy(dx: 40, dy: 40)
        XCTAssertEqual(panel.maxSize.width, allowedFrame.width, accuracy: 0.5)
        XCTAssertEqual(panel.maxSize.height, allowedFrame.height, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(panel.frame.minX, allowedFrame.minX - 0.5)
        XCTAssertGreaterThanOrEqual(panel.frame.minY, allowedFrame.minY - 0.5)
        XCTAssertLessThanOrEqual(panel.frame.maxX, allowedFrame.maxX + 0.5)
        XCTAssertLessThanOrEqual(panel.frame.maxY, allowedFrame.maxY + 0.5)
    }

    func testHostedPanelDoesNotOutgrowTheDisplayAfterItsContentChanges() {
        let visibleFrame = CGRect(x: 0, y: 24, width: 1_024, height: 744)
        let model = HostingSizeModel(size: CGSize(width: 500, height: 280))
        let hostingView = NSHostingView(rootView: HostingSizeProbe(model: model))
        hostingView.sizingOptions = [.intrinsicContentSize]
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }
        panel.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        WindowFrameFitter.fit(
            panel,
            visibleFrame: visibleFrame,
            minimumContentSize: CGSize(width: 360, height: 300)
        )
        model.size = CGSize(
            width: visibleFrame.width * 2,
            height: visibleFrame.height * 2
        )
        hostingView.layoutSubtreeIfNeeded()
        WindowFrameFitter.fit(
            panel,
            visibleFrame: visibleFrame,
            minimumContentSize: CGSize(width: 360, height: 300)
        )

        let allowedFrame = visibleFrame.insetBy(dx: 40, dy: 40)
        XCTAssertGreaterThan(hostingView.fittingSize.height, allowedFrame.height)
        XCTAssertLessThanOrEqual(panel.frame.width, allowedFrame.width + 0.5)
        XCTAssertLessThanOrEqual(panel.frame.height, allowedFrame.height + 0.5)
    }

    func testEarlyReminderSchedulesASecondFitAfterWindowRegistration() {
        let registry = WindowRegistry()
        var scheduledFit: (@MainActor () -> Void)?
        var fittedWindows: [NSWindow] = []
        let controller = EarlyReminderWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { scheduledFit = $0 },
            fitWindow: { window, _ in
                if let window {
                    fittedWindows.append(window)
                }
            }
        )
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.close()
            panel.close()
        }

        controller.present(
            content: EarlyReminderFallbackContent(
                title: "A commitment with enough content to need its natural window size",
                timing: "Aug 25, 2026 at 20:30 local time",
                snoozeOptionsMinutes: [5, 10],
                verificationLabel: nil
            ),
            reopen: {},
            clear: {},
            canSnooze: true,
            snooze: { _ in },
            dismiss: {}
        )

        registry.register(panel, for: .earlyReminder)

        XCTAssertEqual(fittedWindows.count, 1)
        XCTAssertTrue(fittedWindows.first === panel)
        let deferredFit = scheduledFit
        XCTAssertNotNil(deferredFit)

        deferredFit?()

        XCTAssertEqual(fittedWindows.count, 2)
        XCTAssertTrue(fittedWindows.last === panel)
    }
}

private final class VariableFittingView: NSView {
    var targetFittingSize = CGSize(width: 360, height: 300)

    override var fittingSize: NSSize {
        targetFittingSize
    }
}

@MainActor
private final class HostingSizeModel: ObservableObject {
    @Published var size: CGSize

    init(size: CGSize) {
        self.size = size
    }
}

private struct HostingSizeProbe: View {
    @ObservedObject var model: HostingSizeModel

    var body: some View {
        Color.clear
            .frame(width: model.size.width, height: model.size.height)
    }
}
