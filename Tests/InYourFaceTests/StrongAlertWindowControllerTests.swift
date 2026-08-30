import AppKit
import CommitmentProtection
import SwiftUI
import XCTest
@testable import InYourFace

@MainActor
final class StrongAlertWindowControllerTests: XCTestCase {
    func testNativeCloseAttemptDoesNotDismissStrongAlert() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        let controller = StrongAlertWindowController(
            windowRegistry: registry,
            availableScreens: { [screen] }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        controller.suspendInteractionForTestTools()
        defer {
            controller.close()
            window.close()
        }

        controller.present(content: AnyView(Text("Strong Alert")))
        registry.register(window, for: .strongAlert)
        XCTAssertTrue(window.isVisible)

        let shouldClose = try XCTUnwrap(
            window.delegate?.windowShouldClose?(window),
            "The production Strong Alert delegate must own native close attempts."
        )
        window.performClose(nil)
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertFalse(shouldClose)
        XCTAssertTrue(
            window.isVisible,
            "A Strong Alert must remain visible after a native close attempt."
        )
    }

    func testNativeWindowControlsAreNotExposedOnEveryStrongAlertWindow() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        var fittedWindows: [NSWindow] = []
        let controller = StrongAlertWindowController(
            windowRegistry: registry,
            fitWindow: { window, _ in
                guard let window,
                      !fittedWindows.contains(where: { $0 === window }) else { return }
                fittedWindows.append(window)
            },
            availableScreens: { [screen, screen] }
        )
        let primaryWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        primaryWindow.isReleasedWhenClosed = false
        controller.suspendInteractionForTestTools()
        defer {
            controller.close()
            primaryWindow.close()
        }

        controller.present(content: AnyView(Text("Strong Alert")))
        registry.register(primaryWindow, for: .strongAlert)

        let replicaWindow = try XCTUnwrap(
            fittedWindows.first(where: { $0 !== primaryWindow })
        )
        let replicaShouldClose = try XCTUnwrap(
            replicaWindow.delegate?.windowShouldClose?(replicaWindow),
            "The production Strong Alert delegate must own replica close attempts."
        )
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertFalse(replicaShouldClose)
        XCTAssertTrue(primaryWindow.isVisible)
        XCTAssertTrue(replicaWindow.isVisible)
        XCTAssertFalse(replicaWindow.isAccessibilityElement())
        XCTAssertTrue(
            replicaWindow.accessibilityChildren()?.isEmpty ?? true,
            "A Strong Alert replica must not announce provenance from a second accessibility tree."
        )

        let standardButtons: [(type: NSWindow.ButtonType, name: String)] = [
            (.closeButton, "Close"),
            (.miniaturizeButton, "Minimize"),
            (.zoomButton, "Zoom")
        ]
        for button in standardButtons {
            if let primaryButton = primaryWindow.standardWindowButton(button.type) {
                XCTAssertFalse(
                    primaryButton.isHidden,
                    "The primary Strong Alert must preserve SwiftUI's titlebar layout while suppressing \(button.name)."
                )
                XCTAssertTrue(
                    primaryButton.isTransparent,
                    "The primary Strong Alert's native \(button.name) control must never draw."
                )
            }
            if let replicaButton = replicaWindow.standardWindowButton(button.type) {
                XCTAssertFalse(
                    replicaButton.isHidden,
                    "Strong Alert replicas must preserve titlebar layout while suppressing \(button.name)."
                )
                XCTAssertTrue(
                    replicaButton.isTransparent,
                    "Strong Alert replicas' native \(button.name) controls must never draw."
                )
            }
            XCTAssertFalse(
                hasVisuallyExposedStandardWindowButton(button.type, in: primaryWindow),
                "The primary Strong Alert must not expose the native \(button.name) control."
            )
            XCTAssertFalse(
                hasVisuallyExposedStandardWindowButton(button.type, in: replicaWindow),
                "Strong Alert replicas must not expose the native \(button.name) control."
            )
            XCTAssertFalse(
                primaryWindow.standardWindowButton(button.type)?.isEnabled ?? false,
                "The primary Strong Alert's native \(button.name) control must not be operable."
            )
            XCTAssertFalse(
                replicaWindow.standardWindowButton(button.type)?.isEnabled ?? false,
                "Strong Alert replicas' native \(button.name) controls must not be operable."
            )
            XCTAssertFalse(
                primaryWindow.standardWindowButton(button.type)?.isAccessibilityElement() ?? false,
                "The primary Strong Alert's native \(button.name) control must not be exposed to accessibility."
            )
            XCTAssertFalse(
                replicaWindow.standardWindowButton(button.type)?.isAccessibilityElement() ?? false,
                "Strong Alert replicas' native \(button.name) controls must not be exposed to accessibility."
            )
        }
    }

    func testDisplayRecoveryRestartsApplicationActivationObservation() async throws {
        _ = NSApplication.shared
        let screens = NSScreen.screens
        try XCTSkipIf(screens.isEmpty, "Strong Alert display recovery requires a connected test display.")
        let registry = WindowRegistry()
        let notificationCenter = NotificationCenter()
        let screenProvider = MutableStrongAlertScreenProvider()
        let controller = StrongAlertWindowController(
            windowRegistry: registry,
            notificationCenter: notificationCenter,
            availableScreens: { screenProvider.screens }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            controller.close()
            window.close()
        }

        controller.present(content: AnyView(Text("Strong Alert")))
        registry.register(window, for: .strongAlert)

        XCTAssertFalse(controller.isObservingApplicationActivation)

        screenProvider.screens = screens
        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertTrue(controller.isObservingApplicationActivation)
    }

    func testPrimaryWindowSizingIsNeverPassedToControllerFrameFitter() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        let notificationCenter = NotificationCenter()
        var scheduledFits: [@MainActor () -> Void] = []
        var fittedWindows: [NSWindow] = []
        let controller = StrongAlertWindowController(
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
        let window = NSWindow(
            contentRect: NSRect(x: 100_000, y: 100_000, width: 460, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Text("Strong Alert"))
        controller.suspendInteractionForTestTools()
        defer {
            controller.close()
            window.close()
        }

        controller.present(content: AnyView(Text("Strong Alert")))
        registry.register(window, for: .strongAlert)

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.frame.midX, screen.visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(window.frame.midY, screen.visibleFrame.midY, accuracy: 0.5)
        XCTAssertFalse(fittedWindows.isEmpty, "The additional-display replica should be fitted.")
        XCTAssertFalse(fittedWindows.contains(where: { $0 === window }))

        for _ in 0..<10 where !scheduledFits.isEmpty {
            let pendingFits = scheduledFits
            scheduledFits.removeAll()
            pendingFits.forEach { $0() }
        }

        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        for _ in 0..<10 {
            await Task.yield()
        }
        for _ in 0..<10 where !scheduledFits.isEmpty {
            let pendingFits = scheduledFits
            scheduledFits.removeAll()
            pendingFits.forEach { $0() }
        }

        XCTAssertTrue(scheduledFits.isEmpty)
        XCTAssertFalse(
            fittedWindows.contains(where: { $0 === window }),
            "SwiftUI Scene must remain the sole size owner for the primary Strong Alert window."
        )
    }

    func testReplicaResizeDelegateCallbackDoesNotRefitWindow() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        var scheduledFits: [@MainActor () -> Void] = []
        var fittedWindows: [NSWindow] = []
        var fitCounts: [ObjectIdentifier: Int] = [:]
        let controller = StrongAlertWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { scheduledFits.append($0) },
            fitWindow: { window, _ in
                guard let window else { return }
                fitCounts[ObjectIdentifier(window), default: 0] += 1
                if !fittedWindows.contains(where: { $0 === window }) {
                    fittedWindows.append(window)
                }
            },
            availableScreens: { [screen, screen] }
        )
        let primaryWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        primaryWindow.isReleasedWhenClosed = false
        primaryWindow.contentView = NSHostingView(rootView: Text("Strong Alert"))
        controller.suspendInteractionForTestTools()
        defer {
            controller.close()
            primaryWindow.close()
        }

        controller.present(content: AnyView(Text("Strong Alert")))
        registry.register(primaryWindow, for: .strongAlert)
        let replicaWindow = try XCTUnwrap(
            fittedWindows.first(where: { $0 !== primaryWindow })
        )
        for _ in 0..<10 where !scheduledFits.isEmpty {
            let pendingFits = scheduledFits
            scheduledFits.removeAll()
            pendingFits.forEach { $0() }
        }
        XCTAssertTrue(scheduledFits.isEmpty)
        let fitCountBeforeResize = fitCounts[ObjectIdentifier(replicaWindow)]

        replicaWindow.delegate?.windowDidResize?(Notification(
            name: NSWindow.didResizeNotification,
            object: replicaWindow
        ))
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(
            fitCounts[ObjectIdentifier(replicaWindow)],
            fitCountBeforeResize,
            "A replica resize notification must not synchronously refit the same AppKit panel."
        )
        XCTAssertTrue(scheduledFits.isEmpty)
    }

    func testAdditionalDisplayWindowFitsContentThatGrowsAfterHostedLayout() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        var scheduledFits: [@MainActor () -> Void] = []
        var fittedWindows: [NSWindow] = []
        let contentSize = StrongAlertHostedContentSize(
            size: CGSize(width: 500, height: 280)
        )
        let content = ResizingStrongAlertProbe(contentSize: contentSize)
        let primaryWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        primaryWindow.isReleasedWhenClosed = false
        primaryWindow.contentView = NSHostingView(rootView: content)
        let controller = StrongAlertWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { scheduledFits.append($0) },
            fitWindow: { window, _ in
                guard let window else { return }
                if !fittedWindows.contains(where: { $0 === window }) {
                    fittedWindows.append(window)
                }
                WindowFrameFitter.fit(
                    window,
                    visibleFrame: window === primaryWindow
                        ? CGRect(x: 0, y: 24, width: 1_512, height: 944)
                        : CGRect(x: 1_512, y: 0, width: 2_560, height: 1_440),
                    minimumContentSize: CGSize(width: 360, height: 300)
                )
            },
            availableScreens: { [screen, screen] }
        )
        controller.suspendInteractionForTestTools()
        defer {
            controller.close()
            primaryWindow.close()
        }

        controller.present(content: AnyView(content))
        registry.register(primaryWindow, for: .strongAlert)

        XCTAssertFalse(fittedWindows.contains(where: { $0 === primaryWindow }))
        let additionalWindows = fittedWindows
        XCTAssertEqual(additionalWindows.count, 1)

        for _ in 0..<10 where !scheduledFits.isEmpty {
            let pendingFits = scheduledFits
            scheduledFits.removeAll()
            pendingFits.forEach { $0() }
        }
        XCTAssertTrue(scheduledFits.isEmpty)

        contentSize.size = CGSize(width: 500, height: 560)
        for _ in 0..<10 {
            await Task.yield()
        }
        primaryWindow.contentView?.layoutSubtreeIfNeeded()
        fittedWindows.forEach { $0.contentView?.layoutSubtreeIfNeeded() }

        XCTAssertFalse(
            scheduledFits.isEmpty,
            "A later SwiftUI intrinsic-size change should schedule another fit."
        )
        for _ in 0..<10 where !scheduledFits.isEmpty {
            let pendingFits = scheduledFits
            scheduledFits.removeAll()
            pendingFits.forEach { $0() }
        }
        XCTAssertTrue(
            scheduledFits.isEmpty,
            "Intrinsic-size refitting should converge without an async layout loop."
        )
        fittedWindows.forEach { $0.contentView?.layoutSubtreeIfNeeded() }

        let primaryRequiredSize = try XCTUnwrap(primaryWindow.contentView).fittingSize
        let additionalWindow = additionalWindows[0]
        let additionalRequiredHeight = try XCTUnwrap(additionalWindow.contentView).fittingSize.height
        XCTAssertGreaterThanOrEqual(
            additionalWindow.contentLayoutRect.height,
            additionalRequiredHeight - 0.5,
            "The additional-display alert clips content that becomes taller after its first SwiftUI layout pass."
        )
        XCTAssertEqual(
            additionalWindow.contentLayoutRect.width,
            primaryRequiredSize.width,
            accuracy: 0.5,
            "The replica should use the primary SwiftUI content's logical width."
        )
        XCTAssertEqual(
            additionalWindow.contentLayoutRect.height,
            primaryRequiredSize.height,
            accuracy: 0.5,
            "The replica should use the primary SwiftUI content's logical height."
        )
    }

    func testDeferredFitSkipsWindowsReplacedDuringDisplayRecovery() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        let notificationCenter = NotificationCenter()
        var scheduledFits: [@MainActor () -> Void] = []
        var fitCounts: [ObjectIdentifier: Int] = [:]
        var fittedWindows: [NSWindow] = []
        let controller = StrongAlertWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { scheduledFits.append($0) },
            fitWindow: { window, _ in
                guard let window else { return }
                fitCounts[ObjectIdentifier(window), default: 0] += 1
                if !fittedWindows.contains(where: { $0 === window }) {
                    fittedWindows.append(window)
                }
            },
            notificationCenter: notificationCenter,
            availableScreens: { [screen, screen] }
        )
        let primaryWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        primaryWindow.isReleasedWhenClosed = false
        primaryWindow.contentView = NSHostingView(rootView: Text("Strong Alert"))
        controller.suspendInteractionForTestTools()
        defer {
            controller.close()
            primaryWindow.close()
        }

        controller.present(content: AnyView(Text("Strong Alert")))
        registry.register(primaryWindow, for: .strongAlert)

        let staleAdditionalWindow = try XCTUnwrap(
            fittedWindows.first(where: { $0 !== primaryWindow })
        )
        let staleScheduledFits = scheduledFits
        scheduledFits.removeAll()

        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        for _ in 0..<10 {
            await Task.yield()
        }

        let replacementAdditionalWindow = try XCTUnwrap(
            fittedWindows.last(where: {
                $0 !== primaryWindow && $0 !== staleAdditionalWindow
            })
        )
        let countsBeforeStaleCallbacks = fitCounts

        staleScheduledFits.forEach { $0() }

        XCTAssertEqual(fitCounts, countsBeforeStaleCallbacks)

        scheduledFits.forEach { $0() }

        XCTAssertNil(fitCounts[ObjectIdentifier(primaryWindow)])
        XCTAssertEqual(fitCounts[ObjectIdentifier(replacementAdditionalWindow)], 2)
        XCTAssertEqual(fitCounts[ObjectIdentifier(staleAdditionalWindow)], 1)
    }

    func testAdditionalDisplayFitsTheProductionStandardAlertAboveItsMinimum() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        var scheduledFits: [@MainActor () -> Void] = []
        var fittedWindows: [NSWindow] = []
        let content = AnyView(
            StrongAlertView(
                title: "Customer review",
                timing: "Starting now",
                provenance: ProvenancePresentation(
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
                ),
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
        )
        let primaryWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        primaryWindow.isReleasedWhenClosed = false
        let primaryHostingView = NSHostingView(rootView: content)
        primaryHostingView.sizingOptions = [.intrinsicContentSize]
        primaryWindow.contentView = primaryHostingView
        let controller = StrongAlertWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { scheduledFits.append($0) },
            fitWindow: { window, _ in
                guard let window else { return }
                if !fittedWindows.contains(where: { $0 === window }) {
                    fittedWindows.append(window)
                }
                WindowFrameFitter.fit(
                    window,
                    visibleFrame: window === primaryWindow
                        ? CGRect(x: 0, y: 24, width: 1_512, height: 944)
                        : CGRect(x: 1_512, y: 0, width: 2_560, height: 1_440),
                    minimumContentSize: CGSize(width: 360, height: 300)
                )
            },
            availableScreens: { [screen, screen] }
        )
        controller.suspendInteractionForTestTools()
        defer {
            controller.close()
            primaryWindow.close()
        }

        controller.present(content: content)
        registry.register(primaryWindow, for: .strongAlert)

        for _ in 0..<10 {
            let pendingFits = scheduledFits
            scheduledFits.removeAll()
            if pendingFits.isEmpty { break }
            pendingFits.forEach { $0() }
            await Task.yield()
        }
        XCTAssertTrue(
            scheduledFits.isEmpty,
            "The production alert should settle within the bounded refit passes."
        )

        let additionalWindow = try XCTUnwrap(
            fittedWindows.first(where: { $0 !== primaryWindow })
        )
        let primaryRequiredSize = primaryHostingView.fittingSize
        XCTAssertFalse(fittedWindows.contains(where: { $0 === primaryWindow }))
        XCTAssertGreaterThan(
            additionalWindow.contentLayoutRect.height,
            300.5,
            "The standard production alert must not remain compressed at the controller minimum."
        )
        XCTAssertEqual(
            additionalWindow.contentLayoutRect.height,
            primaryRequiredSize.height,
            accuracy: 0.5
        )
        XCTAssertEqual(
            additionalWindow.contentLayoutRect.width,
            primaryRequiredSize.width,
            accuracy: 0.5
        )
        XCTAssertGreaterThanOrEqual(
            additionalWindow.contentLayoutRect.height,
            additionalWindow.contentView!.fittingSize.height - 0.5
        )
    }

    func testDeferredFitsKeepEachWindowOnItsPlannedPhysicalDisplay() async throws {
        _ = NSApplication.shared
        let screens = Array(NSScreen.screens.prefix(2))
        try XCTSkipUnless(
            screens.count == 2,
            "Physical display targeting requires two connected displays."
        )
        let registry = WindowRegistry()
        var scheduledFits: [@MainActor () -> Void] = []
        var fitScreens: [ObjectIdentifier: [NSScreen]] = [:]
        let primaryScreen = screens[0]
        let primaryWindow = NSWindow(
            contentRect: NSRect(
                x: primaryScreen.visibleFrame.midX - 230,
                y: primaryScreen.visibleFrame.midY - 150,
                width: 460,
                height: 300
            ),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        primaryWindow.isReleasedWhenClosed = false
        primaryWindow.contentView = NSHostingView(rootView: Text("Strong Alert"))
        let controller = StrongAlertWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { scheduledFits.append($0) },
            fitWindow: { window, screen in
                guard let window, let screen else { return }
                fitScreens[ObjectIdentifier(window), default: []].append(screen)
                WindowFrameFitter.fit(
                    window,
                    on: screen,
                    minimumContentSize: CGSize(width: 360, height: 300)
                )
            },
            availableScreens: { screens }
        )
        controller.suspendInteractionForTestTools()
        defer {
            controller.close()
            primaryWindow.close()
        }

        controller.present(content: AnyView(Text("Strong Alert")))
        registry.register(primaryWindow, for: .strongAlert)
        for _ in 0..<10 where !scheduledFits.isEmpty {
            let pendingFits = scheduledFits
            scheduledFits.removeAll()
            pendingFits.forEach { $0() }
        }
        XCTAssertTrue(scheduledFits.isEmpty)

        XCTAssertNil(fitScreens[ObjectIdentifier(primaryWindow)])
        XCTAssertEqual(fitScreens.count, 1)
        let replicaScreenCalls = try XCTUnwrap(fitScreens.values.first)
        XCTAssertEqual(
            Set(replicaScreenCalls.map(ObjectIdentifier.init)),
            [ObjectIdentifier(screens[1])],
            "The replica's initial and deferred fits must stay on its planned display."
        )
    }

    func testStableAsyncInvalidationDoesNotRestartTheRefitLoop() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let registry = WindowRegistry()
        var scheduledFits: [@MainActor () -> Void] = []
        var fittedWindows: [NSWindow] = []
        var fitCounts: [ObjectIdentifier: Int] = [:]
        let primaryWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        primaryWindow.isReleasedWhenClosed = false
        primaryWindow.contentView = NSHostingView(rootView: Text("Strong Alert"))
        let controller = StrongAlertWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { scheduledFits.append($0) },
            fitWindow: { window, _ in
                guard let window else { return }
                if !fittedWindows.contains(where: { $0 === window }) {
                    fittedWindows.append(window)
                }
                let windowID = ObjectIdentifier(window)
                fitCounts[windowID, default: 0] += 1
                if window !== primaryWindow, fitCounts[windowID] == 2 {
                    scheduledFits.append {
                        window.contentView?.invalidateIntrinsicContentSize()
                    }
                }
            },
            availableScreens: { [screen, screen] }
        )
        controller.suspendInteractionForTestTools()
        defer {
            controller.close()
            primaryWindow.close()
        }

        controller.present(content: AnyView(Text("Strong Alert")))
        registry.register(primaryWindow, for: .strongAlert)
        let additionalWindow = try XCTUnwrap(
            fittedWindows.first(where: { $0 !== primaryWindow })
        )

        for _ in 0..<10 where !scheduledFits.isEmpty {
            let pendingFits = scheduledFits
            scheduledFits.removeAll()
            pendingFits.forEach { $0() }
        }

        XCTAssertTrue(
            scheduledFits.isEmpty,
            "A late invalidation with an unchanged fitting size must settle without restarting the loop."
        )
        XCTAssertEqual(
            fitCounts[ObjectIdentifier(additionalWindow)],
            2,
            "The initial and first hosted-layout fits are sufficient when the late fitting size is unchanged."
        )
        XCTAssertNil(fitCounts[ObjectIdentifier(primaryWindow)])
    }
}

@MainActor
private func hasVisuallyExposedStandardWindowButton(
    _ type: NSWindow.ButtonType,
    in window: NSWindow
) -> Bool {
    guard let button = window.standardWindowButton(type) else { return false }
    return !button.isHidden && !button.isTransparent && button.alphaValue > 0.01
}

@MainActor
private final class MutableStrongAlertScreenProvider {
    var screens: [NSScreen] = []
}

@MainActor
private final class StrongAlertHostedContentSize: ObservableObject {
    @Published var size: CGSize

    init(size: CGSize) {
        self.size = size
    }
}

private struct ResizingStrongAlertProbe: View {
    @ObservedObject var contentSize: StrongAlertHostedContentSize

    var body: some View {
        Color.clear
            .frame(width: contentSize.size.width, height: contentSize.size.height)
    }
}
