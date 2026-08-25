import AppKit
import SwiftUI

@MainActor
final class StrongAlertWindowController: NSObject, NSWindowDelegate {
    static let shared = StrongAlertWindowController()

    private struct PresentationRequest {
        let content: AnyView
        let surfaceDidClose: @MainActor () -> Void
    }

    private let windowRegistry: WindowRegistry
    private weak var primaryWindow: NSWindow?
    private var additionalWindows: [NSWindow] = []
    private var screenObserver: NSObjectProtocol?
    private var applicationObservers: [NSObjectProtocol] = []
    private var surfaceDidClose: (@MainActor () -> Void)?
    private var allowsWindowClose = false
    private var isPresented = false
    private var content: AnyView?
    private var fittingWindowIDs: Set<ObjectIdentifier> = []
    private lazy var pendingPresentation = PendingWindowPresentation<PresentationRequest>(
        registry: windowRegistry,
        kind: .strongAlert
    ) { [weak self] window, request in
        self?.present(request, in: window)
    }

    init(windowRegistry: WindowRegistry = .shared) {
        self.windowRegistry = windowRegistry
        super.init()
    }

    func present(
        content: AnyView,
        surfaceDidClose: @escaping @MainActor () -> Void
    ) {
        pendingPresentation.submit(PresentationRequest(
            content: content,
            surfaceDidClose: surfaceDidClose
        ))
    }

    private func present(_ request: PresentationRequest, in window: NSWindow) {
        content = request.content
        surfaceDidClose = request.surfaceDidClose

        stopScreenObservation()
        stopApplicationObservation()
        closeAdditionalWindows()
        primaryWindow = window
        configure(window)
        let primaryScreen = window.screen ?? NSScreen.main
        fitAlertWindow(
            window,
            on: primaryScreen
        )
        isPresented = true
        createAdditionalWindows(for: primaryScreen)
        startScreenObservation()
        startApplicationObservation()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        pendingPresentation.clear()
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
        preserveAlertFocus()
    }

    func windowDidResignMain(_ notification: Notification) {
        preserveAlertFocus()
    }

    func windowDidResize(_ notification: Notification) {
        guard isPresented,
              let resizedWindow = notification.object as? NSWindow,
              isManagedAlertWindow(resizedWindow) else { return }
        fitAlertWindow(resizedWindow, on: resizedWindow.screen)
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
        let screens = NSScreen.screens
        guard let displayPlan = StrongAlertDisplayPlan(
            displayCount: screens.count,
            primaryIndex: primaryScreenIndex(in: screens, matching: primaryScreen)
        ) else {
            return
        }

        let resolvedPrimaryScreen = screens[displayPlan.primaryIndex]
        if primaryScreenIndex(in: screens, matching: primaryScreen) != displayPlan.primaryIndex {
            fitAlertWindow(
                primaryWindow,
                on: resolvedPrimaryScreen
            )
        }

        additionalWindows = displayPlan.additionalIndices.map { index in
            let screen = screens[index]
            let hostingView = NSHostingView(
                rootView: content.accessibilityHidden(true)
            )
            hostingView.sizingOptions = [.intrinsicContentSize]
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 330),
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
            panel.setAccessibilityElement(false)
            panel.contentView = hostingView
            fitAlertWindow(
                panel,
                on: screen
            )
            panel.delegate = self
            panel.orderFrontRegardless()
            return panel
        }
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
        let primaryScreen = primaryWindow?.screen ?? NSScreen.main
        fitAlertWindow(
            primaryWindow,
            on: primaryScreen
        )
        closeAdditionalWindows()
        createAdditionalWindows(for: primaryScreen)
        bringAlertToFront()
    }

    private func preserveAlertFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPresented else { return }
            let alertWindows = [self.primaryWindow].compactMap { $0 } + self.additionalWindows
            if self.isAlertOwnedWindow(NSApp.keyWindow) {
                alertWindows.forEach { $0.orderFrontRegardless() }
            } else {
                self.bringAlertToFront()
            }
        }
    }

    private func isManagedAlertWindow(_ window: NSWindow) -> Bool {
        window === primaryWindow || additionalWindows.contains(where: { $0 === window })
    }

    private func isAlertOwnedWindow(_ window: NSWindow?) -> Bool {
        var candidate = window
        var visitedWindowIDs: Set<ObjectIdentifier> = []

        while let currentWindow = candidate {
            guard visitedWindowIDs.insert(ObjectIdentifier(currentWindow)).inserted else {
                return false
            }
            if isManagedAlertWindow(currentWindow) {
                return true
            }
            candidate = currentWindow.sheetParent ?? currentWindow.parent
        }

        return false
    }

    private func fitAlertWindow(_ window: NSWindow?, on screen: NSScreen?) {
        guard let window else { return }
        let windowID = ObjectIdentifier(window)
        guard fittingWindowIDs.insert(windowID).inserted else { return }
        defer { fittingWindowIDs.remove(windowID) }

        WindowFrameFitter.fit(
            window,
            on: screen,
            minimumContentSize: NSSize(width: 360, height: 300)
        )
    }

    private func bringAlertToFront() {
        guard isPresented else { return }
        let keyWindow = NSApp.keyWindow
        NSApp.activate(ignoringOtherApps: true)
        let alertWindows = [primaryWindow].compactMap { $0 } + additionalWindows
        alertWindows.forEach { $0.orderFrontRegardless() }
        guard !isAlertOwnedWindow(keyWindow) else { return }
        (alertWindows.first(where: \.isKeyWindow) ?? primaryWindow)?.makeKey()
    }
}
