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
    private enum AccountTerminationKind {
        case disconnect
        case remove
    }

    private struct PendingAccountTermination {
        let coverage: AccountCoverage
        let kind: AccountTerminationKind
    }

    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @EnvironmentObject private var testToolsController: TestToolsController
    @State private var pendingAccountTermination: PendingAccountTermination?
    @State private var lastAccountTerminationKind: AccountTerminationKind?
    @State private var isEncryptedStorageResetConfirmationPresented = false

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
                        description: Text("Connect Google Calendar to protect selected calendars on this Mac.")
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
                            accountActions(for: coverage)
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
                    Label(
                        testToolsController.isTestMode
                            ? "Isolated simulated calendar access"
                            : "Device-bound encrypted Google access",
                        systemImage: testToolsController.isTestMode ? "testtube.2" : "lock.shield"
                    )
                        .font(.callout.weight(.semibold))
                    Text(testToolsController.isTestMode
                        ? "This account and its calendars are deterministic fixtures stored only in this test profile. No browser or Google grant is used."
                        : "Google credentials and calendar data are encrypted for this Mac, excluded from backups, and never stored in Keychain. Routine relaunches do not require reconnection.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let storageError = flow.encryptedStorageError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Protected Google data needs attention", systemImage: "lock.trianglebadge.exclamationmark")
                            .font(.callout.weight(.semibold))
                        Text(storageError)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if flow.requiresEncryptedStorageReset {
                            Button("Reset Local Encrypted Data…", role: .destructive) {
                                isEncryptedStorageResetConfirmationPresented = true
                            }
                            .disabled(flow.isGoogleAccountOperationInProgress)
                        }
                    }
                }

                if let reviewNotice = flow.googleAccessReviewNotice {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Review Google Account access", systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.callout.weight(.semibold))
                        Text(reviewNotice)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if !testToolsController.isTestMode {
                    Button("Manage Google Account Access…") {
                        openGoogleAccessManagement()
                    }
                }

                Button {
                    Task { await flow.connectGoogleAccount() }
                } label: {
                    Label(
                        connectionActionTitle,
                        systemImage: flow.accountConnectionError == nil ? "person.badge.plus" : "arrow.clockwise"
                    )
                }
                .disabled(flow.isGoogleAccountOperationInProgress)

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
                            Label(accountTerminationFailureTitle, systemImage: "exclamationmark.triangle")
                            Text(message)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(accountTerminationFailureAnnouncement(message))
                        if let coverage = failedDisconnectionCoverage {
                            Button("Try Again…") {
                                pendingAccountTermination = PendingAccountTermination(
                                    coverage: coverage,
                                    kind: lastAccountTerminationKind ?? .disconnect
                                )
                            }
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Section("Availability") {
                Toggle("Start Meeting Incoming at login", isOn: launchAtLoginBinding)
                Text(availabilityDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if flow.launchAtLoginError != nil {
                    Button("Open Login Items…") {
                        openLoginItemsSettings()
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
            announceAccountTerminationError(message)
        }
        .alert(
            accountTerminationTitle,
            isPresented: Binding(
                get: { pendingAccountTermination != nil },
                set: { if !$0 { pendingAccountTermination = nil } }
            )
        ) {
            Button(accountTerminationCancelTitle, role: .cancel) {
                pendingAccountTermination = nil
            }
            Button(accountTerminationConfirmTitle, role: .destructive) {
                confirmAccountTermination()
            }
        } message: {
            Text(accountTerminationMessage)
        }
        .alert(
            "Reset all local encrypted Google data?",
            isPresented: $isEncryptedStorageResetConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Local Data", role: .destructive) {
                _ = flow.resetEncryptedGoogleData()
            }
        } message: {
            Text("First review Google Account access if you want to revoke Meeting Incoming remotely. This permanently removes every locally encrypted credential, calendar choice, event snapshot, and activity entry from this Mac. You’ll need to connect each account again.")
        }
    }

    @ViewBuilder
    private func accountActions(for coverage: AccountCoverage) -> some View {
        let presentation = AccountRowActionPresentation.make(
            connectionState: coverage.connectionState,
            isConnectingThisAccount: flow.connectingAccountID == coverage.account.id
        )

        switch presentation.connectionAction {
        case .connecting:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting…")
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

        case .reconnect:
            HStack(spacing: 6) {
                Button("Reconnect…") {
                    Task {
                        await flow.reconnectGoogleAccount(accountID: coverage.account.id)
                    }
                }
                .disabled(flow.isGoogleAccountOperationInProgress)

                if presentation.showsRemoveAccountAction {
                    Menu {
                        Button("Remove Account…", role: .destructive) {
                            pendingAccountTermination = PendingAccountTermination(
                                coverage: coverage,
                                kind: .remove
                            )
                        }
                    } label: {
                        Label(
                            "More actions for \(accountLabel(for: coverage))",
                            systemImage: "ellipsis.circle"
                        )
                        .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .disabled(flow.isGoogleAccountOperationInProgress)
                    .help("More actions for \(accountLabel(for: coverage))")
                }
            }

        case .disconnect:
            HStack(spacing: 6) {
                Button("Disconnect…") {
                    pendingAccountTermination = PendingAccountTermination(
                        coverage: coverage,
                        kind: .disconnect
                    )
                }
                .disabled(flow.isGoogleAccountOperationInProgress)

                if presentation.showsRemoveAccountAction {
                    Menu {
                        Button("Remove Account…", role: .destructive) {
                            pendingAccountTermination = PendingAccountTermination(
                                coverage: coverage,
                                kind: .remove
                            )
                        }
                    } label: {
                        Label(
                            "More actions for \(accountLabel(for: coverage))",
                            systemImage: "ellipsis.circle"
                        )
                        .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .disabled(flow.isGoogleAccountOperationInProgress)
                    .help("More actions for \(accountLabel(for: coverage))")
                }
            }
        }
    }

    private var connectionActionTitle: String {
        if flow.isConnectingAccount {
            return "Connecting…"
        }
        if flow.accountConnectionError != nil {
            return "Try Again…"
        }
        return testToolsController.isTestMode
            ? "Add Simulated Account"
            : "Add Google Account…"
    }

    private var availabilityDetail: String {
        if testToolsController.isTestMode {
            return flow.isLaunchAtLoginEnabled
                ? "Simulated as enabled for this test profile. The real macOS Login Item is unchanged."
                : "Simulated as disabled for this test profile. The real macOS Login Item is unchanged."
        }
        if flow.isLaunchAtLoginEnabled {
            return "Meeting Incoming opens after sign-in and restores protection automatically while Google authorization remains valid."
        }
        let launchDetail = InterfaceCopy.sentence(
            flow.launchAtLoginError ??
                "Meeting Incoming is open now but won’t start automatically after your next sign-in"
        )
        return "\(launchDetail) Open it manually whenever you want protection."
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { flow.isLaunchAtLoginEnabled },
            set: { flow.setLaunchAtLoginEnabled($0) }
        )
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

    private func announceAccountTerminationError(_ message: String?) {
        guard let message else { return }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [.announcement: accountTerminationFailureAnnouncement(message)]
        )
    }

    private var accountTerminationTitle: String {
        guard let pendingAccountTermination else {
            return "Manage this Google Account?"
        }
        let label = accountLabel(for: pendingAccountTermination.coverage)
        switch pendingAccountTermination.kind {
        case .disconnect:
            return InterfaceCopy.disconnectAccountTitle(label)
        case .remove:
            return InterfaceCopy.removeAccountTitle(label)
        }
    }

    private var accountTerminationCancelTitle: String {
        pendingAccountTermination?.kind == .remove ? "Keep Account" : "Keep Connected"
    }

    private var accountTerminationConfirmTitle: String {
        pendingAccountTermination?.kind == .remove ? "Remove Account" : "Disconnect Account"
    }

    private var accountTerminationMessage: String {
        if pendingAccountTermination?.kind == .remove {
            return InterfaceCopy.removeAccountMessage(
                hasOtherAccounts: flow.accountCoverages.count > 1
            )
        }
        return InterfaceCopy.disconnectAccountMessage(
            hasOtherConnectedAccounts: flow.accountCoverages.count > 1
        )
    }

    private func confirmAccountTermination() {
        guard let pendingAccountTermination else { return }
        lastAccountTerminationKind = pendingAccountTermination.kind
        self.pendingAccountTermination = nil
        Task {
            let accountID = pendingAccountTermination.coverage.account.id
            let didTerminate: Bool
            switch pendingAccountTermination.kind {
            case .disconnect:
                didTerminate = await flow.disconnectGoogleAccount(accountID: accountID)
            case .remove:
                didTerminate = await flow.removeGoogleAccount(accountID: accountID)
            }
            if didTerminate {
                lastAccountTerminationKind = nil
            }
        }
    }

    private func accountTerminationFailureAnnouncement(_ message: String) -> String {
        if lastAccountTerminationKind == .remove {
            return InterfaceCopy.removalFailureAnnouncement(message)
        }
        return InterfaceCopy.disconnectionFailureAnnouncement(message)
    }

    private var accountTerminationFailureTitle: String {
        lastAccountTerminationKind == .remove
            ? "Account couldn’t be removed"
            : "Account couldn’t disconnect"
    }

    private func openLoginItemsSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    private func openGoogleAccessManagement() {
        guard let url = URL(string: "https://myaccount.google.com/connections") else { return }
        NSWorkspace.shared.open(url)
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
                    description: Text("Connect Google Calendar in Accounts. Authorization stays encrypted on this Mac across routine relaunches.")
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
                .disabled(flow.isGoogleAccountOperationInProgress)

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
                            flow.selectedCalendarIDs(for: coverage.account.id).isEmpty ||
                            flow.isGoogleAccountOperationInProgress
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
                EarlyReminderTimingControls(
                    isEnabled: Binding(
                        get: { flow.isEarlyReminderEnabled },
                        set: { flow.setEarlyReminderEnabled($0) }
                    ),
                    leadTimeMinutes: Binding(
                        get: { flow.earlyReminderLeadTimeMinutes },
                        set: { flow.setEarlyReminderLeadTime(minutes: $0) }
                    )
                )
            }

            Section("Strong Alert") {
                StrongAlertTimingControls(
                    repeatIntervalMinutes: Binding(
                        get: { flow.strongAlertRepeatIntervalMinutes },
                        set: { flow.setStrongAlertRepeatInterval(minutes: $0) }
                    )
                )
            }

            Section("Event Types") {
                Toggle(
                    "Protect out-of-office events",
                    isOn: Binding(
                        get: { flow.isOutOfOfficeProtectionEnabled },
                        set: { flow.setOutOfOfficeProtectionEnabled($0) }
                    )
                )
                Text(
                    "Off by default. When on, timed out-of-office events receive Strong Alerts and Early Reminders when Early Reminder is enabled."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Optional Blocking Mode") {
                BlockingModeControls(showsCurrentReminderStatus: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
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
        ProtectionActivityCard(isCard: false)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            ? "Reconnect Required"
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
            return "Reconnect Google Calendar to resume protection. Routine relaunches keep valid authorization."
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
