import AppKit
import CommitmentProtection
import SwiftUI

struct SettingsRootView: View {
    var body: some View {
        TabView {
            AccountsSettingsPane()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            CalendarsSettingsPane()
                .tabItem { Label("Calendars", systemImage: "calendar") }
            RemindersSettingsPane()
                .tabItem { Label("Reminders", systemImage: "bell") }
            ActivitySettingsPane()
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 500, idealHeight: 560)
    }
}

private struct AccountsSettingsPane: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @State private var pendingDisconnect: AccountCoverage?

    var body: some View {
        Form {
            Section("Protection") {
                SettingsProtectionSummary()
            }

            Section("Google Accounts") {
                if flow.accountCoverages.isEmpty {
                    ContentUnavailableView(
                        "No Google Accounts",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Connect Google Calendar for this session to resume protection. Any saved calendar choices will be reapplied.")
                    )
                } else {
                    ForEach(flow.accountCoverages) { coverage in
                        AdaptiveSettingsActionRow {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(accountLabel(for: coverage))
                                    .lineLimit(2)
                                    .help(accountLabel(for: coverage))
                                    .textSelection(.enabled)
                                CoverageHealthView(
                                    coverage: coverage,
                                    warning: flow.coverageWarning(for: coverage.account.id)
                                )
                            }
                        } actions: {
                            if coverage.connectionState == .reconnectRequired {
                                Button("Reconnect…") {
                                    Task {
                                        await flow.reconnectGoogleAccount(accountID: coverage.account.id)
                                    }
                                }
                                .disabled(flow.isConnectingAccount)
                            }
                            Button("Disconnect…") {
                                pendingDisconnect = coverage
                            }
                        }
                    }

                    if isCheckingCoverage {
                        ProgressView("Checking calendar coverage…")
                            .controlSize(.small)
                    } else if needsCoverageRetry, flow.isRefreshingCoverage {
                        ProgressView("Retrying calendar access…")
                            .controlSize(.small)
                    } else if needsCoverageRetry {
                        Button {
                            Task { await flow.refreshCommitmentProtection() }
                        } label: {
                            Label("Retry Calendar Access", systemImage: "arrow.clockwise")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("Session-only Google access", systemImage: "lock.shield")
                        .font(.callout.weight(.semibold))
                    Text("Google access is kept only while In Your Face is open. Reconnect after every relaunch.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await flow.connectGoogleAccount() }
                } label: {
                    Label(
                        connectionActionTitle,
                        systemImage: flow.accountConnectionError == nil ? "person.badge.plus" : "arrow.clockwise"
                    )
                }
                .disabled(flow.isConnectingAccount)

                if let message = flow.accountConnectionError {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Google Calendar couldn’t connect", systemImage: "exclamationmark.triangle")
                        Text(message)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(InterfaceCopy.connectionFailureAnnouncement(message))
                }

                if let message = flow.accountDisconnectionError {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Account couldn’t disconnect", systemImage: "exclamationmark.triangle")
                            Text(message)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(InterfaceCopy.disconnectionFailureAnnouncement(message))
                        if let coverage = failedDisconnectionCoverage {
                            Button("Try Again…") {
                                pendingDisconnect = coverage
                            }
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Section("Availability") {
                Label(
                    flow.isLaunchAtLoginEnabled ? "Starts at Login" : "Won’t Start at Login",
                    systemImage: flow.isLaunchAtLoginEnabled ? "power" : "exclamationmark.triangle"
                )
                Text(availabilityDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !flow.isLaunchAtLoginEnabled {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            launchAtLoginRecoveryActions
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            launchAtLoginRecoveryActions
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear { flow.refreshLaunchAtLoginStatus() }
        .onChange(of: flow.accountConnectionError) { _, message in
            announceConnectionError(message)
        }
        .onChange(of: flow.accountDisconnectionError) { _, message in
            announceDisconnectionError(message)
        }
        .alert(
            pendingDisconnect.map {
                InterfaceCopy.disconnectAccountTitle(accountLabel(for: $0))
            }
                ?? "Disconnect this Connected Account?",
            isPresented: Binding(
                get: { pendingDisconnect != nil },
                set: { if !$0 { pendingDisconnect = nil } }
            )
        ) {
            Button("Keep Connected", role: .cancel) {
                pendingDisconnect = nil
            }
            Button("Disconnect Account", role: .destructive) {
                guard let pendingDisconnect else { return }
                _ = flow.disconnectGoogleAccount(accountID: pendingDisconnect.account.id)
                self.pendingDisconnect = nil
            }
        } message: {
            Text(InterfaceCopy.disconnectAccountMessage(
                hasOtherConnectedAccounts: flow.accountCoverages.count > 1
            ))
        }
    }

    @ViewBuilder
    private var launchAtLoginRecoveryActions: some View {
        Button("Try Again") {
            flow.requestLaunchAtLogin()
        }
        Button("Open Login Items…") {
            openLoginItemsSettings()
        }
    }

    private var connectionActionTitle: String {
        if flow.isConnectingAccount {
            return "Connecting…"
        }
        return flow.accountConnectionError == nil ? "Add Google Account…" : "Try Again…"
    }

    private var availabilityDetail: String {
        if flow.isLaunchAtLoginEnabled {
            return "In Your Face opens at login. Calendar protection begins after you connect Google Calendar for that session."
        }
        let launchDetail = InterfaceCopy.sentence(
            flow.launchAtLoginError ??
                "In Your Face is open now, but it may not start automatically after your next sign-in"
        )
        return "\(launchDetail) After opening, connect Google Calendar for that session to start protection."
    }

    private var failedDisconnectionCoverage: AccountCoverage? {
        guard let accountID = flow.failedAccountDisconnectionID else { return nil }
        return flow.accountCoverages.first { $0.account.id == accountID }
    }

    private func accountLabel(for coverage: AccountCoverage) -> String {
        InterfaceCopy.connectedAccountLabel(
            email: coverage.account.email,
            displayName: coverage.account.displayName
        )
    }

    private var isCheckingCoverage: Bool {
        flow.isCheckingCoverage
    }

    private var needsCoverageRetry: Bool {
        flow.accountCoverages.contains { coverage in
            switch flow.coverage(for: coverage.account.id) {
            case .stale, .unavailable:
                return true
            case .none, .noCoverage, .checking, .fresh, .reconnectRequired:
                return false
            }
        }
    }

    private func announceConnectionError(_ message: String?) {
        guard let message else { return }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [.announcement: InterfaceCopy.connectionFailureAnnouncement(message)]
        )
    }

    private func announceDisconnectionError(_ message: String?) {
        guard let message else { return }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [.announcement: InterfaceCopy.disconnectionFailureAnnouncement(message)]
        )
    }

    private func openLoginItemsSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(settingsURL)
    }
}

private struct CalendarsSettingsPane: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @State private var selectedAccountID: String?
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if flow.accountCoverages.isEmpty {
                ContentUnavailableView(
                    "No Google Account",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Connect Google Calendar for this session in Accounts. Any saved Monitored Calendar choices will be applied when the account returns.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let coverage = selectedCoverage {
                Picker("Account", selection: selectedAccountBinding) {
                    ForEach(flow.accountCoverages) { accountCoverage in
                        Text(InterfaceCopy.connectedAccountLabel(
                            email: accountCoverage.account.email,
                            displayName: accountCoverage.account.displayName
                        ))
                        .tag(Optional(accountCoverage.account.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 420, alignment: .leading)

                CoverageHealthView(
                    coverage: coverage,
                    warning: flow.coverageWarning(for: coverage.account.id)
                )

                CalendarSelectionList(
                    coverage: coverage,
                    searchText: $searchText
                )

                Divider()

                AdaptiveSettingsActionRow {
                    Label(
                        coverage.isProtectionConfirmed
                            ? "Selected calendars confirmed"
                            : "Selected calendars are not protected yet",
                        systemImage: coverage.isProtectionConfirmed
                            ? "checkmark.circle"
                            : "exclamationmark.circle"
                    )
                    .foregroundStyle(.secondary)
                } actions: {
                    Button("Protect Selected Calendars") {
                        flow.confirmProtection(for: coverage.account.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        coverage.isProtectionConfirmed ||
                            flow.selectedCalendarIDs(for: coverage.account.id).isEmpty
                    )
                }
            }
        }
        .padding(24)
        .onAppear { synchronizeSelectedAccount() }
        .onChange(of: flow.accountCoverages.map(\.id)) { _, _ in
            synchronizeSelectedAccount()
        }
        .onChange(of: selectedAccountID) { _, _ in
            searchText = ""
        }
    }

    private var selectedAccountBinding: Binding<String?> {
        Binding(
            get: { selectedAccountID ?? flow.accountCoverages.first?.id },
            set: { selectedAccountID = $0 }
        )
    }

    private var selectedCoverage: AccountCoverage? {
        let resolvedID = selectedAccountID ?? flow.accountCoverages.first?.id
        return flow.accountCoverages.first { $0.id == resolvedID }
    }

    private func synchronizeSelectedAccount() {
        guard let selectedAccountID,
              flow.accountCoverages.contains(where: { $0.id == selectedAccountID }) else {
            self.selectedAccountID = flow.accountCoverages.first?.id
            return
        }
    }
}

private struct RemindersSettingsPane: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var windowController = EarlyReminderWindowController.shared

    var body: some View {
        Form {
            if flow.isProtectionConfirmationRequired {
                Section {
                    AdaptiveSettingsActionRow {
                        Label(
                            "Protection is off until you confirm these timing changes",
                            systemImage: "exclamationmark.circle"
                        )
                    } actions: {
                        Button("Confirm Changes and Resume Protection") {
                            flow.confirmAllProtection()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section("Early Reminder") {
                Toggle(
                    "Show Early Reminder",
                    isOn: Binding(
                        get: { flow.isEarlyReminderEnabled },
                        set: { flow.setEarlyReminderEnabled($0) }
                    )
                )
                Stepper(
                    InterfaceCopy.remindMeBefore(flow.earlyReminderLeadTimeMinutes),
                    value: Binding(
                        get: { flow.earlyReminderLeadTimeMinutes },
                        set: { flow.setEarlyReminderLeadTime(minutes: $0) }
                    ),
                    in: 5...30,
                    step: 5
                )
                .disabled(!flow.isEarlyReminderEnabled)
                .accessibilityLabel("Early Reminder lead time")
                .accessibilityValue(InterfaceCopy.minuteDuration(flow.earlyReminderLeadTimeMinutes))
            }

            Section("Strong Alert") {
                Stepper(
                    InterfaceCopy.repeatEvery(flow.strongAlertRepeatIntervalMinutes),
                    value: Binding(
                        get: { flow.strongAlertRepeatIntervalMinutes },
                        set: { flow.setStrongAlertRepeatInterval(minutes: $0) }
                    ),
                    in: 1...5
                )
                .accessibilityLabel("Strong Alert repeat interval")
                .accessibilityValue(InterfaceCopy.minuteDuration(flow.strongAlertRepeatIntervalMinutes))

                Button("Show Test Alert") {
                    flow.presentTestAlert()
                    openWindow(id: "test-alert")
                }
                .disabled(flow.isTestAlertPresented)
            }

            Section("Optional Blocking Mode") {
                Toggle(
                    "Block other apps while an Early Reminder is open",
                    isOn: Binding(
                        get: { flow.isBlockingModeEnabled },
                        set: { isEnabled in
                            flow.setBlockingModeEnabled(isEnabled)
                            windowController.setBlockingModeEnabled(isEnabled)
                        }
                    )
                )

                if flow.isBlockingModeEnabled {
                    Text("Blocking Mode needs Accessibility and Input Monitoring permissions. Without both, the Early Reminder stays visible but cannot block interaction with other apps.")
                        .foregroundStyle(.secondary)
                    if flow.earlyReminderCommitment != nil {
                        Label(
                            flow.isBlockingAvailable
                                ? "Blocking Mode is active for the current Early Reminder."
                                : "Blocking Mode is unavailable for the current Early Reminder. It remains visible in visual-only mode.",
                            systemImage: flow.isBlockingAvailable
                                ? "checkmark.circle"
                                : "exclamationmark.triangle"
                        )
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            blockingPermissionButtons
                        }
                        VStack(alignment: .leading) {
                            blockingPermissionButtons
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    @ViewBuilder
    private var blockingPermissionButtons: some View {
        Button("Open Accessibility Settings") {
            windowController.openAccessibilitySettings()
        }
        Button("Open Input Monitoring Settings") {
            windowController.openInputMonitoringSettings()
        }
    }
}

private struct AdaptiveSettingsActionRow<Status: View, Actions: View>: View {
    private let status: Status
    private let actions: Actions

    init(
        @ViewBuilder status: () -> Status,
        @ViewBuilder actions: () -> Actions
    ) {
        self.status = status()
        self.actions = actions()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                status
                Spacer(minLength: 12)
                actions
            }

            VStack(alignment: .leading, spacing: 10) {
                status
                    .frame(maxWidth: .infinity, alignment: .leading)
                actions
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

private struct ActivitySettingsPane: View {
    var body: some View {
        ScrollView {
            ProtectionActivityCard(isCard: false)
                .padding(24)
        }
    }
}

private struct SettingsProtectionSummary: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow

    var body: some View {
        LabeledContent {
            Text(statusDetail)
                .foregroundStyle(.secondary)
        } label: {
            Label(statusTitle, systemImage: statusIcon)
                .font(.headline)
        }
    }

    private var statusTitle: String {
        flow.connectionState == .reconnectRequired
            ? "Calendar Access Required"
            : flow.menuBarTitle
    }

    private var statusIcon: String {
        if flow.isPaused() {
            return "pause.circle.fill"
        }
        if flow.connectionState == .reconnectRequired {
            return "person.crop.circle.badge.exclamationmark"
        }
        switch flow.status {
        case .active:
            return "checkmark.shield.fill"
        case .noCoverage:
            return "shield.slash"
        case .unavailable:
            return "exclamationmark.triangle"
        }
    }

    private var statusDetail: String {
        if flow.isPaused() {
            return flow.pauseExpirationText()
        }
        if flow.connectionState == .reconnectRequired {
            return "Reconnect Google Calendar for this session to resume protection."
        }
        switch flow.status {
        case .active:
            return "Selected calendars are protected."
        case .noCoverage:
            return "Choose and confirm at least one calendar."
        case .unavailable:
            return flow.isCheckingCoverage
                ? "Checking Google Calendar before protection becomes active."
                : "Calendar coverage needs attention."
        }
    }
}
