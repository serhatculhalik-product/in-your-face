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

struct OnboardingReminderPreferences: Equatable {
    var isEarlyReminderEnabled: Bool
    var earlyReminderLeadTimeMinutes: Int

    @MainActor
    init(flow: CommitmentProtectionFlow) {
        isEarlyReminderEnabled = flow.isEarlyReminderEnabled
        earlyReminderLeadTimeMinutes = flow.earlyReminderLeadTimeMinutes
    }

    @MainActor
    func commit(to flow: CommitmentProtectionFlow) -> Bool {
        flow.setEarlyReminderEnabled(isEarlyReminderEnabled)
        flow.setEarlyReminderLeadTime(minutes: earlyReminderLeadTimeMinutes)
        guard flow.isProtectionConfirmationRequired else { return true }
        return flow.confirmAllProtection()
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
    @State private var reminderPreferencesDraft: OnboardingReminderPreferences?

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
            focusHeading()
            OnboardingWindowController.shared.bringToFront()
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
                VStack(alignment: .leading, spacing: 14) {
                    if reconnectPresentation.requiresReconnect {
                        reconnectAccountProgress
                        Divider()
                            .padding(.vertical, 2)
                    } else {
                        Label(
                            InterfaceCopy.protectedCalendarCount(
                                reconnectPresentation.activelyProtectedCalendarCount
                            ),
                            systemImage: "calendar.badge.checkmark"
                        )
                        Label(
                            InterfaceCopy.strongAlertRepeatTiming(flow.strongAlertRepeatIntervalMinutes),
                            systemImage: "bell.and.waves.left.and.right"
                        )

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
                                ? "Simulated in this test profile; no macOS Login Item is changed."
                                : "Off by default. You can change this anytime in Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    if let launchAtLoginError = flow.launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !reconnectPresentation.requiresReconnect {
                        Text("Meeting Incoming stays quiet in the menu bar until a commitment needs you. Ongoing controls are available in Settings.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                }
            }
        }
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
                move(to: .connect)
            }
        }

        if step != .ready {
            Button("Set Up Later") {
                onboardingState.deferUntilRequested()
                OnboardingWindowController.shared.close()
            }
        } else if reconnectPresentation.requiresReconnect || flow.status != .active {
            Button("Finish Later") {
                finishLater()
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
                selectedCalendarCount == 0 ||
                    flow.isGoogleAccountOperationInProgress
            )

        case .ready:
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
            } else if flow.status == .active || flow.isProtectionConfirmationRequired {
                Button("Finish Setup") {
                    finishSetup()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else if flow.status == .noCoverage {
                Button("Review Calendars") {
                    move(to: .calendars)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else if flow.isCheckingCoverage || flow.isRefreshingCoverage {
                ProgressView("Checking Calendar Coverage…")
                    .controlSize(.small)
            } else {
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

    private var selectedCalendarCount: Int {
        flow.accountCoverages.reduce(0) { count, coverage in
            count + coverage.selectedCalendarIDs.count
        }
    }

    private var reconnectPresentation: OnboardingReconnectPresentation {
        OnboardingReconnectPresentation.make(
            coverages: flow.accountCoverages,
            preferredAccountID: selectedAccountID,
            connectionError: flow.accountConnectionError
        )
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

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { flow.isLaunchAtLoginEnabled },
            set: { flow.setLaunchAtLoginEnabled($0) }
        )
    }

    private var earlyReminderEnabledDraftBinding: Binding<Bool> {
        Binding(
            get: { reminderPreferences.isEarlyReminderEnabled },
            set: { isEnabled in
                var draft = reminderPreferences
                draft.isEarlyReminderEnabled = isEnabled
                reminderPreferencesDraft = draft
            }
        )
    }

    private var earlyReminderLeadTimeDraftBinding: Binding<Int> {
        Binding(
            get: { reminderPreferences.earlyReminderLeadTimeMinutes },
            set: { minutes in
                var draft = reminderPreferences
                draft.earlyReminderLeadTimeMinutes = minutes
                reminderPreferencesDraft = draft
            }
        )
    }

    private var reminderPreferences: OnboardingReminderPreferences {
        reminderPreferencesDraft ?? OnboardingReminderPreferences(flow: flow)
    }

    private func synchronizeStepWithProtection() {
        synchronizeSelectedAccount()
        if flow.accountCoverages.isEmpty {
            step = .connect
        } else if !flow.accountCoverages.contains(where: {
            !$0.selectedCalendarIDs.isEmpty && $0.isProtectionConfirmed
        }) {
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

    private func initializeReminderPreferencesIfNeeded() {
        guard reminderPreferencesDraft == nil else { return }
        reminderPreferencesDraft = OnboardingReminderPreferences(flow: flow)
    }

    private func commitReminderPreferences() -> Bool {
        let preferences = reminderPreferences
        guard preferences.commit(to: flow) else { return false }
        reminderPreferencesDraft = OnboardingReminderPreferences(flow: flow)
        return true
    }

    private func finishSetup() {
        guard commitReminderPreferences() else { return }
        guard onboardingState.complete() else { return }
        OnboardingWindowController.shared.close()
    }

    private func finishLater() {
        if !reconnectPresentation.requiresReconnect {
            guard commitReminderPreferences() else { return }
        }
        onboardingState.deferUntilRequested()
        OnboardingWindowController.shared.close()
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
