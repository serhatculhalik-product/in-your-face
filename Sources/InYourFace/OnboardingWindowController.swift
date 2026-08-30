import AppKit

enum OnboardingReadinessExitAction: Equatable {
    case finishSetup
    case finishLater
    case continueSetup

    var title: String {
        switch self {
        case .finishSetup:
            "Finish Setup"
        case .finishLater:
            "Finish Later"
        case .continueSetup:
            "Continue Setup"
        }
    }
}

struct OnboardingReadinessClosePrompt: Equatable {
    let title: String
    let message: String
    let actions: [OnboardingReadinessExitAction]

    static func make(canFinishSetup: Bool) -> Self {
        Self(
            title: "Finish setting up Meeting Incoming?",
            message: "Your reminder and Start at Login choices aren’t applied until you finish setup or choose Finish Later.",
            actions: canFinishSetup
                ? [.finishSetup, .finishLater, .continueSetup]
                : [.finishLater, .continueSetup]
        )
    }
}

@MainActor
protocol OnboardingReadinessDecisionPresenting: AnyObject {
    func present(
        _ prompt: OnboardingReadinessClosePrompt,
        for window: NSWindow,
        completion: @escaping @MainActor (OnboardingReadinessExitAction) -> Void
    )
}

@MainActor
private final class NativeOnboardingReadinessDecisionPresenter:
    OnboardingReadinessDecisionPresenting
{
    func present(
        _ prompt: OnboardingReadinessClosePrompt,
        for window: NSWindow,
        completion: @escaping @MainActor (OnboardingReadinessExitAction) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = prompt.title
        alert.informativeText = prompt.message

        var actionByResponse: [NSApplication.ModalResponse: OnboardingReadinessExitAction] = [:]
        for (index, action) in prompt.actions.enumerated() {
            let button = alert.addButton(withTitle: action.title)
            button.keyEquivalentModifierMask = []
            switch action {
            case .finishSetup:
                button.keyEquivalent = "\r"
            case .finishLater:
                button.keyEquivalent = ""
            case .continueSetup:
                button.keyEquivalent = "\u{1b}"
            }
            actionByResponse[NSApplication.ModalResponse(
                rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index
            )] = action
        }

        if !prompt.actions.contains(.finishSetup) {
            alert.window.defaultButtonCell = nil
        }

        alert.beginSheetModal(for: window) { response in
            completion(actionByResponse[response] ?? .continueSetup)
        }
    }
}

@MainActor
private final class OnboardingWindowDelegateProxy: NSObject, NSWindowDelegate {
    weak var controller: OnboardingWindowController?
    nonisolated(unsafe) weak var forwardedDelegate: (any NSWindowDelegate)?

    init(controller: OnboardingWindowController) {
        self.controller = controller
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let decision = controller?.readinessCloseDecision(for: sender) {
            return decision
        }
        return forwardedDelegate?.windowShouldClose?(sender) ?? true
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) {
            return true
        }
        return forwardedDelegate?.responds(to: selector) ?? false
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        guard forwardedDelegate?.responds(to: selector) == true else {
            return super.forwardingTarget(for: selector)
        }
        return forwardedDelegate
    }
}

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private struct ReadinessExitConfiguration {
        let canFinishSetup: Bool
        let resolve: @MainActor (OnboardingReadinessExitAction) -> Bool
    }

    private enum ReadinessOutcomeResolution: Equatable {
        case cancelled
        case unavailable
        case failed
        case succeeded
    }

    private final class ActiveDecision {
        let id: UUID
        weak var window: NSWindow?

        init(window: NSWindow) {
            id = UUID()
            self.window = window
        }
    }

    private struct InterceptedWindow {
        weak var window: NSWindow?
        let delegateProxy: OnboardingWindowDelegateProxy
    }

    private let windowRegistry: WindowRegistry
    private let decisionPresenter: any OnboardingReadinessDecisionPresenting
    private var didShowOnboardingAtLaunch = false
    private var readinessExitConfiguration: ReadinessExitConfiguration?
    private var activeDecision: ActiveDecision?
    private var pendingDecisionPresentationID: UUID?
    private weak var pendingDecisionWindow: NSWindow?
    private var pendingExplicitCloseWindowID: ObjectIdentifier?
    private var explicitlyAllowedCloseWindowID: ObjectIdentifier?
    private var interceptedWindows: [ObjectIdentifier: InterceptedWindow] = [:]
    private lazy var pendingBringToFront = PendingWindowPresentation<Void>(
        registry: windowRegistry,
        kind: .onboarding
    ) { [weak self] window, _ in
        guard let self else { return }
        installCloseInterception(on: window)
        NSApp.activate(ignoringOtherApps: true)
        window.level = .normal
        window.hidesOnDeactivate = false
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    init(
        windowRegistry: WindowRegistry = .shared,
        decisionPresenter: any OnboardingReadinessDecisionPresenting =
            NativeOnboardingReadinessDecisionPresenter()
    ) {
        self.windowRegistry = windowRegistry
        self.decisionPresenter = decisionPresenter
    }

    func show(using openWindow: @escaping @MainActor () -> Void) {
        openWindow()
        bringToFront()
    }

    func showAtLaunch(using openWindow: @escaping @MainActor () -> Void) {
        guard !didShowOnboardingAtLaunch else { return }
        didShowOnboardingAtLaunch = true
        show(using: openWindow)
    }

    func configureReadinessExit(
        canFinishSetup: Bool,
        resolve: @escaping @MainActor (OnboardingReadinessExitAction) -> Bool
    ) {
        let previousCanFinishSetup = readinessExitConfiguration?.canFinishSetup
        readinessExitConfiguration = ReadinessExitConfiguration(
            canFinishSetup: canFinishSetup,
            resolve: resolve
        )
        if let window = windowRegistry.window(for: .onboarding) {
            installCloseInterception(on: window)
        }
        guard previousCanFinishSetup != nil,
              previousCanFinishSetup != canFinishSetup,
              let window = activeDecision?.window ?? pendingDecisionWindow else { return }
        refreshDecisionPresentation(on: window)
    }

    func clearReadinessExit() {
        readinessExitConfiguration = nil
        pendingDecisionPresentationID = nil
        pendingDecisionWindow = nil
        guard let decision = activeDecision else { return }
        activeDecision = nil
        if let window = decision.window, let sheet = window.attachedSheet {
            window.endSheet(sheet, returnCode: .cancel)
        }
    }

    func resolveReadinessExit(_ action: OnboardingReadinessExitAction) {
        guard pendingExplicitCloseWindowID == nil,
              let configuration = readinessExitConfiguration,
              let window = windowRegistry.window(for: .onboarding),
              resolve(action, using: configuration) == .succeeded else { return }
        closeAfterExplicitOutcome(window)
    }

    func closeAfterSetUpLater() {
        guard pendingExplicitCloseWindowID == nil else { return }
        pendingBringToFront.clear()
        guard let window = windowRegistry.window(for: .onboarding) else { return }
        closeAfterExplicitOutcome(window)
    }

    func bringToFront() {
        pendingBringToFront.submit(())
    }

    /// Returns nil when the existing window delegate should decide.
    fileprivate func readinessCloseDecision(for window: NSWindow) -> Bool? {
        let windowID = ObjectIdentifier(window)
        if pendingExplicitCloseWindowID != nil {
            return false
        }
        if explicitlyAllowedCloseWindowID == windowID {
            explicitlyAllowedCloseWindowID = nil
            return true
        }

        guard let configuration = readinessExitConfiguration else { return nil }
        guard activeDecision == nil,
              pendingDecisionPresentationID == nil else { return false }
        presentDecision(using: configuration, on: window)
        return false
    }

    private func handleDecision(
        _ action: OnboardingReadinessExitAction,
        matching decision: ActiveDecision
    ) {
        guard activeDecision?.id == decision.id,
              let window = decision.window else { return }
        activeDecision = nil
        guard let configuration = readinessExitConfiguration else { return }
        switch resolve(action, using: configuration) {
        case .unavailable:
            refreshDecisionPresentation(on: window)
            return
        case .cancelled, .failed:
            return
        case .succeeded:
            break
        }

        // AppKit can invoke a sheet completion before its parent is ready to close.
        // Closing on the next main-loop turn also keeps the bypass scoped to this
        // exact prompted window.
        let windowID = ObjectIdentifier(window)
        pendingExplicitCloseWindowID = windowID
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self,
                  self.pendingExplicitCloseWindowID == windowID else { return }
            self.pendingExplicitCloseWindowID = nil
            guard let window else { return }
            self.closeAfterExplicitOutcome(window)
        }
    }

    private func resolve(
        _ action: OnboardingReadinessExitAction,
        using configuration: ReadinessExitConfiguration
    ) -> ReadinessOutcomeResolution {
        guard action != .continueSetup else { return .cancelled }
        guard action != .finishSetup || configuration.canFinishSetup else {
            return .unavailable
        }
        return configuration.resolve(action) ? .succeeded : .failed
    }

    private func presentDecision(
        using configuration: ReadinessExitConfiguration,
        on window: NSWindow
    ) {
        let decision = ActiveDecision(window: window)
        activeDecision = decision
        decisionPresenter.present(
            .make(canFinishSetup: configuration.canFinishSetup),
            for: window
        ) { [weak self] action in
            self?.handleDecision(action, matching: decision)
        }
    }

    private func refreshDecisionPresentation(on window: NSWindow) {
        activeDecision = nil
        let presentationID = UUID()
        pendingDecisionPresentationID = presentationID
        pendingDecisionWindow = window
        if let sheet = window.attachedSheet {
            window.endSheet(sheet, returnCode: .cancel)
        }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window,
                  self.pendingDecisionPresentationID == presentationID,
                  let configuration = self.readinessExitConfiguration else { return }
            self.pendingDecisionPresentationID = nil
            self.pendingDecisionWindow = nil
            guard self.activeDecision == nil, window.isVisible else { return }
            self.presentDecision(using: configuration, on: window)
        }
    }

    private func closeAfterExplicitOutcome(_ window: NSWindow) {
        pendingBringToFront.clear()
        installCloseInterception(on: window)
        let windowID = ObjectIdentifier(window)
        explicitlyAllowedCloseWindowID = windowID
        window.performClose(nil)
        if explicitlyAllowedCloseWindowID == windowID {
            explicitlyAllowedCloseWindowID = nil
        }
    }

    private func installCloseInterception(on window: NSWindow) {
        interceptedWindows = interceptedWindows.filter { $0.value.window != nil }
        let windowID = ObjectIdentifier(window)
        let delegateProxy: OnboardingWindowDelegateProxy
        if let interceptedWindow = interceptedWindows[windowID],
           interceptedWindow.window === window {
            delegateProxy = interceptedWindow.delegateProxy
        } else {
            delegateProxy = OnboardingWindowDelegateProxy(controller: self)
            interceptedWindows[windowID] = InterceptedWindow(
                window: window,
                delegateProxy: delegateProxy
            )
        }
        guard window.delegate !== delegateProxy else { return }
        delegateProxy.forwardedDelegate = window.delegate
        window.delegate = delegateProxy
    }

}
