import AppKit
import XCTest
@testable import InYourFace

@MainActor
final class RuntimeWindowStateTests: XCTestCase {
    func testResetQuarantineHidesApplicationWindowAndDisablesRestoration() {
        resetRuntimeWindowQuarantine()
        let window = makeVisibleWindow()
        defer {
            RuntimeWindowQuarantine.update(isActive: false)
            window.close()
        }
        _ = window.setFrameAutosaveName("settings-window")
        let policy = RuntimeWindowStatePolicy.applicationWindow(
            isTestProfile: false,
            isResetQuarantined: true
        )

        policy.apply(to: window)

        XCTAssertFalse(policy.allowsInteraction)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isRestorable)
        XCTAssertEqual(window.frameAutosaveName, "")
    }

    func testResetQuarantineKeepsApplicationWindowHiddenAfterAnotherPresentation() {
        resetRuntimeWindowQuarantine()
        let window = makeVisibleWindow()
        defer {
            RuntimeWindowQuarantine.update(isActive: false)
            window.close()
        }
        let policy = RuntimeWindowStatePolicy.applicationWindow(
            isTestProfile: false,
            isResetQuarantined: true
        )
        policy.apply(to: window)
        RuntimeWindowQuarantine.update(isActive: true)

        window.orderFrontRegardless()

        XCTAssertFalse(window.isVisible)
    }

    func testResetQuarantineHidesDelegateManagedWindowWithoutClosingIt() {
        resetRuntimeWindowQuarantine()
        let window = makeVisibleWindow()
        let closeVeto = CloseVetoingWindowDelegate()
        window.delegate = closeVeto
        let closeRecorder = WindowCloseRecorder(window: window)
        defer {
            RuntimeWindowQuarantine.update(isActive: false)
            closeRecorder.stop()
            window.close()
        }
        let policy = RuntimeWindowStatePolicy.applicationWindow(
            isTestProfile: false,
            isResetQuarantined: true
        )

        policy.apply(to: window)

        withExtendedLifetime(closeVeto) {
            XCTAssertFalse(window.isVisible)
        }
        XCTAssertEqual(closeRecorder.closeCount, 0)
    }

    func testResetQuarantineRejectsOnboardingPresentationAfterHidingWindow() {
        resetRuntimeWindowQuarantine()
        let registry = WindowRegistry()
        let controller = OnboardingWindowController(windowRegistry: registry)
        let window = makeVisibleWindow()
        defer {
            RuntimeWindowQuarantine.update(isActive: false)
            window.close()
        }
        registry.register(window, for: .onboarding)
        RuntimeWindowStatePolicy.applicationWindow(
            isTestProfile: false,
            isResetQuarantined: true
        ).apply(to: window)
        RuntimeWindowQuarantine.update(isActive: true)

        controller.bringToFront()

        XCTAssertFalse(window.isVisible)
    }

    func testResetQuarantineHidesExistingProgrammaticPanel() {
        resetRuntimeWindowQuarantine()
        let applicationWindow = makeVisibleWindow()
        let programmaticPanel = makeVisiblePanel()
        let quarantine = RuntimeWindowStatePolicy.applicationWindow(
            isTestProfile: false,
            isResetQuarantined: true
        )
        defer {
            RuntimeWindowQuarantine.update(isActive: false)
            RuntimeWindowStatePolicy.applicationWindow(
                isTestProfile: false,
                isResetQuarantined: false
            ).apply(to: applicationWindow)
            programmaticPanel.close()
            applicationWindow.close()
        }

        quarantine.apply(to: applicationWindow)
        RuntimeWindowQuarantine.update(isActive: true)

        XCTAssertFalse(programmaticPanel.isVisible)
    }

    func testResetQuarantineHidesProgrammaticPanelCreatedAfterActivation() {
        resetRuntimeWindowQuarantine()
        let applicationWindow = makeVisibleWindow()
        let quarantine = RuntimeWindowStatePolicy.applicationWindow(
            isTestProfile: false,
            isResetQuarantined: true
        )
        quarantine.apply(to: applicationWindow)
        RuntimeWindowQuarantine.update(isActive: true)
        let programmaticPanel = makeVisibleShieldPanel()
        defer {
            RuntimeWindowQuarantine.update(isActive: false)
            RuntimeWindowStatePolicy.applicationWindow(
                isTestProfile: false,
                isResetQuarantined: false
            ).apply(to: applicationWindow)
            programmaticPanel.close()
            applicationWindow.close()
        }

        XCTAssertFalse(programmaticPanel.isVisible)
    }

    func testApplicationQuarantineHidesProgrammaticPanelWithoutApplicationWindow() {
        resetRuntimeWindowQuarantine()
        let programmaticPanel = makeVisiblePanel()
        defer {
            RuntimeWindowQuarantine.update(isActive: false)
            programmaticPanel.close()
        }

        RuntimeWindowQuarantine.update(isActive: true)

        XCTAssertFalse(programmaticPanel.isVisible)
    }

    func testApplicationWindowCanBePresentedAfterResetQuarantineEnds() {
        resetRuntimeWindowQuarantine()
        let window = makeVisibleWindow()
        defer {
            RuntimeWindowQuarantine.update(isActive: false)
            window.close()
        }
        RuntimeWindowStatePolicy.applicationWindow(
            isTestProfile: false,
            isResetQuarantined: true
        ).apply(to: window)

        RuntimeWindowQuarantine.update(isActive: true)
        RuntimeWindowQuarantine.update(isActive: false)
        RuntimeWindowStatePolicy.applicationWindow(
            isTestProfile: false,
            isResetQuarantined: false
        ).apply(to: window)
        window.orderFrontRegardless()

        XCTAssertTrue(window.isVisible)
    }

    func testTestToolsWindowRemainsAvailableDuringResetQuarantine() {
        resetRuntimeWindowQuarantine()
        let window = makeVisibleWindow()
        defer { window.close() }

        RuntimeWindowStatePolicy.testTools.apply(to: window)
        window.close()
        window.orderFrontRegardless()

        XCTAssertTrue(RuntimeWindowStatePolicy.testTools.allowsInteraction)
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.isRestorable)
    }

    func testResetQuarantinePreservesTestToolsWindowAndOwnedPanel() {
        resetRuntimeWindowQuarantine()
        let applicationWindow = makeVisibleWindow()
        let testToolsWindow = makeVisibleWindow()
        RuntimeWindowStatePolicy.testTools.apply(to: testToolsWindow)
        let testToolsPanel = makeVisiblePanel()
        testToolsWindow.addChildWindow(testToolsPanel, ordered: .above)
        defer {
            RuntimeWindowQuarantine.update(isActive: false)
            RuntimeWindowStatePolicy.applicationWindow(
                isTestProfile: false,
                isResetQuarantined: false
            ).apply(to: applicationWindow)
            testToolsWindow.removeChildWindow(testToolsPanel)
            testToolsPanel.close()
            testToolsWindow.close()
            applicationWindow.close()
        }

        RuntimeWindowQuarantine.update(isActive: true)
        RuntimeWindowStatePolicy.applicationWindow(
            isTestProfile: false,
            isResetQuarantined: true
        ).apply(to: applicationWindow)
        testToolsWindow.orderFrontRegardless()
        testToolsPanel.orderFrontRegardless()

        XCTAssertTrue(testToolsWindow.isVisible)
        XCTAssertTrue(testToolsPanel.isVisible)
    }

    func testTestToolsCanBePresentedWhenRoleArrivesAfterBootQuarantine() {
        resetRuntimeWindowQuarantine()
        RuntimeWindowQuarantine.update(isActive: true)
        let testToolsWindow = makeVisibleWindow()
        let testToolsPanel = makeVisiblePanel()
        testToolsWindow.addChildWindow(testToolsPanel, ordered: .above)
        defer {
            RuntimeWindowQuarantine.update(isActive: false)
            testToolsWindow.removeChildWindow(testToolsPanel)
            testToolsPanel.close()
            testToolsWindow.close()
        }
        XCTAssertFalse(testToolsWindow.isVisible)
        XCTAssertFalse(testToolsPanel.isVisible)

        RuntimeWindowStatePolicy.testTools.apply(to: testToolsWindow)
        testToolsWindow.orderFrontRegardless()
        testToolsPanel.orderFrontRegardless()

        XCTAssertTrue(testToolsWindow.isVisible)
        XCTAssertTrue(testToolsPanel.isVisible)
    }

    private func makeVisibleWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isRestorable = true
        window.orderFrontRegardless()
        return window
    }

    private func makeVisiblePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        return panel
    }

    private func makeVisibleShieldPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        return panel
    }

    private func resetRuntimeWindowQuarantine() {
        RuntimeWindowQuarantine.update(isActive: false)
    }
}

private final class CloseVetoingWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        false
    }
}

private final class WindowCloseRecorder: @unchecked Sendable {
    private var observer: NSObjectProtocol?
    private(set) var closeCount = 0

    init(window: NSWindow) {
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.closeCount += 1
        }
    }

    func stop() {
        guard let observer else { return }
        NotificationCenter.default.removeObserver(observer)
        self.observer = nil
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
