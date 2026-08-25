import AppKit
import CommitmentProtection
import SwiftUI

private enum OnboardingStep: Int {
    case connect
    case calendars
    case testAlert
    case ready

    var progressValue: Int {
        min(rawValue + 1, 3)
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @EnvironmentObject private var onboardingState: OnboardingState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isHeadingFocused: Bool
    @State private var step: OnboardingStep = .connect
    @State private var selectedAccountID: String?
    @State private var calendarSearch = ""

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
        .onChange(of: onboardingState.didHandleTestAlert) { _, didHandle in
            if didHandle {
                move(to: .ready)
            }
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }

    private var onboardingHeader: some View {
        HStack(spacing: 12) {
            Label("In Your Face", systemImage: "checkmark.shield")
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
                Text("Calendars you haven’t confirmed remain unprotected. Resume later from In Your Face in the menu bar, then choose Finish Setup…")
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
                title: "Connect Google Calendar",
                detail: "Connect Google Calendar for this app session, then choose which calendars In Your Face protects. You’ll reconnect after the app relaunches."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Session-only calendar access", systemImage: "lock.shield")
                        .foregroundStyle(.secondary)
                    Text("In Your Face can read your calendar but cannot change events or RSVPs. Google access is kept only while the app is open and is discarded when it quits.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if flow.isConnectingAccount {
                        ProgressView("Connecting to Google…")
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
                detail: "In Your Face protects accepted, timed commitments only from the calendars you select. Nothing is selected automatically."
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
                    } else {
                        ContentUnavailableView(
                            "No Connected Account",
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text("Go back and connect Google Calendar to continue.")
                        )
                    }
                }
            }

        case .testAlert:
            onboardingSection(
                title: "Try a Test Alert",
                detail: "See what a Strong Alert looks like before you rely on it. This test won’t change any calendar event or RSVP."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    Label("What to check", systemImage: "display.2")
                        .font(.headline)
                    Text("Make sure the alert is noticeable, readable, and keyboard-accessible. Real Strong Alerts appear on every display, remain visible during Full-Screen Sharing, window sharing, and app sharing, and repeat until you act. People who can see a shared surface may also see the alert and commitment title.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Press Return in the Test Alert to finish.", systemImage: "return")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

        case .ready:
            onboardingSection(
                title: readinessTitle,
                detail: readinessDetail
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Label(
                        InterfaceCopy.protectedCalendarCount(protectedCalendarCount),
                        systemImage: "calendar.badge.checkmark"
                    )
                    Label(
                        flow.isEarlyReminderEnabled
                            ? InterfaceCopy.earlyReminderTiming(flow.earlyReminderLeadTimeMinutes)
                            : "Early Reminder off",
                        systemImage: "bell"
                    )
                    Label(
                        InterfaceCopy.strongAlertRepeatTiming(flow.strongAlertRepeatIntervalMinutes),
                        systemImage: "bell.and.waves.left.and.right"
                    )
                    Text("In Your Face will now stay in the menu bar until a commitment needs you. Ongoing controls are available in Settings.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
            }
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
        if step == .calendars || step == .testAlert {
            Button("Back") {
                move(to: step == .testAlert ? .calendars : .connect)
            }
        }

        if step != .ready {
            Button("Set Up Later") {
                onboardingState.deferUntilRequested()
                OnboardingWindowController.shared.close()
            }
        } else if flow.status != .active {
            Button("Finish Later") {
                onboardingState.deferUntilRequested()
                OnboardingWindowController.shared.close()
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
            .disabled(flow.isConnectingAccount)

        case .calendars:
            Button("Turn On Protection") {
                turnOnProtection()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedCalendarCount == 0)

        case .testAlert:
            Button("Show Test Alert") {
                flow.presentTestAlert()
                openWindow(id: "test-alert")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(flow.isTestAlertPresented)

        case .ready:
            if let coverage = reconnectRequiredCoverage {
                Button("Reconnect Google Calendar…") {
                    Task {
                        await flow.reconnectGoogleAccount(accountID: coverage.account.id)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(flow.isConnectingAccount)
            } else if flow.status == .active {
                Button("Finish Setup") {
                    guard onboardingState.complete() else { return }
                    OnboardingWindowController.shared.close()
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
        return flow.accountConnectionError == nil ? "Connect Google Calendar" : "Try Again"
    }

    private var progressLabel: LocalizedStringKey {
        "Step \(step.progressValue) of 3"
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

    private var reconnectRequiredCoverage: AccountCoverage? {
        if let selectedCoverage,
           selectedCoverage.connectionState == .reconnectRequired {
            return selectedCoverage
        }
        return flow.accountCoverages.first { $0.connectionState == .reconnectRequired }
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

    private var protectedCalendarCount: Int {
        flow.accountCoverages.reduce(0) { count, coverage in
            count + (coverage.isProtectionConfirmed ? coverage.selectedCalendarIDs.count : 0)
        }
    }

    private var readinessTitle: LocalizedStringKey {
        if reconnectRequiredCoverage != nil {
            return "Calendar Access Required"
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
        if reconnectRequiredCoverage != nil {
            return "Reconnect every saved Google account before finishing setup. Your Monitored Calendar choices will be reapplied."
        }
        switch flow.status {
        case .active:
            return "Your selected calendars are protected while In Your Face remains open. Reconnect Google Calendar after the app relaunches."
        case .unavailable:
            return isCheckingCoverage
                ? "Your choices are saved. In Your Face is checking Google Calendar before it marks protection active."
                : "Your choices are saved, but Google Calendar could not refresh. Known reminders may be unverified, and new reminders will not be created until coverage returns."
        case .noCoverage:
            return "Choose and confirm at least one calendar before finishing setup."
        }
    }

    private var isCheckingCoverage: Bool {
        flow.isCheckingCoverage
    }

    private func synchronizeStepWithProtection() {
        synchronizeSelectedAccount()
        if flow.accountCoverages.isEmpty {
            step = .connect
        } else if !flow.accountCoverages.contains(where: {
            !$0.selectedCalendarIDs.isEmpty && $0.isProtectionConfirmed
        }) {
            step = .calendars
        } else if onboardingState.didHandleTestAlert {
            step = .ready
        } else {
            step = .testAlert
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
            move(to: .testAlert)
        }
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
