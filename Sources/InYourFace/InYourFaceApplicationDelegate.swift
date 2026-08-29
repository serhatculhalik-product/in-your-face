import AppKit

extension Notification.Name {
    static let inYourFaceApplicationDidRequestReopen = Notification.Name(
        "InYourFaceApplicationDidRequestReopen"
    )
}

@MainActor
final class InYourFaceApplicationDelegate: NSObject, NSApplicationDelegate {
    private let notificationCenter: NotificationCenter

    override init() {
        notificationCenter = .default
        super.init()
    }

    init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter
        super.init()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        notificationCenter.post(
            name: .inYourFaceApplicationDidRequestReopen,
            object: sender
        )
        return false
    }
}
