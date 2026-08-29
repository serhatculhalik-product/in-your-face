import AppKit
import ObjectiveC
import SwiftUI

struct RuntimeWindowStatePolicy: Equatable {
    private enum WindowRole: Equatable {
        case application
        case testTools
    }

    private let role: WindowRole
    private let disablesRestoration: Bool
    private let keepsWindowHidden: Bool

    static func applicationWindow(
        isTestProfile: Bool,
        isResetQuarantined: Bool
    ) -> RuntimeWindowStatePolicy {
        RuntimeWindowStatePolicy(
            role: .application,
            disablesRestoration: isTestProfile || isResetQuarantined,
            keepsWindowHidden: isResetQuarantined
        )
    }

    static let testTools = RuntimeWindowStatePolicy(
        role: .testTools,
        disablesRestoration: true,
        keepsWindowHidden: false
    )

    var allowsInteraction: Bool { !keepsWindowHidden }

    @MainActor
    func apply(to window: NSWindow) {
        RuntimeWindowVisibilityEnforcement.update(
            window: window,
            isTestTools: role == .testTools
        )
        if disablesRestoration {
            window.isRestorable = false
            window.restorationClass = nil
            _ = window.setFrameAutosaveName("")
        }
        if keepsWindowHidden {
            window.orderOut(nil)
        }
    }
}

@MainActor
enum RuntimeWindowQuarantine {
    static func update(isActive: Bool) {
        RuntimeWindowVisibilityEnforcement.setApplicationQuarantineActive(isActive)
    }
}

@MainActor
private enum RuntimeWindowVisibilityEnforcement {
    private static var quarantineAssociationKey: UInt8 = 0
    private static var roleAssociationKey: UInt8 = 0
    private static var isApplicationQuarantineActive = false
    private static var windowUpdateObserver: NSObjectProtocol?

    static func update(
        window: NSWindow,
        isTestTools: Bool
    ) {
        objc_setAssociatedObject(
            window,
            &roleAssociationKey,
            NSNumber(value: isTestTools),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        enforceVisibility(of: window)
    }

    fileprivate static func setApplicationQuarantineActive(_ isActive: Bool) {
        isApplicationQuarantineActive = isActive
        if isActive {
            startWindowObservation()
            NSApplication.shared.windows.forEach(enforceVisibility)
        } else {
            stopWindowObservation()
            NSApplication.shared.windows.forEach(removeQuarantine)
        }
    }

    private static func startWindowObservation() {
        guard windowUpdateObserver == nil else { return }
        // AppKit has no did-become-visible notification. didUpdate arrives during
        // order-front early enough to install the isVisible observation below;
        // the late-created panel regression locks down that synchronous ordering.
        windowUpdateObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                RuntimeWindowVisibilityEnforcement.enforceVisibility(of: window)
            }
        }
    }

    private static func stopWindowObservation() {
        guard let windowUpdateObserver else { return }
        NotificationCenter.default.removeObserver(windowUpdateObserver)
        self.windowUpdateObserver = nil
    }

    private static func enforceVisibility(of window: NSWindow) {
        guard isApplicationQuarantineActive,
              !isTestToolsWindow(window) else {
            removeQuarantine(from: window)
            return
        }

        if objc_getAssociatedObject(window, &quarantineAssociationKey) == nil {
            objc_setAssociatedObject(
                window,
                &quarantineAssociationKey,
                PersistentWindowQuarantine(window: window) { visibleWindow in
                    RuntimeWindowVisibilityEnforcement.enforceVisibility(of: visibleWindow)
                },
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
        window.orderOut(nil)
    }

    private static func removeQuarantine(from window: NSWindow) {
        objc_setAssociatedObject(
            window,
            &quarantineAssociationKey,
            nil,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private static func isTestToolsWindow(_ window: NSWindow) -> Bool {
        var candidate: NSWindow? = window
        var visitedWindowIDs: Set<ObjectIdentifier> = []

        while let currentWindow = candidate {
            guard visitedWindowIDs.insert(ObjectIdentifier(currentWindow)).inserted else {
                return false
            }
            if (objc_getAssociatedObject(currentWindow, &roleAssociationKey) as? NSNumber)?.boolValue == true {
                return true
            }
            candidate = currentWindow.sheetParent ?? currentWindow.parent
        }

        return false
    }
}

@MainActor
private final class PersistentWindowQuarantine {
    private var visibilityObservation: NSKeyValueObservation?

    init(
        window: NSWindow,
        becameVisible: @escaping @MainActor (NSWindow) -> Void
    ) {
        visibilityObservation = window.observe(\.isVisible, options: [.new]) { window, change in
            guard change.newValue == true else { return }
            MainActor.assumeIsolated {
                becameVisible(window)
            }
        }
    }
}

private struct RuntimeWindowStateAccessor: NSViewRepresentable {
    let policy: RuntimeWindowStatePolicy

    func makeNSView(context: Context) -> RuntimeWindowStateView {
        RuntimeWindowStateView(policy: policy)
    }

    func updateNSView(_ view: RuntimeWindowStateView, context: Context) {
        view.update(policy: policy)
    }
}

@MainActor
private final class RuntimeWindowStateView: NSView {
    private var policy: RuntimeWindowStatePolicy

    init(policy: RuntimeWindowStatePolicy) {
        self.policy = policy
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPolicy()
    }

    func update(policy: RuntimeWindowStatePolicy) {
        self.policy = policy
        applyPolicy()
    }

    private func applyPolicy() {
        guard let window else { return }
        policy.apply(to: window)
    }
}

extension View {
    /// Applies restoration and reset-quarantine behavior without exposing AppKit
    /// window lifecycle details to individual scenes.
    func runtimeWindowState(_ policy: RuntimeWindowStatePolicy) -> some View {
        disabled(!policy.allowsInteraction)
            .allowsHitTesting(policy.allowsInteraction)
            .background {
                RuntimeWindowStateAccessor(policy: policy)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
    }
}
