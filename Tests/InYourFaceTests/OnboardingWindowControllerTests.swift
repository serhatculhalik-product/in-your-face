import AppKit
import XCTest
@testable import InYourFace

@MainActor
final class OnboardingWindowControllerTests: XCTestCase {
    func testReadinessNativeClosePresentsOneFinishableDecision() {
        let fixture = makeFixture(canFinishSetup: true)
        defer { fixture.cleanUp() }

        fixture.window.performClose(nil)
        fixture.window.performClose(nil)

        XCTAssertTrue(fixture.window.isVisible)
        XCTAssertEqual(fixture.presenter.presentations.count, 1)
        XCTAssertEqual(
            fixture.presenter.presentations[0].prompt,
            OnboardingReadinessClosePrompt(
                title: "Finish setting up Meeting Incoming?",
                message: "Your reminder and Start at Login choices aren’t applied until you finish setup or choose Finish Later.",
                actions: [.finishSetup, .finishLater, .continueSetup]
            )
        )
    }

    func testUserCloseRoutesUseTheSameReadinessHandler() throws {
        let fixture = makeFixture(canFinishSetup: true)
        defer { fixture.cleanUp() }

        let closeButton = try XCTUnwrap(
            fixture.window.standardWindowButton(.closeButton)
        )
        closeButton.performClick(nil)
        XCTAssertEqual(fixture.presenter.presentations.count, 1)
        fixture.presenter.respond(with: .continueSetup)

        let originalMainMenu = NSApp.mainMenu
        let originalApplicationResponder = NSApp.nextResponder
        let closeCommandResponder = OnboardingWindowCloseCommandResponder(
            window: fixture.window
        )
        closeCommandResponder.nextResponder = originalApplicationResponder
        NSApp.nextResponder = closeCommandResponder
        defer {
            NSApp.mainMenu = originalMainMenu
            NSApp.nextResponder = originalApplicationResponder
        }
        let mainMenu = NSMenu()
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.autoenablesItems = false
        let closeItem = NSMenuItem(
            title: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeItem.keyEquivalentModifierMask = [.command]
        windowMenu.addItem(closeItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.mainMenu = mainMenu
        NSApp.activate(ignoringOtherApps: true)
        fixture.window.makeKeyAndOrderFront(nil)
        drainMainQueue()
        let commandW = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: fixture.window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))

        XCTAssertTrue(mainMenu.performKeyEquivalent(with: commandW))
        XCTAssertEqual(fixture.presenter.presentations.count, 2)
        fixture.presenter.respond(with: .continueSetup)

        fixture.window.performClose(nil)
        XCTAssertEqual(fixture.presenter.presentations.count, 3)
        XCTAssertTrue(fixture.window.isVisible)
        fixture.presenter.respond(with: .continueSetup)

        _ = closeButton.accessibilityPerformPress()
        XCTAssertEqual(fixture.presenter.presentations.count, 4)
        XCTAssertTrue(fixture.window.isVisible)
    }

    func testNonFinishableReadinessOmitsFinishSetup() {
        let fixture = makeFixture(canFinishSetup: false)
        defer { fixture.cleanUp() }

        fixture.window.performClose(nil)

        XCTAssertEqual(
            fixture.presenter.presentations.single?.prompt.actions,
            [.finishLater, .continueSetup]
        )
        fixture.controller.resolveReadinessExit(.finishSetup)
        XCTAssertTrue(fixture.resolvedOutcomes.isEmpty)
        XCTAssertTrue(fixture.window.isVisible)
    }

    func testContinueSetupDismissesOnlyTheDecisionAndAllowsAnotherCloseRequest() {
        let fixture = makeFixture(canFinishSetup: true)
        defer { fixture.cleanUp() }

        fixture.window.performClose(nil)
        fixture.presenter.respond(with: .continueSetup)

        XCTAssertTrue(fixture.resolvedOutcomes.isEmpty)
        XCTAssertTrue(fixture.window.isVisible)

        fixture.window.performClose(nil)
        XCTAssertEqual(fixture.presenter.presentations.count, 2)
    }

    func testSuccessfulSheetOutcomeClosesOnceAndTheBypassIsOneShot() {
        let fixture = makeFixture(canFinishSetup: true)
        defer { fixture.cleanUp() }

        fixture.window.performClose(nil)
        fixture.presenter.respond(with: .finishSetup)
        fixture.window.performClose(nil)
        drainMainQueue()

        XCTAssertEqual(fixture.resolvedOutcomes, [.finishSetup])
        XCTAssertEqual(fixture.presenter.presentations.count, 1)
        XCTAssertEqual(fixture.closeRecorder.closeCount, 1)
        XCTAssertFalse(fixture.window.isVisible)

        fixture.window.orderFrontRegardless()
        fixture.window.performClose(nil)

        XCTAssertTrue(fixture.window.isVisible)
        XCTAssertEqual(fixture.presenter.presentations.count, 2)
        XCTAssertEqual(fixture.closeRecorder.closeCount, 1)
    }

    func testSuccessfulFinishLaterSheetUsesOneShotBypass() {
        let fixture = makeFixture(canFinishSetup: true)
        defer { fixture.cleanUp() }

        fixture.window.performClose(nil)
        fixture.presenter.respond(with: .finishLater)
        drainMainQueue()

        XCTAssertEqual(fixture.resolvedOutcomes, [.finishLater])
        XCTAssertEqual(fixture.closeRecorder.closeCount, 1)
        XCTAssertFalse(fixture.window.isVisible)

        fixture.window.orderFrontRegardless()
        fixture.window.performClose(nil)

        XCTAssertTrue(fixture.window.isVisible)
        XCTAssertEqual(fixture.presenter.presentations.count, 2)
    }

    func testSetUpLaterCloseBypassIsOneShot() {
        let fixture = makeFixture(canFinishSetup: true)
        defer { fixture.cleanUp() }

        fixture.controller.closeAfterSetUpLater()

        XCTAssertEqual(fixture.closeRecorder.closeCount, 1)
        XCTAssertFalse(fixture.window.isVisible)

        fixture.window.orderFrontRegardless()
        fixture.window.performClose(nil)

        XCTAssertTrue(fixture.window.isVisible)
        XCTAssertEqual(fixture.presenter.presentations.count, 1)
    }

    func testOpenDecisionRefreshesWhenReadinessBecomesNonFinishable() {
        let fixture = makeFixture(canFinishSetup: true)
        defer { fixture.cleanUp() }

        fixture.window.performClose(nil)
        fixture.controller.configureReadinessExit(canFinishSetup: false) { _ in true }
        drainMainQueue()

        XCTAssertEqual(fixture.presenter.presentations.count, 2)
        XCTAssertEqual(
            fixture.presenter.presentations[1].prompt.actions,
            [.finishLater, .continueSetup]
        )

        fixture.presenter.respond(with: .finishSetup, presentation: 0)
        drainMainQueue()
        XCTAssertTrue(fixture.window.isVisible)
        XCTAssertEqual(fixture.closeRecorder.closeCount, 0)
    }

    func testSheetOutcomeClosesThePromptedWindowWhenRegistryIsReplaced() {
        let fixture = makeFixture(canFinishSetup: true)
        let replacementWindow = makeWindow()
        replacementWindow.orderFrontRegardless()
        defer {
            replacementWindow.close()
            fixture.cleanUp()
        }

        fixture.window.performClose(nil)
        fixture.registry.register(replacementWindow, for: .onboarding)
        fixture.controller.configureReadinessExit(canFinishSetup: true) { _ in true }
        fixture.presenter.respond(with: .finishLater)
        replacementWindow.performClose(nil)

        XCTAssertEqual(fixture.presenter.presentations.count, 1)
        XCTAssertTrue(replacementWindow.isVisible)

        drainMainQueue()

        XCTAssertFalse(fixture.window.isVisible)
        XCTAssertEqual(fixture.closeRecorder.closeCount, 1)
        XCTAssertTrue(replacementWindow.isVisible)
    }

    func testEachInterceptedWindowKeepsItsOwnForwardedDelegate() {
        let registry = WindowRegistry()
        let presenter = OnboardingReadinessDecisionPresenterSpy()
        let controller = OnboardingWindowController(
            windowRegistry: registry,
            decisionPresenter: presenter
        )
        let firstWindow = makeWindow()
        let secondWindow = makeWindow()
        let firstDelegate = OnboardingWindowDelegateSpy(shouldClose: false)
        let secondDelegate = OnboardingWindowDelegateSpy(shouldClose: false)
        firstWindow.delegate = firstDelegate
        secondWindow.delegate = secondDelegate
        defer {
            firstWindow.close()
            secondWindow.close()
        }

        registry.register(firstWindow, for: .onboarding)
        controller.configureReadinessExit(canFinishSetup: true) { _ in true }
        controller.bringToFront()
        registry.register(secondWindow, for: .onboarding)
        controller.configureReadinessExit(canFinishSetup: true) { _ in true }
        secondWindow.orderFrontRegardless()
        controller.clearReadinessExit()

        firstWindow.performClose(nil)
        secondWindow.performClose(nil)

        XCTAssertEqual(firstDelegate.shouldCloseCallCount, 1)
        XCTAssertEqual(secondDelegate.shouldCloseCallCount, 1)
        XCTAssertTrue(firstWindow.isVisible)
        XCTAssertTrue(secondWindow.isVisible)
    }

    func testExplicitOutcomeCannotBeVetoedByForwardedDelegate() {
        let registry = WindowRegistry()
        let presenter = OnboardingReadinessDecisionPresenterSpy()
        let window = makeWindow()
        let forwardedDelegate = OnboardingWindowDelegateSpy(shouldClose: false)
        window.delegate = forwardedDelegate
        let closeRecorder = OnboardingWindowCloseRecorder(window: window)
        let controller = OnboardingWindowController(
            windowRegistry: registry,
            decisionPresenter: presenter
        )
        registry.register(window, for: .onboarding)
        controller.configureReadinessExit(canFinishSetup: true) { _ in true }
        controller.bringToFront()
        defer {
            closeRecorder.stop()
            window.close()
        }

        controller.resolveReadinessExit(.finishSetup)

        XCTAssertEqual(closeRecorder.closeCount, 1)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(forwardedDelegate.shouldCloseCallCount, 0)
    }

    func testFailedSheetOutcomesKeepReadinessOpenAndRetryable() {
        for action in [
            OnboardingReadinessExitAction.finishSetup,
            .finishLater,
        ] {
            let fixture = makeFixture(canFinishSetup: true, resolutionSucceeds: false)

            fixture.window.performClose(nil)
            fixture.presenter.respond(with: action)

            XCTAssertEqual(fixture.resolvedOutcomes, [action])
            XCTAssertTrue(fixture.window.isVisible)
            XCTAssertEqual(fixture.closeRecorder.closeCount, 0)

            fixture.window.performClose(nil)
            XCTAssertEqual(fixture.presenter.presentations.count, 2)
            fixture.cleanUp()
        }
    }

    func testFooterOutcomesUseTheSameResolverAndExplicitClosePath() {
        for action in [
            OnboardingReadinessExitAction.finishSetup,
            .finishLater,
        ] {
            let fixture = makeFixture(canFinishSetup: true)

            fixture.controller.resolveReadinessExit(action)

            XCTAssertEqual(fixture.resolvedOutcomes, [action])
            XCTAssertEqual(fixture.closeRecorder.closeCount, 1)
            XCTAssertFalse(fixture.window.isVisible)
            XCTAssertTrue(fixture.presenter.presentations.isEmpty)
            fixture.cleanUp()
        }
    }

    func testCloseOutsideReadinessKeepsExistingBehavior() {
        let fixture = makeFixture(canFinishSetup: nil)
        defer { fixture.cleanUp() }

        fixture.window.performClose(nil)

        XCTAssertEqual(fixture.closeRecorder.closeCount, 1)
        XCTAssertFalse(fixture.window.isVisible)
        XCTAssertTrue(fixture.presenter.presentations.isEmpty)
    }

    func testNativePresenterAttachesOnlyOneSheet() throws {
        let registry = WindowRegistry()
        let window = makeWindow()
        let controller = OnboardingWindowController(windowRegistry: registry)
        registry.register(window, for: .onboarding)
        controller.configureReadinessExit(canFinishSetup: true) { _ in false }
        controller.bringToFront()
        defer {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet, returnCode: .cancel)
            }
            window.close()
        }

        window.performClose(nil)
        window.performClose(nil)

        let sheet = try XCTUnwrap(window.attachedSheet)
        XCTAssertEqual(window.sheets.count, 1)
        let buttons = sheet.contentView?
            .subviewsRecursively
            .compactMap { $0 as? NSButton }
        XCTAssertEqual(
            Set(buttons?.map(\.title) ?? []),
            Set(["Finish Setup", "Finish Later", "Continue Setup"])
        )
        XCTAssertEqual(
            sheet.defaultButtonCell?.title,
            "Finish Setup"
        )
        XCTAssertEqual(
            buttons?.first(where: { $0.title == "Continue Setup" })?.keyEquivalent,
            "\u{1b}"
        )
    }

    func testNativeSheetOutcomeClosesAfterTheSheetEnds() throws {
        let registry = WindowRegistry()
        let window = makeWindow()
        let closeRecorder = OnboardingWindowCloseRecorder(window: window)
        let controller = OnboardingWindowController(windowRegistry: registry)
        registry.register(window, for: .onboarding)
        controller.configureReadinessExit(canFinishSetup: true) { _ in true }
        controller.bringToFront()
        defer {
            closeRecorder.stop()
            if let sheet = window.attachedSheet {
                window.endSheet(sheet, returnCode: .cancel)
            }
            window.close()
        }

        window.performClose(nil)
        let sheet = try XCTUnwrap(window.attachedSheet)
        let finishLaterButton = try XCTUnwrap(
            sheet.contentView?.subviewsRecursively
                .compactMap { $0 as? NSButton }
                .first { $0.title == "Finish Later" }
        )

        finishLaterButton.performClick(nil)
        drainMainQueue(duration: 0.2)

        XCTAssertNil(window.attachedSheet)
        XCTAssertEqual(closeRecorder.closeCount, 1)
        XCTAssertFalse(window.isVisible)
    }

    func testNativeSheetRefreshesToCurrentNonFinishableActions() throws {
        let registry = WindowRegistry()
        let window = makeWindow()
        let controller = OnboardingWindowController(windowRegistry: registry)
        registry.register(window, for: .onboarding)
        controller.configureReadinessExit(canFinishSetup: true) { _ in false }
        controller.bringToFront()
        defer {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet, returnCode: .cancel)
            }
            window.close()
        }

        window.performClose(nil)
        XCTAssertNotNil(window.attachedSheet)

        controller.configureReadinessExit(canFinishSetup: false) { _ in false }
        drainMainQueue(duration: 0.2)

        let refreshedSheet = try XCTUnwrap(window.attachedSheet)
        let buttonTitles = Set(
            refreshedSheet.contentView?.subviewsRecursively
                .compactMap { ($0 as? NSButton)?.title } ?? []
        )
        XCTAssertEqual(buttonTitles, Set(["Finish Later", "Continue Setup"]))
        XCTAssertNil(refreshedSheet.defaultButtonCell)
    }

    func testEscapeCancelsTheNativeSheetWithoutResolvingOrClosing() throws {
        let registry = WindowRegistry()
        let window = makeWindow()
        var resolvedActions: [OnboardingReadinessExitAction] = []
        let closeRecorder = OnboardingWindowCloseRecorder(window: window)
        let controller = OnboardingWindowController(windowRegistry: registry)
        registry.register(window, for: .onboarding)
        controller.configureReadinessExit(canFinishSetup: true) { action in
            resolvedActions.append(action)
            return true
        }
        controller.bringToFront()
        defer {
            closeRecorder.stop()
            if let sheet = window.attachedSheet {
                window.endSheet(sheet, returnCode: .cancel)
            }
            window.close()
        }

        window.performClose(nil)
        let sheet = try XCTUnwrap(window.attachedSheet)
        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: sheet.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))

        XCTAssertTrue(sheet.performKeyEquivalent(with: escape))
        drainMainQueue(duration: 0.2)

        XCTAssertNil(window.attachedSheet)
        XCTAssertTrue(resolvedActions.isEmpty)
        XCTAssertEqual(closeRecorder.closeCount, 0)
        XCTAssertTrue(window.isVisible)
    }

    private func makeFixture(
        canFinishSetup: Bool?,
        resolutionSucceeds: Bool = true
    ) -> OnboardingWindowControllerFixture {
        OnboardingWindowControllerFixture(
            canFinishSetup: canFinishSetup,
            resolutionSucceeds: resolutionSucceeds
        )
    }

    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private func drainMainQueue(duration: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }
}

@MainActor
private final class OnboardingWindowControllerFixture {
    let registry = WindowRegistry()
    let presenter = OnboardingReadinessDecisionPresenterSpy()
    let window: NSWindow
    let controller: OnboardingWindowController
    let closeRecorder: OnboardingWindowCloseRecorder
    private(set) var resolvedOutcomes: [OnboardingReadinessExitAction] = []

    init(canFinishSetup: Bool?, resolutionSucceeds: Bool) {
        _ = NSApplication.shared
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        closeRecorder = OnboardingWindowCloseRecorder(window: window)
        controller = OnboardingWindowController(
            windowRegistry: registry,
            decisionPresenter: presenter
        )
        registry.register(window, for: .onboarding)
        if let canFinishSetup {
            controller.configureReadinessExit(canFinishSetup: canFinishSetup) { [weak self] outcome in
                self?.resolvedOutcomes.append(outcome)
                return resolutionSucceeds
            }
        }
        controller.bringToFront()
    }

    func cleanUp() {
        closeRecorder.stop()
        if let sheet = window.attachedSheet {
            window.endSheet(sheet, returnCode: .cancel)
        }
        window.close()
    }
}

@MainActor
private final class OnboardingReadinessDecisionPresenterSpy:
    OnboardingReadinessDecisionPresenting
{
    struct Presentation {
        let prompt: OnboardingReadinessClosePrompt
        let window: NSWindow
        let completion: @MainActor (OnboardingReadinessExitAction) -> Void
    }

    private(set) var presentations: [Presentation] = []

    func present(
        _ prompt: OnboardingReadinessClosePrompt,
        for window: NSWindow,
        completion: @escaping @MainActor (OnboardingReadinessExitAction) -> Void
    ) {
        presentations.append(Presentation(
            prompt: prompt,
            window: window,
            completion: completion
        ))
    }

    func respond(
        with action: OnboardingReadinessExitAction,
        presentation index: Int? = nil
    ) {
        let resolvedIndex = index ?? presentations.index(before: presentations.endIndex)
        presentations[resolvedIndex].completion(action)
    }
}

@MainActor
private final class OnboardingWindowCloseRecorder {
    private(set) var closeCount = 0
    private var observer: NSObjectProtocol?

    init(window: NSWindow) {
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closeCount += 1
            }
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }
}

@MainActor
private final class OnboardingWindowCloseCommandResponder: NSResponder {
    private weak var window: NSWindow?

    init(window: NSWindow) {
        self.window = window
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func performClose(_ sender: Any?) {
        window?.performClose(sender)
    }
}

@MainActor
private final class OnboardingWindowDelegateSpy: NSObject, NSWindowDelegate {
    private let shouldClose: Bool
    private(set) var shouldCloseCallCount = 0

    init(shouldClose: Bool) {
        self.shouldClose = shouldClose
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        shouldCloseCallCount += 1
        return shouldClose
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}

private extension NSView {
    var subviewsRecursively: [NSView] {
        subviews + subviews.flatMap(\.subviewsRecursively)
    }
}
