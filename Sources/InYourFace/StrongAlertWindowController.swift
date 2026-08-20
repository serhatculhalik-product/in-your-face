import AppKit
import SwiftUI

@MainActor
final class StrongAlertWindowController: NSObject, NSWindowDelegate {
    static let shared = StrongAlertWindowController()

    private weak var primaryWindow: NSWindow?
    private var additionalWindows: [NSWindow] = []
    private var screenObserver: NSObjectProtocol?
    private var applicationObservers: [NSObjectProtocol] = []
    private var surfaceDidClose: (@MainActor () -> Void)?
    private var allowsWindowClose = false
    private var isPresented = false
    private var content: AnyView?

    func present(
        content: AnyView,
        surfaceDidClose: @escaping @MainActor () -> Void
    ) {
        self.content = content
        self.surfaceDidClose = surfaceDidClose

        guard let window = NSApp.windows.first(where: {
            $0.title == "Strong Alert" && $0 !== additionalWindows.first
        }) else {
            DispatchQueue.main.async { [weak self] in
                self?.present(content: content, surfaceDidClose: surfaceDidClose)
            }
            return
        }

        stopScreenObservation()
        stopApplicationObservation()
        primaryWindow = window
        configure(window)
        window.center()
        isPresented = true
        createAdditionalWindows(for: window.screen ?? NSScreen.main)
        startScreenObservation()
        startApplicationObservation()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        allowsWindowClose = true
        stopScreenObservation()
        stopApplicationObservation()
        additionalWindows.forEach { $0.delegate = nil; $0.close() }
        additionalWindows.removeAll()
        primaryWindow?.delegate = nil
        primaryWindow?.close()
        primaryWindow = nil
        content = nil
        surfaceDidClose = nil
        isPresented = false
        allowsWindowClose = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !allowsWindowClose else { return true }
        surfaceDidClose?()
        DispatchQueue.main.async { [weak self] in
            self?.close()
        }
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        bringAlertToFront()
    }

    func windowDidResignMain(_ notification: Notification) {
        bringAlertToFront()
    }

    private func configure(_ window: NSWindow) {
        window.delegate = self
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.sharingType = .readOnly
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isMovable = false
    }

    private func createAdditionalWindows(for primaryScreen: NSScreen?) {
        guard let content else { return }
        additionalWindows = NSScreen.screens
            .filter { screen in
                guard let primaryScreen else { return true }
                return screen.frame != primaryScreen.frame
            }
            .map { screen in
                let panel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
                    styleMask: [.titled, .utilityWindow],
                    backing: .buffered,
                    defer: false
                )
                panel.title = "Strong Alert"
                panel.titleVisibility = .hidden
                panel.titlebarAppearsTransparent = true
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
                panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                panel.sharingType = .readOnly
                panel.standardWindowButton(.closeButton)?.isHidden = true
                panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
                panel.standardWindowButton(.zoomButton)?.isHidden = true
                panel.isMovable = false
                panel.isReleasedWhenClosed = false
                panel.contentView = NSHostingView(rootView: content)
                panel.center()
                panel.setFrameOrigin(NSPoint(
                    x: screen.frame.midX - panel.frame.width / 2,
                    y: screen.frame.midY - panel.frame.height / 2
                ))
                panel.delegate = self
                panel.orderFrontRegardless()
                return panel
            }
    }

    private func startScreenObservation() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recreateAdditionalWindows()
            }
        }
    }

    private func stopScreenObservation() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func startApplicationObservation() {
        applicationObservers = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification
        ].map { notificationName in
            NotificationCenter.default.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.bringAlertToFront()
                }
            }
        }
    }

    private func stopApplicationObservation() {
        applicationObservers.forEach(NotificationCenter.default.removeObserver)
        applicationObservers.removeAll()
    }

    private func recreateAdditionalWindows() {
        guard isPresented else { return }
        additionalWindows.forEach { $0.delegate = nil; $0.close() }
        additionalWindows.removeAll()
        createAdditionalWindows(for: primaryWindow?.screen ?? NSScreen.main)
        bringAlertToFront()
    }

    private func bringAlertToFront() {
        guard isPresented else { return }
        NSApp.activate(ignoringOtherApps: true)
        primaryWindow?.orderFrontRegardless()
        primaryWindow?.makeKey()
        additionalWindows.forEach { $0.orderFrontRegardless() }
    }
}
