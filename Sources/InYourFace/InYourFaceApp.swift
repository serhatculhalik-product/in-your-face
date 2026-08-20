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
                    clientID: googleOAuthClientID()
                )
            ),
            launchAtLogin: MacLaunchAtLoginController()
        )
        _flow = StateObject(wrappedValue: protectionFlow)
        Task { await protectionFlow.restoreSavedConnection() }
    }

    var body: some Scene {
        WindowGroup("In Your Face", id: "setup") {
            SetupView()
                .environmentObject(flow)
                .frame(minWidth: 520, minHeight: 560)
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(flow)
        } label: {
            Label(
                flow.menuBarTitle,
                systemImage: flow.status == .active ? "checkmark.circle.fill" : "calendar.badge.exclamationmark"
            )
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HeaderView()
                ProtectionStatusCard()
                AccountSetupCard()

                if flow.connectedAccount != nil {
                    CalendarSelectionCard()
                    TestAlertCard()
                }

                LoginAvailabilityCard()
            }
            .padding(32)
        }
        .onAppear {
            flow.refreshLaunchAtLoginStatus()
        }
        .sheet(
            isPresented: Binding(
                get: { flow.isTestAlertPresented },
                set: { isPresented in
                    if !isPresented {
                        flow.dismissTestAlert()
                    }
                }
            )
        ) {
            TestAlertView()
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
            .foregroundStyle(flow.status == .active ? Color.green : Color.orange)

            Text(
                flow.status == .active
                    ? "Your selected calendars are protected."
                    : flow.status == .needsAttention
                        ? "Protection is configured, but start-at-login needs attention."
                        : "Select a calendar before commitments can be protected."
            )
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusTitle: String {
        switch flow.status {
        case .noCoverage:
            return "No Coverage"
        case .active:
            return "Active Protection"
        case .needsAttention:
            return "Start at Login Needs Attention"
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
            } else {
                Text("Connect one Google account to choose the calendars you want protected.")
                    .foregroundStyle(.secondary)

                Button {
                    Task { await flow.connectGoogleAccount() }
                } label: {
                    Label(
                        flow.connectionState == .connecting ? "Opening Google…" : "Connect Google Account",
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

private struct TestAlertCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test the interruption")
                .font(.headline)
            Text("Make sure the alert is noticeable before trusting it with a real commitment.")
                .foregroundStyle(.secondary)
            Button("Show Test Alert") {
                flow.presentTestAlert()
            }
            .buttonStyle(.bordered)
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
        .foregroundStyle(flow.isLaunchAtLoginEnabled ? Color.secondary : Color.orange)
        .font(.callout)
    }
}

private struct TestAlertView: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow

    var body: some View {
        StrongAlertView(
            title: "Test Commitment",
            timing: "Starting now",
            detail: "This is the same strong-alert experience used for a real commitment. No calendar event will be changed.",
            primaryActionTitle: "Handled",
            primaryAction: flow.dismissTestAlert
        )
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
                .foregroundStyle(.blue)
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
        VStack(alignment: .leading, spacing: 12) {
            Label(
                flow.menuBarTitle,
                systemImage: flow.status == .active ? "checkmark.shield" : "exclamationmark.triangle"
            )
                .font(.headline)

            if let account = flow.connectedAccount {
                Text(account.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .padding(16)
        .frame(width: 260)
        .onAppear {
            flow.refreshLaunchAtLoginStatus()
        }
    }
}
