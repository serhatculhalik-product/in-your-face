import AppKit
import CommitmentProtection
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
                flow.status == .active
                    ? (flow.isLaunchAtLoginEnabled
                        ? "Your selected calendars are protected."
                        : "Protection is configured, but start-at-login needs attention.")
                    : "Select a calendar before commitments can be protected."
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
            Text("A non-blocking reminder before an accepted commitment starts.")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            Label("Early Reminder", systemImage: "bell.fill")
                .font(.headline)
            if let commitment = flow.earlyReminderCommitment {
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
            EarlyReminderWindowController.shared.present()
        }
        .onDisappear {
            EarlyReminderWindowController.shared.stop()
        }
    }
}

@MainActor
private final class EarlyReminderWindowController {
    static let shared = EarlyReminderWindowController()

    private weak var window: NSWindow?
    private var blockedWindows: [NSWindow] = []
    private var isPresented = false

    func present() {
        guard !isPresented else {
            window?.orderFrontRegardless()
            return
        }

        guard let window = NSApp.windows.first(where: { $0.title == "Early Reminder" }) else {
            DispatchQueue.main.async { [weak self] in
                self?.present()
            }
            return
        }

        self.window = window
        window.level = .modalPanel
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.standardWindowButton(.closeButton)?.isEnabled = false
        blockedWindows = NSApp.windows.filter { candidate in
            candidate !== window && candidate.isVisible && !candidate.ignoresMouseEvents
        }
        blockedWindows.forEach { $0.ignoresMouseEvents = true }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        isPresented = true
    }

    func stop() {
        guard isPresented else { return }
        blockedWindows.forEach { $0.ignoresMouseEvents = false }
        blockedWindows.removeAll()
        isPresented = false
        window?.standardWindowButton(.closeButton)?.isEnabled = true
    }

    func close() {
        stop()
        window?.close()
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
            }
        }
    }
}
