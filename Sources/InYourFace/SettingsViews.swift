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

private enum SettingsPaneBodyLayout {
    case groupedForm
    case readable
}

private enum SettingsPaneMetrics {
    static let readableContentWidth: CGFloat = 704
    static let minimumHorizontalInset: CGFloat = 20
    static let readableContentVerticalInset: CGFloat = 20
    static let footerVerticalInset: CGFloat = 12
}

private struct SettingsPaneScaffold<Content: View, Footer: View>: View {
    private let bodyLayout: SettingsPaneBodyLayout
    private let content: Content
    private let footer: Footer
    private let showsFooter: Bool

    init(
        bodyLayout: SettingsPaneBodyLayout,
        showsFooter: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.bodyLayout = bodyLayout
        self.content = content()
        self.footer = footer()
        self.showsFooter = showsFooter
    }

    var body: some View {
        VStack(spacing: 0) {
            paneBody

            if showsFooter {
                Divider()
                footer
                    .frame(
                        maxWidth: SettingsPaneMetrics.readableContentWidth,
                        alignment: .topLeading
                    )
                    .padding(.horizontal, SettingsPaneMetrics.minimumHorizontalInset)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.vertical, SettingsPaneMetrics.footerVerticalInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var paneBody: some View {
        switch bodyLayout {
        case .groupedForm:
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .readable:
            readableColumn {
                content
            }
            .padding(.vertical, SettingsPaneMetrics.readableContentVerticalInset)
        }
    }

    private func readableColumn<Column: View>(
        @ViewBuilder content: () -> Column
    ) -> some View {
        content()
            .frame(
                maxWidth: SettingsPaneMetrics.readableContentWidth,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .padding(.horizontal, SettingsPaneMetrics.minimumHorizontalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private extension SettingsPaneScaffold where Footer == EmptyView {
    init(
        bodyLayout: SettingsPaneBodyLayout,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            bodyLayout: bodyLayout,
            showsFooter: false,
            content: content,
            footer: { EmptyView() }
        )
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
        SettingsPaneScaffold(bodyLayout: .groupedForm) {
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
                                        warning: flow.coverageWarning(for: coverage.account.id),
                                        showsProgress: protectionStatusPresentation.state != .checkingCoverage
                                    )
                                }
                            } actions: {
                                accountActions(for: coverage)
                            }
                        }

                        if protectionStatusPresentation.state == .checkingCoverage {
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
        }
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
                .accessibilityLabel("Reconnect \(accountLabel(for: coverage))")

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

    private var protectionStatusPresentation: ProtectionCoveragePresentation {
        settingsProtectionPresentation(for: flow)
    }

    private func accountLabel(for coverage: AccountCoverage) -> String {
        InterfaceCopy.connectedAccountLabel(
            email: coverage.account.email,
            displayName: coverage.account.displayName
        )
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
        SettingsPaneScaffold(
            bodyLayout: .readable,
            showsFooter: selectedCoverage != nil
        ) {
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
                }
            }
        } footer: {
            if let coverage = selectedCoverage {
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
        SettingsPaneScaffold(bodyLayout: .groupedForm) {
            Form {
                if flow.isProtectionConfirmationRequired {
                    let pendingCoveragePresentation = ProtectionCoveragePresentation(
                        state: .noCoverage
                    )
                    Section {
                        AdaptiveSettingsActionRow {
                            Label {
                                Text("Protection is off until you confirm these timing changes")
                            } icon: {
                                Image(systemName: pendingCoveragePresentation.systemImage)
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(pendingCoveragePresentation.tone.color)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                "Protection is off until you confirm these timing changes"
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
        }
    }
}

struct AdaptiveSettingsActionRow<Status: View, Actions: View>: View {
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
        SettingsPaneScaffold(bodyLayout: .readable) {
            ProtectionActivityCard(isCard: false)
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
            HStack(spacing: 6) {
                ProtectionCoverageStatusLabel(presentation: statusPresentation)
                    .font(.headline)
                if statusPresentation.state == .loadingProtection {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statusPresentation.label). \(statusDetail)")
    }

    private var statusPresentation: ProtectionCoveragePresentation {
        settingsProtectionPresentation(for: flow)
    }

    private var statusDetail: String {
        switch statusPresentation.state {
        case .protectionPaused:
            return flow.pauseExpirationText()
        case .reconnectRequired:
            if reconnectRequiredCoverages.count == 1,
               let coverage = reconnectRequiredCoverages.first {
                return "Reconnect \(accountLabel(for: coverage)) to resume protection. Routine relaunches keep valid authorization."
            }
            return "Reconnect Google Calendar to resume protection. Routine relaunches keep valid authorization."
        case .activeProtection:
            return "Selected calendars are protected."
        case .noCoverage, .finishSetup:
            return "Choose and confirm at least one calendar."
        case .loadingProtection, .checkingCoverage:
            return "Checking Google Calendar before protection becomes active."
        case .coverageNeedsAttention:
            return "Calendar coverage needs attention."
        case .freshCoverage,
             .staleCoverage,
             .coverageUnavailable,
             .unverifiedReminder,
             .commitmentConflict,
             .primary:
            return "Calendar coverage needs attention."
        }
    }

    private var reconnectRequiredCoverages: [AccountCoverage] {
        flow.accountCoverages.filter { coverage in
            coverage.connectionState == .reconnectRequired ||
                (flow.coverage(for: coverage.account.id) ?? coverage.health) == .reconnectRequired
        }
    }

    private func accountLabel(for coverage: AccountCoverage) -> String {
        InterfaceCopy.connectedAccountLabel(
            email: coverage.account.email,
            displayName: coverage.account.displayName
        )
    }
}

@MainActor
private func settingsProtectionPresentation(
    for flow: CommitmentProtectionFlow
) -> ProtectionCoveragePresentation {
    ProtectionCoveragePresentation.global(
        isRestoringConnection: flow.isRestoringConnection,
        needsSetup: false,
        status: flow.status,
        isCheckingCoverage: flow.isCheckingCoverage || flow.isConnectingAccount,
        isPaused: flow.isPaused(),
        hasReconnectRequiredAccount: flow.accountCoverages.contains { coverage in
            coverage.connectionState == .reconnectRequired ||
                (flow.coverage(for: coverage.account.id) ?? coverage.health) == .reconnectRequired
        }
    )
}
