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
    @StateObject private var availabilityMonitor: AppAvailabilityMonitor

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
        let monitor = AppAvailabilityMonitor(flow: protectionFlow)
        _flow = StateObject(wrappedValue: protectionFlow)
        _availabilityMonitor = StateObject(wrappedValue: monitor)
        Task {
            await protectionFlow.restoreSavedConnection()
            protectionFlow.startMonitoring()
            monitor.start()
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

        Window("Strong Alert", id: "strong-alert") {
            StrongAlertWindowView()
                .environmentObject(flow)
        }
        .windowStyle(.hiddenTitleBar)
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

@MainActor
private final class AppAvailabilityMonitor: NSObject, ObservableObject {
    private let flow: CommitmentProtectionFlow
    private var isStarted = false

    init(flow: CommitmentProtectionFlow) {
        self.flow = flow
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ].forEach { notificationName in
            workspaceCenter.addObserver(
                self,
                selector: #selector(handleRecovery(_:)),
                name: notificationName,
                object: nil
            )
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecovery(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        let distributedCenter = DistributedNotificationCenter.default()
        distributedCenter.addObserver(
            self,
            selector: #selector(handleRecovery(_:)),
            name: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc
    private func handleRecovery(_ notification: Notification) {
        Task { @MainActor [weak self] in
            await self?.flow.recoverProtection()
        }
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

                if !flow.accountCoverages.isEmpty {
                    ForEach(flow.accountCoverages) { coverage in
                        CalendarSelectionCard(coverage: coverage)
                    }
                    EarlyReminderSettingsCard()
                    BlockingModeSettingsCard()
                    StrongAlertSettingsCard()
                    PauseProtectionCard()
                    TestAlertCard()
                }

                ProtectionActivityCard()
                LoginAvailabilityCard()
            }
            .padding(32)
        }
        .onAppear {
            flow.refreshLaunchAtLoginStatus()
            SetupWindowController.shared.bringToFront()
        }
        .onChange(of: flow.earlyReminderCommitment) { _, commitment in
            guard commitment != nil else {
                EarlyReminderWindowController.shared.close()
                return
            }
            openEarlyReminderIfNeeded(flow: flow) {
                openWindow(id: "early-reminder")
            }
        }
        .onChange(of: flow.isStrongAlertPresented) { _, isPresented in
            if isPresented {
                openWindow(id: "strong-alert")
            } else {
                StrongAlertWindowController.shared.close()
            }
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }
}

@MainActor
private func openEarlyReminderIfNeeded(
    flow: CommitmentProtectionFlow,
    openWindow: @escaping () -> Void
) {
    guard flow.earlyReminderCommitment != nil else {
        EarlyReminderWindowController.shared.close()
        return
    }
    Task { @MainActor in
        await Task.yield()
        guard flow.earlyReminderCommitment != nil else {
            EarlyReminderWindowController.shared.close()
            return
        }
        openWindow()
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
        if flow.isPaused() {
            return "Protection Paused"
        }
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
        if flow.isPaused() {
            return flow.pauseExpirationText()
        }
        switch flow.status {
        case .noCoverage:
            return "Select and confirm a calendar before commitments can be protected."
        case .active:
            return flow.isLaunchAtLoginEnabled
                ? "Your selected calendars are protected."
                : "Protection is configured, but start-at-login needs attention."
        case .unavailable:
            return "Google Calendar could not be refreshed. Protection is unavailable until coverage returns."
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
            }

            ForEach(flow.accountCoverages) { coverage in
                VStack(alignment: .leading, spacing: 8) {
                    Label(coverage.account.email, systemImage: "person.crop.circle.fill")
                        .foregroundStyle(.secondary)

                    CoverageHealthView(
                        coverage: coverage,
                        warning: flow.coverageWarning(for: coverage.account.id)
                    )

                    Button("Log Out") {
                        flow.disconnectGoogleAccount(accountID: coverage.account.id)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }

            if flow.accountCoverages.isEmpty {
                Text("Sign in with Google to choose the calendars you want protected.")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await flow.connectGoogleAccount() }
            } label: {
                Label(
                    flow.connectionState == .connecting ? "Opening Google…" : "Add Google Account",
                    systemImage: "person.badge.key.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(flow.connectionState == .connecting || flow.isRestoringConnection)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct CoverageHealthView: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    let coverage: AccountCoverage
    let warning: String?

    var body: some View {
        let health = flow.coverage(for: coverage.account.id) ?? coverage.health
        VStack(alignment: .leading, spacing: 4) {
            Label(health.displayTitle, systemImage: health.systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(health.displayColor)

            if let warning {
                Text(warning)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension CoverageHealth {
    var displayTitle: String {
        switch self {
        case .noCoverage:
            return "No Coverage"
        case .fresh:
            return "Fresh Coverage"
        case .stale:
            return "Stale Coverage"
        case .unavailable:
            return "Coverage Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .fresh:
            return "checkmark.circle.fill"
        case .noCoverage, .stale, .unavailable:
            return "exclamationmark.triangle.fill"
        }
    }

    var displayColor: Color {
        switch self {
        case .fresh:
            return .green
        case .noCoverage, .stale, .unavailable:
            return .orange
        }
    }
}

private struct CalendarSelectionCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    let coverage: AccountCoverage
    @State private var pendingDeselection: CalendarOption?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monitored Calendars · \(coverage.account.email)")
                .font(.headline)
            Text("Only selected calendars can create protection.")
                .foregroundStyle(.secondary)

            ForEach(coverage.calendars) { calendar in
                Toggle(
                    isOn: Binding(
                        get: {
                            flow.selectedCalendarIDs(for: coverage.account.id).contains(calendar.id)
                        },
                        set: { isSelected in
                            setCalendarSelected(isSelected, calendar: calendar)
                        }
                    )
                ) {
                    Label(calendar.name, systemImage: "calendar")
                }
                .toggleStyle(.checkbox)
            }

            if !coverage.isProtectionConfirmed {
                Text("Review this account's calendars and confirm protection.")
                    .foregroundStyle(.secondary)
                Button("Confirm Protection") {
                    flow.confirmProtection(for: coverage.account.id)
                }
                .buttonStyle(.borderedProminent)
                .disabled(flow.selectedCalendarIDs(for: coverage.account.id).isEmpty)
            } else {
                Label("Protection settings confirmed", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }

        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .alert(
            "Stop monitoring this calendar?",
            isPresented: Binding(
                get: { pendingDeselection != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeselection = nil
                    }
                }
            )
        ) {
            Button("Keep monitoring", role: .cancel) {
                pendingDeselection = nil
            }
            Button("Stop monitoring", role: .destructive) {
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
            ) ?? "Turning off this calendar removes its reminders.")
        }
    }

    private func setCalendarSelected(_ isSelected: Bool, calendar: CalendarOption) {
        guard !isSelected else {
            flow.setCalendarSelected(true, calendarID: calendar.id, accountID: coverage.account.id)
            return
        }

        if flow.calendarDeselectionWarning(
            for: calendar.id,
            accountID: coverage.account.id
        ) != nil {
            pendingDeselection = calendar
        } else {
            flow.setCalendarSelected(false, calendarID: calendar.id, accountID: coverage.account.id)
        }
    }
}

private struct EarlyReminderSettingsCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Early Reminder")
                .font(.headline)
            Text("A visual reminder before an accepted commitment starts. Strong Alert still appears when the commitment begins.")
                .foregroundStyle(.secondary)

            Toggle(
                isOn: Binding(
                    get: { flow.isEarlyReminderEnabled },
                    set: { flow.setEarlyReminderEnabled($0) }
                )
            ) {
                Text("Show Early Reminder")
            }

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
            .disabled(!flow.isEarlyReminderEnabled)

            if flow.isProtectionConfirmationRequired {
                Text("Review the selected calendars and global timing, then confirm protection.")
                    .foregroundStyle(.secondary)
                Button("Confirm Protection for All Accounts") {
                    flow.confirmAllProtection()
                }
                .buttonStyle(.borderedProminent)
            }

        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct BlockingModeSettingsCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @ObservedObject private var windowController = EarlyReminderWindowController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optional Blocking Mode")
                .font(.headline)
            Text("Keep Early Reminder in front and block background interaction while it is open. Normal reminders work without these permissions.")
                .foregroundStyle(.secondary)

            Toggle(
                isOn: Binding(
                    get: { flow.isBlockingModeEnabled },
                    set: { isEnabled in
                        flow.setBlockingModeEnabled(isEnabled)
                        windowController.setBlockingModeEnabled(isEnabled)
                    }
                )
            ) {
                Text("Keep Early Reminder in front")
            }

            if flow.isBlockingModeEnabled {
                Text("Blocking Mode needs macOS Accessibility and Input Monitoring permissions. You can grant them here or keep using the visual reminder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Open Accessibility Settings") {
                        windowController.openAccessibilitySettings()
                    }
                    Button("Open Input Monitoring Settings") {
                        windowController.openInputMonitoringSettings()
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct StrongAlertSettingsCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Strong Alert")
                .font(.headline)
            Text("After a commitment starts, repeat the alert until you Join, stop reminders, or it ends.")
                .foregroundStyle(.secondary)

            Stepper(
                value: Binding(
                    get: { flow.strongAlertRepeatIntervalMinutes },
                    set: { flow.setStrongAlertRepeatInterval(minutes: $0) }
                ),
                in: 1...5
            ) {
                Text("Repeat every \(flow.strongAlertRepeatIntervalMinutes) minute\(flow.strongAlertRepeatIntervalMinutes == 1 ? "" : "s")")
            }
            .accessibilityLabel("Strong Alert repeat interval")
            .accessibilityValue("\(flow.strongAlertRepeatIntervalMinutes) minutes")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PauseProtectionCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @State private var customExpiration = Date().addingTimeInterval(60 * 60)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pause Protection")
                .font(.headline)

            if flow.isPaused() {
                Label("Protection Paused", systemImage: "pause.circle.fill")
                    .font(.headline)
                Text(flow.pauseExpirationText())
                    .foregroundStyle(.secondary)
            } else {
                Text("Temporarily suppress Early Reminder and Strong Alert while you handle an interruption.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("1 hour") {
                        pause(.oneHour)
                    }
                    .keyboardShortcut("1")

                    Button("End of day") {
                        pause(.endOfDay)
                    }
                    .keyboardShortcut("e")
                }

                DatePicker(
                    "Custom expiration",
                    selection: $customExpiration,
                    in: Date()...
                )
                .datePickerStyle(.field)
                .environment(\.locale, Locale(identifier: "tr_TR"))

                Button("Pause until selected time") {
                    pause(.custom(customExpiration))
                }
                .keyboardShortcut("c")
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Suppress reminders until the selected local date and time.")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private func pause(_ duration: PauseDuration) {
        if flow.pause(for: duration) {
            announceActionResult(flow.lastActionMessage)
        }
    }
}

private struct ProtectionActivityCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @State private var selectedFilterID = Self.allActivityFilterID

    private static let allActivityFilterID = "all-activity"

    private struct CalendarFilter: Hashable, Identifiable {
        let accountID: String
        let accountEmail: String
        let calendarID: String
        let calendarName: String

        var id: String {
            "\(accountID)::\(calendarID)"
        }

        var displayName: String {
            "\(calendarName) · \(accountEmail)"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = .current
        formatter.timeZone = .current
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Protection Activity", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            Text("See what you did and what protection did today. This list resets at the end of your local day.")
                .foregroundStyle(.secondary)

            Picker("Activity scope", selection: $selectedFilterID) {
                Text("All Activity")
                    .tag(Self.allActivityFilterID)
                ForEach(calendarFilters) { filter in
                    Text(filter.displayName)
                        .tag(filter.id)
                }
            }
            .pickerStyle(.menu)

            if visibleActivities.isEmpty {
                Text(emptyStateText)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleActivities) { activity in
                        ActivityRow(activity: activity)
                        if activity.id != visibleActivities.last?.id {
                            Divider()
                                .padding(.leading, 32)
                        }
                    }
                }
            }
        }
        .onChange(of: calendarFilters.map(\.id)) { _, filterIDs in
            guard selectedFilterID != Self.allActivityFilterID,
                  !filterIDs.contains(selectedFilterID) else {
                return
            }
            selectedFilterID = Self.allActivityFilterID
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private var calendarFilters: [CalendarFilter] {
        var filters: [String: CalendarFilter] = [:]
        for coverage in flow.accountCoverages {
            let selectedCalendarIDs = flow.selectedCalendarIDs(for: coverage.account.id)
            for calendar in coverage.calendars where selectedCalendarIDs.contains(calendar.id) {
                let filter = CalendarFilter(
                    accountID: coverage.account.id,
                    accountEmail: coverage.account.email,
                    calendarID: calendar.id,
                    calendarName: calendar.name
                )
                filters[filter.id] = filter
            }
        }

        return filters.values.sorted {
            if $0.accountEmail == $1.accountEmail {
                return $0.calendarName.localizedCaseInsensitiveCompare($1.calendarName) == .orderedAscending
            }
            return $0.accountEmail.localizedCaseInsensitiveCompare($1.accountEmail) == .orderedAscending
        }
    }

    private var visibleActivities: [ProtectionActivity] {
        guard selectedFilterID != Self.allActivityFilterID,
              let selectedFilter = calendarFilters.first(where: { $0.id == selectedFilterID }) else {
            return flow.activityLog
        }
        return flow.activities(
            forCalendarID: selectedFilter.calendarID,
            accountID: selectedFilter.accountID
        )
    }

    private var emptyStateText: String {
        selectedFilterID == Self.allActivityFilterID
            ? "No protection activity recorded today."
            : "No activity recorded for this calendar today."
    }

    private struct ActivityRow: View {
        let activity: ProtectionActivity

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: activity.actor == .user ? "person.circle.fill" : "gearshape.circle.fill")
                    .foregroundStyle(activity.actor == .user ? Color.accentColor : Color.secondary)
                    .font(.title3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(activity.title)
                            .font(.body.weight(.semibold))
                        Spacer(minLength: 8)
                        Text(ProtectionActivityCard.timeFormatter.string(from: activity.occurredAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(activity.actor == .user ? "You" : "System")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(activity.detail)
                        .font(.callout)

                    if let commitmentTitle = activity.commitmentTitle {
                        let commitmentContext = if let startDate = activity.commitmentStartDate {
                            "\(commitmentTitle) · \(ProtectionActivityCard.timeFormatter.string(from: startDate))"
                        } else {
                            commitmentTitle
                        }
                        Text("Commitment: \(commitmentContext)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let calendarContext = activity.calendarName ?? activity.calendarID {
                        Text("Calendar: \(calendarContext)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let accountEmail = activity.accountEmail {
                        Text("Account: \(accountEmail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        }

        private var accessibilityText: String {
            var parts = [
                activity.actor == .user ? "You" : "System",
                activity.title,
                activity.detail
            ]
            if let commitmentTitle = activity.commitmentTitle {
                parts.append("Commitment: \(commitmentTitle)")
            }
            if let calendarContext = activity.calendarName ?? activity.calendarID {
                parts.append("Calendar: \(calendarContext)")
            }
            if let accountEmail = activity.accountEmail {
                parts.append("Account: \(accountEmail)")
            }
            return parts.joined(separator: ", ")
        }
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var windowController = EarlyReminderWindowController.shared
    @State private var isStopRemindersConfirmationPresented = false
    @State private var pendingStopRemindersCommitment: CalendarEvent?

    var body: some View {
        VStack(spacing: 18) {
            if let commitment = flow.earlyReminderCommitment {
                Label("Early Reminder", systemImage: "bell.fill")
                    .font(.headline)
                if flow.isEarlyReminderUnverified {
                    Label("Unverified Reminder", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if let conflict = flow.earlyReminderConflict,
                   conflict.requiresPrimarySelection {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Commitment Conflict", systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.semibold))
                        Text("These commitments start at the same time. Choose a primary commitment before the Strong Alert.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(conflict.commitments) { conflictCommitment in
                            Button("Make primary: \(conflictCommitment.title)") {
                                if flow.selectPrimary(for: conflictCommitment) {
                                    announceActionResult(flow.lastActionMessage)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text(commitment.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(flow.localStartTimeText(for: commitment))
                        .font(.title3.weight(.semibold))
                    Text(flow.countdownText(for: commitment, at: Date()))
                        .foregroundStyle(.secondary)
                    if let conflict = flow.earlyReminderConflict {
                        let otherCommitments = conflict.commitments
                            .filter { $0.id != conflict.primaryCommitment?.id }
                            .map(\.title)
                            .joined(separator: ", ")
                        Text("Conflict includes: \(otherCommitments)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Got it closes this reminder. Strong Alert will still appear when the commitment begins.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Menu("Snooze") {
                    ForEach(flow.snoozeOptionsMinutes, id: \.self) { minutes in
                        Button("\(minutes) minutes") {
                            let didApply = flow.snoozeEarlyReminder(minutes: minutes, for: commitment)
                            if didApply {
                                announceActionResult(flow.lastActionMessage)
                            }
                            closeAfterAction(reopenIfNeeded: !didApply)
                        }
                    }
                }
                .disabled(!flow.canSnoozeEarlyReminder)
                .accessibilityHint("Choose how long to pause all reminders, including Strong Alert.")

                HStack(spacing: 10) {
                    Button("Got it") {
                        let didApply = flow.clearEarlyReminder(for: commitment)
                        if didApply {
                            announceActionResult(flow.lastActionMessage)
                        }
                        closeAfterAction(reopenIfNeeded: !didApply)
                    }
                    .keyboardShortcut("g")
                    .buttonStyle(.bordered)
                    .accessibilityHint("Close this early reminder while keeping the Strong Alert at the commitment start.")

                    Button("Stop reminders") {
                        requestStopReminders(for: commitment)
                    }
                    .keyboardShortcut("s")
                    .buttonStyle(.bordered)
                    .accessibilityHint("Stop Early Reminder and Strong Alert for this commitment occurrence without changing Google Calendar.")
                }
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
        .padding(flow.earlyReminderCommitment == nil ? 0 : 28)
        .frame(
            minWidth: flow.earlyReminderCommitment == nil ? 1 : 380,
            minHeight: flow.earlyReminderCommitment == nil ? 1 : 0
        )
        .accessibilityAddTraits(.isModal)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .onAppear {
            flow.setBlockingAvailability(false)
            windowController.setBlockingModeEnabled(flow.isBlockingModeEnabled)
            guard let commitment = flow.earlyReminderCommitment else {
                flow.setBlockingAvailability(true)
                EarlyReminderWindowController.shared.prepareForProgrammaticClose()
                dismiss()
                EarlyReminderWindowController.shared.close()
                return
            }
            EarlyReminderWindowController.shared.present(
                content: EarlyReminderFallbackContent(
                    title: commitment.title,
                    timing: flow.localStartTimeText(for: commitment),
                    snoozeOptionsMinutes: flow.snoozeOptionsMinutes,
                    verificationLabel: flow.isEarlyReminderUnverified ? "Unverified Reminder" : nil
                ),
                reopen: {
                    openEarlyReminderIfNeeded(flow: flow) {
                        openWindow(id: "early-reminder")
                    }
                },
                clear: {
                    let didApply = flow.clearEarlyReminder(for: commitment)
                    if didApply {
                        announceActionResult(flow.lastActionMessage)
                    }
                    closeAfterAction(reopenIfNeeded: !didApply)
                },
                canSnooze: flow.canSnoozeEarlyReminder,
                snooze: { minutes in
                    let didApply = flow.snoozeEarlyReminder(minutes: minutes, for: commitment)
                    if didApply {
                        announceActionResult(flow.lastActionMessage)
                    }
                    closeAfterAction(reopenIfNeeded: !didApply)
                },
                dismiss: {
                    let didApply = flow.dismissCommitment(for: commitment)
                    if didApply {
                        announceActionResult(flow.lastActionMessage)
                    }
                    closeAfterAction(reopenIfNeeded: !didApply)
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
                        timing: flow.localStartTimeText(for: commitment),
                        snoozeOptionsMinutes: flow.snoozeOptionsMinutes,
                        verificationLabel: flow.isEarlyReminderUnverified ? "Unverified Reminder" : nil
                    ),
                    reopen: {
                        openEarlyReminderIfNeeded(flow: flow) {
                            openWindow(id: "early-reminder")
                        }
                    },
                    clear: {
                        let didApply = flow.clearEarlyReminder(for: commitment)
                        if didApply {
                            announceActionResult(flow.lastActionMessage)
                        }
                        closeAfterAction(reopenIfNeeded: !didApply)
                    },
                    canSnooze: flow.canSnoozeEarlyReminder,
                    snooze: { minutes in
                        let didApply = flow.snoozeEarlyReminder(minutes: minutes, for: commitment)
                        if didApply {
                            announceActionResult(flow.lastActionMessage)
                        }
                        closeAfterAction(reopenIfNeeded: !didApply)
                    },
                    dismiss: {
                        let didApply = flow.dismissCommitment(for: commitment)
                        if didApply {
                            announceActionResult(flow.lastActionMessage)
                        }
                        closeAfterAction(reopenIfNeeded: !didApply)
                    }
                )
            }
        }
        .onChange(of: flow.earlyReminderCommitment) { _, commitment in
            if commitment == nil {
                flow.setBlockingAvailability(true)
                EarlyReminderWindowController.shared.prepareForProgrammaticClose()
                dismiss()
                EarlyReminderWindowController.shared.close()
            }
        }
        .onChange(of: windowController.isGlobalInteractionBarrierAvailable) { _, isAvailable in
            flow.setBlockingAvailability(isAvailable)
        }
        .stopRemindersConfirmation(
            isPresented: $isStopRemindersConfirmationPresented,
            onCancel: { pendingStopRemindersCommitment = nil },
            onConfirm: {
                guard let pendingStopRemindersCommitment,
                      flow.dismissCommitment(for: pendingStopRemindersCommitment) else {
                    self.pendingStopRemindersCommitment = nil
                    return
                }
                announceActionResult(flow.lastActionMessage)
                self.pendingStopRemindersCommitment = nil
            }
        )
    }

    private func requestStopReminders(for commitment: CalendarEvent) {
        pendingStopRemindersCommitment = commitment
        isStopRemindersConfirmationPresented = true
    }

    private func closeAfterAction(reopenIfNeeded: Bool = false) {
        EarlyReminderWindowController.shared.prepareForProgrammaticClose()
        dismiss()
        EarlyReminderWindowController.shared.close()
        if reopenIfNeeded {
            openEarlyReminderIfNeeded(flow: flow) {
                openWindow(id: "early-reminder")
            }
        }
    }
}

private struct StrongAlertWindowView: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StrongAlertContentView(flow: flow)
            .accessibilityAddTraits(.isModal)
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                }
            }
            .onAppear {
                presentStrongAlertSurface()
            }
            .onChange(of: flow.isStrongAlertPresented) { _, isPresented in
                if isPresented {
                    presentStrongAlertSurface()
                } else {
                    StrongAlertWindowController.shared.close()
                }
            }
    }

    private func presentStrongAlertSurface() {
        StrongAlertWindowController.shared.present(
            content: AnyView(StrongAlertContentView(flow: flow)),
            surfaceDidClose: {
                flow.closeStrongAlertSurface()
                announceActionResult(flow.lastActionMessage)
            }
        )
    }
}

private struct StrongAlertContentView: View {
    @ObservedObject var flow: CommitmentProtectionFlow
    @State private var isStopRemindersConfirmationPresented = false
    @State private var pendingStopRemindersCommitment: CalendarEvent?

    var body: some View {
        Group {
            if let conflict = flow.strongAlertConflict,
               conflict.requiresPrimarySelection {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    StrongAlertConflictContentView(
                        flow: flow,
                        conflict: conflict,
                        date: context.date,
                        requestStopReminders: requestStopReminders
                    )
                }
            } else if let commitment = flow.strongAlertCommitment {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    VStack(spacing: 12) {
                        StrongAlertView(
                            title: commitment.title,
                            timing: flow.strongAlertTimingText(for: commitment, at: context.date),
                            detail: flow.strongAlertContextText(for: commitment),
                            verificationLabel: flow.isStrongAlertUnverified ? "Unverified Reminder" : nil,
                            primaryActionTitle: flow.strongAlertPrimaryActionTitle,
                            primaryAction: {
                                if flow.strongAlertMeetingLinkOptions.isEmpty {
                                    requestStopReminders(for: commitment)
                                } else if let primaryLink = flow.strongAlertPrimaryMeetingLink,
                                          let meetingLink = flow.joinStrongAlert(using: primaryLink) {
                                    NSWorkspace.shared.open(meetingLink)
                                    announceActionResult(flow.lastActionMessage)
                                } else if let meetingLink = flow.joinStrongAlert() {
                                    NSWorkspace.shared.open(meetingLink)
                                    announceActionResult(flow.lastActionMessage)
                                }
                            },
                            primaryActionChoices: flow.strongAlertPrimaryMeetingLink == nil &&
                                flow.strongAlertMeetingLinkOptions.count > 1
                                ? flow.strongAlertMeetingLinkOptions.enumerated().map { _, link in
                                    (meetingLinkChoiceTitle(for: link), {
                                        if let meetingLink = flow.joinStrongAlert(using: link) {
                                            NSWorkspace.shared.open(meetingLink)
                                            announceActionResult(flow.lastActionMessage)
                                        }
                                    })
                                }
                                : [],
                            secondaryActionTitle: flow.strongAlertMeetingLinkOptions.isEmpty ? nil : "Stop reminders",
                            secondaryAction: {
                                requestStopReminders(for: commitment)
                            },
                            secondaryActionKeyboardShortcut: "s",
                            tertiaryActionTitle: "Got it",
                            tertiaryAction: {
                                flow.closeStrongAlertSurface()
                                announceActionResult(flow.lastActionMessage)
                            },
                            pauseAction: { duration in
                                if flow.pause(for: duration) {
                                    announceActionResult(flow.lastActionMessage)
                                }
                            }
                        )
                        if let conflict = flow.strongAlertConflict {
                            StrongAlertConflictSummaryView(flow: flow, conflict: conflict)
                        }
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Text("No commitment needs attention.")
                        .foregroundStyle(.secondary)
                }
                .padding(32)
            }
        }
        .frame(minWidth: 460, minHeight: 330)
        .stopRemindersConfirmation(
            isPresented: $isStopRemindersConfirmationPresented,
            onCancel: { pendingStopRemindersCommitment = nil },
            onConfirm: {
                guard let pendingStopRemindersCommitment,
                      flow.dismissCommitment(for: pendingStopRemindersCommitment) else {
                    self.pendingStopRemindersCommitment = nil
                    return
                }
                announceActionResult(flow.lastActionMessage)
                self.pendingStopRemindersCommitment = nil
            }
        )
    }

    private func requestStopReminders(for commitment: CalendarEvent) {
        pendingStopRemindersCommitment = commitment
        isStopRemindersConfirmationPresented = true
    }

    private func meetingLinkChoiceTitle(for link: URL) -> String {
        let provider = link.host ?? "meeting link"
        let path = link.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            return "Join via \(provider)"
        }
        return "Join via \(provider) · \(path)"
    }
}

private struct StrongAlertConflictSummaryView: View {
    @ObservedObject var flow: CommitmentProtectionFlow
    let conflict: CommitmentConflict

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Commitment Conflict", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
            Text("Other commitments in this conflict remain visible while the primary commitment gets your attention.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(conflict.commitments.enumerated()), id: \.offset) { _, commitment in
                HStack(spacing: 8) {
                    if let primaryCommitment = conflict.primaryCommitment,
                       primaryCommitment.id == commitment.id {
                        Label("Primary", systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    Text(commitment.title)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(flow.localStartTimeText(for: commitment))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct StrongAlertConflictContentView: View {
    @ObservedObject var flow: CommitmentProtectionFlow
    let conflict: CommitmentConflict
    let date: Date
    let requestStopReminders: (CalendarEvent) -> Void
    @State private var customPauseExpiration = Date().addingTimeInterval(60 * 60)
    @State private var isCustomPausePresented = false

    var body: some View {
        VStack(spacing: 16) {
            Label("Strong Alert", systemImage: "bell.and.waves.left.and.right.fill")
                .font(.headline)
            if flow.isStrongAlertUnverified {
                Label("Unverified Reminder", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text("Choose a commitment")
                .font(.title2.bold())
            Text("These commitments start at the same time. Choose which one to make primary, or act on either one.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(conflict.commitments) { commitment in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(commitment.title)
                            .font(.headline)
                        Text(flow.strongAlertTimingText(for: commitment, at: date))
                            .font(.subheadline.weight(.semibold))
                        Text(flow.strongAlertContextText(for: commitment))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            primaryAction(for: commitment)
                            Button("Make primary") {
                                if flow.selectPrimary(for: commitment) {
                                    announceActionResult(flow.lastActionMessage)
                                }
                            }
                            .buttonStyle(.bordered)
                            .accessibilityHint("Use this commitment as the primary choice for this conflict.")
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }
            }

            Button("Got it") {
                flow.closeStrongAlertSurface()
                announceActionResult(flow.lastActionMessage)
            }
            .keyboardShortcut("g")
            .buttonStyle(.bordered)
            .accessibilityHint("Close this Strong Alert. Protection remains active and it will repeat after the configured interval.")

            if let pauseAction = pauseAction {
                Menu("Pause protection") {
                    Button("Pause for 1 hour") {
                        pauseAction(.oneHour)
                    }
                    Button("Pause until end of day") {
                        pauseAction(.endOfDay)
                    }
                    Button("Pause until selected time") {
                        isCustomPausePresented = true
                    }
                }
                .keyboardShortcut("p")
                .accessibilityHint("Suppress Early Reminder and Strong Alert until the selected expiration.")
            }
        }
        .padding(28)
        .frame(minWidth: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .sheet(isPresented: $isCustomPausePresented) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pause protection")
                    .font(.headline)
                DatePicker(
                    "Expiration",
                    selection: $customPauseExpiration,
                    in: Date()...
                )
                .environment(\.locale, Locale(identifier: "tr_TR"))
                Button("Pause until selected time") {
                    pauseAction?(.custom(customPauseExpiration))
                    isCustomPausePresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(minWidth: 320)
        }
    }

    @ViewBuilder
    private func primaryAction(for commitment: CalendarEvent) -> some View {
        let links = flow.strongAlertMeetingLinkOptions(for: commitment)
        if links.isEmpty {
            Button("Stop reminders") {
                requestStopReminders(commitment)
            }
            .buttonStyle(.borderedProminent)
        } else if let primaryLink = flow.strongAlertPrimaryMeetingLink(for: commitment) {
            Button("Join") {
                if let meetingLink = flow.joinStrongAlert(for: commitment, using: primaryLink) {
                    NSWorkspace.shared.open(meetingLink)
                    announceActionResult(flow.lastActionMessage)
                }
            }
            .buttonStyle(.borderedProminent)
        } else {
            Menu("Choose link") {
                ForEach(links, id: \.absoluteString) { link in
                    Button(meetingLinkChoiceTitle(for: link)) {
                        if let meetingLink = flow.joinStrongAlert(for: commitment, using: link) {
                            NSWorkspace.shared.open(meetingLink)
                            announceActionResult(flow.lastActionMessage)
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }

        if !links.isEmpty {
            Button("Stop reminders") {
                requestStopReminders(commitment)
            }
            .buttonStyle(.bordered)
        }
    }

    private var pauseAction: ((PauseDuration) -> Void)? {
        { duration in
            if flow.pause(for: duration) {
                announceActionResult(flow.lastActionMessage)
            }
        }
    }

    private func meetingLinkChoiceTitle(for link: URL) -> String {
        let provider = link.host ?? "meeting link"
        let path = link.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            return "Join via \(provider)"
        }
        return "Join via \(provider) · \(path)"
    }
}

private struct EarlyReminderFallbackContent {
    let title: String
    let timing: String
    let snoozeOptionsMinutes: [Int]
    let verificationLabel: String?
}

private struct EarlyReminderFallbackView: View {
    let content: EarlyReminderFallbackContent
    let canSnooze: Bool
    let clear: () -> Void
    let snooze: (Int) -> Void
    let dismiss: () -> Void
    @State private var isStopRemindersConfirmationPresented = false

    var body: some View {
        VStack(spacing: 16) {
            Label("Early Reminder", systemImage: "bell.fill")
                .font(.headline)
            if let verificationLabel = content.verificationLabel {
                Label(verificationLabel, systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            Text(content.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(content.timing)
                .font(.title3.weight(.semibold))
            Text("Got it closes this reminder. Strong Alert will still appear when the commitment begins.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Menu("Snooze") {
                ForEach(content.snoozeOptionsMinutes, id: \.self) { minutes in
                    Button("\(minutes) minutes") { snooze(minutes) }
                }
            }
            .disabled(!canSnooze)
            .accessibilityHint("Choose how long to pause all reminders, including Strong Alert.")
            HStack(spacing: 10) {
                Button("Got it", action: clear)
                    .keyboardShortcut("g")
                    .buttonStyle(.bordered)
                    .accessibilityHint("Close this early reminder while keeping the Strong Alert at the commitment start.")
                Button("Stop reminders") {
                    isStopRemindersConfirmationPresented = true
                }
                    .keyboardShortcut("s")
                    .buttonStyle(.bordered)
                    .accessibilityHint("Stop Early Reminder and Strong Alert for this commitment occurrence without changing Google Calendar.")
            }
        }
        .padding(28)
        .frame(minWidth: 380)
        .stopRemindersConfirmation(
            isPresented: $isStopRemindersConfirmationPresented,
            onCancel: {},
            onConfirm: dismiss
        )
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
            // The controller notices the disabled tap on its retry timer and
            // returns the reminder to visual-only mode.
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

        guard CGPreflightListenEventAccess(),
              AXIsProcessTrustedWithOptions(nil) else {
            return nil
        }

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
    private var snoozeEarlyReminder: ((Int) -> Void)?
    private var dismissCommitment: (() -> Void)?
    private var canSnoozeEarlyReminder = false
    private var fallbackContent: EarlyReminderFallbackContent?
    private var fallbackPanel: NSPanel?
    private var surfaceRecoveryAttempts = 0
    private var screenObserver: NSObjectProtocol?
    private var allowsWindowClose = false
    private var isPresented = false
    private var isInteractionBarrierActive = false
    private var blockingMode = EarlyReminderBlockingMode()
    private var lifecycle = AlertPresentationLifecycle()
    private let normalPresentationContract = AlertPresentationContract(variant: .earlyReminderNormal)
    private let fallbackPresentationContract = AlertPresentationContract(variant: .earlyReminderFallback)
    @Published private(set) var isGlobalInteractionBarrierAvailable = false

    func present(
        content: EarlyReminderFallbackContent,
        reopen: @escaping @MainActor () -> Void,
        clear: @escaping @MainActor () -> Void,
        canSnooze: Bool,
        snooze: @escaping (Int) -> Void,
        dismiss: @escaping () -> Void
    ) {
        reopenSurface = reopen
        clearEarlyReminder = clear
        canSnoozeEarlyReminder = canSnooze
        snoozeEarlyReminder = snooze
        dismissCommitment = dismiss
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
            _ = lifecycle.present(
                surface: .earlyReminderNormal,
                displayCount: NSScreen.screens.count,
                primaryIndex: nil,
                surfaceDiscovered: false
            )
            DispatchQueue.main.async { [weak self] in
                self?.present(
                    content: content,
                    reopen: reopen,
                    clear: clear,
                    canSnooze: canSnooze,
                    snooze: snooze,
                    dismiss: dismiss
                )
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
        window.sharingType = normalPresentationContract.remainsVisibleDuringDisplaySharing ? .readOnly : .none
        window.standardWindowButton(.closeButton)?.isEnabled = true
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isMovable = false
        _ = lifecycle.present(
            surface: .earlyReminderNormal,
            displayCount: NSScreen.screens.count,
            primaryIndex: NSScreen.screens.firstIndex(where: { $0 === window.screen }),
            surfaceDiscovered: true
        )
        isPresented = lifecycle.isPresented
        startScreenObservation()
        let barrierAvailable: Bool
        if blockingMode.shouldAttemptBlocking {
            startBarrierRetryMonitoring()
            barrierAvailable = attemptBlockingMode()
        } else {
            barrierAvailable = false
        }
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
        lifecycle.surfaceDisappeared()
        deactivateInteractionBarrier()
        isPresented = false
        window?.standardWindowButton(.closeButton)?.isEnabled = true
    }

    func close() {
        allowsWindowClose = true
        let window = self.window
        stop()
        stopScreenObservation()
        window?.delegate = nil
        window?.close()
        fallbackPanel = nil
        self.window = nil
        self.fallbackContent = nil
        self.clearEarlyReminder = nil
        self.snoozeEarlyReminder = nil
        self.dismissCommitment = nil
        self.canSnoozeEarlyReminder = false
        lifecycle.close()
        allowsWindowClose = false
    }

    func prepareForProgrammaticClose() {
        allowsWindowClose = true
        window?.delegate = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !allowsWindowClose else { return true }
        lifecycle.surfaceDisappeared()
        clearEarlyReminder?()
        return false
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
        clear: @escaping @MainActor () -> Void,
        canSnooze: Bool,
        snooze: @escaping (Int) -> Void,
        dismiss: @escaping () -> Void
    ) {
        reopenSurface = reopen
        clearEarlyReminder = clear
        canSnoozeEarlyReminder = canSnooze
        snoozeEarlyReminder = snooze
        dismissCommitment = dismiss
        fallbackContent = content
        guard isPresented else {
            lifecycle.surfaceDisappeared()
            startSurfaceRecoveryMonitoring()
            return
        }
        stopBarrierRetryMonitoring()
        deactivateInteractionBarrier()
        lifecycle.surfaceDisappeared()
        isPresented = false
        window = nil
        startSurfaceRecoveryMonitoring()
    }

    private func startSurfaceRecoveryMonitoring() {
        guard lifecycle.requiresSurfaceRecovery,
              surfaceRecoveryTimer == nil,
              reopenSurface != nil else { return }
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

    private func startScreenObservation() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reconcilePresentationTopology()
            }
        }
    }

    private func stopScreenObservation() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func reconcilePresentationTopology() {
        guard isPresented || lifecycle.requiresSurfaceRecovery || lifecycle.requiresSurfaceCreation else { return }
        _ = lifecycle.displayTopologyChanged(
            displayCount: NSScreen.screens.count,
            primaryIndex: NSScreen.screens.firstIndex(where: { $0 === window?.screen })
        )
        guard lifecycle.displayPlan != nil else { return }
        isPresented = lifecycle.isPresented
        bringReminderToFront()
    }

    private func showFallbackSurface() {
        guard !isPresented,
              let content = fallbackContent,
              let clearEarlyReminder,
              let snoozeEarlyReminder,
              let dismissCommitment else { return }

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
        panel.sharingType = fallbackPresentationContract.remainsVisibleDuringDisplaySharing ? .readOnly : .none
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: EarlyReminderFallbackView(
                content: content,
                canSnooze: canSnoozeEarlyReminder,
                clear: clearEarlyReminder,
                snooze: snoozeEarlyReminder,
                dismiss: dismissCommitment
            )
        )
        panel.center()
        fallbackPanel = panel
        window = panel
        _ = lifecycle.present(
            surface: .earlyReminderFallback,
            displayCount: NSScreen.screens.count,
            primaryIndex: NSScreen.screens.firstIndex(where: { $0 === panel.screen }),
            surfaceDiscovered: true
        )
        isPresented = lifecycle.isPresented
        startScreenObservation()
        let barrierAvailable: Bool
        if blockingMode.shouldAttemptBlocking {
            startBarrierRetryMonitoring()
            barrierAvailable = attemptBlockingMode()
        } else {
            barrierAvailable = false
        }
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

    func setBlockingModeEnabled(_ isEnabled: Bool) {
        if isEnabled {
            blockingMode.enableBlocking()
        } else {
            blockingMode.disableBlocking()
        }

        guard isPresented else { return }

        stopBarrierRetryMonitoring()
        deactivateInteractionBarrier()
        if isEnabled {
            startBarrierRetryMonitoring()
            retryInteractionBarrierIfNeeded()
        } else {
            window?.orderFrontRegardless()
        }
    }

    @discardableResult
    private func activateInteractionBarrier() -> Bool {
        guard isPresented, let window else { return false }
        if isInteractionBarrierActive { return true }
        guard let eventTap = interactionGate.start(
            for: window,
            isApplicationActive: NSApp.isActive
        ) else {
            setInteractionBarrierAvailability(false)
            return false
        }
        guard let eventSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0) else {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            interactionGate.stop()
            setInteractionBarrierAvailability(false)
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
        setInteractionBarrierAvailability(true)
        refreshFallbackPanelContent()
        return true
    }

    private func refreshFallbackPanelContent() {
        guard let panel = fallbackPanel,
              let content = fallbackContent,
              let clearEarlyReminder,
              let snoozeEarlyReminder,
              let dismissCommitment else { return }
        panel.contentView = NSHostingView(
            rootView: EarlyReminderFallbackView(
                content: content,
                canSnooze: canSnoozeEarlyReminder,
                clear: clearEarlyReminder,
                snooze: snoozeEarlyReminder,
                dismiss: dismissCommitment
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
        setInteractionBarrierAvailability(false)
    }

    private func startBarrierRetryMonitoring() {
        guard blockingMode.shouldAttemptBlocking, barrierRetryTimer == nil else { return }
        barrierRetryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retryInteractionBarrierIfNeeded()
            }
        }
    }

    private func setInteractionBarrierAvailability(_ isAvailable: Bool) {
        isGlobalInteractionBarrierAvailable = isAvailable
        lifecycle.interactionBarrierAvailabilityChanged(isAvailable)
    }

    private func stopBarrierRetryMonitoring() {
        barrierRetryTimer?.invalidate()
        barrierRetryTimer = nil
    }

    private func retryInteractionBarrierIfNeeded() {
        guard isPresented, blockingMode.shouldAttemptBlocking else { return }
        if lifecycle.isInteractionBarrierAvailable && isInteractionBarrierActive {
            if interactionGate.userDisabledEventTap() {
                stopBarrierRetryMonitoring()
                deactivateInteractionBarrier()
                blockingMode.disableBlocking()
                refreshFallbackPanelContent()
                return
            }
            guard let globalEventTap, CGEvent.tapIsEnabled(tap: globalEventTap) else {
                return
            }
            return
        }
        guard attemptBlockingMode() else { return }
        bringReminderToFront()
    }

    @discardableResult
    private func attemptBlockingMode() -> Bool {
        guard blockingMode.shouldAttemptBlocking else { return false }
        guard activateInteractionBarrier() else {
            return false
        }
        return true
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
        lifecycle.markActivated()
    }
}

private struct StopRemindersConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert("Stop reminders for this commitment?", isPresented: $isPresented) {
            Button("Keep reminders", role: .cancel, action: onCancel)
            Button("Stop reminders", role: .destructive, action: onConfirm)
        } message: {
            Text("You will not receive an Early Reminder or Strong Alert when it starts. Your Google Calendar RSVP will not change.")
        }
    }
}

private extension View {
    func stopRemindersConfirmation(
        isPresented: Binding<Bool>,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(
            StopRemindersConfirmationModifier(
                isPresented: isPresented,
                onCancel: onCancel,
                onConfirm: onConfirm
            )
        )
    }
}

private struct StrongAlertView: View {
    let title: String
    let timing: String
    let detail: String
    var verificationLabel: String? = nil
    let primaryActionTitle: String
    let primaryAction: () -> Void
    var primaryActionChoices: [(String, () -> Void)] = []
    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var secondaryActionKeyboardShortcut: KeyEquivalent = "h"
    var tertiaryActionTitle: String? = nil
    var tertiaryAction: (() -> Void)? = nil
    var pauseAction: ((PauseDuration) -> Void)? = nil
    @State private var customPauseExpiration = Date().addingTimeInterval(60 * 60)
    @State private var isCustomPausePresented = false

    var body: some View {
        VStack(spacing: 20) {
            Label("Strong Alert", systemImage: "bell.and.waves.left.and.right.fill")
                .font(.headline)
                .foregroundStyle(.primary)
            if let verificationLabel {
                Label(verificationLabel, systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text(title)
                .font(.largeTitle.bold())
            Text(timing)
                .font(.title3.weight(.semibold))
            Text(detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if primaryActionChoices.isEmpty {
                Button(primaryActionTitle, action: primaryAction)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(primaryActionTitle)
                    .accessibilityHint("Take the primary action for this commitment.")
            } else {
                Menu(primaryActionTitle) {
                    ForEach(Array(primaryActionChoices.enumerated()), id: \.offset) { _, choice in
                        Button(choice.0, action: choice.1)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(primaryActionTitle)
                .accessibilityHint("Choose which Recognized Meeting Link to use for Join.")
            }
            if let secondaryActionTitle, let secondaryAction {
                Button(secondaryActionTitle, action: secondaryAction)
                    .keyboardShortcut(secondaryActionKeyboardShortcut)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(secondaryActionTitle)
                    .accessibilityHint("Stop Early Reminder and Strong Alert for this commitment occurrence without changing Google Calendar.")
            }
            if let tertiaryActionTitle, let tertiaryAction {
                Button(tertiaryActionTitle, action: tertiaryAction)
                    .keyboardShortcut("g")
                    .buttonStyle(.bordered)
                    .accessibilityLabel(tertiaryActionTitle)
                    .accessibilityHint("Close this Strong Alert. Protection remains active and it will repeat after the configured interval.")
            }
            if let pauseAction {
                Menu("Pause protection") {
                    Button("Pause for 1 hour") {
                        pauseAction(.oneHour)
                    }
                    Button("Pause until end of day") {
                        pauseAction(.endOfDay)
                    }
                    Button("Pause until selected time") {
                        isCustomPausePresented = true
                    }
                }
                .keyboardShortcut("p")
                .accessibilityHint("Suppress Early Reminder and Strong Alert until the selected expiration.")
            }
        }
        .padding(32)
        .frame(minWidth: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .sheet(isPresented: $isCustomPausePresented) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pause protection")
                    .font(.headline)
                DatePicker(
                    "Expiration",
                    selection: $customPauseExpiration,
                    in: Date()...
                )
                .environment(\.locale, Locale(identifier: "tr_TR"))
                Button("Pause until selected time") {
                    pauseAction?(.custom(customPauseExpiration))
                    isCustomPausePresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(minWidth: 320)
        }
    }
}

@MainActor
private func announceActionResult(_ message: String?) {
    guard let message else { return }
    NSAccessibility.post(
        element: NSApplication.shared,
        notification: .announcementRequested,
        userInfo: [.announcement: message]
    )
}

private struct MenuBarConflictView: View {
    @ObservedObject var flow: CommitmentProtectionFlow
    let conflict: CommitmentConflict

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Commitment Conflict", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
            if conflict.requiresPrimarySelection {
                Text("Choose which commitment is primary:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(conflict.commitments) { commitment in
                    Button("Make primary: \(commitment.title)") {
                        if flow.selectPrimary(for: commitment) {
                            announceActionResult(flow.lastActionMessage)
                        }
                    }
                }
            } else {
                let otherCommitments = conflict.commitments
                    .filter { $0.id != conflict.primaryCommitment?.id }
                    .map(\.title)
                    .joined(separator: ", ")
                Text("Conflict includes: \(otherCommitments)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @Environment(\.openWindow) private var openWindow
    @State private var customPauseExpiration = Date().addingTimeInterval(60 * 60)

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
                            openEarlyReminderIfNeeded(flow: flow) {
                                openWindow(id: "early-reminder")
                            }
                        }
                        .keyboardShortcut("r")
                    }

                    if let conflict = flow.strongAlertConflict ?? flow.upcomingConflict {
                        MenuBarConflictView(flow: flow, conflict: conflict)
                    }

                    Divider()
                }

                if flow.upcomingCommitment == nil,
                   let conflict = flow.strongAlertConflict {
                    MenuBarConflictView(flow: flow, conflict: conflict)
                    Divider()
                }

                if flow.isPaused(at: context.date) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Protection Paused", systemImage: "pause.circle.fill")
                            .font(.headline)
                        Text(flow.pauseExpirationText(at: context.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    Divider()
                } else if flow.status == .active {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Pause Protection", systemImage: "pause.circle")
                            .font(.headline)
                        Button("Pause for 1 hour") {
                            pause(.oneHour)
                        }
                        .keyboardShortcut("1")
                        Button("Pause until end of day") {
                            pause(.endOfDay)
                        }
                        .keyboardShortcut("e")
                        DatePicker(
                            "Custom expiration",
                            selection: $customPauseExpiration,
                            in: context.date...
                        )
                        .datePickerStyle(.field)
                        .environment(\.locale, Locale(identifier: "tr_TR"))
                        Button("Pause until selected time") {
                            pause(.custom(customPauseExpiration))
                        }
                        .keyboardShortcut("c")
                        .accessibilityHint("Suppress reminders until the selected local date and time.")
                    }

                    Divider()
                }

                if let decisionCommitment = flow.decisionCommitment,
                   let decision = flow.currentCommitmentDecision,
                   decision.isRestorable {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            decision == .dismissed ? "Protection dismissed" : "Commitment handled",
                            systemImage: "pause.circle"
                        )
                        .font(.headline)
                        Text(decisionCommitment.title)
                            .lineLimit(2)
                        if flow.canRestoreProtection {
                            Button("Restore Protection") {
                                if flow.restoreProtection() {
                                    announceActionResult(flow.lastActionMessage)
                                }
                            }
                            .keyboardShortcut("u")
                            .buttonStyle(.borderedProminent)
                            .accessibilityHint("Resume protection for this occurrence until it ends.")
                        } else {
                            Text("Protection cannot be restored after the commitment ends.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .contain)

                    Divider()
                }

                Label(
                    flow.menuBarTitle,
                    systemImage: flow.status == .active ? "checkmark.shield" : "exclamationmark.triangle"
                )
                    .font(.headline)

                ForEach(flow.accountCoverages) { coverage in
                    let health = flow.coverage(for: coverage.account.id) ?? coverage.health
                    VStack(alignment: .leading, spacing: 4) {
                        Text(coverage.account.email)
                            .font(.caption.weight(.semibold))
                        Text(health.displayTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let warning = flow.coverageWarning(for: coverage.account.id) {
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Button("Log Out") {
                            flow.disconnectGoogleAccount(accountID: coverage.account.id)
                        }
                    }

                    if coverage.id != flow.accountCoverages.last?.id {
                        Divider()
                    }
                }

                Divider()

                Button("Open Setup") {
                    SetupWindowController.shared.show {
                        openWindow(id: "setup")
                    }
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

    private func pause(_ duration: PauseDuration) {
        if flow.pause(for: duration) {
            announceActionResult(flow.lastActionMessage)
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
        .onAppear {
            SetupWindowController.shared.showAtLaunch {
                openWindow(id: "setup")
            }
            if flow.earlyReminderCommitment != nil {
                openEarlyReminderIfNeeded(flow: flow) {
                    openWindow(id: "early-reminder")
                }
            }
            if flow.isStrongAlertPresented {
                openWindow(id: "strong-alert")
            }
        }
        .onChange(of: flow.earlyReminderCommitment) { _, commitment in
            if commitment != nil {
                openEarlyReminderIfNeeded(flow: flow) {
                    openWindow(id: "early-reminder")
                }
            } else {
                EarlyReminderWindowController.shared.close()
            }
        }
        .onChange(of: flow.isStrongAlertPresented) { _, isPresented in
            if isPresented {
                openWindow(id: "strong-alert")
            } else {
                StrongAlertWindowController.shared.close()
            }
        }
    }
}
