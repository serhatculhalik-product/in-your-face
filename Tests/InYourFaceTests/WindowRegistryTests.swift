import AppKit
import XCTest
@testable import InYourFace

@MainActor
final class WindowRegistryTests: XCTestCase {
    func testRegisterAndUnregisterUseSemanticWindowKind() {
        let registry = WindowRegistry()
        let window = makeWindow(title: "Configuración de Meeting Incoming")

        registry.register(window, for: .onboarding)

        XCTAssertTrue(registry.window(for: .onboarding) === window)
        XCTAssertNil(registry.window(for: .earlyReminder))

        registry.unregister(window, for: .onboarding)

        XCTAssertNil(registry.window(for: .onboarding))
    }

    func testUnregisteringAnOldWindowDoesNotRemoveItsReplacement() {
        let registry = WindowRegistry()
        let oldWindow = makeWindow(title: "Old")
        let replacementWindow = makeWindow(title: "Replacement")

        registry.register(oldWindow, for: .strongAlert)
        registry.register(replacementWindow, for: .strongAlert)
        registry.unregister(oldWindow, for: .strongAlert)

        XCTAssertTrue(registry.window(for: .strongAlert) === replacementWindow)
    }

    func testRegistryRecognizesItsRootAndOwnedChildWindows() {
        let registry = WindowRegistry()
        let rootWindow = makeWindow(title: "Settings")
        let childWindow = makeWindow(title: "Confirmation")
        let unrelatedWindow = makeWindow(title: "Menu Bar Popover")
        rootWindow.addChildWindow(childWindow, ordered: .above)
        registry.register(rootWindow, for: .settings)

        XCTAssertTrue(registry.manages(rootWindow))
        XCTAssertTrue(registry.manages(childWindow))
        XCTAssertFalse(registry.manages(unrelatedWindow))
    }

    func testLocalizedVisibleTitleDoesNotAffectPendingPresentation() {
        let registry = WindowRegistry()
        let localizedWindow = makeWindow(title: "تذكير مبكر")
        var deliveredWindow: NSWindow?
        var deliveredContent: String?
        let presentation = PendingWindowPresentation<String>(
            registry: registry,
            kind: .earlyReminder
        ) { window, content in
            deliveredWindow = window
            deliveredContent = content
        }

        presentation.submit("reminder")
        registry.register(localizedWindow, for: .earlyReminder)

        XCTAssertTrue(deliveredWindow === localizedWindow)
        XCTAssertEqual(deliveredContent, "reminder")
    }

    func testOnlyLatestPendingContentIsDeliveredAfterRegistration() {
        let registry = WindowRegistry()
        let window = makeWindow(title: "Strong Alert")
        var deliveries: [String] = []
        let presentation = PendingWindowPresentation<String>(
            registry: registry,
            kind: .strongAlert
        ) { _, content in
            deliveries.append(content)
        }

        presentation.submit("stale")
        presentation.submit("latest")
        registry.register(window, for: .strongAlert)

        XCTAssertEqual(deliveries, ["latest"])
    }

    func testClearPreventsStalePendingContentFromBeingDelivered() {
        let registry = WindowRegistry()
        let window = makeWindow(title: "Strong Alert")
        var deliveries: [String] = []
        let presentation = PendingWindowPresentation<String>(
            registry: registry,
            kind: .strongAlert
        ) { _, content in
            deliveries.append(content)
        }

        presentation.submit("stale")
        presentation.clear()
        registry.register(window, for: .strongAlert)

        XCTAssertTrue(deliveries.isEmpty)
    }

    func testNewContentUsesTheLatestRegisteredWindow() {
        let registry = WindowRegistry()
        let firstWindow = makeWindow(title: "First")
        let latestWindow = makeWindow(title: "Latest")
        var deliveredWindow: NSWindow?
        let presentation = PendingWindowPresentation<String>(
            registry: registry,
            kind: .strongAlert
        ) { window, _ in
            deliveredWindow = window
        }

        registry.register(firstWindow, for: .strongAlert)
        registry.register(latestWindow, for: .strongAlert)
        presentation.submit("content")

        XCTAssertTrue(deliveredWindow === latestWindow)
    }

    func testOnboardingCloseDoesNotActOnAWindowRegisteredLater() {
        let registry = WindowRegistry()
        let controller = OnboardingWindowController(windowRegistry: registry)
        let futureWindow = makeWindow(title: "Configurer Meeting Incoming")

        controller.bringToFront()
        controller.closeAfterSetUpLater()
        registry.register(futureWindow, for: .onboarding)

        XCTAssertTrue(registry.window(for: .onboarding) === futureWindow)
        XCTAssertFalse(futureWindow.isVisible)
    }

    func testOnboardingCloseTargetsTheRegisteredWindowRegardlessOfTitle() {
        let registry = WindowRegistry()
        let controller = OnboardingWindowController(windowRegistry: registry)
        let localizedWindow = makeWindow(title: "Meeting Incoming einrichten")
        localizedWindow.orderFrontRegardless()
        registry.register(localizedWindow, for: .onboarding)

        controller.closeAfterSetUpLater()

        XCTAssertFalse(localizedWindow.isVisible)
    }

    private func makeWindow(title: String) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        return window
    }
}
