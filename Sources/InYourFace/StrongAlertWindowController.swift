import AppKit
import SwiftUI

@MainActor
private final class StrongAlertHostingView: NSHostingView<AnyView> {
    var intrinsicContentSizeDidInvalidate: (@MainActor () -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        intrinsicContentSizeDidInvalidate?()
    }
}

@MainActor
final class StrongAlertWindowController: NSObject, NSWindowDelegate {
    static let shared = StrongAlertWindowController()

    private struct ScheduledRefit {
        enum Phase {
            case pending
            case running
        }

        let generation: UInt
        var phase: Phase
        var needsTrailingPass: Bool
    }

    private struct PresentationRequest {
        let content: AnyView
        let surfaceDidClose: @MainActor () -> Void
    }

    private let windowRegistry: WindowRegistry
    private let scheduleAfterLayout: (@escaping @MainActor () -> Void) -> Void
    private let fitWindow: @MainActor (NSWindow?, NSScreen?) -> Void
    private let notificationCenter: NotificationCenter
    private let availableScreens: @MainActor () -> [NSScreen]
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
    private var windowLayoutGeneration: UInt = 0
    private var scheduledRefits: [ObjectIdentifier: ScheduledRefit] = [:]
    private var lastFittedContentSizes: [ObjectIdentifier: CGSize] = [:]
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
        },
        notificationCenter: NotificationCenter = .default,
        availableScreens: @escaping @MainActor () -> [NSScreen] = { NSScreen.screens }
    ) {
        self.windowRegistry = windowRegistry
        self.scheduleAfterLayout = scheduleAfterLayout
        self.fitWindow = fitWindow
        self.notificationCenter = notificationCenter
        self.availableScreens = availableScreens
        super.init()
    }

    var isObservingApplicationActivation: Bool {
        !applicationObservers.isEmpty
    }

    func present(
        content: AnyView,
        surfaceDidClose: @escaping @MainActor () -> Void
    ) {
        if windowRegistry.window(for: .strongAlert) == nil {
            _ = lifecycle.present(
                surface: .strongAlert,
                displayCount: availableScreens().count,
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
        windowLayoutGeneration &+= 1
        scheduledRefits.removeAll()
        lastFittedContentSizes.removeAll()
        let layoutGeneration = windowLayoutGeneration
        primaryWindow = window
        configure(window)
        let screens = availableScreens()
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
        positionPrimaryWindow(window, on: screens[displayPlan.primaryIndex])
        isPresented = true
        createAdditionalWindows(
            using: displayPlan,
            screens: screens,
            layoutGeneration: layoutGeneration
        )
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
        windowLayoutGeneration &+= 1
        scheduledRefits.removeAll()
        lastFittedContentSizes.removeAll()
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

    private func createAdditionalWindows(
        using displayPlan: StrongAlertDisplayPlan,
        screens: [NSScreen],
        layoutGeneration: UInt
    ) {
        guard let content else { return }

        additionalWindows = displayPlan.additionalIndices.map { index in
            let screen = screens[index]
            let hostingView = StrongAlertHostingView(
                rootView: AnyView(content.accessibilityHidden(true))
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
            hostingView.intrinsicContentSizeDidInvalidate = { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.refitAdditionalWindowAfterLayout(
                    panel,
                    on: screen,
                    layoutGeneration: layoutGeneration
                )
            }
            fitAdditionalWindow(
                panel,
                on: screen
            )
            panel.delegate = self
            panel.orderFrontRegardless()
            return panel
        }
        for (window, screenIndex) in zip(additionalWindows, displayPlan.additionalIndices) {
            refitAdditionalWindowAfterLayout(
                window,
                on: screens[screenIndex],
                layoutGeneration: layoutGeneration
            )
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
        screenObserver = notificationCenter.addObserver(
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
            notificationCenter.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func startApplicationObservation() {
        applicationObservers = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification
        ].map { notificationName in
            notificationCenter.addObserver(
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
        applicationObservers.forEach(notificationCenter.removeObserver)
        applicationObservers.removeAll()
    }

    private func recreateAdditionalWindows() {
        guard isPresented || lifecycle.requiresSurfaceRecovery || lifecycle.requiresSurfaceCreation else {
            return
        }
        let screens = availableScreens()
        let primaryScreen = primaryWindow?.screen ?? NSScreen.main
        windowLayoutGeneration &+= 1
        scheduledRefits.removeAll()
        lastFittedContentSizes.removeAll()
        let layoutGeneration = windowLayoutGeneration
        guard let displayPlan = lifecycle.displayTopologyChanged(
            displayCount: screens.count,
            primaryIndex: primaryScreenIndex(in: screens, matching: primaryScreen)
        ), lifecycle.isPresented else {
            isPresented = false
            stopApplicationObservation()
            closeAdditionalWindows()
            return
        }
        positionPrimaryWindow(primaryWindow, on: screens[displayPlan.primaryIndex])
        isPresented = true
        closeAdditionalWindows()
        createAdditionalWindows(
            using: displayPlan,
            screens: screens,
            layoutGeneration: layoutGeneration
        )
        restartApplicationObservation()
        bringAlertToFront()
    }

    private func restartApplicationObservation() {
        stopApplicationObservation()
        guard !isInteractionSuspendedForTestTools else { return }
        startApplicationObservation()
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

    private func fitAdditionalWindow(_ window: NSWindow?, on screen: NSScreen?) {
        guard let window, window !== primaryWindow else { return }
        let windowID = ObjectIdentifier(window)
        guard fittingWindowIDs.insert(windowID).inserted else { return }
        defer { fittingWindowIDs.remove(windowID) }

        fitWindow(window, screen)
    }

    private func positionPrimaryWindow(_ window: NSWindow?, on screen: NSScreen) {
        guard let window else { return }
        let visibleFrame = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - window.frame.width / 2,
            y: visibleFrame.midY - window.frame.height / 2
        ))
    }

    private func refitAdditionalWindowAfterLayout(
        _ window: NSWindow,
        on screen: NSScreen,
        layoutGeneration: UInt
    ) {
        let windowID = ObjectIdentifier(window)
        if var scheduledRefit = scheduledRefits[windowID],
           scheduledRefit.generation == layoutGeneration {
            if scheduledRefit.phase == .running {
                scheduledRefit.needsTrailingPass = true
                scheduledRefits[windowID] = scheduledRefit
            }
            return
        }
        scheduledRefits[windowID] = ScheduledRefit(
            generation: layoutGeneration,
            phase: .pending,
            needsTrailingPass: false
        )
        enqueueAdditionalWindowRefit(
            window,
            on: screen,
            layoutGeneration: layoutGeneration
        )
    }

    private func enqueueAdditionalWindowRefit(
        _ window: NSWindow,
        on screen: NSScreen,
        layoutGeneration: UInt
    ) {
        let windowID = ObjectIdentifier(window)
        scheduleAfterLayout { [weak self, weak window] in
            guard let self,
                  var scheduledRefit = self.scheduledRefits[windowID],
                  scheduledRefit.generation == layoutGeneration,
                  scheduledRefit.phase == .pending else { return }
            guard let window,
                  self.isPresented,
                  self.windowLayoutGeneration == layoutGeneration,
                  self.additionalWindows.contains(where: { $0 === window }) else {
                self.removeScheduledRefit(
                    for: windowID,
                    layoutGeneration: layoutGeneration
                )
                return
            }

            window.contentView?.layoutSubtreeIfNeeded()
            let contentSize = window.contentView?.fittingSize ?? window.contentLayoutRect.size
            if let lastFittedContentSize = self.lastFittedContentSizes[windowID],
               self.contentSizesAreEquivalent(contentSize, lastFittedContentSize) {
                self.removeScheduledRefit(
                    for: windowID,
                    layoutGeneration: layoutGeneration
                )
                return
            }

            scheduledRefit.phase = .running
            scheduledRefit.needsTrailingPass = false
            self.scheduledRefits[windowID] = scheduledRefit
            self.fitAdditionalWindow(window, on: screen)
            self.lastFittedContentSizes[windowID] = contentSize
            window.contentView?.layoutSubtreeIfNeeded()
            let settledContentSize = window.contentView?.fittingSize ?? window.contentLayoutRect.size

            guard let completedRefit = self.scheduledRefits[windowID],
                  completedRefit.generation == layoutGeneration else { return }
            if completedRefit.needsTrailingPass ||
                !self.contentSizesAreEquivalent(contentSize, settledContentSize) {
                self.scheduledRefits[windowID] = ScheduledRefit(
                    generation: layoutGeneration,
                    phase: .pending,
                    needsTrailingPass: false
                )
                self.enqueueAdditionalWindowRefit(
                    window,
                    on: screen,
                    layoutGeneration: layoutGeneration
                )
            } else {
                self.removeScheduledRefit(
                    for: windowID,
                    layoutGeneration: layoutGeneration
                )
            }
        }
    }

    private func removeScheduledRefit(
        for windowID: ObjectIdentifier,
        layoutGeneration: UInt
    ) {
        guard scheduledRefits[windowID]?.generation == layoutGeneration else { return }
        scheduledRefits.removeValue(forKey: windowID)
    }

    private func contentSizesAreEquivalent(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) <= 0.5 && abs(lhs.height - rhs.height) <= 0.5
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
