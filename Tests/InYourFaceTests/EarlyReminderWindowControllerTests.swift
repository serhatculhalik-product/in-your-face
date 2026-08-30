import AppKit
import SwiftUI
import XCTest
@testable import InYourFace

@MainActor
final class EarlyReminderWindowControllerTests: XCTestCase {
    func testSwiftUIPrimaryWindowIsNeverPassedToControllerFrameFitter() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        let notificationCenter = NotificationCenter()
        var scheduledFits: [@MainActor () -> Void] = []
        var fittedWindows: [NSWindow] = []
        let controller = EarlyReminderWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { scheduledFits.append($0) },
            fitWindow: { window, _ in
                if let window {
                    fittedWindows.append(window)
                }
            },
            notificationCenter: notificationCenter,
            availableScreens: { [screen, screen] }
        )
        let primaryWindow = NSPanel(
            contentRect: CGRect(x: 100_000, y: 100_000, width: 360, height: 300),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        primaryWindow.isReleasedWhenClosed = false
        primaryWindow.contentView = NSHostingView(rootView: Text("Early Reminder"))
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

        XCTAssertEqual(primaryWindow.frame.midX, screen.visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(primaryWindow.frame.midY, screen.visibleFrame.midY, accuracy: 0.5)
        XCTAssertFalse(fittedWindows.isEmpty, "The additional-display replica should be fitted.")
        XCTAssertFalse(
            fittedWindows.contains(where: { $0 === primaryWindow }),
            "Forcing an AppKit layout from the SwiftUI Scene window's resize cycle causes a fatal layout recursion."
        )

        primaryWindow.delegate?.windowDidResize?(Notification(
            name: NSWindow.didResizeNotification,
            object: primaryWindow
        ))
        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        await settleEarlyReminderWindowTasks()
        for _ in 0..<10 where !scheduledFits.isEmpty {
            let pendingFits = scheduledFits
            scheduledFits.removeAll()
            pendingFits.forEach { $0() }
        }

        XCTAssertFalse(
            fittedWindows.contains(where: { $0 === primaryWindow }),
            "SwiftUI must remain the sole size owner for the primary Early Reminder window."
        )
    }

    func testTopologyChangesReplaceReplicasAndPreserveOneSurfacePerDisplay() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        let notificationCenter = NotificationCenter()
        let screenProvider = MutableEarlyReminderScreenProvider(screens: [screen, screen])
        let controller = EarlyReminderWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { _ in },
            fitWindow: { _, _ in },
            notificationCenter: notificationCenter,
            availableScreens: { screenProvider.screens }
        )
        let primaryWindow = makeEarlyReminderTestWindow()
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

        XCTAssertEqual(controller.managedWindows.count, 2)
        let firstReplica = try XCTUnwrap(
            controller.managedWindows.first(where: { $0 !== primaryWindow })
        )

        screenProvider.screens = [screen, screen, screen]
        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        await settleEarlyReminderWindowTasks()

        XCTAssertEqual(controller.managedWindows.count, 3)
        XCTAssertFalse(controller.managedWindows.contains(where: { $0 === firstReplica }))
        XCTAssertFalse(firstReplica.isVisible)
        let expandedReplicas = controller.managedWindows.filter { $0 !== primaryWindow }

        screenProvider.screens = [screen]
        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        await settleEarlyReminderWindowTasks()

        XCTAssertEqual(controller.managedWindows.count, 1)
        XCTAssertTrue(controller.managedWindows.first === primaryWindow)
        XCTAssertTrue(expandedReplicas.allSatisfy { !$0.isVisible })
    }

    func testAppActivationRestoresEveryDisplayWindow() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        let notificationCenter = NotificationCenter()
        let controller = EarlyReminderWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { _ in },
            fitWindow: { _, _ in },
            notificationCenter: notificationCenter,
            availableScreens: { [screen, screen] }
        )
        let primaryWindow = makeEarlyReminderTestWindow()
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

        let replicaWindow = try XCTUnwrap(
            controller.managedWindows.first(where: { $0 !== primaryWindow })
        )
        XCTAssertTrue(primaryWindow.isVisible)
        XCTAssertTrue(replicaWindow.isVisible)

        replicaWindow.orderOut(nil)
        XCTAssertFalse(replicaWindow.isVisible)

        notificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: NSApp
        )
        await settleEarlyReminderWindowTasks()

        XCTAssertTrue(primaryWindow.isVisible)
        XCTAssertTrue(
            replicaWindow.isVisible,
            "App activation must restore the Early Reminder on every connected display."
        )
    }

    func testSurfaceRecoversWhenDisplaysReturnAfterTemporaryZeroDisplayTopology() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        let notificationCenter = NotificationCenter()
        let screenProvider = MutableEarlyReminderScreenProvider(screens: [screen, screen])
        let controller = EarlyReminderWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { _ in },
            fitWindow: { _, _ in },
            notificationCenter: notificationCenter,
            availableScreens: { screenProvider.screens }
        )
        let primaryWindow = makeEarlyReminderTestWindow()
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
        let firstReplica = try XCTUnwrap(
            controller.managedWindows.first(where: { $0 !== primaryWindow })
        )

        screenProvider.screens = []
        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        await settleEarlyReminderWindowTasks()

        XCTAssertFalse(controller.isSurfacePresented)
        XCTAssertEqual(controller.managedWindows.count, 1)
        XCTAssertFalse(firstReplica.isVisible)

        screenProvider.screens = [screen]
        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        await settleEarlyReminderWindowTasks()

        XCTAssertTrue(controller.isSurfacePresented)
        XCTAssertEqual(controller.managedWindows.count, 1)
        XCTAssertTrue(controller.managedWindows.first === primaryWindow)
        XCTAssertTrue(primaryWindow.isVisible)
    }

    func testZeroDisplayPrimaryIsClosedWhenAReplacementWindowRegisters() async throws {
        _ = NSApplication.shared
        let registry = WindowRegistry()
        let controller = EarlyReminderWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { _ in },
            fitWindow: { _, _ in },
            availableScreens: { [] }
        )
        let firstWindow = makeEarlyReminderTestWindow()
        let replacementWindow = makeEarlyReminderTestWindow()
        controller.suspendInteractionForTestTools()
        defer {
            controller.close()
            firstWindow.close()
            replacementWindow.close()
        }

        let flow = await makeWindowFittingEarlyReminderFlow()
        controller.present(
            flow: flow,
            content: AnyView(Text("First Early Reminder")),
            reopen: {},
            closingActionCompleted: { _ in }
        )
        registry.register(firstWindow, for: .earlyReminder)
        XCTAssertFalse(controller.isSurfacePresented)
        XCTAssertTrue(controller.managedWindows.first === firstWindow)

        registry.unregister(firstWindow, for: .earlyReminder)
        controller.present(
            flow: flow,
            content: AnyView(Text("Replacement Early Reminder")),
            reopen: {},
            closingActionCompleted: { _ in }
        )
        registry.register(replacementWindow, for: .earlyReminder)

        XCTAssertTrue(controller.managedWindows.first === replacementWindow)
        XCTAssertFalse(controller.managedWindows.contains(where: { $0 === firstWindow }))
        XCTAssertNil(firstWindow.delegate)
        XCTAssertFalse(firstWindow.isVisible)
    }

    func testReplicaMatchesThePrimaryNaturalProductionContentHeight() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        var scheduledFits: [@MainActor () -> Void] = []
        let controller = EarlyReminderWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { scheduledFits.append($0) },
            fitWindow: { window, _ in
                WindowFrameFitter.fit(
                    window,
                    visibleFrame: CGRect(x: 0, y: 24, width: 1_512, height: 944),
                    minimumContentSize: CGSize(width: 360, height: 300)
                )
            },
            availableScreens: { [screen, screen] }
        )
        let flow = await makeWindowFittingEarlyReminderFlow()
        let content = AnyView(EarlyReminderContentView(
            flow: flow,
            variant: .normal,
            closingActionCompleted: { _ in },
            maximumContentHeight: 680
        ))
        let primaryWindow = makeEarlyReminderTestWindow()
        primaryWindow.contentView = NSHostingView(rootView: content)
        controller.suspendInteractionForTestTools()
        defer {
            controller.close()
            primaryWindow.close()
        }

        controller.present(
            flow: flow,
            content: content,
            reopen: {},
            closingActionCompleted: { _ in }
        )
        registry.register(primaryWindow, for: .earlyReminder)

        for _ in 0..<20 where !scheduledFits.isEmpty {
            let pendingFits = scheduledFits
            scheduledFits.removeAll()
            pendingFits.forEach { $0() }
        }
        XCTAssertTrue(scheduledFits.isEmpty)

        let replicaWindow = try XCTUnwrap(
            controller.managedWindows.first(where: { $0 !== primaryWindow })
        )
        primaryWindow.contentView?.layoutSubtreeIfNeeded()
        replicaWindow.contentView?.layoutSubtreeIfNeeded()
        let primaryHeight = try XCTUnwrap(primaryWindow.contentView).fittingSize.height
        let replicaHeight = try XCTUnwrap(replicaWindow.contentView).fittingSize.height

        XCTAssertGreaterThan(primaryHeight, 300)
        XCTAssertLessThan(
            primaryHeight,
            519,
            "Production Early Reminder content must not retain the old 520-point fixed height."
        )
        XCTAssertEqual(replicaHeight, primaryHeight, accuracy: 0.5)
        XCTAssertEqual(
            replicaWindow.contentLayoutRect.height,
            primaryHeight,
            accuracy: 0.5,
            "Every display should use the same content-fit Early Reminder height."
        )
    }

    func testCloseTearsDownPrimaryAndEveryReplica() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        let controller = EarlyReminderWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { _ in },
            fitWindow: { _, _ in },
            availableScreens: { [screen, screen] }
        )
        let primaryWindow = makeEarlyReminderTestWindow()
        controller.suspendInteractionForTestTools()

        let flow = await makeWindowFittingEarlyReminderFlow()
        controller.present(
            flow: flow,
            content: AnyView(Text("Early Reminder")),
            reopen: {},
            closingActionCompleted: { _ in }
        )
        registry.register(primaryWindow, for: .earlyReminder)
        let presentedWindows = controller.managedWindows

        XCTAssertEqual(presentedWindows.count, 2)
        controller.close()

        XCTAssertTrue(controller.managedWindows.isEmpty)
        XCTAssertTrue(presentedWindows.allSatisfy { !$0.isVisible })
    }

    func testNativeCloseFromReplicaPerformsCloseForNowOnceAndClosesAllWindows() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        var completionResults: [Bool] = []
        var controller: EarlyReminderWindowController!
        controller = EarlyReminderWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { _ in },
            fitWindow: { _, _ in },
            availableScreens: { [screen, screen] }
        )
        let primaryWindow = makeEarlyReminderTestWindow()
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
            closingActionCompleted: { didApply in
                completionResults.append(didApply)
                controller.close()
            }
        )
        registry.register(primaryWindow, for: .earlyReminder)
        let replica = try XCTUnwrap(
            controller.managedWindows.first(where: { $0 !== primaryWindow })
        )

        let shouldCloseOnlyReplica = try XCTUnwrap(
            replica.delegate?.windowShouldClose?(replica)
        )

        XCTAssertFalse(shouldCloseOnlyReplica)
        XCTAssertEqual(completionResults, [true])
        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertTrue(controller.managedWindows.isEmpty)
    }

    func testEveryEarlyReminderWindowExposesOnlyTheNativeCloseControl() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        let controller = EarlyReminderWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { _ in },
            fitWindow: { _, _ in },
            availableScreens: { [screen, screen] }
        )
        let primaryWindow = makeEarlyReminderTestWindow()
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

        XCTAssertEqual(controller.managedWindows.count, 2)
        let replicaWindow = try XCTUnwrap(
            controller.managedWindows.first(where: { $0 !== primaryWindow })
        )
        for managedWindow in controller.managedWindows {
            let closeButton = try XCTUnwrap(
                managedWindow.standardWindowButton(.closeButton)
            )
            XCTAssertTrue(closeButton.isEnabled)
            XCTAssertFalse(closeButton.isHidden)
            XCTAssertFalse(closeButton.isTransparent)
            XCTAssertFalse(
                managedWindow.standardWindowButton(.miniaturizeButton)?.isEnabled ?? true
            )
            XCTAssertFalse(
                managedWindow.standardWindowButton(.zoomButton)?.isEnabled ?? true
            )
        }

        XCTAssertFalse(replicaWindow.isAccessibilityElement())
        XCTAssertTrue(
            replicaWindow.accessibilityChildren()?.isEmpty ?? true,
            "A visual replica must not create a second accessible interaction tree."
        )
        for buttonType in [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ] {
            XCTAssertFalse(
                replicaWindow.standardWindowButton(buttonType)?.isAccessibilityElement() ?? false,
                "Replica title-bar controls must remain mouse-visible without duplicating accessibility actions."
            )
        }
    }
}

@MainActor
private func makeEarlyReminderTestWindow() -> NSPanel {
    let panel = NSPanel(
        contentRect: CGRect(x: 0, y: 0, width: 360, height: 300),
        styleMask: [.titled, .closable, .utilityWindow],
        backing: .buffered,
        defer: false
    )
    panel.isReleasedWhenClosed = false
    return panel
}

@MainActor
private func settleEarlyReminderWindowTasks() async {
    for _ in 0..<10 {
        await Task.yield()
    }
}

@MainActor
private final class MutableEarlyReminderScreenProvider {
    var screens: [NSScreen]

    init(screens: [NSScreen]) {
        self.screens = screens
    }
}
