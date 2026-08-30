import AppKit
import CommitmentProtection
import SwiftUI

private enum OnboardingStep: Int {
    case connect
    case calendars
    case ready

    var progressValue: Int {
        min(rawValue + 1, 2)
    }
}

enum OnboardingAdditionalProtectionDestination: Equatable {
    case connectAccount
    case reviewCalendars(accountID: String)

    static func make(coverages: [AccountCoverage]) -> Self {
        guard let coverage = coverages.first(where: {
            $0.connectionState == .connected &&
                ($0.selectedCalendarIDs.isEmpty || !$0.isProtectionConfirmed)
        }) else {
            return .connectAccount
        }
        return .reviewCalendars(accountID: coverage.id)
    }
}

struct OnboardingReadinessActionState: Equatable {
    enum PrimaryAction: Equatable {
        case reconnect
        case checkingCoverage
        case finishSetup
        case reviewCalendars
        case retryCalendarAccess
    }

    let primaryAction: PrimaryAction
    let canFinishSetup: Bool

    static func make(
        requiresReconnect: Bool,
        isGoogleAccountOperationInProgress: Bool,
        isCheckingCoverage: Bool,
        isRefreshingCoverage: Bool,
        status: ProtectionStatus,
        isProtectionConfirmationRequired: Bool
    ) -> Self {
        let primaryAction: PrimaryAction
        if requiresReconnect {
            primaryAction = .reconnect
        } else if isCheckingCoverage || isRefreshingCoverage {
            primaryAction = .checkingCoverage
        } else if status == .active || isProtectionConfirmationRequired {
            primaryAction = .finishSetup
        } else if status == .noCoverage {
            primaryAction = .reviewCalendars
        } else {
            primaryAction = .retryCalendarAccess
        }
        return Self(
            primaryAction: primaryAction,
            canFinishSetup: primaryAction == .finishSetup &&
                !isGoogleAccountOperationInProgress
        )
    }
}

enum OnboardingProtectionConfirmationPolicy {
    case confirmIfRequired
    case preservePendingConfirmation
}

struct OnboardingReadinessPreferences: Equatable {
    var isEarlyReminderEnabled: Bool
    var earlyReminderLeadTimeMinutes: Int
    var strongAlertRepeatIntervalMinutes: Int
    var isLaunchAtLoginEnabled: Bool

    init(
        isEarlyReminderEnabled: Bool,
        earlyReminderLeadTimeMinutes: Int,
        strongAlertRepeatIntervalMinutes: Int,
        isLaunchAtLoginEnabled: Bool
    ) {
        self.isEarlyReminderEnabled = isEarlyReminderEnabled
        self.earlyReminderLeadTimeMinutes = earlyReminderLeadTimeMinutes
        self.strongAlertRepeatIntervalMinutes = strongAlertRepeatIntervalMinutes
        self.isLaunchAtLoginEnabled = isLaunchAtLoginEnabled
    }

    @MainActor
    init(
        flow: CommitmentProtectionFlow,
        defaultsLaunchAtLoginToEnabled: Bool = false
    ) {
        isEarlyReminderEnabled = flow.isEarlyReminderEnabled
        earlyReminderLeadTimeMinutes = flow.earlyReminderLeadTimeMinutes
        strongAlertRepeatIntervalMinutes = flow.strongAlertRepeatIntervalMinutes
        isLaunchAtLoginEnabled = flow.isLaunchAtLoginEnabled || defaultsLaunchAtLoginToEnabled
    }

    @MainActor
    func commit(
        to flow: CommitmentProtectionFlow,
        protectionConfirmation: OnboardingProtectionConfirmationPolicy = .confirmIfRequired
    ) -> Bool {
        guard !flow.isAppManagedDataResetInProgress else { return false }
        if flow.isLaunchAtLoginEnabled != isLaunchAtLoginEnabled ||
            flow.launchAtLoginError != nil {
            flow.setLaunchAtLoginEnabled(isLaunchAtLoginEnabled)
        }
        guard flow.isLaunchAtLoginEnabled == isLaunchAtLoginEnabled else { return false }

        flow.setEarlyReminderEnabled(isEarlyReminderEnabled)
        flow.setEarlyReminderLeadTime(minutes: earlyReminderLeadTimeMinutes)
        flow.setStrongAlertRepeatInterval(minutes: strongAlertRepeatIntervalMinutes)
        guard flow.isEarlyReminderEnabled == isEarlyReminderEnabled,
              flow.earlyReminderLeadTimeMinutes == earlyReminderLeadTimeMinutes,
              flow.strongAlertRepeatIntervalMinutes == strongAlertRepeatIntervalMinutes else {
            return false
        }
        switch protectionConfirmation {
        case .confirmIfRequired:
            guard flow.isProtectionConfirmationRequired else { return true }
            return flow.confirmAllProtection()
        case .preservePendingConfirmation:
            return true
        }
    }
}

@MainActor
enum OnboardingReadinessOutcomeResolver {
    static func resolve(
        _ action: OnboardingReadinessExitAction,
        preferences: OnboardingReadinessPreferences,
        isReconnectRequired: Bool,
        flow: CommitmentProtectionFlow,
        onboardingState: OnboardingState
    ) -> Bool {
        let protectionConfirmation: OnboardingProtectionConfirmationPolicy =
            isReconnectRequired ? .preservePendingConfirmation : .confirmIfRequired
        guard action != .continueSetup,
              onboardingState.canResolveReadiness,
              preferences.commit(
                  to: flow,
                  protectionConfirmation: protectionConfirmation
              ) else { return false }

        switch action {
        case .finishSetup:
            return onboardingState.complete()
        case .finishLater:
            return onboardingState.deferReadinessUntilRequested()
        case .continueSetup:
            return false
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var testToolsController: TestToolsController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isHeadingFocused: Bool
    @State private var step: OnboardingStep = .connect
    @State private var selectedAccountID: String?
    @State private var calendarSearch = ""
    @State private var lastReconnectAccountID: String?
    @State private var readinessPreferencesDraft: OnboardingReadinessPreferences?

    var body: some View {
        VStack(spacing: 0) {
            onboardingHeader
            Divider()
            onboardingContent
            Divider()
            onboardingFooterContainer
        }
        .frame(
            minWidth: 520,
            idealWidth: 616,
            maxWidth: 720,
            minHeight: 560,
            idealHeight: 640,
            maxHeight: 760
        )
        .onAppear {
            initializeReminderPreferencesIfNeeded()
            synchronizeStepWithProtection()
            synchronizeReadinessExitHandling()
            focusHeading()
            OnboardingWindowController.shared.bringToFront()
        }
        .onChange(of: readinessExitAvailability) { _, _ in
            synchronizeReadinessExitHandling()
        }
        .onChange(of: flow.accountCoverages.map(\.id)) { _, _ in
            synchronizeSelectedAccount()
            if step == .connect, !flow.accountCoverages.isEmpty {
                move(to: .calendars)
            }
        }
        .onChange(of: selectedAccountID) { _, _ in
            calendarSearch = ""
        }
        .onChange(of: flow.accountConnectionError) { _, message in
            announceConnectionError(message)
        }
        .onDisappear {
            OnboardingWindowController.shared.clearReadinessExit()
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }

    private var onboardingHeader: some View {
        HStack(spacing: 12) {
            Label(AppIdentity.displayName, systemImage: "checkmark.shield")
                .font(.headline)
            Spacer()
            if step != .ready {
                Text(progressLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var onboardingContent: some View {
        ScrollView {
            renderedStepContent
                .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
                .padding(28)
        }
        .frame(minHeight: 360, idealHeight: 416, maxHeight: .infinity)
    }

    private var onboardingFooterContainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            onboardingFooter
            if step != .ready {
                Text("Calendars you haven’t confirmed remain unprotected. Resume later from Meeting Incoming in the menu bar, then choose Finish Setup…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if reconnectPresentation.requiresReconnect {
                Text("Reconnect the remaining Saved Accounts to restore all protection. Finish Later keeps setup available from the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if flow.status != .active {
                Text("Protection isn’t active yet. Finish Later keeps setup available from the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .connect:
            onboardingSection(
                title: testToolsController.isTestMode
                    ? "Connect Simulated Calendar"
                    : "Connect Google Calendar",
                detail: testToolsController.isTestMode
                    ? "Use the deterministic Test Mode fixture, then choose simulated calendars. No browser opens and no Google authorization is created."
                    : "Connect Google Calendar once, then choose which calendars Meeting Incoming protects. Access stays encrypted on this Mac until you disconnect it or Google requires authorization again."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    Label(
                        testToolsController.isTestMode
                            ? "Isolated fixture data"
                            : "Device-bound encrypted access",
                        systemImage: testToolsController.isTestMode ? "testtube.2" : "lock.shield"
                    )
                        .foregroundStyle(.secondary)
                    Text(testToolsController.isTestMode
                        ? "The fixture behaves like a calendar connection only inside this test profile. Your production accounts, settings, and encrypted data remain untouched."
                        : "Meeting Incoming can read selected calendar lists and events but cannot change events or RSVPs. Credentials and calendar data are encrypted for this Mac and never stored in Keychain.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if flow.isConnectingAccount {
                        ProgressView(
                            testToolsController.isTestMode
                                ? "Connecting fixture…"
                                : "Connecting to Google…"
                        )
                            .controlSize(.small)
                    } else if let message = flow.accountConnectionError {
                        Label("Google Calendar couldn’t connect", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

        case .calendars:
            onboardingSection(
                title: "Choose Monitored Calendars",
                detail: "Meeting Incoming protects accepted or self-organized timed commitments only from the calendars you select. A video-meeting link is optional, and nothing is selected automatically."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    if flow.accountCoverages.count > 1 {
                        Picker("Account", selection: selectedAccountBinding) {
                            ForEach(flow.accountCoverages) { coverage in
                                Text(accountLabel(for: coverage))
                                    .tag(Optional(coverage.account.id))
                            }
                        }
                        .pickerStyle(.menu)
                    } else if let coverage = selectedCoverage {
                        Label(accountLabel(for: coverage), systemImage: "person.crop.circle")
                            .foregroundStyle(.secondary)
                    }

                    if let coverage = selectedCoverage {
                        CoverageHealthView(
                            coverage: coverage,
                            warning: flow.coverageWarning(for: coverage.account.id)
                        )
                        CalendarSelectionList(
                            coverage: coverage,
                            searchText: $calendarSearch,
                            maximumHeight: 205
                        )
                        .disabled(flow.isGoogleAccountOperationInProgress)
                    } else {
                        ContentUnavailableView(
                            "No Connected Account",
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text("Go back and connect Google Calendar to continue.")
                        )
                    }
                }
            }

        case .ready:
            onboardingSection(
                title: readinessTitle,
                detail: readinessDetail
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if reconnectPresentation.requiresReconnect {
                        reconnectAccountProgress
                        Divider()
                            .padding(.vertical, 2)
                    } else {
                        protectedCoverageSummary

                        Divider()
                            .padding(.vertical, 2)

                        readinessPreferenceSection(title: "Strong Alert") {
                            StrongAlertTimingControls(
                                repeatIntervalMinutes: strongAlertRepeatIntervalDraftBinding
                            )
                        }

                        Divider()
                            .padding(.vertical, 2)

                        readinessPreferenceSection(title: "Early Reminder") {
                            EarlyReminderTimingControls(
                                isEnabled: earlyReminderEnabledDraftBinding,
                                leadTimeMinutes: earlyReminderLeadTimeDraftBinding
                            )
                        }

                        Divider()
                            .padding(.vertical, 2)

                        readinessPreferenceSection(title: "Optional Blocking Mode") {
                            BlockingModeControls(showsCurrentReminderStatus: false)
                        }
                    }

                    Divider()
                        .padding(.vertical, 2)

                    Toggle(isOn: launchAtLoginBinding) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Start Meeting Incoming at login")
                            Text(testToolsController.isTestMode
                                ? "Enabled in this test profile after setup; no macOS Login Item changes."
                                : "Recommended. Starts quietly after sign-in; change anytime in Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .accessibilityLabel("Start Meeting Incoming at login")
                    if let launchAtLoginError = flow.launchAtLoginError {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Start at login couldn’t be updated", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                            Text(launchAtLoginError)
                                .textSelection(.enabled)
                            Text("Turn this off to finish without it, or try Finish Setup again.")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var protectedCoverageSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    protectedCalendarCountLabel
                    Spacer(minLength: 12)
                    protectAnotherAccountButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    protectedCalendarCountLabel
                    protectAnotherAccountButton
                }
            }

            if !protectionSummary.accountGroups.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(protectionSummary.accountGroups) { accountGroup in
                        protectedAccountGroup(accountGroup)
                    }
                }
            }

            if flow.isConnectingAccount {
                ProgressView(testToolsController.isTestMode
                    ? "Connecting another simulated account…"
                    : "Connecting another Google Account…")
                    .controlSize(.small)
            } else if let message = flow.accountConnectionError {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Another account couldn’t connect", systemImage: "exclamationmark.triangle")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var protectedCalendarCountLabel: some View {
        Label(
            InterfaceCopy.protectedCalendarCount(protectionSummary.activeCalendarCount),
            systemImage: "calendar.badge.checkmark"
        )
    }

    private func protectedAccountGroup(
        _ accountGroup: OnboardingProtectionSummary.AccountGroup
    ) -> some View {
        let calendarNames = accountGroup.calendars.map(\.name).joined(separator: " · ")
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                protectedAccountLabel(accountGroup)
                    .frame(maxWidth: 240, alignment: .leading)
                Spacer(minLength: 12)
                protectedCalendarLabel(calendarNames)
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                protectedAccountLabel(accountGroup)
                protectedCalendarLabel(calendarNames)
                    .padding(.leading, 24)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(accountGroup.label), monitored calendars: \(calendarNames)"
        )
    }

    private func protectedAccountLabel(
        _ accountGroup: OnboardingProtectionSummary.AccountGroup
    ) -> some View {
        Label(accountGroup.label, systemImage: "person.crop.circle")
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .help(accountGroup.label)
    }

    private func protectedCalendarLabel(_ calendarNames: String) -> some View {
        Label(calendarNames, systemImage: "calendar")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .help(calendarNames)
    }

    private var protectAnotherAccountButton: some View {
        Button {
            protectAnotherAccount()
        } label: {
            Label("Protect Another Account…", systemImage: "person.badge.plus")
        }
        .disabled(flow.isGoogleAccountOperationInProgress)
    }

    private var reconnectAccountProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                InterfaceCopy.googleAccountConnectionProgress(
                    connectedCount: reconnectPresentation.connectedAccountCount,
                    totalCount: reconnectPresentation.savedAccountCount
                ),
                systemImage: "person.2"
            )
            .font(.headline)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(reconnectPresentation.accounts) { account in
                    reconnectAccountRow(account)
                    if account.id != reconnectPresentation.accounts.last?.id {
                        Divider()
                            .padding(.leading, 28)
                    }
                }
            }

            Label(
                InterfaceCopy.monitoredCalendarProtectionProgress(
                    protectedCount: reconnectPresentation.activelyProtectedCalendarCount,
                    savedCount: reconnectPresentation.savedCalendarCount
                ),
                systemImage: "calendar.badge.clock"
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            if let message = reconnectPresentation.connectionError {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "Couldn’t reconnect \(failedReconnectAccountLabel)",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.red)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(InterfaceCopy.connectionFailureAnnouncement(message))
            }
        }
    }

    private func reconnectAccountRow(
        _ account: OnboardingReconnectAccountPresentation
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(account.label)
                Text(InterfaceCopy.savedMonitoredCalendarCount(account.savedCalendarCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)
            reconnectAccountState(account)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func reconnectAccountState(
        _ account: OnboardingReconnectAccountPresentation
    ) -> some View {
        if flow.connectingAccountID == account.id {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Reconnecting…")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        } else if account.isConnected {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        } else if account.requiresReconnect {
            Label("Reconnect Required", systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        } else {
            Label("Needs Attention", systemImage: "exclamationmark.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var renderedStepContent: AnyView {
        AnyView(stepContent)
    }

    private func onboardingSection<Content: View>(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isHeadingFocused)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func readinessPreferenceSection<Content: View>(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var onboardingFooter: some View {
        ViewThatFits(in: .horizontal) {
            onboardingFooterRow

            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        onboardingSecondaryActions
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        onboardingSecondaryActions
                    }
                }
                HStack {
                    Spacer()
                    onboardingPrimaryAction
                }
            }
        }
    }

    private var onboardingFooterRow: some View {
        HStack(spacing: 10) {
            onboardingSecondaryActions
            Spacer()
            onboardingPrimaryAction
        }
    }

    @ViewBuilder
    private var onboardingSecondaryActions: some View {
        if step == .calendars {
            Button("Back") {
                move(to: hasConfirmedProtection ? .ready : .connect)
            }
        }

        if step != .ready {
            Button("Set Up Later") {
                guard onboardingState.deferUntilRequested() else { return }
                OnboardingWindowController.shared.closeAfterSetUpLater()
            }
        } else if reconnectPresentation.requiresReconnect || flow.status != .active {
            Button("Finish Later") {
                OnboardingWindowController.shared.resolveReadinessExit(.finishLater)
            }
        }
    }

    @ViewBuilder
    private var onboardingPrimaryAction: some View {
        switch step {
        case .connect:
            Button {
                if flow.accountCoverages.isEmpty {
                    Task { await flow.connectGoogleAccount() }
                } else {
                    move(to: .calendars)
                }
            } label: {
                Text(connectActionTitle)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(flow.isGoogleAccountOperationInProgress)

        case .calendars:
            Button("Turn On Protection") {
                turnOnProtection()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(
                !flow.isProtectionConfirmationRequired ||
                    flow.isGoogleAccountOperationInProgress
            )

        case .ready:
            switch readinessActionState.primaryAction {
            case .reconnect:
                if let target = reconnectPresentation.currentTarget {
                    Button("Reconnect \(target.label)…") {
                        lastReconnectAccountID = target.id
                        Task {
                            await flow.reconnectGoogleAccount(accountID: target.id)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(flow.isGoogleAccountOperationInProgress)
                    .accessibilityLabel("Reconnect Google Account \(target.label)")
                }

            case .checkingCoverage:
                ProgressView("Checking Calendar Coverage…")
                    .controlSize(.small)

            case .finishSetup:
                Button("Finish Setup") {
                    OnboardingWindowController.shared.resolveReadinessExit(.finishSetup)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(flow.isGoogleAccountOperationInProgress)

            case .reviewCalendars:
                Button("Review Calendars") {
                    move(to: .calendars)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

            case .retryCalendarAccess:
                Button("Retry Calendar Access") {
                    Task { await flow.refreshCommitmentProtection() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var connectActionTitle: LocalizedStringKey {
        if !flow.accountCoverages.isEmpty {
            return "Continue"
        }
        if flow.isConnectingAccount {
            return "Connecting…"
        }
        if flow.accountConnectionError != nil {
            return "Try Again"
        }
        return testToolsController.isTestMode
            ? "Connect Simulated Calendar"
            : "Connect Google Calendar"
    }

    private var progressLabel: LocalizedStringKey {
        "Step \(step.progressValue) of 2"
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

    private func accountLabel(for coverage: AccountCoverage) -> String {
        InterfaceCopy.connectedAccountLabel(
            email: coverage.account.email,
            displayName: coverage.account.displayName
        )
    }

    private var reconnectPresentation: OnboardingReconnectPresentation {
        OnboardingReconnectPresentation.make(
            coverages: flow.accountCoverages,
            preferredAccountID: selectedAccountID,
            connectionError: flow.accountConnectionError
        )
    }

    private var protectionSummary: OnboardingProtectionSummary {
        OnboardingProtectionSummary.make(coverages: flow.accountCoverages)
    }

    private var failedReconnectAccountLabel: String {
        if let lastReconnectAccountID,
           let account = reconnectPresentation.accounts.first(where: {
               $0.id == lastReconnectAccountID
           }) {
            return account.label
        }
        return reconnectPresentation.currentTarget?.label ?? "Google Account"
    }

    private var readinessTitle: LocalizedStringKey {
        if reconnectPresentation.requiresReconnect {
            return "Reconnect Required"
        }
        switch flow.status {
        case .active:
            return "Protection ready"
        case .unavailable:
            return isCheckingCoverage ? "Checking Calendar Coverage" : "Coverage Needs Attention"
        case .noCoverage:
            return "Protection needs a calendar"
        }
    }

    private var readinessDetail: LocalizedStringKey {
        if reconnectPresentation.requiresReconnect {
            return "Reconnect each Saved Account once—not each calendar. Meeting Incoming restores its Monitored Calendar choices automatically after each reconnect."
        }
        switch flow.status {
        case .active:
            return "Your selected calendars stay protected across app relaunches and Mac restarts while Google authorization remains valid."
        case .unavailable:
            return isCheckingCoverage
                ? "Your choices are saved. Meeting Incoming is checking Google Calendar before it marks protection active."
                : "Your choices are saved, but Google Calendar could not refresh. Known reminders may be unverified, and new reminders will not be created until coverage returns."
        case .noCoverage:
            return "Choose and confirm at least one calendar before finishing setup."
        }
    }

    private var isCheckingCoverage: Bool {
        flow.isCheckingCoverage
    }

    private var readinessExitAvailability: Bool? {
        guard step == .ready else { return nil }
        return readinessActionState.canFinishSetup
    }

    private var readinessActionState: OnboardingReadinessActionState {
        OnboardingReadinessActionState.make(
            requiresReconnect: reconnectPresentation.requiresReconnect,
            isGoogleAccountOperationInProgress: flow.isGoogleAccountOperationInProgress,
            isCheckingCoverage: flow.isCheckingCoverage,
            isRefreshingCoverage: flow.isRefreshingCoverage,
            status: flow.status,
            isProtectionConfirmationRequired: flow.isProtectionConfirmationRequired
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { readinessPreferences.isLaunchAtLoginEnabled },
            set: { isEnabled in
                var draft = readinessPreferences
                draft.isLaunchAtLoginEnabled = isEnabled
                readinessPreferencesDraft = draft
            }
        )
    }

    private var earlyReminderEnabledDraftBinding: Binding<Bool> {
        Binding(
            get: { readinessPreferences.isEarlyReminderEnabled },
            set: { isEnabled in
                var draft = readinessPreferences
                draft.isEarlyReminderEnabled = isEnabled
                readinessPreferencesDraft = draft
            }
        )
    }

    private var earlyReminderLeadTimeDraftBinding: Binding<Int> {
        Binding(
            get: { readinessPreferences.earlyReminderLeadTimeMinutes },
            set: { minutes in
                var draft = readinessPreferences
                draft.earlyReminderLeadTimeMinutes = minutes
                readinessPreferencesDraft = draft
            }
        )
    }

    private var strongAlertRepeatIntervalDraftBinding: Binding<Int> {
        Binding(
            get: { readinessPreferences.strongAlertRepeatIntervalMinutes },
            set: { minutes in
                var draft = readinessPreferences
                draft.strongAlertRepeatIntervalMinutes = minutes
                readinessPreferencesDraft = draft
            }
        )
    }

    private var readinessPreferences: OnboardingReadinessPreferences {
        readinessPreferencesDraft ?? OnboardingReadinessPreferences(
            flow: flow,
            defaultsLaunchAtLoginToEnabled: !onboardingState.didChooseLaunchAtLogin
        )
    }

    private var hasConfirmedProtection: Bool {
        flow.accountCoverages.contains(where: {
            !$0.selectedCalendarIDs.isEmpty && $0.isProtectionConfirmed
        })
    }

    private func synchronizeStepWithProtection() {
        synchronizeSelectedAccount()
        if flow.accountCoverages.isEmpty {
            step = .connect
        } else if !hasConfirmedProtection {
            step = .calendars
        } else {
            step = .ready
        }
    }

    private func synchronizeSelectedAccount() {
        guard let selectedAccountID,
              flow.accountCoverages.contains(where: { $0.id == selectedAccountID }) else {
            self.selectedAccountID = flow.accountCoverages.first?.id
            return
        }
    }

    private func turnOnProtection() {
        if flow.confirmAllProtection() {
            move(to: .ready)
        }
    }

    private func protectAnotherAccount() {
        switch OnboardingAdditionalProtectionDestination.make(
            coverages: flow.accountCoverages
        ) {
        case let .reviewCalendars(accountID):
            selectedAccountID = accountID
            move(to: .calendars)

        case .connectAccount:
            let existingAccountIDs = Set(flow.accountCoverages.map(\.id))
            Task {
                await flow.connectGoogleAccount()
                guard flow.accountConnectionError == nil else { return }
                selectedAccountID = flow.accountCoverages.first(where: {
                    !existingAccountIDs.contains($0.id)
                })?.id ?? flow.connectedAccount?.id ?? selectedAccountID
                move(to: .calendars)
            }
        }
    }

    private func initializeReminderPreferencesIfNeeded() {
        guard readinessPreferencesDraft == nil else { return }
        readinessPreferencesDraft = OnboardingReadinessPreferences(
            flow: flow,
            defaultsLaunchAtLoginToEnabled: !onboardingState.didChooseLaunchAtLogin
        )
    }

    private func resolveReadinessExit(_ action: OnboardingReadinessExitAction) -> Bool {
        let preferences = readinessPreferences
        guard OnboardingReadinessOutcomeResolver.resolve(
            action,
            preferences: preferences,
            isReconnectRequired: reconnectPresentation.requiresReconnect,
            flow: flow,
            onboardingState: onboardingState
        ) else { return false }
        readinessPreferencesDraft = OnboardingReadinessPreferences(flow: flow)
        return true
    }

    private func synchronizeReadinessExitHandling() {
        guard let canFinishSetup = readinessExitAvailability else {
            OnboardingWindowController.shared.clearReadinessExit()
            return
        }
        OnboardingWindowController.shared.configureReadinessExit(
            canFinishSetup: canFinishSetup,
            resolve: resolveReadinessExit
        )
    }

    private func move(to newStep: OnboardingStep) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            step = newStep
        }
        focusHeading()
    }

    private func focusHeading() {
        isHeadingFocused = false
        DispatchQueue.main.async {
            isHeadingFocused = true
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
}

struct CalendarSelectionList: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    let coverage: AccountCoverage
    @Binding var searchText: String
    var maximumHeight: CGFloat? = nil
    @State private var pendingDeselection: CalendarOption?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if coverage.calendars.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "No Calendars Found",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Google Calendar returned no calendars for this Connected Account. Retry access. If calendars remain missing, reconnect the account from Settings › Accounts.")
                    )
                    if flow.isRefreshingCoverage {
                        ProgressView("Retrying Calendar Access…")
                            .controlSize(.small)
                    } else {
                        Button {
                            Task { await flow.refreshCommitmentProtection() }
                        } label: {
                            Label("Retry Calendar Access", systemImage: "arrow.clockwise")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if coverage.calendars.count > 8 {
                TextField("Search calendars", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }

            if !coverage.calendars.isEmpty {
                Text(selectionSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                List(visibleCalendars) { calendar in
                    Toggle(
                        isOn: Binding(
                            get: { selectedCalendarIDs.contains(calendar.id) },
                            set: { setCalendarSelected($0, calendar: calendar) }
                        )
                    ) {
                        Label(calendar.name, systemImage: "calendar")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.checkbox)
                }
                .listStyle(.inset)
                .frame(maxHeight: maximumHeight)
                .overlay {
                    if visibleCalendars.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
        }
        .alert(
            "Remove this calendar from protection?",
            isPresented: Binding(
                get: { pendingDeselection != nil },
                set: { if !$0 { pendingDeselection = nil } }
            )
        ) {
            Button("Keep Protected", role: .cancel) {
                pendingDeselection = nil
            }
            Button("Remove from Protection", role: .destructive) {
                guard let pendingDeselection else { return }
                flow.setCalendarSelected(
                    false,
                    calendarID: pendingDeselection.id,
                    accountID: coverage.account.id
                )
                self.pendingDeselection = nil
            }
        } message: {
            Text(flow.calendarDeselectionWarning(
                for: pendingDeselection?.id ?? "",
                accountID: coverage.account.id
            ) ?? "Removing this calendar stops its current and future reminders immediately.")
        }
    }

    private var selectedCalendarIDs: Set<String> {
        flow.selectedCalendarIDs(for: coverage.account.id)
    }

    private var selectionSummary: String {
        InterfaceCopy.calendarSelectionSummary(
            selectedCount: selectedCalendarIDs.count,
            totalCount: coverage.calendars.count
        )
    }

    private var visibleCalendars: [CalendarOption] {
        let filtered = searchText.isEmpty
            ? coverage.calendars
            : coverage.calendars.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        return filtered.sorted { lhs, rhs in
            let lhsSelected = selectedCalendarIDs.contains(lhs.id)
            let rhsSelected = selectedCalendarIDs.contains(rhs.id)
            if lhsSelected != rhsSelected {
                return lhsSelected
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func setCalendarSelected(_ isSelected: Bool, calendar: CalendarOption) {
        guard !isSelected else {
            flow.setCalendarSelected(
                true,
                calendarID: calendar.id,
                accountID: coverage.account.id
            )
            return
        }

        pendingDeselection = calendar
    }
}
