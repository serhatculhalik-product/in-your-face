import AppKit
import CommitmentProtection
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

    func testFitEnforcesTheMinimumContentSizeDuringLaterUserResizes() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }

        WindowFrameFitter.fit(
            panel,
            visibleFrame: CGRect(x: 0, y: 24, width: 1_440, height: 876),
            minimumContentSize: CGSize(width: 360, height: 300)
        )

        panel.setContentSize(CGSize(width: 84, height: 720))

        XCTAssertGreaterThanOrEqual(panel.contentLayoutRect.width, 359.5)
        XCTAssertGreaterThanOrEqual(panel.contentLayoutRect.height, 299.5)
    }

    func testFitClampsTheDurableMinimumToTheAvailableDisplayContentSize() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }
        let visibleFrame = CGRect(x: 100, y: 200, width: 380, height: 280)

        WindowFrameFitter.fit(
            panel,
            visibleFrame: visibleFrame,
            minimumContentSize: CGSize(width: 360, height: 300)
        )

        let availableContentSize = panel.contentRect(
            forFrameRect: CGRect(origin: .zero, size: panel.maxSize)
        ).size
        XCTAssertEqual(panel.contentMinSize.width, availableContentSize.width, accuracy: 0.5)
        XCTAssertEqual(panel.contentMinSize.height, availableContentSize.height, accuracy: 0.5)
        XCTAssertLessThan(panel.contentMinSize.height, 300)
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

    func testEarlyReminderPrimaryKeepsSwiftUIAsItsSoleSizeOwner() async {
        guard let screen = NSScreen.screens.first else {
            XCTFail("Early Reminder window fitting requires a connected display.")
            return
        }
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
            },
            availableScreens: { [screen] }
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

        let flow = await makeWindowFittingEarlyReminderFlow()
        controller.present(
            flow: flow,
            content: AnyView(Text("Early Reminder")),
            reopen: {},
            closingActionCompleted: { _ in }
        )

        registry.register(panel, for: .earlyReminder)

        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(fittedWindows.isEmpty)
        XCTAssertNil(
            scheduledFit,
            "The SwiftUI Scene owns primary sizing, so the controller must not schedule a layout-forcing refit."
        )
    }

    func testEarlyReminderCreatesAReplicaForEveryAdditionalDisplay() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        var fittedWindows: [NSWindow] = []
        let controller = EarlyReminderWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { _ in },
            fitWindow: { window, _ in
                if let window {
                    fittedWindows.append(window)
                }
            },
            availableScreens: { [screen, screen] }
        )
        let primaryWindow = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        primaryWindow.isReleasedWhenClosed = false
        controller.suspendInteractionForTestTools()
        defer {
            controller.close()
            primaryWindow.close()
        }

        let flow = await makeWindowFittingEarlyReminderFlow()
        controller.present(
            flow: flow,
            content: AnyView(Text("Early Reminder")),
            reopen: {},
            closingActionCompleted: { _ in }
        )

        registry.register(primaryWindow, for: .earlyReminder)

        let uniqueFittedWindows = Set(fittedWindows.map(ObjectIdentifier.init))
        XCTAssertEqual(
            uniqueFittedWindows.count,
            1,
            "Only the additional-display replica should use the AppKit content fitter."
        )
        XCTAssertEqual(controller.managedWindows.count, 2)
        XCTAssertTrue(controller.managedWindows.contains(where: { $0 === primaryWindow }))
    }
}

@MainActor
func makeWindowFittingEarlyReminderFlow() async -> CommitmentProtectionFlow {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
    let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
    let commitment = CalendarEvent(
        id: "event-1",
        title: "A commitment with enough content to need its natural window size",
        startDate: now.addingTimeInterval(5 * 60),
        endDate: now.addingTimeInterval(65 * 60),
        timeZoneIdentifier: nil,
        isAllDay: false,
        isAccepted: true,
        calendarID: calendar.id,
        accountID: account.id
    )
    let flow = CommitmentProtectionFlow(
        calendarConnector: WindowFittingCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            commitment: commitment
        ),
        launchAtLogin: WindowFittingLaunchAtLoginController(),
        stateStore: UserDefaults(suiteName: "WindowFrameFitterTests.\(UUID().uuidString)")!,
        now: { now }
    )
    await flow.connectGoogleAccount()
    flow.setCalendarSelected(true, calendarID: calendar.id)
    _ = flow.confirmProtection()
    for _ in 0..<10 { await Task.yield() }
    await flow.refreshCommitmentProtection(at: now)
    return flow
}

private struct WindowFittingCalendarConnector: GoogleCalendarConnecting {
    let connection: GoogleCalendarConnection
    let commitment: CalendarEvent

    func connect() async throws -> GoogleCalendarConnection { connection }
    func restore(accountID: String) async throws -> GoogleCalendarConnection? { connection }
    func disconnect(accountID: String) throws {}
    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        [commitment]
    }
}

@MainActor
private final class WindowFittingLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled = false
    func enable() throws { isEnabled = true }
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
