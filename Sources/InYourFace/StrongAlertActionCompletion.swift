import AppKit

@MainActor
enum StrongAlertActionCompletion {
    static func finish(
        hasRemainingAlert: Bool,
        closeAlertWindow: @MainActor () -> Void = {
            StrongAlertWindowController.shared.close()
        },
        hideApplication: @MainActor () -> Void = {
            NSApplication.shared.hide(nil)
        }
    ) {
        guard !hasRemainingAlert else { return }
        closeAlertWindow()
        hideApplication()
    }
}
