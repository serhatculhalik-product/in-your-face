import AppKit

@MainActor
final class ApplicationWindowPresenter {
    static let shared = ApplicationWindowPresenter()

    private let windowRegistry: WindowRegistry
    private let activateApplication: @MainActor () -> Void
    private let foregroundWindow: @MainActor (NSWindow) -> Void
    private let currentKeyWindow: @MainActor () -> NSWindow?
    private let currentEventWindow: @MainActor () -> NSWindow?
    private lazy var pendingSettingsPresentation = PendingWindowPresentation<Void>(
        registry: windowRegistry,
        kind: .settings
    ) { [weak self] window, _ in
        self?.foreground(window)
    }

    init(
        windowRegistry: WindowRegistry = .shared,
        activateApplication: @escaping @MainActor () -> Void = {
            let application = NSApplication.shared
            guard !application.isActive else { return }
            application.activate(ignoringOtherApps: true)
        },
        foregroundWindow: @escaping @MainActor (NSWindow) -> Void = { window in
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            var frontmostWindow = window
            while let attachedSheet = frontmostWindow.attachedSheet {
                frontmostWindow = attachedSheet
            }
            frontmostWindow.makeKeyAndOrderFront(nil)
            frontmostWindow.orderFrontRegardless()
        },
        currentKeyWindow: @escaping @MainActor () -> NSWindow? = {
            NSApplication.shared.keyWindow
        },
        currentEventWindow: @escaping @MainActor () -> NSWindow? = {
            NSApplication.shared.currentEvent?.window
        }
    ) {
        self.windowRegistry = windowRegistry
        self.activateApplication = activateApplication
        self.foregroundWindow = foregroundWindow
        self.currentKeyWindow = currentKeyWindow
        self.currentEventWindow = currentEventWindow
    }

    func showSettings(using openSettings: @escaping @MainActor () -> Void) {
        openSettings()
        pendingSettingsPresentation.submit(())
    }

    func applicationDidBecomeActive(
        initialSurface: OnboardingState.InitialSurface,
        hasEarlyReminder: Bool,
        hasStrongAlert: Bool,
        triggeringWindow: NSWindow? = nil,
        using openSettings: @escaping @MainActor () -> Void
    ) {
        guard initialSurface != .waiting else { return }

        // Test Tools deliberately suspends alert interaction while its confirmation
        // UI is open. Keep that visible window in front until the user closes it;
        // the alert controllers resume and reclaim priority at that point.
        if foregroundVisibleRegisteredWindow(.testTools) {
            return
        }

        if hasStrongAlert {
            foregroundRegisteredWindow(.strongAlert)
            return
        }

        if hasEarlyReminder {
            foregroundRegisteredWindow(.earlyReminder)
            return
        }

        if initialSurface == .onboarding {
            foregroundRegisteredWindow(.onboarding)
            return
        }

        if shouldPreserveVisibleWindow(currentKeyWindow()) ||
            shouldPreserveInteractionWindow(triggeringWindow) ||
            shouldPreserveInteractionWindow(currentEventWindow()) {
            return
        }

        if !foregroundRegisteredWindow(.settings) {
            showSettings(using: openSettings)
        }
    }

    func initialSurfaceDidResolve(
        initialSurface: OnboardingState.InitialSurface,
        isApplicationActive: Bool,
        hasEarlyReminder: Bool,
        hasStrongAlert: Bool,
        triggeringWindow: NSWindow? = nil,
        using openSettings: @escaping @MainActor () -> Void
    ) {
        guard isApplicationActive else { return }
        applicationDidBecomeActive(
            initialSurface: initialSurface,
            hasEarlyReminder: hasEarlyReminder,
            hasStrongAlert: hasStrongAlert,
            triggeringWindow: triggeringWindow,
            using: openSettings
        )
    }

    private func foreground(_ window: NSWindow) {
        activateApplication()
        foregroundWindow(window)
    }

    private func shouldPreserveVisibleWindow(_ window: NSWindow?) -> Bool {
        guard let window, window.isVisible else { return false }
        return !windowRegistry.manages(window)
    }

    private func shouldPreserveInteractionWindow(_ window: NSWindow?) -> Bool {
        window != nil
    }

    @discardableResult
    private func foregroundRegisteredWindow(_ kind: AppWindowKind) -> Bool {
        guard let window = windowRegistry.window(for: kind) else { return false }
        foreground(window)
        return true
    }

    @discardableResult
    private func foregroundVisibleRegisteredWindow(_ kind: AppWindowKind) -> Bool {
        guard let window = windowRegistry.window(for: kind), window.isVisible else {
            return false
        }
        foreground(window)
        return true
    }
}
