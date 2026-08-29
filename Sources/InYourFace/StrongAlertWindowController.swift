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
    private let scheduleAfterLayout: (@escaping @MainActor () -> Void) -> Void
    private let fitWindow: @MainActor (NSWindow?, NSScreen?) -> Void
    private let presentationContract = AlertPresentationContract(variant: .strongAlert)
    private weak var primaryWindow: NSWindow?
    private var additionalWindows: [NSWindow] = []
    private var screenObserver: NSObjectProtocol?
    private var applicationObservers: [NSObjectProtocol] = []
    private var surfaceDidClose: (@MainActor () -> Void)?
    private var allowsWindowClose = false
    private var isPresented = false
    private var isInteractionSuspendedForTestTools = false
    private var content: AnyView?
    private var fittingWindowIDs: Set<ObjectIdentifier> = []
    private var lifecycle = AlertPresentationLifecycle()
    private lazy var pendingPresentation = PendingWindowPresentation<PresentationRequest>(
        registry: windowRegistry,
        kind: .strongAlert
    ) { [weak self] window, request in
        self?.present(request, in: window)
    }

    init(
        windowRegistry: WindowRegistry = .shared,
        scheduleAfterLayout: @escaping (@escaping @MainActor () -> Void) -> Void = { action in
            DispatchQueue.main.async { action() }
        },
        fitWindow: @escaping @MainActor (NSWindow?, NSScreen?) -> Void = { window, screen in
            WindowFrameFitter.fit(
                window,
                on: screen,
                minimumContentSize: NSSize(width: 360, height: 300)
            )
        }
    ) {
        self.windowRegistry = windowRegistry
        self.scheduleAfterLayout = scheduleAfterLayout
        self.fitWindow = fitWindow
        super.init()
    }

    func present(
        content: AnyView,
        surfaceDidClose: @escaping @MainActor () -> Void
    ) {
        if windowRegistry.window(for: .strongAlert) == nil {
            _ = lifecycle.present(
                surface: .strongAlert,
                displayCount: NSScreen.screens.count,
                primaryIndex: nil,
                surfaceDiscovered: false
            )
        }
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
        let screens = NSScreen.screens
        let primaryScreen = window.screen ?? NSScreen.main
        guard let displayPlan = lifecycle.present(
            surface: .strongAlert,
            displayCount: screens.count,
            primaryIndex: primaryScreenIndex(in: screens, matching: primaryScreen),
            surfaceDiscovered: true
        ) else {
            isPresented = false
            startScreenObservation()
            return
        }
        fitAlertWindow(
            window,
            on: primaryScreen
        )
        isPresented = true
        createAdditionalWindows(using: displayPlan)
        startScreenObservation()
        if isInteractionSuspendedForTestTools {
            window.orderFront(nil)
        } else {
            startApplicationObservation()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            lifecycle.markActivated()
        }
        refitPrimaryWindowAfterLayout(window)
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
        lifecycle.close()
        allowsWindowClose = false
    }

    func suspendInteractionForTestTools() {
        guard !isInteractionSuspendedForTestTools else { return }
        isInteractionSuspendedForTestTools = true
        stopApplicationObservation()
        primaryWindow?.level = .normal
        additionalWindows.forEach { $0.level = .normal }
    }

    func resumeInteractionAfterTestTools() {
        guard isInteractionSuspendedForTestTools else { return }
        isInteractionSuspendedForTestTools = false
        guard isPresented else { return }
        let alertLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        primaryWindow?.level = alertLevel
        additionalWindows.forEach { $0.level = alertLevel }
        startApplicationObservation()
        bringAlertToFront()
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
        window.level = isInteractionSuspendedForTestTools
            ? .normal
            : NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.sharingType = presentationContract.sharingPolicy.windowSharingType
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isMovable = false
    }

    private func createAdditionalWindows(using displayPlan: StrongAlertDisplayPlan) {
        guard let content else { return }
        let screens = NSScreen.screens

        let resolvedPrimaryScreen = screens[displayPlan.primaryIndex]
        if primaryScreenIndex(in: screens, matching: primaryWindow?.screen) != displayPlan.primaryIndex {
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
            panel.level = isInteractionSuspendedForTestTools
                ? .normal
                : NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.sharingType = presentationContract.sharingPolicy.windowSharingType
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
        guard isPresented || lifecycle.requiresSurfaceRecovery || lifecycle.requiresSurfaceCreation else {
            return
        }
        let screens = NSScreen.screens
        let primaryScreen = primaryWindow?.screen ?? NSScreen.main
        fitAlertWindow(
            primaryWindow,
            on: primaryScreen
        )
        guard let displayPlan = lifecycle.displayTopologyChanged(
            displayCount: screens.count,
            primaryIndex: primaryScreenIndex(in: screens, matching: primaryScreen)
        ), lifecycle.isPresented else {
            isPresented = false
            closeAdditionalWindows()
            return
        }
        isPresented = true
        closeAdditionalWindows()
        createAdditionalWindows(using: displayPlan)
        bringAlertToFront()
    }

    private func preserveAlertFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isPresented,
                  !self.isInteractionSuspendedForTestTools else { return }
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

        fitWindow(window, screen)
    }

    private func refitPrimaryWindowAfterLayout(_ window: NSWindow) {
        scheduleAfterLayout { [weak self, weak window] in
            guard let self,
                  let window,
                  self.isPresented,
                  self.primaryWindow === window else { return }
            self.fitAlertWindow(window, on: window.screen)
        }
    }

    private func bringAlertToFront() {
        guard isPresented, !isInteractionSuspendedForTestTools else { return }
        let keyWindow = NSApp.keyWindow
        NSApp.activate(ignoringOtherApps: true)
        let alertWindows = [primaryWindow].compactMap { $0 } + additionalWindows
        alertWindows.forEach { $0.orderFrontRegardless() }
        if !isAlertOwnedWindow(keyWindow) {
            (alertWindows.first(where: \.isKeyWindow) ?? primaryWindow)?.makeKey()
        }
        lifecycle.markActivated()
    }
}
