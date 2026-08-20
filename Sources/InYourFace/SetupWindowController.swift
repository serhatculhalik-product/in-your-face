import AppKit

@MainActor
final class SetupWindowController {
    static let shared = SetupWindowController()

    private var didShowSetupAtLaunch = false
    private var bringToFrontTask: Task<Void, Never>?

    func show(using openWindow: @escaping @MainActor () -> Void) {
        openWindow()
        bringToFront()
    }

    func showAtLaunch(using openWindow: @escaping @MainActor () -> Void) {
        guard !didShowSetupAtLaunch else { return }
        didShowSetupAtLaunch = true
        show(using: openWindow)
    }

    func bringToFront() {
        bringToFrontTask?.cancel()
        bringToFrontTask = Task { @MainActor [weak self] in
            for _ in 0..<20 {
                guard let self, !Task.isCancelled else { return }

                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title == "In Your Face" }) {
                    window.level = .normal
                    window.hidesOnDeactivate = false
                    window.orderFrontRegardless()
                    window.makeKeyAndOrderFront(nil)
                    self.bringToFrontTask = nil
                    return
                }

                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            self?.bringToFrontTask = nil
        }
    }
}
