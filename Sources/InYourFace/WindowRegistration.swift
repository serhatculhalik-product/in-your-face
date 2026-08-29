import AppKit
import SwiftUI

enum AppWindowKind: Hashable, Sendable {
    case settings
    case onboarding
    case testTools
    case earlyReminder
    case strongAlert
}

@MainActor
final class WindowRegistry {
    static let shared = WindowRegistry()

    private struct WeakWindow {
        weak var value: NSWindow?
    }

    private var windows: [AppWindowKind: WeakWindow] = [:]
    private var registrationWaiters: [AppWindowKind: [UUID: (NSWindow) -> Void]] = [:]

    func window(for kind: AppWindowKind) -> NSWindow? {
        guard let window = windows[kind]?.value else {
            windows[kind] = nil
            return nil
        }
        return window
    }

    func register(_ window: NSWindow, for kind: AppWindowKind) {
        windows[kind] = WeakWindow(value: window)
        let waiters = registrationWaiters
            .removeValue(forKey: kind)
            .map { Array($0.values) } ?? []
        waiters.forEach { $0(window) }
    }

    func unregister(_ window: NSWindow, for kind: AppWindowKind) {
        guard windows[kind]?.value === window else { return }
        windows[kind] = nil
    }

    func manages(_ candidate: NSWindow) -> Bool {
        windows.values.contains { registeredWindow in
            windowIsOwned(candidate, by: registeredWindow.value)
        }
    }

    @discardableResult
    func whenRegistered(
        _ kind: AppWindowKind,
        perform action: @escaping (NSWindow) -> Void
    ) -> UUID {
        let id = UUID()
        if let window = window(for: kind) {
            action(window)
        } else {
            registrationWaiters[kind, default: [:]][id] = action
        }
        return id
    }

    func cancelRegistrationWaiter(_ id: UUID, for kind: AppWindowKind) {
        registrationWaiters[kind]?[id] = nil
        if registrationWaiters[kind]?.isEmpty == true {
            registrationWaiters[kind] = nil
        }
    }
}

@MainActor
final class PendingWindowPresentation<Content> {
    private let registry: WindowRegistry
    private let kind: AppWindowKind
    private let deliver: (NSWindow, Content) -> Void
    private var pendingContent: Content?
    private var registrationWaiterID: UUID?

    init(
        registry: WindowRegistry,
        kind: AppWindowKind,
        deliver: @escaping (NSWindow, Content) -> Void
    ) {
        self.registry = registry
        self.kind = kind
        self.deliver = deliver
    }

    func submit(_ content: Content) {
        pendingContent = content

        if let window = registry.window(for: kind) {
            deliverPendingContent(to: window)
            return
        }

        guard registrationWaiterID == nil else { return }
        registrationWaiterID = registry.whenRegistered(kind) { [weak self] window in
            guard let self else { return }
            registrationWaiterID = nil
            deliverPendingContent(to: window)
        }
    }

    func clear() {
        pendingContent = nil
        if let registrationWaiterID {
            registry.cancelRegistrationWaiter(registrationWaiterID, for: kind)
            self.registrationWaiterID = nil
        }
    }

    private func deliverPendingContent(to window: NSWindow) {
        guard let content = pendingContent else { return }
        pendingContent = nil
        deliver(window, content)
    }
}

private struct WindowRegistrationAccessor: NSViewRepresentable {
    let kind: AppWindowKind

    func makeNSView(context: Context) -> WindowRegistrationView {
        WindowRegistrationView(kind: kind)
    }

    func updateNSView(_ view: WindowRegistrationView, context: Context) {
        view.updateKind(kind)
    }

    static func dismantleNSView(_ view: WindowRegistrationView, coordinator: ()) {
        view.unregister()
    }
}

@MainActor
private final class WindowRegistrationView: NSView {
    private var kind: AppWindowKind
    private weak var registeredWindow: NSWindow?

    init(kind: AppWindowKind) {
        self.kind = kind
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateRegistration()
    }

    func updateKind(_ kind: AppWindowKind) {
        guard self.kind != kind else { return }
        unregister()
        self.kind = kind
        updateRegistration()
    }

    func unregister() {
        guard let registeredWindow else { return }
        WindowRegistry.shared.unregister(registeredWindow, for: kind)
        self.registeredWindow = nil
    }

    private func updateRegistration() {
        guard registeredWindow !== window else { return }
        unregister()
        guard let window else { return }
        registeredWindow = window
        WindowRegistry.shared.register(window, for: kind)
    }
}

extension View {
    func registerWindow(_ kind: AppWindowKind) -> some View {
        background {
            WindowRegistrationAccessor(kind: kind)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
