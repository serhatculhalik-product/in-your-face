import AppKit
import ApplicationServices
import Combine
import CommitmentProtection
import CoreGraphics
import ServiceManagement
import SwiftUI

@main
@MainActor
struct InYourFaceApp: App {
    @StateObject private var flow: CommitmentProtectionFlow

    init() {
        let protectionFlow = CommitmentProtectionFlow(
            calendarConnector: GoogleCalendarConnector(
                configuration: GoogleCalendarOAuthConfiguration(
                    clientID: googleOAuthClientID(),
                    clientSecret: googleOAuthClientSecret()
                )
            ),
            launchAtLogin: MacLaunchAtLoginController()
        )
        _flow = StateObject(wrappedValue: protectionFlow)
        Task {
            await protectionFlow.restoreSavedConnection()
            protectionFlow.startMonitoring()
        }
    }

    var body: some Scene {
        Window("In Your Face", id: "setup") {
            SetupView()
                .environmentObject(flow)
                .frame(minWidth: 520, minHeight: 560)
        }

        Window("Test Alert", id: "test-alert") {
            TestAlertView()
                .environmentObject(flow)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("Early Reminder", id: "early-reminder") {
            EarlyReminderView()
                .environmentObject(flow)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(flow)
        } label: {
            MenuBarLabel()
                .environmentObject(flow)
        }
        .menuBarExtraStyle(.window)
    }
}

private func googleOAuthClientID() -> String {
    if let bundledClientID = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String,
       !bundledClientID.isEmpty {
        return bundledClientID
    }
    return ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"] ?? ""
}

private func googleOAuthClientSecret() -> String? {
    if let bundledClientSecret = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientSecret") as? String,
       !bundledClientSecret.isEmpty {
        return bundledClientSecret
    }
    guard let environmentClientSecret = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_SECRET"],
          !environmentClientSecret.isEmpty else {
        return nil
    }
    return environmentClientSecret
}

@MainActor
private final class MacLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func enable() throws {
        try SMAppService.mainApp.register()
    }
}

private struct SetupView: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HeaderView()
                ProtectionStatusCard()
                AccountSetupCard()

                if flow.connectedAccount != nil {
                    CalendarSelectionCard()
                    EarlyReminderSettingsCard()
                    TestAlertCard()
                }

                LoginAvailabilityCard()
            }
            .padding(32)
        }
        .onAppear {
            flow.refreshLaunchAtLoginStatus()
        }
        .onChange(of: flow.earlyReminderCommitment) { _, commitment in
            if commitment != nil {
                openWindow(id: "early-reminder")
            } else {
                EarlyReminderWindowController.shared.close()
            }
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }
}

private struct HeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stay on time")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Choose the calendars that deserve your attention. In Your Face stays quiet until a commitment needs you.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProtectionStatusCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                statusTitle,
                systemImage: statusIcon
            )
            .font(.headline)
            .foregroundStyle(.primary)

            Text(
                statusDetail
            )
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusTitle: String {
        switch flow.status {
        case .noCoverage:
            return "No Coverage"
        case .active:
            return "Active Protection"
        case .unavailable:
            return "Coverage Needs Attention"
        }
    }

    private var statusDetail: String {
        switch flow.status {
        case .noCoverage:
            return "Select and confirm a calendar before commitments can be protected."
        case .active:
            return flow.isLaunchAtLoginEnabled
                ? "Your selected calendars are protected."
                : "Protection is configured, but start-at-login needs attention."
        case .unavailable:
            return flow.isBlockingAvailable
                ? "Google Calendar could not be refreshed. Protection is unavailable until coverage returns."
                : "Blocking requires Accessibility and Input Monitoring access before this reminder can protect you."
        }
    }

    private var statusIcon: String {
        flow.status == .active ? "checkmark.shield.fill" : "exclamationmark.triangle"
    }
}

private struct AccountSetupCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Google Calendar")
                .font(.headline)

            if flow.isRestoringConnection {
                ProgressView("Restoring Google Calendar…")
                    .controlSize(.small)
            } else if let account = flow.connectedAccount {
                Label(account.email, systemImage: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
                Button("Log Out") {
                    flow.disconnectGoogleAccount()
                }
                .buttonStyle(.bordered)
            } else {
                Text("Sign in with Google to choose the calendars you want protected.")
                    .foregroundStyle(.secondary)

                Button {
                    Task { await flow.connectGoogleAccount() }
                } label: {
                    Label(
                        flow.connectionState == .connecting ? "Opening Google…" : "Sign in with Google",
                        systemImage: "person.badge.key.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(flow.connectionState == .connecting)
            }

            if case .failed(let message) = flow.connectionState {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct CalendarSelectionCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monitored Calendars")
                .font(.headline)
            Text("Only selected calendars can create protection.")
                .foregroundStyle(.secondary)

            ForEach(flow.availableCalendars) { calendar in
                Toggle(
                    isOn: Binding(
                        get: { flow.selectedCalendarIDs.contains(calendar.id) },
                        set: { isSelected in
                            flow.setCalendarSelected(isSelected, calendarID: calendar.id)
                        }
                    )
                ) {
                    Label(calendar.name, systemImage: "calendar")
                }
                .toggleStyle(.checkbox)
            }

        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct EarlyReminderSettingsCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Early Reminder")
                .font(.headline)
            Text("A blocking reminder before an accepted commitment starts.")
                .foregroundStyle(.secondary)

            Stepper(
                value: Binding(
                    get: { flow.earlyReminderLeadTimeMinutes },
                    set: { flow.setEarlyReminderLeadTime(minutes: $0) }
                ),
                in: 5...30,
                step: 5
            ) {
                Text("Remind me \(flow.earlyReminderLeadTimeMinutes) minutes before")
            }
            .accessibilityLabel("Early Reminder lead time")
            .accessibilityValue("\(flow.earlyReminderLeadTimeMinutes) minutes")

            if !flow.isProtectionConfirmed {
                Text("Review your calendars and reminder timing, then confirm protection.")
                    .foregroundStyle(.secondary)
                Button("Confirm Protection") {
                    flow.confirmProtection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(flow.selectedCalendarIDs.isEmpty)
            } else {
                Label("Protection settings confirmed", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct TestAlertCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test the interruption")
                .font(.headline)
            Text("Make sure the alert is noticeable before trusting it with a real commitment.")
                .foregroundStyle(.secondary)
            Button("Show Test Alert") {
                flow.presentTestAlert()
                openWindow(id: "test-alert")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("t")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct LoginAvailabilityCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow

    var body: some View {
        Label(
            flow.isLaunchAtLoginEnabled ? "Ready at login" : "Start-at-login needs attention",
            systemImage: flow.isLaunchAtLoginEnabled ? "power" : "exclamationmark.triangle"
        )
        .foregroundStyle(.primary)
        .font(.callout)
    }
}

private struct TestAlertView: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StrongAlertView(
            title: "Test Commitment",
            timing: "Starting now",
            detail: "This is the same strong-alert experience used for a real commitment. No calendar event will be changed.",
            primaryActionTitle: "Handled",
            primaryAction: {
                flow.dismissTestAlert()
                dismiss()
            }
        )
        .accessibilityAddTraits(.isModal)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .onDisappear {
            flow.dismissTestAlert()
        }
    }
}

private struct EarlyReminderView: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var windowController = EarlyReminderWindowController.shared

    var body: some View {
        VStack(spacing: 18) {
            Label("Early Reminder", systemImage: "bell.fill")
                .font(.headline)
            if !windowController.isGlobalInteractionBarrierAvailable {
                if let commitment = flow.earlyReminderCommitment {
                    Text(commitment.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(flow.localStartTimeText(for: commitment))
                        .font(.title3.weight(.semibold))
                }
                Text("Blocking is unavailable until required privacy permissions are granted.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("Grant Accessibility and Input Monitoring access to continue.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Open Accessibility Settings") {
                    windowController.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                Button("Open Input Monitoring Settings") {
                    windowController.openInputMonitoringSettings()
                }
                Button("Try Again") {
                    windowController.retryBlocking()
                }
                Button("Clear Early Reminder") {
                    flow.clearEarlyReminder()
                    EarlyReminderWindowController.shared.close()
                }
            } else if let commitment = flow.earlyReminderCommitment {
                Text(commitment.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(flow.localStartTimeText(for: commitment))
                    .font(.title3.weight(.semibold))
                Text(flow.countdownText(for: commitment, at: Date()))
                    .foregroundStyle(.secondary)
                Text("Protection stays active if you clear this reminder.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Clear Early Reminder") {
                    flow.clearEarlyReminder()
                    EarlyReminderWindowController.shared.close()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            } else {
                Text("No upcoming commitment needs an early reminder.")
                    .foregroundStyle(.secondary)
                Button("Close") {
                    EarlyReminderWindowController.shared.close()
                }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(minWidth: 380)
        .accessibilityAddTraits(.isModal)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .onAppear {
            flow.setBlockingAvailability(false)
            guard let commitment = flow.earlyReminderCommitment else { return }
            EarlyReminderWindowController.shared.present(
                content: EarlyReminderFallbackContent(
                    title: commitment.title,
                    timing: flow.localStartTimeText(for: commitment)
                ),
                reopen: {
                    openWindow(id: "early-reminder")
                },
                clear: {
                    flow.clearEarlyReminder()
                    EarlyReminderWindowController.shared.close()
                }
            )
        }
        .onDisappear {
            if flow.earlyReminderCommitment == nil {
                flow.setBlockingAvailability(true)
                EarlyReminderWindowController.shared.close()
            } else {
                guard let commitment = flow.earlyReminderCommitment else { return }
                EarlyReminderWindowController.shared.surfaceDidDisappear(
                    content: EarlyReminderFallbackContent(
                        title: commitment.title,
                        timing: flow.localStartTimeText(for: commitment)
                    ),
                    reopen: {
                        openWindow(id: "early-reminder")
                    },
                    clear: {
                        flow.clearEarlyReminder()
                        EarlyReminderWindowController.shared.close()
                    }
                )
            }
        }
        .onChange(of: flow.earlyReminderCommitment) { _, commitment in
            if commitment == nil {
                flow.setBlockingAvailability(true)
                EarlyReminderWindowController.shared.close()
            }
        }
        .onChange(of: windowController.isGlobalInteractionBarrierAvailable) { _, isAvailable in
            flow.setBlockingAvailability(isAvailable)
        }
    }
}

private struct EarlyReminderFallbackContent {
    let title: String
    let timing: String
}

private struct EarlyReminderFallbackView: View {
    let content: EarlyReminderFallbackContent
    let isBlockingAvailable: Bool
    let clear: () -> Void
    let openAccessibilitySettings: () -> Void
    let openInputMonitoringSettings: () -> Void
    let retryBlocking: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Label("Early Reminder", systemImage: "bell.fill")
                .font(.headline)

            if isBlockingAvailable {
                Text(content.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(content.timing)
                    .font(.title3.weight(.semibold))
                Text("Protection stays active if you clear this reminder.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Clear Early Reminder", action: clear)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Text(content.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(content.timing)
                    .font(.title3.weight(.semibold))
                Text("Blocking is unavailable until required privacy permissions are granted.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Open Accessibility Settings", action: openAccessibilitySettings)
                    .buttonStyle(.borderedProminent)
                Button("Open Input Monitoring Settings", action: openInputMonitoringSettings)
                Button("Try Again", action: retryBlocking)
                Button("Clear Early Reminder", action: clear)
                    .buttonStyle(.borderedProminent)
                Text("The reminder will remain available here while permissions are being restored.")
                    .multilineTextAlignment(.center)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(minWidth: 380)
    }
}

private final class EarlyReminderInteractionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var reminderWindow: NSWindow?
    private var isApplicationActive = false
    private var eventTap: CFMachPort?
    private var wasDisabledByUserInput = false

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let gate = Unmanaged<EarlyReminderInteractionGate>
            .fromOpaque(refcon)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout {
            gate.reenableEventTap()
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByUserInput {
            // Respect a user/system request to stop this global event tap. The
            // controller notices the disabled tap on its retry timer and moves
            // the reminder into the permission-required state.
            gate.markDisabledByUserInput()
            return Unmanaged.passUnretained(event)
        }

        return gate.allows(type: type, event: event)
            ? Unmanaged.passUnretained(event)
            : nil
    }

    func start(for window: NSWindow, isApplicationActive: Bool) -> CFMachPort? {
        lock.lock()
        reminderWindow = window
        self.isApplicationActive = isApplicationActive
        let existingEventTap = eventTap
        lock.unlock()

        if existingEventTap != nil { return existingEventTap }

        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        let accessibilityOptions = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(accessibilityOptions)

        let eventMask = [
            CGEventType.leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .keyDown,
            .keyUp,
            .flagsChanged
        ].reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
        let newEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        lock.lock()
        eventTap = newEventTap
        lock.unlock()
        return newEventTap
    }

    func updateApplicationActivity(_ isActive: Bool) {
        lock.lock()
        isApplicationActive = isActive
        lock.unlock()
    }

    func allows(_ event: NSEvent) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return event.window === reminderWindow
    }

    func stop() {
        lock.lock()
        reminderWindow = nil
        isApplicationActive = false
        eventTap = nil
        wasDisabledByUserInput = false
        lock.unlock()
    }

    func markDisabledByUserInput() {
        lock.lock()
        wasDisabledByUserInput = true
        lock.unlock()
    }

    func userDisabledEventTap() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return wasDisabledByUserInput
    }

    private func reenableEventTap() {
        lock.lock()
        let eventTap: CFMachPort? = self.eventTap
        lock.unlock()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func allows(type: CGEventType, event: CGEvent) -> Bool {
        lock.lock()
        let isApplicationActive: Bool = self.isApplicationActive
        lock.unlock()

        switch type {
        case .leftMouseDown, .leftMouseUp,
             .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp,
             .mouseMoved, .leftMouseDragged,
             .rightMouseDragged, .otherMouseDragged,
             .scrollWheel:
            // Full-screen shield panels consume mouse events outside the
            // reminder. Avoid window-server enumeration in the event-tap
            // callback so pointer input remains responsive.
            return true
        case .flagsChanged:
            // VoiceOver builds its Control-Option chord from separate
            // modifier transitions. Never consume those transitions.
            return true
        case .keyDown, .keyUp:
            guard isApplicationActive else { return false }
            let systemModifierFlags: CGEventFlags = [
                .maskCommand,
                .maskAlternate,
                .maskControl
            ]
            let modifiers = event.flags.intersection(systemModifierFlags)
            let hasVoiceOverModifiers = modifiers.contains(.maskControl) && modifiers.contains(.maskAlternate)
            return modifiers.isEmpty || hasVoiceOverModifiers
        default:
            return true
        }
    }
}

@MainActor
private final class EarlyReminderWindowController: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = EarlyReminderWindowController()

    private weak var window: NSWindow?
    private var blockedWindows: [ObjectIdentifier: (window: NSWindow, wasIgnoringMouseEvents: Bool)] = [:]
    private var windowInteractionObservers: [NSObjectProtocol] = []
    private var shieldWindows: [NSWindow] = []
    private let interactionGate = EarlyReminderInteractionGate()
    private var localEventMonitor: Any?
    private var globalEventTap: CFMachPort?
    private var globalEventSource: CFRunLoopSource?
    private var workspaceInteractionObserver: NSObjectProtocol?
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    private var barrierRetryTimer: Timer?
    private var surfaceRecoveryTimer: Timer?
    private var reopenSurface: (@MainActor () -> Void)?
    private var clearEarlyReminder: (@MainActor () -> Void)?
    private var fallbackContent: EarlyReminderFallbackContent?
    private var fallbackPanel: NSPanel?
    private var surfaceRecoveryAttempts = 0
    private var allowsWindowClose = false
    private var isPresented = false
    private var isInteractionBarrierActive = false
    @Published private(set) var isGlobalInteractionBarrierAvailable = false

    func present(
        content: EarlyReminderFallbackContent,
        reopen: @escaping @MainActor () -> Void,
        clear: @escaping @MainActor () -> Void
    ) {
        reopenSurface = reopen
        clearEarlyReminder = clear
        fallbackContent = content
        if isPresented,
           let fallbackPanel,
           let swiftUIWindow = NSApp.windows.first(where: {
               $0 !== fallbackPanel && $0.title == "Early Reminder"
           }) {
            stopBarrierRetryMonitoring()
            deactivateInteractionBarrier()
            fallbackPanel.delegate = nil
            fallbackPanel.close()
            self.fallbackPanel = nil
            window = nil
            isPresented = false
            self.window = swiftUIWindow
        }
        if isPresented {
            window?.orderFrontRegardless()
            return
        }

        guard let window = NSApp.windows.first(where: {
            $0 !== fallbackPanel && $0.title == "Early Reminder"
        }) else {
            DispatchQueue.main.async { [weak self] in
                self?.present(content: content, reopen: reopen, clear: clear)
            }
            return
        }

        stopSurfaceRecoveryMonitoring()
        self.window = window
        window.delegate = self
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Keep the reminder visible through full-display, window, and app sharing.
        window.sharingType = .readOnly
        window.standardWindowButton(.closeButton)?.isEnabled = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isMovable = false
        isPresented = true
        startBarrierRetryMonitoring()
        let barrierAvailable = activateInteractionBarrier()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !barrierAvailable {
            window.orderFrontRegardless()
        }
    }

    func stop() {
        stopBarrierRetryMonitoring()
        stopSurfaceRecoveryMonitoring()
        guard isPresented else { return }
        deactivateInteractionBarrier()
        isPresented = false
        window?.standardWindowButton(.closeButton)?.isEnabled = true
    }

    func close() {
        allowsWindowClose = true
        let window = self.window
        stop()
        window?.delegate = nil
        window?.close()
        fallbackPanel = nil
        self.window = nil
        self.fallbackContent = nil
        self.clearEarlyReminder = nil
        allowsWindowClose = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        allowsWindowClose
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard isPresented, isInteractionBarrierActive else { return }
        window?.deminiaturize(nil)
        bringReminderToFront()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isPresented, isInteractionBarrierActive else { return }
        bringReminderToFront()
    }

    func windowDidResignMain(_ notification: Notification) {
        guard isPresented, isInteractionBarrierActive else { return }
        bringReminderToFront()
    }

    func surfaceDidDisappear(
        content: EarlyReminderFallbackContent,
        reopen: @escaping @MainActor () -> Void,
        clear: @escaping @MainActor () -> Void
    ) {
        reopenSurface = reopen
        clearEarlyReminder = clear
        fallbackContent = content
        guard isPresented else {
            startSurfaceRecoveryMonitoring()
            return
        }
        stopBarrierRetryMonitoring()
        deactivateInteractionBarrier()
        isPresented = false
        window = nil
        startSurfaceRecoveryMonitoring()
    }

    private func startSurfaceRecoveryMonitoring() {
        guard surfaceRecoveryTimer == nil, reopenSurface != nil else { return }
        surfaceRecoveryAttempts = 0
        surfaceRecoveryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.surfaceRecoveryAttempts += 1
                self.reopenSurface?()
                if self.surfaceRecoveryAttempts >= 4 {
                    self.showFallbackSurface()
                }
            }
        }
    }

    private func stopSurfaceRecoveryMonitoring() {
        surfaceRecoveryTimer?.invalidate()
        surfaceRecoveryTimer = nil
        surfaceRecoveryAttempts = 0
        reopenSurface = nil
    }

    private func showFallbackSurface() {
        guard !isPresented,
              let content = fallbackContent,
              let clearEarlyReminder else { return }

        let reopenSurface = self.reopenSurface
        stopSurfaceRecoveryMonitoring()
        self.reopenSurface = reopenSurface

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 290),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Early Reminder"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.sharingType = .readOnly
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: EarlyReminderFallbackView(
                content: content,
                isBlockingAvailable: isGlobalInteractionBarrierAvailable,
                clear: clearEarlyReminder,
                openAccessibilitySettings: { [weak self] in
                    self?.openAccessibilitySettings()
                },
                openInputMonitoringSettings: { [weak self] in
                    self?.openInputMonitoringSettings()
                },
                retryBlocking: { [weak self] in
                    self?.retryBlocking()
                }
            )
        )
        panel.center()
        fallbackPanel = panel
        window = panel
        isPresented = true
        startBarrierRetryMonitoring()
        let barrierAvailable = activateInteractionBarrier()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if !barrierAvailable {
            panel.orderFrontRegardless()
        }
    }

    func openAccessibilitySettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }

    func openInputMonitoringSettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }

    func retryBlocking() {
        guard isPresented else { return }
        stopBarrierRetryMonitoring()
        deactivateInteractionBarrier()
        startBarrierRetryMonitoring()
        retryInteractionBarrierIfNeeded()
    }

    @discardableResult
    private func activateInteractionBarrier() -> Bool {
        guard isPresented, let window else { return false }
        if isInteractionBarrierActive { return true }
        guard let eventTap = interactionGate.start(
            for: window,
            isApplicationActive: NSApp.isActive
        ) else {
            isGlobalInteractionBarrierAvailable = false
            return false
        }
        guard let eventSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0) else {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            interactionGate.stop()
            isGlobalInteractionBarrierAvailable = false
            return false
        }
        if previousPresentationOptions == nil {
            previousPresentationOptions = NSApp.presentationOptions
            NSApp.presentationOptions.formUnion([
                .disableProcessSwitching,
                .disableAppleMenu,
                .disableForceQuit,
                .disableSessionTermination,
                .disableHideApplication,
                .hideDock
            ])
        }
        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
                .leftMouseDragged,
                .rightMouseDragged,
                .otherMouseDragged,
                .scrollWheel,
                .keyDown
            ]) { [interactionGate] event in
                interactionGate.allows(event) ? event : nil
            }
        }
        if globalEventSource == nil {
            globalEventTap = eventTap
            globalEventSource = eventSource
            CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        blockVisibleWindows()
        if shieldWindows.isEmpty {
            createShieldWindows()
        }
        if windowInteractionObservers.isEmpty {
            windowInteractionObservers = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didBecomeMainNotification,
                NSApplication.didChangeScreenParametersNotification,
                NSApplication.didBecomeActiveNotification,
                NSApplication.didResignActiveNotification
            ].map { notificationName in
                NotificationCenter.default.addObserver(
                    forName: notificationName,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    if notification.name == NSApplication.didChangeScreenParametersNotification {
                        Task { @MainActor [weak self] in
                            self?.recreateShieldWindows()
                        }
                        return
                    }
                    if notification.name == NSApplication.didBecomeActiveNotification {
                        self?.interactionGate.updateApplicationActivity(true)
                        return
                    }
                    if notification.name == NSApplication.didResignActiveNotification {
                        self?.interactionGate.updateApplicationActivity(false)
                        return
                    }
                    guard let candidate = notification.object as? NSWindow else { return }
                    Task { @MainActor [weak self] in
                        self?.block(candidate)
                    }
                }
            }
        }
        if workspaceInteractionObserver == nil {
            workspaceInteractionObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let activatedProcessIdentifier = (notification.object as? NSRunningApplication)?.processIdentifier
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isPresented,
                          self.isInteractionBarrierActive,
                          let activatedProcessIdentifier else {
                        return
                    }
                    let isThisApplication = activatedProcessIdentifier == ProcessInfo.processInfo.processIdentifier
                    self.interactionGate.updateApplicationActivity(isThisApplication)
                    if !isThisApplication {
                        NSApp.activate(ignoringOtherApps: true)
                        self.window?.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
        isInteractionBarrierActive = true
        isGlobalInteractionBarrierAvailable = true
        refreshFallbackPanelContent()
        return true
    }

    private func refreshFallbackPanelContent() {
        guard let panel = fallbackPanel,
              let content = fallbackContent,
              let clearEarlyReminder else { return }
        panel.contentView = NSHostingView(
            rootView: EarlyReminderFallbackView(
                content: content,
                isBlockingAvailable: isGlobalInteractionBarrierAvailable,
                clear: clearEarlyReminder,
                openAccessibilitySettings: { [weak self] in
                    self?.openAccessibilitySettings()
                },
                openInputMonitoringSettings: { [weak self] in
                    self?.openInputMonitoringSettings()
                },
                retryBlocking: { [weak self] in
                    self?.retryBlocking()
                }
            )
        )
    }

    private func deactivateInteractionBarrier() {
        guard isInteractionBarrierActive || localEventMonitor != nil || globalEventSource != nil else { return }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), globalEventSource, .commonModes)
            CFRunLoopSourceInvalidate(globalEventSource)
            self.globalEventSource = nil
        }
        if let globalEventTap {
            CGEvent.tapEnable(tap: globalEventTap, enable: false)
            self.globalEventTap = nil
        }
        interactionGate.stop()
        if let workspaceInteractionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceInteractionObserver)
            self.workspaceInteractionObserver = nil
        }
        windowInteractionObservers.forEach(NotificationCenter.default.removeObserver)
        windowInteractionObservers.removeAll()
        shieldWindows.forEach { $0.close() }
        shieldWindows.removeAll()
        if let previousPresentationOptions {
            NSApp.presentationOptions = previousPresentationOptions
            self.previousPresentationOptions = nil
        }
        blockedWindows.values.forEach { entry in
            entry.window.ignoresMouseEvents = entry.wasIgnoringMouseEvents
        }
        blockedWindows.removeAll()
        isInteractionBarrierActive = false
        isGlobalInteractionBarrierAvailable = false
    }

    private func startBarrierRetryMonitoring() {
        guard barrierRetryTimer == nil else { return }
        barrierRetryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retryInteractionBarrierIfNeeded()
            }
        }
    }

    private func stopBarrierRetryMonitoring() {
        barrierRetryTimer?.invalidate()
        barrierRetryTimer = nil
    }

    private func retryInteractionBarrierIfNeeded() {
        guard isPresented else { return }
        if isInteractionBarrierActive {
            if interactionGate.userDisabledEventTap() {
                stopBarrierRetryMonitoring()
                deactivateInteractionBarrier()
                refreshFallbackPanelContent()
                return
            }
            guard let globalEventTap, CGEvent.tapIsEnabled(tap: globalEventTap) else {
                return
            }
            return
        }
        guard activateInteractionBarrier() else { return }
        bringReminderToFront()
    }

    private func blockVisibleWindows() {
        NSApp.windows.forEach(block)
    }

    private func block(_ candidate: NSWindow) {
        guard isPresented,
              let reminderWindow = window,
              candidate !== reminderWindow,
              !shieldWindows.contains(where: { $0 === candidate }),
              candidate.isVisible else { return }
        let identifier = ObjectIdentifier(candidate)
        guard blockedWindows[identifier] == nil else { return }
        blockedWindows[identifier] = (
            window: candidate,
            wasIgnoringMouseEvents: candidate.ignoresMouseEvents
        )
        candidate.ignoresMouseEvents = true
    }

    private func createShieldWindows() {
        shieldWindows = NSScreen.screens.map { screen in
            let shield = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            shield.level = .screenSaver
            shield.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            shield.isOpaque = false
            shield.backgroundColor = .clear
            shield.hasShadow = false
            shield.hidesOnDeactivate = false
            shield.ignoresMouseEvents = false
            shield.isReleasedWhenClosed = false
            shield.orderFrontRegardless()
            return shield
        }
    }

    private func recreateShieldWindows() {
        guard isPresented, isInteractionBarrierActive else { return }
        shieldWindows.forEach { $0.close() }
        shieldWindows.removeAll()
        createShieldWindows()
        bringReminderToFront()
    }

    private func bringReminderToFront() {
        guard isPresented else { return }
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
        window?.makeKey()
    }
}

private struct StrongAlertView: View {
    let title: String
    let timing: String
    let detail: String
    let primaryActionTitle: String
    let primaryAction: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Label("Strong Alert", systemImage: "bell.and.waves.left.and.right.fill")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(title)
                .font(.largeTitle.bold())
            Text(timing)
                .font(.title3.weight(.semibold))
            Text(detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(primaryActionTitle, action: primaryAction)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(primaryActionTitle)
        }
        .padding(32)
        .frame(minWidth: 460)
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            VStack(alignment: .leading, spacing: 12) {
                if let commitment = flow.upcomingCommitment {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(commitment.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(flow.countdownText(for: commitment, at: context.date))
                            .font(.subheadline.weight(.semibold))
                        Text(flow.localStartTimeText(for: commitment))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if flow.earlyReminderCommitment != nil {
                        Button("Open Early Reminder") {
                            openWindow(id: "early-reminder")
                        }
                        .keyboardShortcut("r")
                    }

                    Divider()
                }

                Label(
                    flow.menuBarTitle,
                    systemImage: flow.status == .active ? "checkmark.shield" : "exclamationmark.triangle"
                )
                    .font(.headline)

                if let account = flow.connectedAccount {
                    Text(account.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Log Out") {
                        flow.disconnectGoogleAccount()
                    }
                    .keyboardShortcut("l")
                }

                Divider()

                Button("Open Setup") {
                    openWindow(id: "setup")
                }
                .keyboardShortcut("o")

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear {
            flow.refreshLaunchAtLoginStatus()
        }
    }

}

private struct MenuBarLabel: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(
            flow.menuBarTitle,
            systemImage: flow.status == .active ? "checkmark.circle.fill" : "calendar.badge.exclamationmark"
        )
        .onChange(of: flow.earlyReminderCommitment) { _, commitment in
            if commitment != nil {
                openWindow(id: "early-reminder")
            } else {
                EarlyReminderWindowController.shared.close()
            }
        }
    }
}
