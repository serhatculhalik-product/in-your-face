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
    private let presentationContract = AlertPresentationContract(variant: .strongAlert)
    private var lifecycle = AlertPresentationLifecycle()

    func present(
        content: AnyView,
        surfaceDidClose: @escaping @MainActor () -> Void
    ) {
        self.content = content
        self.surfaceDidClose = surfaceDidClose
        let screens = NSScreen.screens

        let existingAdditionalWindows = additionalWindows
        guard let window = NSApp.windows.first(where: { candidate in
            candidate.title == "Strong Alert" &&
                !existingAdditionalWindows.contains(where: { $0 === candidate })
        }) else {
            _ = lifecycle.present(
                surface: .strongAlert,
                displayCount: screens.count,
                primaryIndex: nil,
                surfaceDiscovered: false
            )
            DispatchQueue.main.async { [weak self] in
                self?.present(content: content, surfaceDidClose: surfaceDidClose)
            }
            return
        }

        stopScreenObservation()
        stopApplicationObservation()
        closeAdditionalWindows()
        primaryWindow = window
        configure(window)
        window.center()
        let displayPlan = lifecycle.present(
            surface: .strongAlert,
            displayCount: screens.count,
            primaryIndex: primaryScreenIndex(in: screens, matching: window.screen ?? NSScreen.main),
            surfaceDiscovered: true
        )
        isPresented = lifecycle.isPresented
        if let displayPlan {
            createAdditionalWindows(using: displayPlan)
        }
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
        closeAdditionalWindows()
        primaryWindow?.delegate = nil
        primaryWindow?.close()
        primaryWindow = nil
        content = nil
        surfaceDidClose = nil
        isPresented = false
        lifecycle.close()
        allowsWindowClose = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !allowsWindowClose else { return true }
        lifecycle.surfaceDisappeared()
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
        window.sharingType = presentationContract.remainsVisibleDuringDisplaySharing ? .readOnly : .none
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isMovable = false
    }

    private func createAdditionalWindows(using displayPlan: StrongAlertDisplayPlan) {
        guard let content else { return }
        let screens = NSScreen.screens

        let resolvedPrimaryScreen = screens[displayPlan.primaryIndex]
        if primaryScreenIndex(in: screens, matching: primaryWindow?.screen) != displayPlan.primaryIndex {
            center(primaryWindow, on: resolvedPrimaryScreen)
        }

        additionalWindows = displayPlan.additionalIndices.map { index in
            let screen = screens[index]
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
            panel.sharingType = presentationContract.remainsVisibleDuringDisplaySharing ? .readOnly : .none
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.isMovable = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: content)
            center(panel, on: screen)
            panel.delegate = self
            panel.orderFrontRegardless()
            return panel
        }
    }

    private func center(_ window: NSWindow?, on screen: NSScreen) {
        guard let window else { return }
        window.setFrameOrigin(NSPoint(
            x: screen.frame.midX - window.frame.width / 2,
            y: screen.frame.midY - window.frame.height / 2
        ))
    }

    private func closeAdditionalWindows() {
        additionalWindows.forEach {
            $0.delegate = nil
            $0.close()
        }
        additionalWindows.removeAll()
    }

    private func primaryScreenIndex(
        in screens: [NSScreen],
        matching primaryScreen: NSScreen?
    ) -> Int? {
        guard let primaryScreen else { return nil }
        return screens.firstIndex(where: { $0 === primaryScreen })
            ?? screens.firstIndex(where: { $0.frame == primaryScreen.frame })
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
                    self?.lifecycle.applicationActivationChanged()
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
        guard isPresented || lifecycle.requiresSurfaceRecovery || lifecycle.requiresSurfaceCreation else { return }
        let screens = NSScreen.screens
        guard let displayPlan = lifecycle.displayTopologyChanged(
            displayCount: screens.count,
            primaryIndex: primaryScreenIndex(in: screens, matching: primaryWindow?.screen ?? NSScreen.main)
        ) else {
            closeAdditionalWindows()
            return
        }
        guard lifecycle.isPresented else {
            closeAdditionalWindows()
            return
        }
        isPresented = lifecycle.isPresented
        closeAdditionalWindows()
        createAdditionalWindows(using: displayPlan)
        bringAlertToFront()
    }

    private func bringAlertToFront() {
        guard isPresented else { return }
        NSApp.activate(ignoringOtherApps: true)
        primaryWindow?.orderFrontRegardless()
        primaryWindow?.makeKey()
        additionalWindows.forEach { $0.orderFrontRegardless() }
        lifecycle.markActivated()
    }
}
