import AppKit
import ApplicationServices
import Carbon.HIToolbox
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
    @StateObject private var onboardingState: OnboardingState

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
        let onboarding = OnboardingState()
        _flow = StateObject(wrappedValue: protectionFlow)
        _availabilityMonitor = StateObject(wrappedValue: monitor)
        _onboardingState = StateObject(wrappedValue: onboarding)
        Task {
            await protectionFlow.restoreSavedConnection()
            onboarding.resolveInitialLaunch(
                hasConfiguredProtection: protectionFlow.accountCoverages.contains { coverage in
                    !coverage.selectedCalendarIDs.isEmpty && coverage.isProtectionConfirmed
                }
            )
            protectionFlow.startMonitoring()
            monitor.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(flow)
                .environmentObject(onboardingState)
        } label: {
            MenuBarLabel()
                .environmentObject(flow)
                .environmentObject(onboardingState)
        }
        .menuBarExtraStyle(.window)

        Window("Set Up In Your Face", id: "onboarding") {
            OnboardingView()
                .environmentObject(flow)
                .environmentObject(onboardingState)
                .registerWindow(.onboarding)
        }
        .defaultSize(width: 616, height: 640)
        .windowResizability(.contentSize)

        Settings {
            SettingsRootView()
                .environmentObject(flow)
                .environmentObject(onboardingState)
        }

        Window("Test Alert", id: "test-alert") {
            TestAlertView()
                .environmentObject(flow)
                .environmentObject(onboardingState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("Early Reminder", id: "early-reminder") {
            EarlyReminderView()
                .environmentObject(flow)
                .registerWindow(.earlyReminder)
        }
        .windowResizability(.contentSize)

        Window("Strong Alert", id: "strong-alert") {
            StrongAlertWindowView()
                .environmentObject(flow)
                .registerWindow(.strongAlert)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
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

struct CoverageHealthView: View {
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
        case .checking:
            return "Checking Coverage"
        case .fresh:
            return "Fresh Coverage"
        case .stale:
            return "Stale Coverage"
        case .reconnectRequired:
            return "Calendar Access Required"
        case .unavailable:
            return "Coverage Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .fresh:
            return "checkmark.circle.fill"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .noCoverage, .stale, .reconnectRequired, .unavailable:
            return "exclamationmark.triangle.fill"
        }
    }

    var displayColor: Color {
        switch self {
        case .fresh:
            return .green
        case .checking:
            return .secondary
        case .noCoverage, .stale, .reconnectRequired, .unavailable:
            return .orange
        }
    }
}

struct ProtectionActivityCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @State private var selectedFilterID: CalendarFilter.ID?
    @State private var filterSearchText = ""
    var isCard = true

    private struct CalendarFilterID: Hashable {
        let accountID: String
        let calendarID: String
    }

    private struct CalendarFilter: Hashable, Identifiable {
        let accountID: String
        let accountLabel: String
        let calendarID: String
        let calendarName: String

        var id: CalendarFilterID {
            CalendarFilterID(accountID: accountID, calendarID: calendarID)
        }

        var displayName: String {
            InterfaceCopy.calendarActivityScope(
                calendarName: calendarName,
                accountLabel: accountLabel
            )
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    var body: some View {
        let filters = calendarFilters
        let activities = visibleActivities(for: filters)
        let lastActivityID = activities.last?.id

        VStack(alignment: .leading, spacing: 12) {
            Label("Protection Activity", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            Text("See today’s reminder actions and protection changes. Activity resets at the end of your local day.")
                .foregroundStyle(.secondary)

            activityScopeControl(filters: filters)

            if activities.isEmpty {
                Text(emptyStateText)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(activities) { activity in
                        ActivityRow(activity: activity)
                        if activity.id != lastActivityID {
                            Divider()
                                .padding(.leading, 32)
                        }
                    }
                }
            }
        }
        .onChange(of: filters.map(\.id)) { _, filterIDs in
            guard let selectedFilterID,
                  !filterIDs.contains(selectedFilterID) else {
                return
            }
            self.selectedFilterID = nil
        }
        .padding(isCard ? 20 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isCard {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.quaternary.opacity(0.35))
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func activityScopeControl(filters: [CalendarFilter]) -> some View {
        if filters.count > 12 {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search activity calendars", text: $filterSearchText)
                    .textFieldStyle(.roundedBorder)
                List(selection: $selectedFilterID) {
                    Text("All Activity")
                        .tag(CalendarFilter.ID?.none)
                    ForEach(matchingFilters(in: filters)) { filter in
                        Text(filter.displayName)
                            .tag(Optional(filter.id))
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 120, maxHeight: 180)
                .accessibilityLabel("Activity scope")
            }
        } else {
            Picker("Activity scope", selection: $selectedFilterID) {
                Text("All Activity")
                    .tag(CalendarFilter.ID?.none)
                ForEach(filters) { filter in
                    Text(filter.displayName)
                        .tag(Optional(filter.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var calendarFilters: [CalendarFilter] {
        var filters: [CalendarFilter.ID: CalendarFilter] = [:]
        for coverage in flow.accountCoverages {
            let selectedCalendarIDs = flow.selectedCalendarIDs(for: coverage.account.id)
            for calendar in coverage.calendars where selectedCalendarIDs.contains(calendar.id) {
                let filter = CalendarFilter(
                    accountID: coverage.account.id,
                    accountLabel: InterfaceCopy.connectedAccountLabel(
                        email: coverage.account.email,
                        displayName: coverage.account.displayName
                    ),
                    calendarID: calendar.id,
                    calendarName: calendar.name
                )
                filters[filter.id] = filter
            }
        }

        return filters.values.sorted {
            if $0.accountLabel == $1.accountLabel {
                return $0.calendarName.localizedCaseInsensitiveCompare($1.calendarName) == .orderedAscending
            }
            return $0.accountLabel.localizedCaseInsensitiveCompare($1.accountLabel) == .orderedAscending
        }
    }

    private func matchingFilters(in filters: [CalendarFilter]) -> [CalendarFilter] {
        let query = filterSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return filters }
        return filters.filter { filter in
            filter.calendarName.localizedCaseInsensitiveContains(query) ||
                filter.accountLabel.localizedCaseInsensitiveContains(query)
        }
    }

    private func visibleActivities(for filters: [CalendarFilter]) -> [ProtectionActivity] {
        guard let selectedFilterID,
              let selectedFilter = filters.first(where: { $0.id == selectedFilterID }) else {
            return flow.activityLog
        }
        return flow.activities(
            forCalendarID: selectedFilter.calendarID,
            accountID: selectedFilter.accountID
        )
    }

    private var emptyStateText: String {
        selectedFilterID == nil
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
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            activityTitle
                            Spacer(minLength: 8)
                            activityTime
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            activityTitle
                            activityTime
                        }
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

                    if let calendarContext = activity.calendarName ??
                        (activity.calendarID == nil ? nil : "Calendar unavailable") {
                        Text("Calendar: \(calendarContext)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let accountEmail = activity.accountEmail {
                        let accountLabel = InterfaceCopy.connectedAccountLabel(
                            email: accountEmail,
                            displayName: ""
                        )
                        Text("Account: \(accountLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        }

        private var activityTitle: some View {
            Text(activity.title)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }

        private var activityTime: some View {
            Text(timeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        private var accessibilityText: String {
            var parts = [
                activity.actor == .user ? "You" : "System",
                timeText,
                activity.title,
                activity.detail
            ]
            if let commitmentTitle = activity.commitmentTitle {
                let commitmentContext = if let startDate = activity.commitmentStartDate {
                    "\(commitmentTitle), \(ProtectionActivityCard.timeFormatter.string(from: startDate))"
                } else {
                    commitmentTitle
                }
                parts.append("Commitment: \(commitmentContext)")
            }
            if let calendarContext = activity.calendarName ??
                (activity.calendarID == nil ? nil : "Calendar unavailable") {
                parts.append("Calendar: \(calendarContext)")
            }
            if let accountEmail = activity.accountEmail {
                let accountLabel = InterfaceCopy.connectedAccountLabel(
                    email: accountEmail,
                    displayName: ""
                )
                parts.append("Account: \(accountLabel)")
            }
            return parts.joined(separator: ", ")
        }

        private var timeText: String {
            ProtectionActivityCard.timeFormatter.string(from: activity.occurredAt)
        }
    }
}

private struct TestAlertView: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @EnvironmentObject private var onboardingState: OnboardingState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StrongAlertView(
            title: "Test Alert",
            timing: "Ready now",
            detail: "This preview shows the Strong Alert experience. It won’t change any calendar event or RSVP.",
            primaryActionHint: "Finish this Test Alert without changing a calendar event or RSVP.",
            primaryActionTitle: "Finish Test",
            primaryAction: {
                flow.dismissTestAlert()
                onboardingState.markTestAlertHandled()
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
                    Text(InterfaceCopy.unverifiedReminderDetail())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let conflict = flow.earlyReminderConflict,
                   conflict.requiresPrimarySelection {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Commitment Conflict", systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.semibold))
                        Text("These commitments start at the same time. You can choose which commitment Strong Alert features; otherwise they remain equal choices.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(conflict.commitments, id: \.occurrenceID) { conflictCommitment in
                                Button("Make primary: \(conflictCommitment.title)") {
                                    if flow.selectPrimary(for: conflictCommitment) {
                                        announceActionResult(flow.lastActionMessage)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text(commitment.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                    Text(flow.localStartTimeText(for: commitment))
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(flow.countdownText(for: commitment, at: Date()))
                        .foregroundStyle(.secondary)
                    if let conflict = flow.earlyReminderConflict {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Also in this conflict")
                                .font(.caption.weight(.semibold))
                            ForEach(conflict.commitments.filter {
                                $0.occurrenceID != conflict.primaryCommitment?.occurrenceID
                            }, id: \.occurrenceID) { otherCommitment in
                                Label(otherCommitment.title, systemImage: "calendar")
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("Close for now hides this Early Reminder. Strong Alert still appears when the commitment begins.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Menu("Snooze") {
                    ForEach(flow.snoozeOptionsMinutes, id: \.self) { minutes in
                        Button(InterfaceCopy.minuteDuration(minutes)) {
                            let didApply = flow.snoozeEarlyReminder(minutes: minutes, for: commitment)
                            if didApply {
                                announceActionResult(flow.lastActionMessage)
                            }
                            closeAfterAction(reopenIfNeeded: !didApply)
                        }
                    }
                }
                .disabled(!flow.canSnoozeEarlyReminder)
                .accessibilityHint("Choose how long to delay this occurrence’s Early Reminder and Strong Alert.")
                Text("Snooze delays both reminders for this occurrence and can continue past its start time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        earlyReminderActions(for: commitment)
                    }
                    VStack(spacing: 8) {
                        earlyReminderActions(for: commitment)
                    }
                }
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
        .padding(flow.earlyReminderCommitment == nil ? 0 : 28)
        .frame(
            idealWidth: flow.earlyReminderCommitment == nil ? 1 : 500,
            maxWidth: flow.earlyReminderCommitment == nil ? 1 : 560,
            maxHeight: flow.earlyReminderCommitment == nil ? 1 : 680
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

    @ViewBuilder
    private func earlyReminderActions(for commitment: CalendarEvent) -> some View {
        Button("Close for now") {
            let didApply = flow.clearEarlyReminder(for: commitment)
            if didApply {
                announceActionResult(flow.lastActionMessage)
            }
            closeAfterAction(reopenIfNeeded: !didApply)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Close this Early Reminder while keeping Strong Alert active at the commitment start.")

        Button("Stop reminders") {
            requestStopReminders(for: commitment)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Stop Early Reminder and Strong Alert for this occurrence without changing Google Calendar.")
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
        guard flow.isStrongAlertPresented,
              flow.strongAlertCommitment != nil else {
            StrongAlertWindowController.shared.close()
            WindowRegistry.shared.window(for: .strongAlert)?.close()
            return
        }
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
                    let meetingLinkChoices = InterfaceCopy.meetingLinkChoices(
                        flow.strongAlertMeetingLinkOptions
                    )
                    StrongAlertView(
                        title: commitment.title,
                        timing: flow.strongAlertTimingText(for: commitment, at: context.date),
                        detail: flow.strongAlertContextText(for: commitment),
                        verificationLabel: flow.isStrongAlertUnverified ? "Unverified Reminder" : nil,
                        statusMessage: meetingLinkFailure(for: commitment),
                        repeatConsequence: InterfaceCopy.strongAlertRepeatConsequence(
                            minutes: flow.strongAlertRepeatIntervalMinutes,
                            canJoin: !flow.strongAlertMeetingLinkOptions.isEmpty
                        ),
                        supportingContent: flow.strongAlertConflict.map { conflict in
                            AnyView(StrongAlertConflictSummaryView(flow: flow, conflict: conflict))
                        },
                        primaryActionHint: flow.strongAlertMeetingLinkOptions.isEmpty
                            ? "Stop reminders for this occurrence without changing Google Calendar."
                            : "Open a recognized meeting link and stop reminders for this occurrence.",
                        primaryActionTitle: flow.strongAlertPrimaryActionTitle,
                        primaryAction: {
                            if flow.strongAlertMeetingLinkOptions.isEmpty {
                                requestStopReminders(for: commitment)
                            } else if let primaryLink = flow.strongAlertPrimaryMeetingLink {
                                openMeetingLink(primaryLink, for: commitment)
                            } else if flow.strongAlertMeetingLinkOptions.count == 1,
                                      let link = flow.strongAlertMeetingLinkOptions.first {
                                openMeetingLink(link, for: commitment)
                            }
                        },
                        primaryActionChoices: flow.strongAlertPrimaryMeetingLink == nil &&
                            flow.strongAlertMeetingLinkOptions.count > 1
                            ? meetingLinkChoices.map { choice in
                                (choice.title, {
                                    openMeetingLink(choice.url, for: commitment)
                                })
                            }
                            : [],
                        secondaryActionTitle: flow.strongAlertMeetingLinkOptions.isEmpty ? nil : "Stop reminders",
                        secondaryAction: {
                            requestStopReminders(for: commitment)
                        },
                        tertiaryActionTitle: "Got it",
                        tertiaryAction: {
                            flow.closeStrongAlertSurface()
                            announceActionResult(flow.lastActionMessage)
                        },
                        pauseAction: { duration in
                            let didPause = flow.pause(for: duration)
                            if didPause {
                                announceActionResult(flow.lastActionMessage)
                            }
                            return didPause
                        }
                    )
                }
            } else {
                VStack(spacing: 20) {
                    Text("No commitment needs attention.")
                        .foregroundStyle(.secondary)
                }
                .padding(32)
            }
        }
        .accessibilityAddTraits(.isModal)
        .frame(minWidth: 360, minHeight: 300)
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

    private func openMeetingLink(_ link: URL, for commitment: CalendarEvent) {
        _ = flow.openStrongAlertMeetingLink(
            for: commitment,
            using: link,
            open: NSWorkspace.shared.open
        )
        announceActionResult(flow.lastActionMessage)
    }

    private func meetingLinkFailure(for commitment: CalendarEvent) -> String? {
        flow.meetingLinkOpenFailureMessage(for: commitment)
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
            ForEach(conflict.commitments, id: \.occurrenceID) { commitment in
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        conflictCommitmentIdentity(commitment)
                        Spacer(minLength: 8)
                        conflictCommitmentTime(commitment)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        conflictCommitmentIdentity(commitment)
                        conflictCommitmentTime(commitment)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func conflictCommitmentIdentity(_ commitment: CalendarEvent) -> some View {
        if let primaryCommitment = conflict.primaryCommitment,
           primaryCommitment.occurrenceID == commitment.occurrenceID {
            Label("Primary", systemImage: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
        Text(commitment.title)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func conflictCommitmentTime(_ commitment: CalendarEvent) -> some View {
        Text(flow.localStartTimeText(for: commitment))
            .font(.caption)
            .foregroundStyle(.secondary)
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
        ScrollView {
            VStack(spacing: 16) {
            Label("Strong Alert", systemImage: "bell.and.waves.left.and.right.fill")
                .font(.headline)
            if flow.isStrongAlertUnverified {
                Label("Unverified Reminder", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(InterfaceCopy.unverifiedReminderDetail())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Choose a commitment")
                .font(.title2.bold())
            Text("These commitments start at the same time. Choose which one to make primary, or act on either one.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(conflict.commitments, id: \.occurrenceID) { commitment in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(commitment.title)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(flow.strongAlertTimingText(for: commitment, at: date))
                                .font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(flow.strongAlertContextText(for: commitment))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) {
                                    conflictActions(for: commitment)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    conflictActions(for: commitment)
                                }
                            }
                            if let meetingLinkError = meetingLinkFailure(for: commitment) {
                                Label(meetingLinkError, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
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
            .buttonStyle(.bordered)
            .accessibilityHint("Close this Strong Alert. Protection remains active and it will repeat after the configured interval.")
                Text(InterfaceCopy.strongAlertRepeatConsequence(
                    minutes: flow.strongAlertRepeatIntervalMinutes,
                    canJoin: conflict.commitments.contains {
                        !flow.strongAlertMeetingLinkOptions(for: $0).isEmpty
                    }
            ))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let pauseAction = pauseAction {
                Menu("Pause All Protection") {
                    Button("Pause all for 1 hour") {
                        _ = pauseAction(.oneHour)
                    }
                    Button("Pause all until end of day") {
                        _ = pauseAction(.endOfDay)
                    }
                    Button("Choose when to resume all protection…") {
                        customPauseExpiration = Date().addingTimeInterval(60 * 60)
                        isCustomPausePresented = true
                    }
                }
                Text(InterfaceCopy.pauseAllProtectionDetail())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            }
            .padding(28)
        }
        .frame(minWidth: 360, idealWidth: 560, maxWidth: 620, maxHeight: 680)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .sheet(isPresented: $isCustomPausePresented) {
            if let pauseAction {
                CustomPauseSheet(
                    expiration: $customPauseExpiration,
                    pause: pauseAction
                )
            }
        }
    }

    @ViewBuilder
    private func conflictActions(for commitment: CalendarEvent) -> some View {
        let links = flow.strongAlertMeetingLinkOptions(for: commitment)
        let choices = InterfaceCopy.meetingLinkChoices(links)
        if links.isEmpty {
            Button("Stop reminders") {
                requestStopReminders(commitment)
            }
            .buttonStyle(.borderedProminent)
        } else if let primaryLink = flow.strongAlertPrimaryMeetingLink(for: commitment) {
            Button("Join") {
                openMeetingLink(primaryLink, for: commitment)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Menu("Choose link") {
                ForEach(choices, id: \.url.absoluteString) { choice in
                    Button(choice.title) {
                        openMeetingLink(choice.url, for: commitment)
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

        Button("Make primary") {
            if flow.selectPrimary(for: commitment) {
                announceActionResult(flow.lastActionMessage)
            }
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Use this commitment as the primary choice for this conflict.")
    }

    private var pauseAction: ((PauseDuration) -> Bool)? {
        { duration in
            let didPause = flow.pause(for: duration)
            if didPause {
                announceActionResult(flow.lastActionMessage)
            }
            return didPause
        }
    }

    private func openMeetingLink(_ link: URL, for commitment: CalendarEvent) {
        _ = flow.openStrongAlertMeetingLink(
            for: commitment,
            using: link,
            open: NSWorkspace.shared.open
        )
        announceActionResult(flow.lastActionMessage)
    }

    private func meetingLinkFailure(for commitment: CalendarEvent) -> String? {
        flow.meetingLinkOpenFailureMessage(for: commitment)
    }
}

struct EarlyReminderFallbackContent {
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
                Text(InterfaceCopy.unverifiedReminderDetail())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(content.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            Text(content.timing)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Close for now hides this Early Reminder. Strong Alert still appears when the commitment begins.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Menu("Snooze") {
                ForEach(content.snoozeOptionsMinutes, id: \.self) { minutes in
                    Button(InterfaceCopy.minuteDuration(minutes)) { snooze(minutes) }
                }
            }
            .disabled(!canSnooze)
            .accessibilityHint("Choose how long to delay this occurrence’s Early Reminder and Strong Alert.")
            Text("Snooze delays both reminders for this occurrence and can continue past its start time.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    fallbackActions
                }
                VStack(spacing: 8) {
                    fallbackActions
                }
            }
        }
        .padding(28)
        .frame(idealWidth: 500, maxWidth: 560, maxHeight: 680)
        .accessibilityAddTraits(.isModal)
        .stopRemindersConfirmation(
            isPresented: $isStopRemindersConfirmationPresented,
            onCancel: {},
            onConfirm: dismiss
        )
    }

    @ViewBuilder
    private var fallbackActions: some View {
        Button("Close for now", action: clear)
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Close this Early Reminder while keeping Strong Alert active at the commitment start.")
        Button("Stop reminders") {
            isStopRemindersConfirmationPresented = true
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Stop Early Reminder and Strong Alert for this occurrence without changing Google Calendar.")
    }
}

func objectIsOwned<Object: AnyObject>(
    _ candidate: Object?,
    by root: Object?,
    parent: (Object) -> Object?
) -> Bool {
    guard let root else { return false }
    var currentObject = candidate
    var visitedObjectIDs: Set<ObjectIdentifier> = []

    while let object = currentObject {
        guard visitedObjectIDs.insert(ObjectIdentifier(object)).inserted else {
            return false
        }
        if object === root {
            return true
        }
        currentObject = parent(object)
    }

    return false
}

@MainActor
func windowIsOwned(_ candidate: NSWindow?, by rootWindow: NSWindow?) -> Bool {
    objectIsOwned(candidate, by: rootWindow) { window in
        window.sheetParent ?? window.parent
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

    @MainActor
    func allows(_ event: NSEvent) -> Bool {
        lock.lock()
        let reminderWindow = self.reminderWindow
        lock.unlock()
        return windowIsOwned(event.window, by: reminderWindow)
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
            let systemModifierFlags: CGEventFlags = [
                .maskCommand,
                .maskAlternate,
                .maskControl
            ]
            let modifiers = event.flags.intersection(systemModifierFlags)
            let hasVoiceOverModifiers = modifiers.contains(.maskControl) && modifiers.contains(.maskAlternate)
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isAccessibilityShortcut = keyCode == Int64(kVK_F5) &&
                modifiers.contains(.maskCommand)
            if hasVoiceOverModifiers || isAccessibilityShortcut {
                return true
            }
            guard isApplicationActive else { return false }
            return modifiers.isEmpty
        default:
            return true
        }
    }
}

@MainActor
final class EarlyReminderWindowController: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = EarlyReminderWindowController()

    private struct PresentationRequest {
        let content: EarlyReminderFallbackContent
        let reopen: @MainActor () -> Void
        let clear: @MainActor () -> Void
        let canSnooze: Bool
        let snooze: (Int) -> Void
        let dismiss: () -> Void
    }

    private let windowRegistry: WindowRegistry
    private let scheduleAfterLayout: (@escaping @MainActor () -> Void) -> Void
    private let fitWindow: @MainActor (NSWindow?, NSScreen?) -> Void
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
    private var screenObserver: NSObjectProtocol?
    private var reopenSurface: (@MainActor () -> Void)?
    private var clearEarlyReminder: (@MainActor () -> Void)?
    private var snoozeEarlyReminder: ((Int) -> Void)?
    private var dismissCommitment: (() -> Void)?
    private var canSnoozeEarlyReminder = false
    private var fallbackContent: EarlyReminderFallbackContent?
    private var fallbackPanel: NSPanel?
    private var surfaceRecoveryAttempts = 0
    private var allowsWindowClose = false
    private var isPresented = false
    private var isInteractionBarrierActive = false
    private var fittingWindowIDs: Set<ObjectIdentifier> = []
    private var blockingMode = EarlyReminderBlockingMode()
    @Published private(set) var isGlobalInteractionBarrierAvailable = false
    private lazy var pendingPresentation = PendingWindowPresentation<PresentationRequest>(
        registry: windowRegistry,
        kind: .earlyReminder
    ) { [weak self] window, request in
        self?.present(request, in: window)
    }

    init(
        windowRegistry: WindowRegistry = .shared,
        scheduleAfterLayout: @escaping (@escaping @MainActor () -> Void) -> Void = { action in
            DispatchQueue.main.async { action() }
        },
        fitWindow: @escaping @MainActor (NSWindow?, NSScreen?) -> Void = { window, screen in
            WindowFrameFitter.fit(
                window,
                on: screen,
                minimumContentSize: NSSize(width: 360, height: 300)
            )
        }
    ) {
        self.windowRegistry = windowRegistry
        self.scheduleAfterLayout = scheduleAfterLayout
        self.fitWindow = fitWindow
        super.init()
    }

    func present(
        content: EarlyReminderFallbackContent,
        reopen: @escaping @MainActor () -> Void,
        clear: @escaping @MainActor () -> Void,
        canSnooze: Bool,
        snooze: @escaping (Int) -> Void,
        dismiss: @escaping () -> Void
    ) {
        pendingPresentation.submit(PresentationRequest(
            content: content,
            reopen: reopen,
            clear: clear,
            canSnooze: canSnooze,
            snooze: snooze,
            dismiss: dismiss
        ))
    }

    private func present(_ request: PresentationRequest, in registeredWindow: NSWindow) {
        reopenSurface = request.reopen
        clearEarlyReminder = request.clear
        canSnoozeEarlyReminder = request.canSnooze
        snoozeEarlyReminder = request.snooze
        dismissCommitment = request.dismiss
        fallbackContent = request.content

        if isPresented, window !== registeredWindow {
            stopBarrierRetryMonitoring()
            stopScreenObservation()
            deactivateInteractionBarrier()
            if let fallbackPanel {
                fallbackPanel.delegate = nil
                fallbackPanel.close()
                self.fallbackPanel = nil
            } else {
                window?.delegate = nil
            }
            window = nil
            isPresented = false
        }
        if isPresented {
            window?.orderFrontRegardless()
            return
        }

        stopSurfaceRecoveryMonitoring()
        window = registeredWindow
        registeredWindow.delegate = self
        registeredWindow.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        registeredWindow.hidesOnDeactivate = false
        registeredWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Keep the reminder visible through full-display, window, and app sharing.
        registeredWindow.sharingType = .readOnly
        registeredWindow.standardWindowButton(.closeButton)?.isEnabled = true
        registeredWindow.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        registeredWindow.standardWindowButton(.zoomButton)?.isEnabled = false
        registeredWindow.isMovable = false
        fitReminderWindow(
            registeredWindow,
            on: registeredWindow.screen
        )
        isPresented = true
        startScreenObservation()
        let barrierAvailable: Bool
        if blockingMode.shouldAttemptBlocking {
            startBarrierRetryMonitoring()
            barrierAvailable = attemptBlockingMode()
        } else {
            barrierAvailable = false
        }
        NSApp.activate(ignoringOtherApps: true)
        registeredWindow.makeKeyAndOrderFront(nil)
        if !barrierAvailable {
            registeredWindow.orderFrontRegardless()
        }
        refitRegisteredWindowAfterLayout(registeredWindow)
    }

    func stop() {
        stopBarrierRetryMonitoring()
        stopSurfaceRecoveryMonitoring()
        stopScreenObservation()
        guard isPresented else { return }
        deactivateInteractionBarrier()
        isPresented = false
        window?.standardWindowButton(.closeButton)?.isEnabled = true
    }

    func close() {
        pendingPresentation.clear()
        allowsWindowClose = true
        let window = self.window
        stop()
        window?.delegate = nil
        window?.close()
        fallbackPanel = nil
        self.window = nil
        self.fallbackContent = nil
        self.clearEarlyReminder = nil
        self.snoozeEarlyReminder = nil
        self.dismissCommitment = nil
        self.canSnoozeEarlyReminder = false
        allowsWindowClose = false
    }

    func prepareForProgrammaticClose() {
        allowsWindowClose = true
        window?.delegate = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !allowsWindowClose else { return true }
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
        preserveReminderFocus()
    }

    func windowDidResignMain(_ notification: Notification) {
        guard isPresented, isInteractionBarrierActive else { return }
        preserveReminderFocus()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard isPresented,
              let changedWindow = notification.object as? NSWindow,
              changedWindow === window else { return }
        fitReminderWindow(changedWindow, on: changedWindow.screen)
    }

    func windowDidResize(_ notification: Notification) {
        guard isPresented,
              let resizedWindow = notification.object as? NSWindow,
              resizedWindow === window else { return }
        fitReminderWindow(resizedWindow, on: resizedWindow.screen)
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
            startSurfaceRecoveryMonitoring()
            return
        }
        stopBarrierRetryMonitoring()
        stopScreenObservation()
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
              let clearEarlyReminder,
              let snoozeEarlyReminder,
              let dismissCommitment else { return }

        pendingPresentation.clear()
        let reopenSurface = self.reopenSurface
        stopSurfaceRecoveryMonitoring()
        self.reopenSurface = reopenSurface

        let hostingView = NSHostingView(
            rootView: EarlyReminderFallbackView(
                content: content,
                canSnooze: canSnoozeEarlyReminder,
                clear: clearEarlyReminder,
                snooze: snoozeEarlyReminder,
                dismiss: dismissCommitment
            )
        )
        hostingView.sizingOptions = [.intrinsicContentSize]
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
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
        panel.contentView = hostingView
        fitReminderWindow(
            panel,
            on: NSScreen.main
        )
        fallbackPanel = panel
        window = panel
        isPresented = true
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
                NSApplication.didBecomeActiveNotification,
                NSApplication.didResignActiveNotification
            ].map { notificationName in
                NotificationCenter.default.addObserver(
                    forName: notificationName,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
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
              let clearEarlyReminder,
              let snoozeEarlyReminder,
              let dismissCommitment else { return }
        let hostingView = NSHostingView(
            rootView: EarlyReminderFallbackView(
                content: content,
                canSnooze: canSnoozeEarlyReminder,
                clear: clearEarlyReminder,
                snooze: snoozeEarlyReminder,
                dismiss: dismissCommitment
            )
        )
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView
        fitReminderWindow(
            panel,
            on: panel.screen
        )
    }

    private func fitReminderWindow(_ window: NSWindow?, on screen: NSScreen?) {
        guard let window else { return }
        let windowID = ObjectIdentifier(window)
        guard fittingWindowIDs.insert(windowID).inserted else { return }
        defer { fittingWindowIDs.remove(windowID) }

        fitWindow(window, screen)
    }

    private func refitRegisteredWindowAfterLayout(_ registeredWindow: NSWindow) {
        scheduleAfterLayout { [weak self, weak registeredWindow] in
            guard let self,
                  let registeredWindow,
                  self.isPresented,
                  self.window === registeredWindow else { return }
            self.fitReminderWindow(
                registeredWindow,
                on: registeredWindow.screen
            )
        }
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
        guard blockingMode.shouldAttemptBlocking, barrierRetryTimer == nil else { return }
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
        guard isPresented, blockingMode.shouldAttemptBlocking else { return }
        if isInteractionBarrierActive {
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
              !windowIsOwned(candidate, by: reminderWindow),
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
            shield.setAccessibilityElement(false)
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

    private func startScreenObservation() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.screenParametersDidChange()
            }
        }
    }

    private func stopScreenObservation() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func screenParametersDidChange() {
        guard isPresented, let window else { return }
        fitReminderWindow(window, on: window.screen ?? NSScreen.main)
        if isInteractionBarrierActive {
            recreateShieldWindows()
        }
    }

    private func preserveReminderFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPresented else { return }
            if windowIsOwned(NSApp.keyWindow, by: self.window) {
                self.window?.orderFrontRegardless()
            } else {
                self.bringReminderToFront()
            }
        }
    }

    private func bringReminderToFront() {
        guard isPresented else { return }
        let keyWindow = NSApp.keyWindow
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
        guard !windowIsOwned(keyWindow, by: window) else { return }
        window?.makeKey()
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
            Text(InterfaceCopy.stopRemindersConfirmationMessage())
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

private struct StrongAlertContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 280

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct StrongAlertView: View {
    let title: String
    let timing: String
    let detail: String
    var verificationLabel: String? = nil
    var statusMessage: String? = nil
    var repeatConsequence: String? = nil
    var supportingContent: AnyView? = nil
    var primaryActionHint: String = "Take the primary action for this commitment."
    let primaryActionTitle: String
    let primaryAction: () -> Void
    var primaryActionChoices: [(String, () -> Void)] = []
    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var tertiaryActionTitle: String? = nil
    var tertiaryAction: (() -> Void)? = nil
    var pauseAction: ((PauseDuration) -> Bool)? = nil
    @State private var customPauseExpiration = Date().addingTimeInterval(60 * 60)
    @State private var isCustomPausePresented = false
    @State private var measuredContentHeight: CGFloat = 280

    var body: some View {
        ScrollView {
            alertContent
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: StrongAlertContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
        }
        .frame(minWidth: 360, idealWidth: 500, maxWidth: 620)
        .frame(height: min(measuredContentHeight, 680))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .onPreferenceChange(StrongAlertContentHeightKey.self) { height in
            measuredContentHeight = max(240, height)
        }
        .sheet(isPresented: $isCustomPausePresented) {
            if let pauseAction {
                CustomPauseSheet(
                    expiration: $customPauseExpiration,
                    pause: pauseAction
                )
            }
        }
    }

    private var alertContent: some View {
        VStack(spacing: 24) {
            Label("Strong Alert", systemImage: "bell.and.waves.left.and.right.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            if let verificationLabel {
                VStack(spacing: 6) {
                    Label(verificationLabel, systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(InterfaceCopy.unverifiedReminderDetail())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 10) {
                Text(title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                Text(timing)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let statusMessage {
                Label(statusMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isStaticText)
            }

            if let supportingContent {
                supportingContent
            }

            VStack(spacing: 12) {
                primaryActionControl

                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .buttonStyle(.bordered)
                        .accessibilityLabel(secondaryActionTitle)
                        .accessibilityHint("Stop Early Reminder and Strong Alert for this commitment occurrence without changing Google Calendar.")
                }

                if let tertiaryActionTitle, let tertiaryAction {
                    VStack(spacing: 6) {
                        Button(tertiaryActionTitle, action: tertiaryAction)
                            .buttonStyle(.bordered)
                            .accessibilityLabel(tertiaryActionTitle)
                            .accessibilityHint("Close this Strong Alert. Protection remains active and it will repeat after the configured interval.")
                        Text(repeatConsequence ?? "Closes this alert now. Protection stays active and Strong Alert returns at the configured interval.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let pauseAction {
                VStack(spacing: 6) {
                    Divider()
                        .padding(.bottom, 6)
                    Menu("Pause All Protection") {
                        Button("Pause all for 1 hour") {
                            _ = pauseAction(.oneHour)
                        }
                        Button("Pause all until end of day") {
                            _ = pauseAction(.endOfDay)
                        }
                        Button("Choose when to resume all protection…") {
                            customPauseExpiration = Date().addingTimeInterval(60 * 60)
                            isCustomPausePresented = true
                        }
                    }
                    Text(InterfaceCopy.pauseAllProtectionDetail())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
    }

    @ViewBuilder
    private var primaryActionControl: some View {
        if primaryActionChoices.isEmpty {
            Button(primaryActionTitle, action: primaryAction)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(primaryActionTitle)
                .accessibilityHint(primaryActionHint)
        } else {
            Menu(primaryActionTitle) {
                ForEach(Array(primaryActionChoices.enumerated()), id: \.offset) { _, choice in
                    Button(choice.0, action: choice.1)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(primaryActionTitle)
            .accessibilityHint(primaryActionHint)
        }
    }
}

private struct CustomPauseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var expiration: Date
    let pause: (PauseDuration) -> Bool
    @State private var validationMessage: String?
    @AccessibilityFocusState private var isValidationFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pause All Protection")
                .font(.headline)
            Text(InterfaceCopy.pauseAllProtectionDetail())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker(
                "Pause until",
                selection: $expiration,
                in: Date()...
            )
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($isValidationFocused)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { customPauseActions }
                VStack(alignment: .leading, spacing: 8) { customPauseActions }
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }

    @ViewBuilder
    private var customPauseActions: some View {
        Button("Cancel", role: .cancel) {
            dismiss()
        }
        Button("Pause All Protection") {
            if pause(.custom(expiration)) {
                validationMessage = nil
                dismiss()
            } else {
                let message = "Choose a future date and time, then try again."
                validationMessage = message
                isValidationFocused = true
                announceActionResult(message)
            }
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
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
                ForEach(conflict.commitments, id: \.occurrenceID) { commitment in
                    Button("Make primary: \(commitment.title)") {
                        if flow.selectPrimary(for: commitment) {
                            announceActionResult(flow.lastActionMessage)
                        }
                    }
                }
            } else {
                Text("Also in this conflict")
                    .font(.caption.weight(.semibold))
                ForEach(conflict.commitments.filter {
                    $0.occurrenceID != conflict.primaryCommitment?.occurrenceID
                }, id: \.occurrenceID) { commitment in
                    Label(commitment.title, systemImage: "calendar")
                        .font(.caption)
                        .lineLimit(2)
                        .help(commitment.title)
                }
                Text("The primary commitment appears in the menu bar; every commitment remains protected.")
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
    @EnvironmentObject private var onboardingState: OnboardingState
    @Environment(\.openWindow) private var openWindow
    @State private var customPauseExpiration = Date().addingTimeInterval(60 * 60)

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        scrollableContent(at: context.date)
                    }
                    .padding(16)
                }
                .frame(maxHeight: maximumScrollableHeight)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    if onboardingState.needsSetup {
                        Button("Finish Setup…") {
                            onboardingState.resume()
                            OnboardingWindowController.shared.show {
                                openWindow(id: "onboarding")
                            }
                        }
                        .keyboardShortcut("o")
                    }

                    SettingsLink {
                        Text("Settings…")
                    }
                    .keyboardShortcut(",")

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
        .onAppear {
            flow.refreshLaunchAtLoginStatus()
            if customPauseExpiration <= Date() {
                customPauseExpiration = Date().addingTimeInterval(60 * 60)
            }
        }
    }

    @ViewBuilder
    private func scrollableContent(at date: Date) -> some View {
        if let commitment = flow.upcomingCommitment {
            VStack(alignment: .leading, spacing: 4) {
                Text(commitment.title)
                    .font(.headline)
                    .lineLimit(2)
                    .help(commitment.title)
                Text(flow.countdownText(for: commitment, at: date))
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

        if flow.isPaused(at: date) {
            VStack(alignment: .leading, spacing: 6) {
                Label("All Protection Paused", systemImage: "pause.circle.fill")
                    .font(.headline)
                Text(flow.pauseExpirationText(at: date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Divider()
        } else if flow.status == .active {
            VStack(alignment: .leading, spacing: 8) {
                Label("Pause All Protection", systemImage: "pause.circle")
                    .font(.headline)
                Text(InterfaceCopy.pauseAllProtectionDetail())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Pause all for 1 hour") {
                    pause(.oneHour)
                }
                .keyboardShortcut("1")
                Button("Pause all until end of day") {
                    pause(.endOfDay)
                }
                .keyboardShortcut("e")
                DatePicker(
                    "Resume all protection",
                    selection: $customPauseExpiration,
                    in: date...
                )
                .datePickerStyle(.field)
                Button("Pause all until selected time") {
                    pause(.custom(customPauseExpiration))
                }
                .disabled(customPauseExpiration <= date)
                .keyboardShortcut("c")
                .accessibilityHint("Pause reminders for every Monitored Calendar until the selected local date and time.")
            }

            Divider()
        }

        if let decisionCommitment = flow.decisionCommitment,
           let decision = flow.currentCommitmentDecision,
           decision.isRestorable {
            VStack(alignment: .leading, spacing: 6) {
                Label(decisionTitle(decision), systemImage: "pause.circle")
                    .font(.headline)
                Text(decisionCommitment.title)
                    .lineLimit(2)
                    .help(decisionCommitment.title)
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

        Label(flow.menuBarTitle, systemImage: menuBarStatusIcon)
            .font(.headline)

        ForEach(flow.accountCoverages) { coverage in
            let health = flow.coverage(for: coverage.account.id) ?? coverage.health
            VStack(alignment: .leading, spacing: 4) {
                Text(InterfaceCopy.connectedAccountLabel(
                    email: coverage.account.email,
                    displayName: coverage.account.displayName
                ))
                    .font(.caption.weight(.semibold))
                Text(health.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let warning = flow.coverageWarning(for: coverage.account.id) {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if coverage.connectionState == .reconnectRequired {
                    Button("Reconnect Google Calendar…") {
                        Task {
                            await flow.reconnectGoogleAccount(accountID: coverage.account.id)
                        }
                    }
                    .disabled(flow.isConnectingAccount)
                }
            }

            if coverage.id != flow.accountCoverages.last?.id {
                Divider()
            }
        }
    }

    private var maximumScrollableHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 800
        return max(180, min(520, visibleHeight - 220))
    }

    private func pause(_ duration: PauseDuration) {
        if flow.pause(for: duration) {
            announceActionResult(flow.lastActionMessage)
        }
    }

    private func decisionTitle(_ decision: CommitmentProtectionDecision) -> String {
        switch decision {
        case .dismissed:
            return "Reminders stopped"
        case .joined:
            return "Meeting link opened"
        case .handled:
            return "Commitment handled"
        }
    }

    private var menuBarStatusIcon: String {
        if flow.isRestoringConnection {
            return "arrow.triangle.2.circlepath"
        }
        if flow.isPaused() {
            return "pause.circle.fill"
        }
        switch flow.status {
        case .active:
            return "checkmark.shield"
        case .noCoverage:
            return "shield.slash"
        case .unavailable:
            return flow.isCheckingCoverage
                ? "arrow.triangle.2.circlepath"
                : "exclamationmark.triangle"
        }
    }
}

private struct MenuBarLabel: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @EnvironmentObject private var onboardingState: OnboardingState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(
            flow.menuBarTitle,
            systemImage: menuBarStatusIcon
        )
        .onAppear {
            presentInitialOnboardingIfNeeded()
            if flow.earlyReminderCommitment != nil {
                openEarlyReminderIfNeeded(flow: flow) {
                    openWindow(id: "early-reminder")
                }
            }
            if flow.isStrongAlertPresented {
                openWindow(id: "strong-alert")
            }
        }
        .onChange(of: onboardingState.initialSurface) { _, _ in
            presentInitialOnboardingIfNeeded()
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

    private func presentInitialOnboardingIfNeeded() {
        guard onboardingState.initialSurface == .onboarding else { return }
        OnboardingWindowController.shared.showAtLaunch {
            openWindow(id: "onboarding")
        }
    }

    private var menuBarStatusIcon: String {
        if flow.isRestoringConnection {
            return "arrow.triangle.2.circlepath"
        }
        if flow.isPaused() {
            return "pause.circle.fill"
        }
        switch flow.status {
        case .active:
            return "checkmark.circle.fill"
        case .noCoverage:
            return "shield.slash"
        case .unavailable:
            return flow.isCheckingCoverage
                ? "arrow.triangle.2.circlepath"
                : "calendar.badge.exclamationmark"
        }
    }
}
