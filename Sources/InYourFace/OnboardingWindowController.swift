import AppKit

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var didShowOnboardingAtLaunch = false
    private let windowRegistry: WindowRegistry
    private lazy var pendingBringToFront = PendingWindowPresentation<Void>(
        registry: windowRegistry,
        kind: .onboarding
    ) { window, _ in
        NSApp.activate(ignoringOtherApps: true)
        window.level = .normal
        window.hidesOnDeactivate = false
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    init(windowRegistry: WindowRegistry = .shared) {
        self.windowRegistry = windowRegistry
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

    func close() {
        pendingBringToFront.clear()
        windowRegistry.window(for: .onboarding)?.close()
    }

    func bringToFront() {
        pendingBringToFront.submit(())
    }
}
