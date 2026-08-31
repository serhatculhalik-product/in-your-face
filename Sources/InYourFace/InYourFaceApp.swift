import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CommitmentProtection
import CoreGraphics
import SwiftUI

@main
@MainActor
struct InYourFaceApp: App {
    @NSApplicationDelegateAdaptor(InYourFaceApplicationDelegate.self)
    private var applicationDelegate
    @ObservedObject private var productionFlow: CommitmentProtectionFlow
    private let productionBlockingPermissions: BlockingPermissionController
    private let runtimeProfile: RuntimeProfile
    private let runtimeStateStore: UserDefaults
    private let resetRecoveryDisablesWindowRestoration: Bool
    private let windowQuarantineObservation: AnyCancellable
    @StateObject private var flow: CommitmentProtectionFlow
    @StateObject private var availabilityMonitor: AppAvailabilityMonitor
    @StateObject private var onboardingState: OnboardingState
    @StateObject private var blockingPermissions: BlockingPermissionController
    @StateObject private var testToolsController: TestToolsController
    @StateObject private var resetCoordinator: AppManagedDataResetCoordinator
#if INTERNAL_BUILD
    @StateObject private var internalResetCoordinator: AppManagedDataResetCoordinator
#endif

    init() {
        let bootstrap = RuntimeBootstrap.load()
        let oauthConfiguration = GoogleOAuthConfigurationResolver.resolve(
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            environment: ProcessInfo.processInfo.environment
        )
        let hasHelperResetRecovery = bootstrap.appDataResetRecoveryAvailable ||
            bootstrap.internalResetRecoveryAvailable ||
            bootstrap.resetRecoveryRequiresManualRepair
        let hasJournalResetRecovery = bootstrap.appDataResetJournalRequiresResume ||
            bootstrap.internalResetJournalRequiresResume
        let hasAnyResetRecovery = hasHelperResetRecovery || hasJournalResetRecovery
        let productionComposition = RuntimeProtectionFactory.make(
            profile: .production(
                vaultApplicationIdentifier: bootstrap.namespace
            ),
            stateStore: .standard,
            oauthConfiguration: oauthConfiguration,
            startupMode: bootstrap.protectionStartupMode
        )
        let activeComposition: RuntimeProtectionComposition
        if RuntimeProtectionCompositionPolicy.usesIsolatedTestComposition(
            profile: bootstrap.profile,
            hasResetRecovery: hasAnyResetRecovery
        ) {
            activeComposition = RuntimeProtectionFactory.make(
                profile: bootstrap.profile,
                stateStore: bootstrap.stateStore,
                oauthConfiguration: oauthConfiguration,
                startupMode: bootstrap.protectionStartupMode
            )
        } else {
            activeComposition = productionComposition
        }
        let monitor = AppAvailabilityMonitor(flow: productionComposition.flow)
        let onboarding = OnboardingState(
            stateStore: bootstrap.stateStore,
            allowsPreferenceMutation: {
                !productionComposition.flow.isAppManagedDataResetInProgress
            }
        )
        let testTools = TestToolsController(
            profile: bootstrap.profile,
            router: bootstrap.router,
            productionFlow: productionComposition.flow,
            recoveryReport: bootstrap.recoveryReport,
            appDataResetRecoveryAvailable: bootstrap.appDataResetRecoveryAvailable,
            internalResetRecoveryAvailable: bootstrap.internalResetRecoveryAvailable,
            resetRecoveryRequiresManualRepair: bootstrap.resetRecoveryRequiresManualRepair,
            isCleanupRecovery: bootstrap.isCleanupRecovery,
            productionReady: false
        )
        let resetRelauncher = EmbeddedApplicationRelauncher(
            helperExecutableName: "MeetingIncomingAppDataResetHelper"
        )
        let resetJournalURL = bootstrap.applicationSupportDirectory
            .appendingPathComponent("\(bootstrap.namespace).reset-control", isDirectory: true)
            .appendingPathComponent("app-managed-data-reset.v1.json", isDirectory: false)
        let resetJournal = ResetJournal(fileURL: resetJournalURL)
        let reset = AppManagedDataResetCoordinator(
            journal: resetJournal,
            flow: productionComposition.flow,
            unregisterLaunchAtLogin: {
                let launchAtLogin = SystemLaunchAtLoginController()
                if launchAtLogin.isEnabled {
                    try launchAtLogin.disable()
                }
            },
            stageRelaunch: {
                try resetRelauncher.stageRelaunch()
                if bootstrap.profile.isTest {
                    _ = try bootstrap.router.requestExitTest()
                }
            },
            commitStagedRelaunch: {
                resetRelauncher.commitStagedRelaunch()
            },
            cancelStagedRelaunch: {
                resetRelauncher.cancelStagedRelaunch()
            }
        )
        testTools.installEraseAppManagedDataAction {
            try resetRelauncher.validate()
            _ = try await reset.begin()
        }

#if INTERNAL_BUILD
        let internalRelauncher = EmbeddedApplicationRelauncher(
            helperExecutableName: "MeetingIncomingInternalResetHelper"
        )
        let internalResetJournalURL = bootstrap.applicationSupportDirectory
            .appendingPathComponent("\(bootstrap.namespace).reset-control", isDirectory: true)
            .appendingPathComponent("internal-full-first-run.v1.json", isDirectory: false)
        let internalResetJournal = ResetJournal(fileURL: internalResetJournalURL)
        let internalReset = AppManagedDataResetCoordinator(
            journal: internalResetJournal,
            flow: productionComposition.flow,
            unregisterLaunchAtLogin: {
                let launchAtLogin = SystemLaunchAtLoginController()
                if launchAtLogin.isEnabled {
                    try launchAtLogin.disable()
                }
            },
            stageRelaunch: {
                try internalRelauncher.stageRelaunch()
                if bootstrap.profile.isTest {
                    _ = try bootstrap.router.requestExitTest()
                }
            },
            commitStagedRelaunch: {
                internalRelauncher.commitStagedRelaunch()
            },
            cancelStagedRelaunch: {
                internalRelauncher.cancelStagedRelaunch()
            }
        )
        testTools.installFullFirstRunInternalAction {
            try internalRelauncher.validate()
            _ = try await internalReset.begin()
        }
        testTools.installResetBusyCheck {
            reset.state.blocksRuntimeChanges || internalReset.state.blocksRuntimeChanges
        }
        testTools.installResetRetryableCheck {
            reset.state.allowsExplicitRetry
        }
        testTools.installInternalResetRetryableCheck {
            internalReset.state.allowsExplicitRetry
        }
#else
        testTools.installResetBusyCheck {
            reset.state.blocksRuntimeChanges
        }
        testTools.installResetRetryableCheck {
            reset.state.allowsExplicitRetry
        }
#endif

        _productionFlow = ObservedObject(wrappedValue: productionComposition.flow)
        productionBlockingPermissions = productionComposition.blockingPermissions
        runtimeProfile = bootstrap.profile
        runtimeStateStore = bootstrap.stateStore
        resetRecoveryDisablesWindowRestoration = hasAnyResetRecovery
        RuntimeWindowQuarantine.update(
            isActive: hasAnyResetRecovery ||
                productionComposition.flow.isAppManagedDataResetInProgress
        )
        windowQuarantineObservation = productionComposition.flow
            .$isAppManagedDataResetInProgress
            .removeDuplicates()
            .sink { isResetInProgress in
                MainActor.assumeIsolated {
                    RuntimeWindowQuarantine.update(
                        isActive: hasAnyResetRecovery || isResetInProgress
                    )
                }
            }
        _flow = StateObject(wrappedValue: activeComposition.flow)
        _availabilityMonitor = StateObject(wrappedValue: monitor)
        _onboardingState = StateObject(wrappedValue: onboarding)
        _blockingPermissions = StateObject(
            wrappedValue: activeComposition.blockingPermissions
        )
        _testToolsController = StateObject(wrappedValue: testTools)
        _resetCoordinator = StateObject(wrappedValue: reset)
#if INTERNAL_BUILD
        _internalResetCoordinator = StateObject(wrappedValue: internalReset)
#endif
        testTools.start()
        Task {
            if hasHelperResetRecovery {
                testTools.productionDidFinishInitialRestore()
                NotificationCenter.default.post(name: .showTestTools, object: nil)
                return
            }
            if hasJournalResetRecovery {
#if INTERNAL_BUILD
                if bootstrap.internalResetJournalRequiresResume {
                    _ = try? await internalReset.resume()
                    switch internalReset.state {
                    case .completed:
                        break
                    default:
                        NotificationCenter.default.post(name: .showTestTools, object: nil)
                    }
                } else {
                    _ = try? await reset.resume()
                    switch reset.state {
                    case .completed:
                        break
                    default:
                        NotificationCenter.default.post(name: .showTestTools, object: nil)
                    }
                }
#else
                _ = try? await reset.resume()
                switch reset.state {
                case .completed:
                    break
                default:
                    NotificationCenter.default.post(name: .showTestTools, object: nil)
                }
#endif
                testTools.productionDidFinishInitialRestore()
                return
            }
            await productionComposition.flow.restoreSavedConnection()
            if activeComposition.flow !== productionComposition.flow {
                await activeComposition.flow.restoreSavedConnection()
            }
#if INTERNAL_BUILD
            do {
                let internalResolution = try await internalResetJournal.resumeResolution()
                switch internalResolution {
                case .run, .reconcile, .retry, .readyToFinish:
                    _ = try? await internalReset.resume()
                case .noJournal, .finished:
                    _ = try? await reset.resume()
                }
            } catch {
                // Preserve a visible, locked recovery state instead of treating
                // an unreadable internal journal as if it did not exist.
                _ = try? await internalReset.resume()
            }
            switch internalReset.state {
            case .blocked, .unavailable:
                NotificationCenter.default.post(name: .showTestTools, object: nil)
            default:
                break
            }
#else
            _ = try? await reset.resume()
#endif
            testTools.productionDidFinishInitialRestore()
            onboarding.resolveInitialLaunch(
                hasConfiguredProtection: activeComposition.flow.accountCoverages.contains { coverage in
                    !coverage.selectedCalendarIDs.isEmpty && coverage.isProtectionConfirmed
                }
            )
            productionComposition.flow.startMonitoring()
            if activeComposition.flow !== productionComposition.flow {
                activeComposition.flow.startMonitoring()
            }
            monitor.start()
        }
    }

    private var applicationWindowStatePolicy: RuntimeWindowStatePolicy {
        .applicationWindow(
            isTestProfile: runtimeProfile.isTest,
            isResetQuarantined: isApplicationWindowResetQuarantined
        )
    }

    private var isApplicationWindowResetQuarantined: Bool {
        resetRecoveryDisablesWindowRestoration ||
            productionFlow.isAppManagedDataResetInProgress
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(flow)
                .environmentObject(onboardingState)
                .environmentObject(testToolsController)
                .environmentObject(resetCoordinator)
                .defaultAppStorage(runtimeStateStore)
                .runtimeModeSurface(testToolsController)
        } label: {
            MenuBarLabel(productionFlow: productionFlow)
                .environmentObject(flow)
                .environmentObject(onboardingState)
                .environmentObject(testToolsController)
                .environmentObject(resetCoordinator)
        }
        .menuBarExtraStyle(.window)

        Window(AppIdentity.onboardingWindowTitle, id: "onboarding") {
            OnboardingView()
                .environmentObject(flow)
                .environmentObject(onboardingState)
                .environmentObject(blockingPermissions)
                .environmentObject(testToolsController)
                .registerWindow(.onboarding)
                .defaultAppStorage(runtimeStateStore)
                .runtimeWindowState(applicationWindowStatePolicy)
                .runtimeModeSurface(testToolsController)
        }
        .defaultSize(width: 616, height: 640)
        .windowResizability(.contentSize)

        Settings {
            SettingsRootView()
                .environmentObject(flow)
                .environmentObject(onboardingState)
                .environmentObject(blockingPermissions)
                .environmentObject(testToolsController)
                .registerWindow(.settings)
                .defaultAppStorage(runtimeStateStore)
                .runtimeWindowState(applicationWindowStatePolicy)
                .runtimeModeSurface(testToolsController)
        }

        Window("Early Reminder", id: "early-reminder") {
            PriorityEarlyReminderView(
                activeFlow: flow,
                productionFlow: productionFlow,
                blockingPermissions: blockingPermissions,
                productionBlockingPermissions: productionBlockingPermissions,
                testToolsController: testToolsController
            )
                .registerWindow(.earlyReminder)
                .runtimeWindowState(applicationWindowStatePolicy)
        }
        .windowResizability(.contentSize)

        Window("Strong Alert", id: "strong-alert") {
            PriorityStrongAlertView(
                activeFlow: flow,
                productionFlow: productionFlow,
                testToolsController: testToolsController
            )
                .registerWindow(.strongAlert)
                .runtimeWindowState(applicationWindowStatePolicy)
                .fixedSize(horizontal: true, vertical: true)
        }
        .windowStyle(.hiddenTitleBar)
        // SwiftUI owns the primary window's size. StrongAlertWindowController sizes only
        // the AppKit replicas it creates for additional displays.
        .windowResizability(.contentSize)

        Window("Test Tools", id: "test-tools") {
            Group {
#if INTERNAL_BUILD
                TestToolsView(internalResetCoordinator: internalResetCoordinator)
#else
                TestToolsView()
#endif
            }
                .environmentObject(testToolsController)
                .environmentObject(resetCoordinator)
                .registerWindow(.testTools)
                .runtimeWindowState(.testTools)
        }
        .defaultSize(width: 560, height: 560)
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

enum GoogleOAuthConfigurationResolver {
    static func resolve(
        infoDictionary: [String: Any],
        environment: [String: String]
    ) -> GoogleCalendarOAuthConfiguration {
        let clientID = nonBlankString(infoDictionary["GoogleOAuthClientID"])
            ?? nonBlankString(environment["GOOGLE_OAUTH_CLIENT_ID"])
            ?? ""
        let clientSecret = nonBlankString(infoDictionary["GoogleOAuthClientSecret"])
            ?? nonBlankString(environment["GOOGLE_OAUTH_CLIENT_SECRET"])
        return GoogleCalendarOAuthConfiguration(
            clientID: clientID,
            clientSecret: clientSecret
        )
    }

    private static func nonBlankString(_ value: Any?) -> String? {
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return string
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

private struct PriorityEarlyReminderView: View {
    @ObservedObject var activeFlow: CommitmentProtectionFlow
    @ObservedObject var productionFlow: CommitmentProtectionFlow
    @ObservedObject var blockingPermissions: BlockingPermissionController
    @ObservedObject var productionBlockingPermissions: BlockingPermissionController
    @ObservedObject var testToolsController: TestToolsController

    private var presentedFlow: CommitmentProtectionFlow {
        if productionHasPriorityAlert {
            return productionFlow
        }
        return activeFlow
    }

    private var productionHasPriorityAlert: Bool {
        productionFlow.earlyReminderCommitment != nil ||
            productionFlow.isStrongAlertPresented ||
            productionFlow.strongAlertCommitment != nil
    }

    private var isRealProtection: Bool {
        activeFlow !== productionFlow && productionFlow.earlyReminderCommitment != nil
    }

    private var runtimeModeBadgeTitle: String? {
        guard testToolsController.isTestMode else { return nil }
        return isRealProtection ? "REAL PROTECTION" : "TEST MODE"
    }

    var body: some View {
        EarlyReminderView(runtimeModeBadgeTitle: runtimeModeBadgeTitle)
            .id(ObjectIdentifier(presentedFlow))
            .environmentObject(presentedFlow)
            .environmentObject(
                isRealProtection
                    ? productionBlockingPermissions
                    : blockingPermissions
            )
            .runtimeModeSurface(
                testToolsController,
                isRealProtection: isRealProtection
            )
    }
}

private struct PriorityStrongAlertView: View {
    @ObservedObject var activeFlow: CommitmentProtectionFlow
    @ObservedObject var productionFlow: CommitmentProtectionFlow
    @ObservedObject var testToolsController: TestToolsController

    private var presentedFlow: CommitmentProtectionFlow {
        if productionHasPriorityAlert {
            return productionFlow
        }
        return activeFlow
    }

    private var productionHasPriorityAlert: Bool {
        productionFlow.earlyReminderCommitment != nil ||
            productionFlow.isStrongAlertPresented ||
            productionFlow.strongAlertCommitment != nil
    }

    private var isRealProtection: Bool {
        activeFlow !== productionFlow &&
            (productionFlow.isStrongAlertPresented || productionFlow.strongAlertCommitment != nil)
    }

    private var runtimeModeBadgeTitle: String? {
        guard testToolsController.isTestMode else { return nil }
        return isRealProtection ? "REAL PROTECTION" : "TEST MODE"
    }

    var body: some View {
        StrongAlertWindowView(runtimeModeBadgeTitle: runtimeModeBadgeTitle)
            .id(ObjectIdentifier(presentedFlow))
            .environmentObject(presentedFlow)
            .runtimeModeSurface(
                testToolsController,
                isRealProtection: isRealProtection
            )
    }
}

struct CoverageHealthView: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    let coverage: AccountCoverage
    let warning: String?
    var showsProgress = true

    var body: some View {
        let health = flow.coverage(for: coverage.account.id) ?? coverage.health
        let presentation = ProtectionCoveragePresentation.account(
            health,
            requiresReconnect: coverage.connectionState == .reconnectRequired
        )
        let displayedWarning = presentation.state == .reconnectRequired
            ? reconnectCoverageWarning(accountLabel: accountLabel(for: coverage))
            : warning
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ProtectionCoverageStatusLabel(presentation: presentation)
                    .font(.callout.weight(.semibold))

                if showsProgress && presentation.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }

            if let displayedWarning {
                Text(displayedWarning)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func accountLabel(for coverage: AccountCoverage) -> String {
        InterfaceCopy.connectedAccountLabel(
            email: coverage.account.email,
            displayName: coverage.account.displayName
        )
    }
}

private func reconnectCoverageWarning(accountLabel: String) -> String {
    "Reconnect \(accountLabel) to resume calendar protection. Routine relaunches stay connected; Google authorization or encrypted device data needs attention."
}

struct ProtectionActivityCard: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @State private var selectedFilterID: CalendarFilter.ID?
    @State private var filterSearchText = ""
    var isCard = true

    private typealias CalendarFilter = ProtectionActivityProvenancePresentation.Scope

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

        VStack(alignment: .leading, spacing: 12) {
            Label("Protection Activity", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            Text("See today’s reminder actions and protection changes. Activity resets at the end of your local day.")
                .foregroundStyle(.secondary)

            activityScopeControl(filters: filters)

            if activities.isEmpty {
                ContentUnavailableView {
                    Label(emptyStateText, systemImage: "clock.badge.questionmark")
                } description: {
                    Text("Reminder actions and protection changes from the current local day will appear here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(activities) { activity in
                        ActivityRow(activity: activity)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 180, maxHeight: .infinity)
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
                        Text(filter.label)
                            .help(filter.help)
                            .accessibilityLabel(filter.accessibilityDescription)
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
                    Text(filter.label)
                        .help(filter.help)
                        .accessibilityLabel(filter.accessibilityDescription)
                        .tag(Optional(filter.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var calendarFilters: [CalendarFilter] {
        var sources: [ProvenancePresentation.SourceID: ProtectionProvenanceSource] = [:]
        for coverage in flow.accountCoverages {
            let selectedCalendarIDs = flow.selectedCalendarIDs(for: coverage.account.id)
            for calendar in coverage.calendars where selectedCalendarIDs.contains(calendar.id) {
                let source = ProtectionProvenanceSource(
                    accountID: coverage.account.id,
                    accountEmail: coverage.account.email,
                    accountDisplayName: coverage.account.displayName,
                    calendarID: calendar.id,
                    calendarName: calendar.name
                )
                sources[
                    ProvenancePresentation.SourceID(
                        accountID: coverage.account.id,
                        calendarID: calendar.id
                    )
                ] = source
            }
        }

        return ProtectionActivityProvenancePresentation.scopes(
            sources: Array(sources.values)
        )
    }

    private func matchingFilters(in filters: [CalendarFilter]) -> [CalendarFilter] {
        ProtectionActivityProvenancePresentation.matchingScopes(
            filters,
            query: filterSearchText
        )
    }

    private func visibleActivities(for filters: [CalendarFilter]) -> [ProtectionActivity] {
        guard let selectedFilterID,
              let selectedFilter = filters.first(where: { $0.id == selectedFilterID }),
              let calendarID = selectedFilter.calendarID else {
            return flow.activityLog
        }
        return flow.activities(
            forCalendarID: calendarID,
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

                    ForEach(provenance.standardGroups) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            if let calendarsText = group.calendarsText {
                                Text(calendarsText)
                            }
                            Text(group.accountText)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(group.help)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(group.accessibilityDescription)
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
            if !provenance.accessibilityDescription.isEmpty {
                parts.append(provenance.accessibilityDescription)
            }
            return parts.joined(separator: ", ")
        }

        private var provenance: ProtectionActivityProvenancePresentation.Row {
            ProtectionActivityProvenancePresentation.row(
                sources: activity.resolvedProvenanceSources
            )
        }

        private var timeText: String {
            ProtectionActivityCard.timeFormatter.string(from: activity.occurredAt)
        }
    }
}

private struct EarlyReminderView: View {
    let runtimeModeBadgeTitle: String?
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @EnvironmentObject private var blockingPermissions: BlockingPermissionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var windowController = EarlyReminderWindowController.shared

    var body: some View {
        EarlyReminderContentView(
            flow: flow,
            variant: .normal,
            closingActionCompleted: handleClosingAction
        )
        .onAppear {
            windowController.setRuntimeModeBadgeTitle(runtimeModeBadgeTitle)
            if blockingPermissions.isSimulated {
                flow.setBlockingAvailability(
                    blockingPermissions.hasAccessibilityPermission &&
                        blockingPermissions.hasInputMonitoringPermission
                )
            } else {
                flow.setBlockingAvailability(false)
            }
            windowController.setBlockingModeEnabled(
                flow.isBlockingModeEnabled && !blockingPermissions.isSimulated
            )
            guard flow.earlyReminderCommitment != nil else {
                flow.setBlockingAvailability(true)
                EarlyReminderWindowController.shared.prepareForProgrammaticClose()
                dismiss()
                EarlyReminderWindowController.shared.close()
                return
            }
            EarlyReminderWindowController.shared.present(
                flow: flow,
                content: replicaContent,
                reopen: {
                    openEarlyReminderIfNeeded(flow: flow) {
                        openWindow(id: "early-reminder")
                    }
                },
                closingActionCompleted: { didApply in
                    closeAfterAction(reopenIfNeeded: !didApply)
                }
            )
        }
        .onDisappear {
            if flow.earlyReminderCommitment == nil {
                flow.setBlockingAvailability(true)
                EarlyReminderWindowController.shared.close()
            } else {
                EarlyReminderWindowController.shared.surfaceDidDisappear(
                    flow: flow,
                    reopen: {
                        openEarlyReminderIfNeeded(flow: flow) {
                            openWindow(id: "early-reminder")
                        }
                    },
                    closingActionCompleted: { didApply in
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
            if !blockingPermissions.isSimulated {
                flow.setBlockingAvailability(isAvailable)
            }
        }
    }

    private var replicaContent: AnyView {
        AnyView(
            EarlyReminderContentView(
                flow: flow,
                variant: .normal,
                closingActionCompleted: handleClosingAction
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                if let runtimeModeBadgeTitle {
                    HStack {
                        Spacer()
                        TestModeBadge(title: runtimeModeBadgeTitle)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
                }
            }
        )
    }

    private func handleClosingAction(_ didApply: Bool) {
        closeAfterAction(reopenIfNeeded: !didApply)
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

enum EarlyReminderContentVariant {
    case normal
    case fallback
}

struct EarlyReminderContentView: View {
    @ObservedObject var flow: CommitmentProtectionFlow
    let variant: EarlyReminderContentVariant
    let closingActionCompleted: (Bool) -> Void
    var maximumContentHeight: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isStopRemindersConfirmationPresented = false
    @State private var pendingStopRemindersCommitment: CalendarEvent?

    var body: some View {
        EarlyReminderViewport(maximumContentHeight: resolvedMaximumContentHeight) {
            content
        }
        .accessibilityAddTraits(.isModal)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .stopRemindersConfirmation(
            isPresented: $isStopRemindersConfirmationPresented,
            onCancel: { pendingStopRemindersCommitment = nil },
            onConfirm: confirmStopReminders
        )
    }

    private var resolvedMaximumContentHeight: CGFloat {
        maximumContentHeight ?? EarlyReminderDisplayMetrics.maximumContentHeight(
            visibleFrameHeights: NSScreen.screens.map(\.visibleFrame.height)
        )
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 18) {
            if let commitment = flow.earlyReminderCommitment {
                let surface = surfaceModel(for: commitment)
                Label("Early Reminder", systemImage: "bell.fill")
                    .font(.headline)
                if flow.isEarlyReminderUnverified {
                    ProtectionCoverageStatusLabel(
                        presentation: ProtectionCoveragePresentation(state: .unverifiedReminder)
                    )
                        .font(.subheadline.weight(.semibold))
                    Text(InterfaceCopy.unverifiedReminderDetail())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if surface.conflict?.requiresPrimarySelection == true {
                    EarlyReminderConflictSelectionView(flow: flow, surface: surface)
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
                    EarlyReminderConflictSummaryView(
                        commitments: surface.secondaryConflictCommitments
                    )
                    if let meetingDescription = commitment.meetingDescription {
                        MeetingDescriptionView(text: meetingDescription)
                    }
                }
                Text("Close for now hides this Early Reminder. Strong Alert still appears when the commitment begins.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Menu("Snooze") {
                    ForEach(flow.snoozeOptionsMinutes, id: \.self) { minutes in
                        Button(InterfaceCopy.minuteDuration(minutes)) {
                            finishClosingAction(surface.actions.snooze(minutes))
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
                        actionButtons(for: surface)
                    }
                    VStack(spacing: 8) {
                        actionButtons(for: surface)
                    }
                }
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
        .padding(flow.earlyReminderCommitment == nil ? 0 : 28)
    }

    @ViewBuilder
    private func actionButtons(for surface: EarlyReminderSurfaceModel) -> some View {
        Button("Close for now") {
            finishClosingAction(surface.actions.clear())
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Close this Early Reminder while keeping Strong Alert active at the commitment start.")

        Button("Stop reminders") {
            pendingStopRemindersCommitment = surface.commitment
            isStopRemindersConfirmationPresented = true
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Stop Early Reminder and Strong Alert for this occurrence without changing Google Calendar.")
    }

    private func surfaceModel(for commitment: CalendarEvent) -> EarlyReminderSurfaceModel {
        switch variant {
        case .normal:
            EarlyReminderSurfaceModel.normal(flow: flow, commitment: commitment)
        case .fallback:
            EarlyReminderSurfaceModel.fallback(flow: flow, commitment: commitment)
        }
    }

    private func confirmStopReminders() {
        guard let pendingStopRemindersCommitment else {
            self.pendingStopRemindersCommitment = nil
            return
        }
        let didApply = surfaceModel(for: pendingStopRemindersCommitment).actions.dismiss()
        self.pendingStopRemindersCommitment = nil
        finishClosingAction(didApply)
    }

    private func finishClosingAction(_ didApply: Bool) {
        if didApply {
            announceActionResult(flow.lastActionMessage)
        }
        closingActionCompleted(didApply)
    }
}

struct EarlyReminderViewport<Content: View>: View {
    let maximumContentHeight: CGFloat
    @ViewBuilder let content: Content

    init(
        maximumContentHeight: CGFloat = EarlyReminderDisplayMetrics.maximumContentHeightLimit,
        @ViewBuilder content: () -> Content
    ) {
        self.maximumContentHeight = maximumContentHeight
        self.content = content()
    }

    var body: some View {
        IntrinsicHeightCappedLayout(
            minimumHeight: EarlyReminderDisplayMetrics.minimumContentHeight,
            maximumHeight: maximumContentHeight
        ) {
            ScrollView(.vertical, showsIndicators: true) {
                content
            }
        }
        .frame(minWidth: 360, idealWidth: 500, maxWidth: 560)
    }
}

private struct EarlyReminderConflictSummaryView: View {
    let commitments: [CalendarEvent]

    @ViewBuilder
    var body: some View {
        if !commitments.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ProtectionCoverageStatusLabel(
                    presentation: ProtectionCoveragePresentation(state: .commitmentConflict)
                )
                .font(.subheadline.weight(.semibold))
                ProtectionCoverageStatusLabel(
                    presentation: ProtectionCoveragePresentation(state: .primary)
                )
                .font(.caption.weight(.semibold))
                Text("Also in this conflict")
                    .font(.caption.weight(.semibold))
                ForEach(commitments, id: \.occurrenceID) { commitment in
                    Label(commitment.title, systemImage: "calendar")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct EarlyReminderConflictSelectionView: View {
    @ObservedObject var flow: CommitmentProtectionFlow
    let surface: EarlyReminderSurfaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProtectionCoverageStatusLabel(
                presentation: ProtectionCoveragePresentation(state: .commitmentConflict)
            )
                .font(.subheadline.weight(.semibold))
            Text("These commitments start at the same time. You can choose which commitment Strong Alert features; otherwise they remain equal choices.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(surface.primarySelectionOptions, id: \.occurrenceID) { commitment in
                VStack(alignment: .leading, spacing: 6) {
                    Text(commitment.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(flow.localStartTimeText(for: commitment))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let meetingDescription = commitment.meetingDescription {
                        MeetingDescriptionView(text: meetingDescription)
                    }
                    Button("Make primary") {
                        if surface.actions.selectPrimary(commitment) {
                            announceActionResult(flow.lastActionMessage)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Make \(commitment.title) primary")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct StrongAlertWindowView: View {
    let runtimeModeBadgeTitle: String?
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
            content: AnyView(
                StrongAlertContentView(flow: flow)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if let runtimeModeBadgeTitle {
                            HStack {
                                Spacer()
                                TestModeBadge(title: runtimeModeBadgeTitle)
                            }
                            .padding(10)
                            .allowsHitTesting(false)
                        }
                    }
            )
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
                        provenance: ProvenancePresentation(
                            sources: flow.strongAlertProvenanceSources(for: commitment)
                        ),
                        meetingDescription: commitment.meetingDescription,
                        verificationPresentation: flow.isStrongAlertUnverified
                            ? ProtectionCoveragePresentation(state: .unverifiedReminder)
                            : nil,
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
                        handledActionTitle: "I joined another way",
                        handledAction: {
                            guard flow.handleStrongAlert(for: commitment) else { return }
                            announceActionResult(flow.lastActionMessage)
                            finishStrongAlertAction(flow)
                        },
                        tertiaryActionTitle: "Got it",
                        tertiaryAction: {
                            closeStrongAlertAndYieldFocus(flow)
                        },
                        pauseAction: { duration in
                            let didPause = flow.pause(for: duration)
                            if didPause {
                                announceActionResult(flow.lastActionMessage)
                                finishStrongAlertAction(flow)
                            }
                            return didPause
                        },
                        maximumContentHeight: StrongAlertDisplayMetrics.maximumContentHeight(
                            visibleFrameHeights: NSScreen.screens.map(\.visibleFrame.height)
                        )
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
                finishStrongAlertAction(flow)
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
            ProtectionCoverageStatusLabel(
                presentation: ProtectionCoveragePresentation(state: .commitmentConflict)
            )
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
            ProtectionCoverageStatusLabel(
                presentation: ProtectionCoveragePresentation(state: .primary)
            )
                .font(.caption.weight(.semibold))
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
        IntrinsicHeightCappedLayout(
            minimumHeight: StrongAlertDisplayMetrics.minimumContentHeight,
            maximumHeight: StrongAlertDisplayMetrics.maximumContentHeight(
                visibleFrameHeights: NSScreen.screens.map(\.visibleFrame.height)
            )
        ) {
            ScrollView {
                VStack(spacing: 16) {
            Label("Strong Alert", systemImage: "bell.and.waves.left.and.right.fill")
                .font(.headline)
            ProtectionCoverageStatusLabel(
                presentation: ProtectionCoveragePresentation(state: .commitmentConflict)
            )
            .font(.subheadline.weight(.semibold))
            if flow.isStrongAlertUnverified {
                ProtectionCoverageStatusLabel(
                    presentation: ProtectionCoveragePresentation(state: .unverifiedReminder)
                )
                    .font(.subheadline.weight(.semibold))
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
                                .accessibilityAddTraits(.isHeader)
                            Text(flow.strongAlertTimingText(for: commitment, at: date))
                                .font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            strongAlertProvenanceRenderer(
                                ProvenancePresentation(
                                    sources: flow.strongAlertProvenanceSources(for: commitment)
                                )
                            )
                            if let meetingDescription = commitment.meetingDescription {
                                MeetingDescriptionView(text: meetingDescription)
                            }
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
                closeStrongAlertAndYieldFocus(flow)
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
        }
        .frame(minWidth: 360, idealWidth: 560, maxWidth: 620)
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
        let conflictPosition = conflict.commitments.firstIndex(where: {
            $0.occurrenceID == commitment.occurrenceID
        }).map { "option \($0 + 1) of \(conflict.commitments.count)" } ?? "conflict option"
        let provenance = ProvenancePresentation(
            sources: flow.strongAlertProvenanceSources(for: commitment)
        )
        let actionContext = [
            commitment.title,
            flow.localStartTimeText(for: commitment),
            provenance.accessibilityDescription,
            conflictPosition,
        ].joined(separator: ", ")

        Button("Make primary") {
            if flow.selectPrimary(for: commitment) {
                announceActionResult(flow.lastActionMessage)
            }
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("Make \(actionContext) primary")
        .accessibilityHint("Use this commitment as the primary choice for this conflict.")

        if links.isEmpty {
            Button("Stop reminders") {
                requestStopReminders(commitment)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Stop reminders for \(actionContext)")
        } else if let primaryLink = flow.strongAlertPrimaryMeetingLink(for: commitment) {
            Button("Join") {
                openMeetingLink(primaryLink, for: commitment)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Join \(actionContext)")
        } else {
            Menu("Choose link") {
                ForEach(choices, id: \.url.absoluteString) { choice in
                    Button(choice.title) {
                        openMeetingLink(choice.url, for: commitment)
                    }
                }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Choose a meeting link for \(actionContext)")
        }

        if !links.isEmpty {
            Button("Stop reminders") {
                requestStopReminders(commitment)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Stop reminders for \(actionContext)")
        }

        Button("I joined another way") {
            guard flow.handleStrongAlert(for: commitment) else { return }
            announceActionResult(flow.lastActionMessage)
            finishStrongAlertAction(flow)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("I joined \(actionContext) another way")
        .accessibilityHint("Mark this commitment as handled because you joined it outside Meeting Incoming.")
    }

    private var pauseAction: ((PauseDuration) -> Bool)? {
        { duration in
            let didPause = flow.pause(for: duration)
            if didPause {
                announceActionResult(flow.lastActionMessage)
                finishStrongAlertAction(flow)
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

private struct EarlyReminderFallbackView: View {
    @ObservedObject var flow: CommitmentProtectionFlow
    let closingActionCompleted: (Bool) -> Void

    var body: some View {
        EarlyReminderContentView(
            flow: flow,
            variant: .fallback,
            closingActionCompleted: closingActionCompleted
        )
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

func objectIsOwned<Object: AnyObject>(
    _ candidate: Object?,
    byAny roots: [Object],
    parent: (Object) -> Object?
) -> Bool {
    roots.contains { root in
        objectIsOwned(candidate, by: root, parent: parent)
    }
}

@MainActor
func windowIsOwned(_ candidate: NSWindow?, by rootWindow: NSWindow?) -> Bool {
    objectIsOwned(candidate, by: rootWindow) { window in
        window.sheetParent ?? window.parent
    }
}

@MainActor
func windowIsOwned(_ candidate: NSWindow?, byAny rootWindows: [NSWindow]) -> Bool {
    objectIsOwned(candidate, byAny: rootWindows) { window in
        window.sheetParent ?? window.parent
    }
}

@MainActor
private final class EarlyReminderHostingView: NSHostingView<AnyView> {
    var intrinsicContentSizeDidInvalidate: (@MainActor () -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        intrinsicContentSizeDidInvalidate?()
    }
}

@MainActor
private final class EarlyReminderReplicaPanel: NSPanel {
    override func accessibilityChildren() -> [Any]? {
        []
    }
}

private final class EarlyReminderInteractionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var reminderWindows: [NSWindow] = []
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

    func start(for windows: [NSWindow], isApplicationActive: Bool) -> CFMachPort? {
        lock.lock()
        reminderWindows = windows
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
        if event.type == .keyDown,
           event.keyCode == UInt16(kVK_ANSI_R),
           event.modifierFlags.intersection([.command, .control, .shift, .option]) ==
            [.command, .control, .shift] {
            return true
        }
        lock.lock()
        let reminderWindows = self.reminderWindows
        lock.unlock()
        return windowIsOwned(event.window, byAny: reminderWindows)
    }

    func stop() {
        lock.lock()
        reminderWindows = []
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
                .maskControl,
                .maskShift
            ]
            let modifiers = event.flags.intersection(systemModifierFlags)
            let hasVoiceOverModifiers = modifiers.contains(.maskControl) && modifiers.contains(.maskAlternate)
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isAccessibilityShortcut = keyCode == Int64(kVK_F5) &&
                modifiers.contains(.maskCommand)
            let isTestToolsShortcut = keyCode == Int64(kVK_ANSI_R) &&
                modifiers.contains(.maskCommand) &&
                modifiers.contains(.maskControl) &&
                modifiers.contains(.maskShift) &&
                !modifiers.contains(.maskAlternate)
            if hasVoiceOverModifiers || isAccessibilityShortcut || isTestToolsShortcut {
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

    private struct ScheduledRefit {
        enum Phase {
            case pending
            case running
        }

        let generation: UInt
        var phase: Phase
        var needsTrailingPass: Bool
    }

    private struct PresentationRequest {
        let generation: Int
        let flow: CommitmentProtectionFlow
        let content: AnyView
        let reopen: @MainActor () -> Void
        let closingActionCompleted: @MainActor (Bool) -> Void
    }

    private let windowRegistry: WindowRegistry
    private let scheduleAfterLayout: (@escaping @MainActor () -> Void) -> Void
    private let fitWindow: @MainActor (NSWindow?, NSScreen?) -> Void
    private let notificationCenter: NotificationCenter
    private let availableScreens: @MainActor () -> [NSScreen]
    private weak var window: NSWindow?
    private var additionalWindows: [NSWindow] = []
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
    private var applicationObserver: NSObjectProtocol?
    private var reopenSurface: (@MainActor () -> Void)?
    private var reminderFlow: CommitmentProtectionFlow?
    private var closingActionCompleted: (@MainActor (Bool) -> Void)?
    private var runtimeModeBadgeTitle: String?
    private var fallbackPanel: NSPanel?
    private var surfaceRecoveryAttempts = 0
    private var allowsWindowClose = false
    private var isPresented = false
    private var isInteractionBarrierActive = false
    private var isInteractionSuspendedForTestTools = false
    private var fittingWindowIDs: Set<ObjectIdentifier> = []
    private var content: AnyView?
    private var windowLayoutGeneration: UInt = 0
    private var scheduledRefits: [ObjectIdentifier: ScheduledRefit] = [:]
    private var lastFittedContentSizes: [ObjectIdentifier: CGSize] = [:]
    private var blockingMode = EarlyReminderBlockingMode()
    private var lifecycle = AlertPresentationLifecycle()
    private var presentationState = EarlyReminderPresentationState()
    private var windowTrackingState = EarlyReminderWindowTrackingState()
    private var barrierLifecycle = EarlyReminderInteractionBarrierLifecycle()
    @Published private(set) var isGlobalInteractionBarrierAvailable = false
    private lazy var pendingPresentation = PendingWindowPresentation<PresentationRequest>(
        registry: windowRegistry,
        kind: .earlyReminder
    ) { [weak self] window, request in
        self?.present(request, in: window)
    }

    var managedWindows: [NSWindow] {
        [window].compactMap { $0 } + additionalWindows
    }

    var isSurfacePresented: Bool {
        isPresented
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
        },
        notificationCenter: NotificationCenter = .default,
        availableScreens: @escaping @MainActor () -> [NSScreen] = { NSScreen.screens }
    ) {
        self.windowRegistry = windowRegistry
        self.scheduleAfterLayout = scheduleAfterLayout
        self.fitWindow = fitWindow
        self.notificationCenter = notificationCenter
        self.availableScreens = availableScreens
        super.init()
    }

    func present(
        flow: CommitmentProtectionFlow,
        content: AnyView,
        reopen: @escaping @MainActor () -> Void,
        closingActionCompleted: @escaping @MainActor (Bool) -> Void
    ) {
        let generation = presentationState.beginPresentation()
        if windowRegistry.window(for: .earlyReminder) == nil {
            _ = lifecycle.present(
                surface: .earlyReminderNormal,
                displayCount: availableScreens().count,
                primaryIndex: nil,
                surfaceDiscovered: false
            )
        }
        pendingPresentation.submit(PresentationRequest(
            generation: generation,
            flow: flow,
            content: content,
            reopen: reopen,
            closingActionCompleted: closingActionCompleted
        ))
    }

    private func present(_ request: PresentationRequest, in registeredWindow: NSWindow) {
        guard presentationState.acceptsPresentationRequest(
            request.generation,
            hasCommitment: request.flow.earlyReminderCommitment != nil
        ) else { return }
        reopenSurface = request.reopen
        reminderFlow = request.flow
        closingActionCompleted = request.closingActionCompleted
        content = request.content

        if let retainedWindow = window, retainedWindow !== registeredWindow {
            stopBarrierRetryMonitoring()
            stopScreenObservation()
            stopApplicationObservation()
            deactivateInteractionBarrier()
            closeAdditionalWindows()
            if let fallbackPanel {
                fallbackPanel.delegate = nil
                fallbackPanel.close()
                self.fallbackPanel = nil
                if retainedWindow !== fallbackPanel {
                    retainedWindow.delegate = nil
                    retainedWindow.close()
                }
            } else {
                retainedWindow.delegate = nil
                retainedWindow.close()
            }
            windowTrackingState.unregisterAll()
            window = nil
            isPresented = false
        }
        if isPresented {
            screenParametersDidChange()
            return
        }

        stopSurfaceRecoveryMonitoring()
        closeAdditionalWindows()
        beginWindowLayoutGeneration()
        window = registeredWindow
        windowTrackingState.register(ObjectIdentifier(registeredWindow))
        configureReminderWindow(registeredWindow)
        let screens = availableScreens()
        guard let displayPlan = lifecycle.present(
            surface: .earlyReminderNormal,
            displayCount: screens.count,
            primaryIndex: primaryScreenIndex(for: registeredWindow),
            surfaceDiscovered: true
        ) else {
            isPresented = false
            startScreenObservation()
            return
        }
        positionPrimaryWindow(
            registeredWindow,
            on: screens[displayPlan.primaryIndex]
        )
        isPresented = true
        createAdditionalWindows(
            using: displayPlan,
            screens: screens,
            layoutGeneration: windowLayoutGeneration
        )
        startScreenObservation()
        if !isInteractionSuspendedForTestTools {
            startApplicationObservation()
        }
        let barrierAvailable: Bool
        if blockingMode.shouldAttemptBlocking && !isInteractionSuspendedForTestTools {
            startBarrierRetryMonitoring()
            barrierAvailable = attemptBlockingMode()
        } else {
            barrierAvailable = false
        }
        if isInteractionSuspendedForTestTools {
            managedWindows.forEach { $0.orderFront(nil) }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            registeredWindow.makeKeyAndOrderFront(nil)
            if !barrierAvailable {
                managedWindows.forEach { $0.orderFrontRegardless() }
            }
            lifecycle.markActivated()
        }
    }

    func stop() {
        stopBarrierRetryMonitoring()
        stopSurfaceRecoveryMonitoring()
        stopScreenObservation()
        stopApplicationObservation()
        guard isPresented else { return }
        deactivateInteractionBarrier()
        isPresented = false
        managedWindows.forEach {
            $0.standardWindowButton(.closeButton)?.isEnabled = true
        }
    }

    func close() {
        presentationState.requestCloseWhenWindowAppears()
        pendingPresentation.clear()
        allowsWindowClose = true
        let window = self.window
        stop()
        closeAdditionalWindows()
        window?.delegate = nil
        window?.close()
        fallbackPanel = nil
        windowTrackingState.unregisterAll()
        self.window = nil
        self.content = nil
        self.runtimeModeBadgeTitle = nil
        self.reminderFlow = nil
        self.closingActionCompleted = nil
        beginWindowLayoutGeneration()
        lifecycle.close()
        allowsWindowClose = false
    }

    func prepareForProgrammaticClose() {
        allowsWindowClose = true
        managedWindows.forEach { $0.delegate = nil }
    }

    func setRuntimeModeBadgeTitle(_ title: String?) {
        runtimeModeBadgeTitle = title
    }

    func suspendInteractionForTestTools() {
        guard !isInteractionSuspendedForTestTools else { return }
        isInteractionSuspendedForTestTools = true
        stopBarrierRetryMonitoring()
        stopApplicationObservation()
        deactivateInteractionBarrier()
        managedWindows.forEach { $0.level = .normal }
    }

    func resumeInteractionAfterTestTools() {
        guard isInteractionSuspendedForTestTools else { return }
        isInteractionSuspendedForTestTools = false
        guard isPresented else { return }
        let reminderLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        managedWindows.forEach { $0.level = reminderLevel }
        startApplicationObservation()
        if blockingMode.shouldAttemptBlocking {
            startBarrierRetryMonitoring()
            retryInteractionBarrierIfNeeded()
        }
        bringReminderToFront()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !allowsWindowClose else { return true }
        guard let reminderFlow,
              let commitment = reminderFlow.earlyReminderCommitment else { return false }
        let didApply = EarlyReminderActionHandlers.fallback(
            flow: reminderFlow,
            commitment: commitment
        ).clear()
        if didApply {
            announceActionResult(reminderFlow.lastActionMessage)
        }
        closingActionCompleted?(didApply)
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard isPresented,
              isInteractionBarrierActive,
              let miniaturizedWindow = notification.object as? NSWindow,
              windowTrackingState.tracks(ObjectIdentifier(miniaturizedWindow)) else { return }
        miniaturizedWindow.deminiaturize(nil)
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

    private func configureReminderWindow(_ reminderWindow: NSWindow) {
        reminderWindow.delegate = self
        reminderWindow.level = isInteractionSuspendedForTestTools
            ? .normal
            : NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        reminderWindow.hidesOnDeactivate = false
        reminderWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Keep every reminder surface visible through full-display, window, and app sharing.
        reminderWindow.sharingType = .readOnly
        reminderWindow.standardWindowButton(.closeButton)?.isEnabled = true
        reminderWindow.standardWindowButton(.closeButton)?.isHidden = false
        reminderWindow.standardWindowButton(.closeButton)?.isTransparent = false
        reminderWindow.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        reminderWindow.standardWindowButton(.zoomButton)?.isEnabled = false
        reminderWindow.isMovable = false
    }

    private func createAdditionalWindows(
        using displayPlan: StrongAlertDisplayPlan,
        screens: [NSScreen],
        layoutGeneration: UInt
    ) {
        guard let content else { return }

        additionalWindows = displayPlan.additionalIndices.map { index in
            let screen = screens[index]
            let hostingView = EarlyReminderHostingView(
                rootView: AnyView(content.accessibilityHidden(true))
            )
            hostingView.sizingOptions = [.intrinsicContentSize]
            let panel = EarlyReminderReplicaPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "Early Reminder"
            panel.isReleasedWhenClosed = false
            panel.setAccessibilityElement(false)
            panel.contentView = hostingView
            configureReminderWindow(panel)
            [
                NSWindow.ButtonType.closeButton,
                .miniaturizeButton,
                .zoomButton
            ].forEach { buttonType in
                panel.standardWindowButton(buttonType)?.setAccessibilityElement(false)
            }
            windowTrackingState.register(ObjectIdentifier(panel))
            hostingView.intrinsicContentSizeDidInvalidate = { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.refitAdditionalWindowAfterLayout(
                    panel,
                    on: screen,
                    layoutGeneration: layoutGeneration
                )
            }
            fitReminderWindow(panel, on: screen)
            panel.orderFrontRegardless()
            return panel
        }

        for (additionalWindow, screenIndex) in zip(
            additionalWindows,
            displayPlan.additionalIndices
        ) {
            refitAdditionalWindowAfterLayout(
                additionalWindow,
                on: screens[screenIndex],
                layoutGeneration: layoutGeneration
            )
        }
    }

    private func closeAdditionalWindows() {
        additionalWindows.forEach { additionalWindow in
            windowTrackingState.unregister(ObjectIdentifier(additionalWindow))
            additionalWindow.delegate = nil
            additionalWindow.close()
        }
        additionalWindows.removeAll()
    }

    private func beginWindowLayoutGeneration() {
        windowLayoutGeneration &+= 1
        scheduledRefits.removeAll()
        lastFittedContentSizes.removeAll()
    }

    func surfaceDidDisappear(
        flow: CommitmentProtectionFlow,
        reopen: @escaping @MainActor () -> Void,
        closingActionCompleted: @escaping @MainActor (Bool) -> Void
    ) {
        presentationState.requestCloseWhenWindowAppears()
        pendingPresentation.clear()
        reopenSurface = reopen
        reminderFlow = flow
        self.closingActionCompleted = closingActionCompleted
        lifecycle.surfaceDisappeared()
        guard isPresented else {
            startSurfaceRecoveryMonitoring()
            return
        }
        stopBarrierRetryMonitoring()
        stopScreenObservation()
        stopApplicationObservation()
        deactivateInteractionBarrier()
        isPresented = false
        closeAdditionalWindows()
        windowTrackingState.unregisterAll()
        beginWindowLayoutGeneration()
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
              let reminderFlow,
              reminderFlow.earlyReminderCommitment != nil,
              let closingActionCompleted else { return }

        pendingPresentation.clear()
        let reopenSurface = self.reopenSurface
        stopSurfaceRecoveryMonitoring()
        self.reopenSurface = reopenSurface
        closeAdditionalWindows()
        beginWindowLayoutGeneration()

        let fallbackContent = makeFallbackContent(
            flow: reminderFlow,
            closingActionCompleted: closingActionCompleted
        )
        content = fallbackContent
        let hostingView = EarlyReminderHostingView(rootView: fallbackContent)
        hostingView.sizingOptions = [.intrinsicContentSize]
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Early Reminder"
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        configureReminderWindow(panel)
        fallbackPanel = panel
        window = panel
        windowTrackingState.register(ObjectIdentifier(panel))

        let screens = availableScreens()
        let mainScreenIndex = NSScreen.main.flatMap { screen in
            screens.firstIndex(where: { $0 === screen || $0.frame == screen.frame })
        }
        guard let displayPlan = lifecycle.present(
            surface: .earlyReminderFallback,
            displayCount: screens.count,
            primaryIndex: mainScreenIndex,
            surfaceDiscovered: true
        ) else {
            panel.delegate = nil
            panel.close()
            fallbackPanel = nil
            window = nil
            windowTrackingState.unregisterAll()
            startSurfaceRecoveryMonitoring()
            return
        }

        fitReminderWindow(panel, on: screens[displayPlan.primaryIndex])
        isPresented = true
        createAdditionalWindows(
            using: displayPlan,
            screens: screens,
            layoutGeneration: windowLayoutGeneration
        )
        startScreenObservation()
        if !isInteractionSuspendedForTestTools {
            startApplicationObservation()
        }
        let barrierAvailable: Bool
        if blockingMode.shouldAttemptBlocking && !isInteractionSuspendedForTestTools {
            startBarrierRetryMonitoring()
            barrierAvailable = attemptBlockingMode()
        } else {
            barrierAvailable = false
        }
        if isInteractionSuspendedForTestTools {
            managedWindows.forEach { $0.orderFront(nil) }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            if !barrierAvailable {
                managedWindows.forEach { $0.orderFrontRegardless() }
            }
            lifecycle.markActivated()
        }
        hostingView.intrinsicContentSizeDidInvalidate = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.refitFallbackWindowAfterLayout(panel)
        }
        refitFallbackWindowAfterLayout(panel)
    }

    private func makeFallbackContent(
        flow: CommitmentProtectionFlow,
        closingActionCompleted: @escaping @MainActor (Bool) -> Void
    ) -> AnyView {
        AnyView(
            EarlyReminderFallbackView(
                flow: flow,
                closingActionCompleted: closingActionCompleted
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                if let runtimeModeBadgeTitle {
                    HStack {
                        Spacer()
                        TestModeBadge(title: runtimeModeBadgeTitle)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
                }
            }
        )
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

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    var hasInputMonitoringPermission: Bool {
        CGPreflightListenEventAccess()
    }

    func setBlockingModeEnabled(_ isEnabled: Bool) {
        if isEnabled && !isInteractionSuspendedForTestTools {
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
            managedWindows.forEach { $0.orderFrontRegardless() }
        }
    }

    @discardableResult
    private func activateInteractionBarrier() -> Bool {
        guard isPresented, !managedWindows.isEmpty else {
            barrierLifecycle.activationFailed()
            lifecycle.interactionBarrierAvailabilityChanged(false)
            isGlobalInteractionBarrierAvailable = false
            return false
        }
        if isInteractionBarrierActive { return barrierLifecycle.isActive }
        guard let eventTap = interactionGate.start(
            for: managedWindows,
            isApplicationActive: NSApp.isActive
        ) else {
            barrierLifecycle.activationFailed()
            lifecycle.interactionBarrierAvailabilityChanged(false)
            isGlobalInteractionBarrierAvailable = false
            return false
        }
        guard let eventSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0) else {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            interactionGate.stop()
            barrierLifecycle.activationFailed()
            lifecycle.interactionBarrierAvailabilityChanged(false)
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
                notificationCenter.addObserver(
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
                        self.managedWindows.forEach { $0.orderFrontRegardless() }
                        self.window?.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
        isInteractionBarrierActive = true
        barrierLifecycle.activated(restoresWindowInteraction: !blockedWindows.isEmpty)
        lifecycle.interactionBarrierAvailabilityChanged(barrierLifecycle.isAvailable)
        isGlobalInteractionBarrierAvailable = barrierLifecycle.isAvailable
        refreshFallbackPanelContent()
        return true
    }

    private func refreshFallbackPanelContent() {
        guard let panel = fallbackPanel,
              let reminderFlow,
              let closingActionCompleted else { return }
        let fallbackContent = makeFallbackContent(
            flow: reminderFlow,
            closingActionCompleted: closingActionCompleted
        )
        content = fallbackContent
        let hostingView = EarlyReminderHostingView(rootView: fallbackContent)
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.intrinsicContentSizeDidInvalidate = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.refitFallbackWindowAfterLayout(panel)
        }
        panel.contentView = hostingView
        fitReminderWindow(
            panel,
            on: panel.screen
        )
    }

    private func fitReminderWindow(_ window: NSWindow?, on screen: NSScreen?) {
        guard let window,
              window !== self.window || window === fallbackPanel else { return }
        let windowID = ObjectIdentifier(window)
        guard fittingWindowIDs.insert(windowID).inserted else { return }
        defer { fittingWindowIDs.remove(windowID) }

        fitWindow(window, screen)
    }

    private func positionPrimaryWindow(_ primaryWindow: NSWindow?, on screen: NSScreen) {
        guard let primaryWindow else { return }
        let visibleFrame = screen.visibleFrame
        primaryWindow.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - primaryWindow.frame.width / 2,
            y: visibleFrame.midY - primaryWindow.frame.height / 2
        ))
    }

    private func refitFallbackWindowAfterLayout(_ fallbackWindow: NSWindow) {
        scheduleAfterLayout { [weak self, weak fallbackWindow] in
            guard let self,
                  let fallbackWindow,
                  self.isPresented,
                  self.fallbackPanel === fallbackWindow,
                  self.window === fallbackWindow else { return }
            self.fitReminderWindow(
                fallbackWindow,
                on: fallbackWindow.screen
            )
        }
    }

    private func refitAdditionalWindowAfterLayout(
        _ additionalWindow: NSWindow,
        on screen: NSScreen,
        layoutGeneration: UInt
    ) {
        let windowID = ObjectIdentifier(additionalWindow)
        if var scheduledRefit = scheduledRefits[windowID],
           scheduledRefit.generation == layoutGeneration {
            if scheduledRefit.phase == .running {
                scheduledRefit.needsTrailingPass = true
                scheduledRefits[windowID] = scheduledRefit
            }
            return
        }
        scheduledRefits[windowID] = ScheduledRefit(
            generation: layoutGeneration,
            phase: .pending,
            needsTrailingPass: false
        )
        enqueueAdditionalWindowRefit(
            additionalWindow,
            on: screen,
            layoutGeneration: layoutGeneration
        )
    }

    private func enqueueAdditionalWindowRefit(
        _ additionalWindow: NSWindow,
        on screen: NSScreen,
        layoutGeneration: UInt
    ) {
        let windowID = ObjectIdentifier(additionalWindow)
        scheduleAfterLayout { [weak self, weak additionalWindow] in
            guard let self,
                  var scheduledRefit = self.scheduledRefits[windowID],
                  scheduledRefit.generation == layoutGeneration,
                  scheduledRefit.phase == .pending else { return }
            guard let additionalWindow,
                  self.isPresented,
                  self.windowLayoutGeneration == layoutGeneration,
                  self.additionalWindows.contains(where: { $0 === additionalWindow }) else {
                self.removeScheduledRefit(for: windowID, layoutGeneration: layoutGeneration)
                return
            }

            additionalWindow.contentView?.layoutSubtreeIfNeeded()
            let contentSize = additionalWindow.contentView?.fittingSize
                ?? additionalWindow.contentLayoutRect.size
            if let lastFittedContentSize = self.lastFittedContentSizes[windowID],
               self.contentSizesAreEquivalent(contentSize, lastFittedContentSize) {
                self.removeScheduledRefit(for: windowID, layoutGeneration: layoutGeneration)
                return
            }

            scheduledRefit.phase = .running
            scheduledRefit.needsTrailingPass = false
            self.scheduledRefits[windowID] = scheduledRefit
            self.fitReminderWindow(additionalWindow, on: screen)
            self.lastFittedContentSizes[windowID] = contentSize
            additionalWindow.contentView?.layoutSubtreeIfNeeded()
            let settledContentSize = additionalWindow.contentView?.fittingSize
                ?? additionalWindow.contentLayoutRect.size

            guard let completedRefit = self.scheduledRefits[windowID],
                  completedRefit.generation == layoutGeneration else { return }
            if completedRefit.needsTrailingPass ||
                !self.contentSizesAreEquivalent(contentSize, settledContentSize) {
                self.scheduledRefits[windowID] = ScheduledRefit(
                    generation: layoutGeneration,
                    phase: .pending,
                    needsTrailingPass: false
                )
                self.enqueueAdditionalWindowRefit(
                    additionalWindow,
                    on: screen,
                    layoutGeneration: layoutGeneration
                )
            } else {
                self.removeScheduledRefit(for: windowID, layoutGeneration: layoutGeneration)
            }
        }
    }

    private func removeScheduledRefit(
        for windowID: ObjectIdentifier,
        layoutGeneration: UInt
    ) {
        guard scheduledRefits[windowID]?.generation == layoutGeneration else { return }
        scheduledRefits.removeValue(forKey: windowID)
    }

    private func contentSizesAreEquivalent(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) <= 0.5 && abs(lhs.height - rhs.height) <= 0.5
    }

    private func deactivateInteractionBarrier() {
        barrierLifecycle.deactivated()
        lifecycle.interactionBarrierAvailabilityChanged(false)
        isGlobalInteractionBarrierAvailable = false
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
        windowInteractionObservers.forEach(notificationCenter.removeObserver)
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
        guard isPresented,
              blockingMode.shouldAttemptBlocking,
              !isInteractionSuspendedForTestTools else { return }
        if isInteractionBarrierActive {
            if interactionGate.userDisabledEventTap() {
                disableInteractionBarrierAfterSystemRequest()
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

    private func disableInteractionBarrierAfterSystemRequest() {
        stopBarrierRetryMonitoring()
        deactivateInteractionBarrier()
        barrierLifecycle.disabledBySystem()
        lifecycle.interactionBarrierAvailabilityChanged(false)
        blockingMode.disableBlocking()
        refreshFallbackPanelContent()
    }

    @discardableResult
    private func attemptBlockingMode() -> Bool {
        guard blockingMode.shouldAttemptBlocking,
              !isInteractionSuspendedForTestTools else { return false }
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
              !windowIsOwned(candidate, byAny: managedWindows),
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
        shieldWindows = availableScreens().map { screen in
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
        screenObserver = notificationCenter.addObserver(
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
            notificationCenter.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func startApplicationObservation() {
        guard applicationObserver == nil else { return }
        applicationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bringReminderToFront()
            }
        }
    }

    private func stopApplicationObservation() {
        if let applicationObserver {
            notificationCenter.removeObserver(applicationObserver)
            self.applicationObserver = nil
        }
    }

    private func screenParametersDidChange() {
        guard let window,
              isPresented || lifecycle.requiresSurfaceRecovery || lifecycle.requiresSurfaceCreation else {
            return
        }
        let wasDisabledBySystemOrUser = interactionGate.userDisabledEventTap()
        let shouldRestoreBarrier = blockingMode.shouldAttemptBlocking &&
            !isInteractionSuspendedForTestTools &&
            !wasDisabledBySystemOrUser
        if wasDisabledBySystemOrUser {
            disableInteractionBarrierAfterSystemRequest()
        } else if isInteractionBarrierActive {
            deactivateInteractionBarrier()
        }
        beginWindowLayoutGeneration()
        let screens = availableScreens()
        guard let displayPlan = lifecycle.displayTopologyChanged(
            displayCount: screens.count,
            primaryIndex: primaryScreenIndex(for: window)
        ), lifecycle.isPresented else {
            closeAdditionalWindows()
            stopApplicationObservation()
            isPresented = false
            return
        }
        closeAdditionalWindows()
        if window === fallbackPanel {
            fitReminderWindow(window, on: screens[displayPlan.primaryIndex])
        } else {
            positionPrimaryWindow(window, on: screens[displayPlan.primaryIndex])
        }
        createAdditionalWindows(
            using: displayPlan,
            screens: screens,
            layoutGeneration: windowLayoutGeneration
        )
        isPresented = true
        if !isInteractionSuspendedForTestTools {
            startApplicationObservation()
        }
        if shouldRestoreBarrier {
            startBarrierRetryMonitoring()
            _ = attemptBlockingMode()
        }
        bringReminderToFront()
    }

    private func preserveReminderFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isPresented,
                  !self.isInteractionSuspendedForTestTools else { return }
            if windowIsOwned(NSApp.keyWindow, byAny: self.managedWindows) {
                self.managedWindows.forEach { $0.orderFrontRegardless() }
            } else {
                self.bringReminderToFront()
            }
        }
    }

    private func bringReminderToFront() {
        guard isPresented, !isInteractionSuspendedForTestTools else { return }
        lifecycle.applicationActivationChanged()
        let keyWindow = NSApp.keyWindow
        NSApp.activate(ignoringOtherApps: true)
        managedWindows.forEach { $0.orderFrontRegardless() }
        if !windowIsOwned(keyWindow, byAny: managedWindows) {
            window?.makeKey()
        }
        lifecycle.markActivated()
    }

    private func primaryScreenIndex(for window: NSWindow) -> Int? {
        guard let screen = window.screen ?? NSScreen.main else { return nil }
        return availableScreens().firstIndex { candidate in
            candidate === screen || candidate.frame == screen.frame
        }
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

private struct MeetingDescriptionView: View {
    let text: String
    @State private var isExpanded = false

    private var canExpand: Bool {
        text.count > 180 || text.split(separator: "\n").count > 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Meeting description", systemImage: "text.alignleft")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .lineLimit(isExpanded || !canExpand ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if canExpand {
                Button(isExpanded ? "Show less" : "Show full description") {
                    isExpanded.toggle()
                }
                .buttonStyle(.link)
                .controlSize(.small)
                .accessibilityLabel(
                    isExpanded
                        ? "Collapse meeting description"
                        : "Expand meeting description"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .contain)
    }
}

struct StrongAlertView: View {
    let title: String
    let timing: String
    let provenance: ProvenancePresentation
    var meetingDescription: String? = nil
    var verificationPresentation: ProtectionCoveragePresentation? = nil
    var statusMessage: String? = nil
    var repeatConsequence: String? = nil
    var supportingContent: AnyView? = nil
    var primaryActionHint: String = "Take the primary action for this commitment."
    let primaryActionTitle: String
    let primaryAction: () -> Void
    var primaryActionChoices: [(String, () -> Void)] = []
    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var handledActionTitle: String? = nil
    var handledAction: (() -> Void)? = nil
    var tertiaryActionTitle: String? = nil
    var tertiaryAction: (() -> Void)? = nil
    var pauseAction: ((PauseDuration) -> Bool)? = nil
    var maximumContentHeight: CGFloat = StrongAlertDisplayMetrics.maximumContentHeightLimit
    @State private var customPauseExpiration = Date().addingTimeInterval(60 * 60)
    @State private var isCustomPausePresented = false

    var body: some View {
        IntrinsicHeightCappedLayout(
            minimumHeight: StrongAlertDisplayMetrics.minimumContentHeight,
            maximumHeight: maximumContentHeight
        ) {
            ScrollView(.vertical, showsIndicators: true) {
                alertContent
            }
        }
        .frame(minWidth: 360, idealWidth: 500, maxWidth: 620)
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

    private var alertContent: some View {
        VStack(spacing: 24) {
            Label("Strong Alert", systemImage: "bell.and.waves.left.and.right.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            if let verificationPresentation {
                VStack(spacing: 6) {
                    ProtectionCoverageStatusLabel(presentation: verificationPresentation)
                        .font(.subheadline.weight(.semibold))
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
                provenanceRenderer
            }

            if let meetingDescription {
                MeetingDescriptionView(text: meetingDescription)
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

                if let handledActionTitle, let handledAction {
                    Button(handledActionTitle, action: handledAction)
                        .keyboardShortcut("i")
                        .buttonStyle(.bordered)
                        .accessibilityLabel(handledActionTitle)
                        .accessibilityHint("Mark this commitment as handled because you joined it outside Meeting Incoming.")
                }

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

    var provenanceRenderer: StrongAlertProvenanceView {
        strongAlertProvenanceRenderer(provenance)
    }
}

struct StrongAlertProvenanceSemantics: Equatable, Sendable {
    let primaryText: String
    let secondaryText: String?
    let help: String
    let accessibilityLabel: String

    init(urgent: ProvenancePresentation.Urgent) {
        primaryText = urgent.primaryText
        secondaryText = urgent.secondaryText
        help = urgent.help
        accessibilityLabel = urgent.accessibilityDescription
    }
}

struct StrongAlertProvenanceView: View {
    let presentation: ProvenancePresentation

    var semantics: StrongAlertProvenanceSemantics? {
        presentation.urgent.map(StrongAlertProvenanceSemantics.init(urgent:))
    }

    @ViewBuilder
    var body: some View {
        if let semantics {
            VStack(spacing: 2) {
                Text(semantics.primaryText)
                    .font(.callout.weight(.medium))
                if let secondaryText = semantics.secondaryText {
                    Text(secondaryText)
                        .font(.caption)
                }
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .help(semantics.help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(semantics.accessibilityLabel)
        }
    }
}

/// The single provenance-rendering seam used by normal and unresolved-conflict Strong Alerts.
func strongAlertProvenanceRenderer(
    _ presentation: ProvenancePresentation
) -> StrongAlertProvenanceView {
    StrongAlertProvenanceView(presentation: presentation)
}

enum StrongAlertDisplayMetrics {
    static let minimumContentHeight: CGFloat = 300
    static let maximumContentHeightLimit: CGFloat = 680

    // Preserve the fitter's 40-point margins above and below, with room for
    // title-bar chrome, on the shortest connected display.
    private static let verticalWindowAllowance: CGFloat = 120

    static func maximumContentHeight(visibleFrameHeights: [CGFloat]) -> CGFloat {
        guard let shortestVisibleHeight = visibleFrameHeights
            .filter(\.isFinite)
            .min() else {
            return maximumContentHeightLimit
        }
        return Swift.min(
            maximumContentHeightLimit,
            Swift.max(
                minimumContentHeight,
                shortestVisibleHeight - verticalWindowAllowance
            )
        )
    }
}

enum EarlyReminderDisplayMetrics {
    static let minimumContentHeight = StrongAlertDisplayMetrics.minimumContentHeight
    static let maximumContentHeightLimit = StrongAlertDisplayMetrics.maximumContentHeightLimit

    static func maximumContentHeight(visibleFrameHeights: [CGFloat]) -> CGFloat {
        StrongAlertDisplayMetrics.maximumContentHeight(
            visibleFrameHeights: visibleFrameHeights
        )
    }
}

private struct IntrinsicHeightCappedLayout: Layout {
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let naturalSize = subview.sizeThatFits(ProposedViewSize(
            width: proposal.width,
            height: nil
        ))
        let resolvedMinimum = Swift.max(minimumHeight, 0)
        let resolvedMaximum = Swift.max(maximumHeight, resolvedMinimum)
        return CGSize(
            width: proposal.width ?? naturalSize.width,
            height: Swift.min(
                Swift.max(naturalSize.height, resolvedMinimum),
                resolvedMaximum
            )
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
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

@MainActor
private func closeStrongAlertAndYieldFocus(_ flow: CommitmentProtectionFlow) {
    flow.closeStrongAlertSurface()
    announceActionResult(flow.lastActionMessage)
    finishStrongAlertAction(flow)
}

@MainActor
private func finishStrongAlertAction(_ flow: CommitmentProtectionFlow) {
    StrongAlertActionCompletion.finish(
        hasRemainingAlert: flow.isStrongAlertPresented
    )
}

private struct MenuBarConflictView: View {
    @ObservedObject var flow: CommitmentProtectionFlow
    let conflict: CommitmentConflict

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProtectionCoverageStatusLabel(
                presentation: ProtectionCoveragePresentation(state: .commitmentConflict)
            )
                .font(.subheadline.weight(.semibold))
            if conflict.requiresPrimarySelection {
                Text("Choose which commitment is primary:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if conflict.commitments.count <= 3 {
                    ForEach(conflict.commitments, id: \.occurrenceID) { commitment in
                        Button("Make primary: \(commitment.title)") {
                            selectPrimary(commitment)
                        }
                    }
                } else {
                    Menu("Choose primary commitment…") {
                        ForEach(conflict.commitments, id: \.occurrenceID) { commitment in
                            Button(commitment.title) {
                                selectPrimary(commitment)
                            }
                        }
                    }
                }
            } else {
                ProtectionCoverageStatusLabel(
                    presentation: ProtectionCoveragePresentation(state: .primary)
                )
                .font(.caption.weight(.semibold))
                Text("Also in this conflict")
                    .font(.caption.weight(.semibold))
                let secondaryCommitments = conflict.commitments.filter {
                    $0.occurrenceID != conflict.primaryCommitment?.occurrenceID
                }
                ForEach(secondaryCommitments.prefix(3), id: \.occurrenceID) { commitment in
                    Label(commitment.title, systemImage: "calendar")
                        .font(.caption)
                        .lineLimit(2)
                        .help(commitment.title)
                }
                if secondaryCommitments.count > 3 {
                    Text("+\(secondaryCommitments.count - 3) more protected commitments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("The primary commitment appears in the menu bar; every commitment remains protected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func selectPrimary(_ commitment: CalendarEvent) {
        if flow.selectPrimary(for: commitment) {
            announceActionResult(flow.lastActionMessage)
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @EnvironmentObject private var onboardingState: OnboardingState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var customPauseExpiration = Date().addingTimeInterval(60 * 60)
    @State private var isCustomPausePresented = false

    var body: some View {
        VStack(spacing: 0) {
            primaryContent
                .padding(.horizontal, 16)
                .padding(.vertical, 16)

            if hasSupplementalContent {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    supplementalContent
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            Divider()
            utilityFooter
        }
        .frame(width: 336)
        .sheet(isPresented: $isCustomPausePresented) {
            CustomPauseSheet(
                expiration: $customPauseExpiration,
                pause: { duration in
                    let didPause = flow.pause(for: duration)
                    if didPause {
                        announceActionResult(flow.lastActionMessage)
                    }
                    return didPause
                }
            )
        }
        .onAppear {
            flow.refreshLaunchAtLoginStatus()
            if customPauseExpiration <= Date() {
                customPauseExpiration = Date().addingTimeInterval(60 * 60)
            }
        }
    }

    @ViewBuilder
    private var primaryContent: some View {
        if let commitment = flow.upcomingCommitment {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                upcomingCommitmentContent(commitment, at: context.date)
            }
        } else if let conflict = flow.strongAlertConflict {
            MenuBarConflictView(flow: flow, conflict: conflict)
        } else if hasRestorableDecision {
            decisionTimeline
        } else {
            protectionStatusTimeline
        }
    }

    private func upcomingCommitmentContent(_ commitment: CalendarEvent, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)

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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Next commitment, \(commitment.title), \(flow.countdownText(for: commitment, at: date)), \(flow.localStartTimeText(for: commitment))"
            )

            if flow.earlyReminderCommitment != nil {
                Button("Open Early Reminder") {
                    openEarlyReminderIfNeeded(flow: flow) {
                        openWindow(id: "early-reminder")
                    }
                }
                .keyboardShortcut("r")
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var supplementalContent: some View {
        if flow.upcomingCommitment != nil,
           let conflict = flow.strongAlertConflict ?? flow.upcomingConflict {
            MenuBarConflictView(flow: flow, conflict: conflict)
        }

        if showsProtectionStatusInSupplementalContent {
            protectionStatusTimeline
        }

        if hasRestorableDecision && !isDecisionPrimary {
            decisionTimeline
        }

        if !visibleAccountIssues.isEmpty {
            accountIssuesContent
        }
    }

    @ViewBuilder
    private var decisionContent: some View {
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
        }
    }

    private var decisionTimeline: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { _ in
            decisionContent
        }
    }

    private var protectionStatusTimeline: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            protectionStatusContent(at: context.date)
        }
    }

    private func protectionStatusContent(at date: Date) -> some View {
        let presentation = protectionPresentation(at: date)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: presentation.systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(presentation.tone.color)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(.headline)
                    Text(presentation.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if presentation.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(presentation.title). \(presentation.detail)")

            if let primaryAction = presentation.primaryAction {
                primaryActionButton(primaryAction)
            } else if flow.status == .active && !flow.isPaused(at: date) {
                pauseMenu
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func primaryActionButton(_ action: MenuBarProtectionPresentation.PrimaryAction) -> some View {
        switch action {
        case .finishSetup:
            Button("Finish Setup…") {
                showOnboarding()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)

        case .openSettings:
            Button("Open Settings…") {
                showSettings()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)

        case .reconnect(let accountID):
            Button("Reconnect Google Calendar…") {
                reconnect(accountID: accountID)
            }
            .disabled(flow.isConnectingAccount)
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    private var pauseMenu: some View {
        Menu {
            Button("Pause all for 1 hour") {
                pause(.oneHour)
            }
            .keyboardShortcut("1")
            Button("Pause all until end of day") {
                pause(.endOfDay)
            }
            .keyboardShortcut("e")
            Button("Choose when to resume…") {
                customPauseExpiration = Date().addingTimeInterval(60 * 60)
                isCustomPausePresented = true
            }
            .keyboardShortcut("c")
        } label: {
            Label("Pause All Protection", systemImage: "pause.circle")
        }
        .menuStyle(.button)
        .accessibilityHint(InterfaceCopy.pauseAllProtectionDetail())
    }

    private var accountIssuesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(visibleAccountIssues) { coverage in
                accountIssueRow(coverage)
            }

            if remainingAccountIssueCount > 0 {
                Button("Review \(remainingAccountIssueCount) more in Settings…") {
                    showSettings()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountIssueRow(_ coverage: AccountCoverage) -> some View {
        let health = effectiveHealth(for: coverage)
        let presentation = ProtectionCoveragePresentation.account(
            health,
            requiresReconnect: coverage.connectionState == .reconnectRequired
        )
        let detail = accountIssueDetail(for: presentation, health: health)
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: presentation.systemImage)
                .foregroundStyle(presentation.tone.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(accountLabel(for: coverage))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .help(accountLabel(for: coverage))
                HStack(spacing: 5) {
                    Text(
                        detail == presentation.label
                            ? presentation.label
                            : "\(presentation.label) · \(detail)"
                    )
                    if presentation.showsProgress {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    }
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if flow.connectingAccountID == coverage.account.id {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            } else if coverage.connectionState == .reconnectRequired || health == .reconnectRequired {
                Button("Reconnect…") {
                    reconnect(accountID: coverage.account.id)
                }
                .disabled(flow.isConnectingAccount)
                .controlSize(.small)
                .accessibilityLabel("Reconnect \(accountLabel(for: coverage))")
            }
        }
        .help(accountIssueHelp(for: coverage, presentation: presentation))
        .accessibilityElement(children: .contain)
    }

    private var utilityFooter: some View {
        HStack(spacing: 10) {
            Button {
                showSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",")

            Divider()
                .frame(height: 18)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit \(AppIdentity.displayName)", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private var hasSupplementalContent: Bool {
        let hasUpcomingConflict = flow.upcomingCommitment != nil &&
            (flow.strongAlertConflict != nil || flow.upcomingConflict != nil)
        return hasUpcomingConflict ||
            showsProtectionStatusInSupplementalContent ||
            (hasRestorableDecision && !isDecisionPrimary) ||
            !visibleAccountIssues.isEmpty
    }

    private var showsProtectionStatusInSupplementalContent: Bool {
        flow.upcomingCommitment != nil || flow.strongAlertConflict != nil || isDecisionPrimary
    }

    private var hasRestorableDecision: Bool {
        flow.decisionCommitment != nil && flow.currentCommitmentDecision?.isRestorable == true
    }

    private var isDecisionPrimary: Bool {
        flow.upcomingCommitment == nil && flow.strongAlertConflict == nil && hasRestorableDecision
    }

    private var visibleAccountIssues: [AccountCoverage] {
        Array(accountIssues.prefix(3))
    }

    private var remainingAccountIssueCount: Int {
        max(accountIssues.count - visibleAccountIssues.count, 0)
    }

    private var accountIssues: [AccountCoverage] {
        guard flow.status != .noCoverage,
              !flow.isRestoringConnection,
              !flow.isCheckingCoverage else {
            return []
        }

        let consumedReconnectAccountID: String?
        if case .reconnect(let accountID) = protectionPresentation(at: Date()).primaryAction {
            consumedReconnectAccountID = accountID
        } else {
            consumedReconnectAccountID = nil
        }

        return flow.accountCoverages.filter { coverage in
            effectiveHealth(for: coverage) != .fresh &&
                coverage.account.id != consumedReconnectAccountID
        }
    }

    private func protectionPresentation(at date: Date) -> MenuBarProtectionPresentation {
        MenuBarProtectionPresentation.make(
            isRestoringConnection: flow.isRestoringConnection,
            needsSetup: onboardingState.needsSetup,
            status: flow.status,
            isCheckingCoverage: flow.isCheckingCoverage || flow.isConnectingAccount,
            isPaused: flow.isPaused(at: date),
            pauseDetail: flow.pauseExpirationText(at: date),
            isLaunchAtLoginEnabled: flow.isLaunchAtLoginEnabled,
            hasUpcomingCommitment: flow.upcomingCommitment != nil,
            accounts: flow.accountCoverages.map { coverage in
                MenuBarAccountPresentation(
                    id: coverage.account.id,
                    label: accountLabel(for: coverage),
                    connectionState: coverage.connectionState,
                    health: effectiveHealth(for: coverage)
                )
            },
            confirmation: .global(flow.accountCoverages)
        )
    }

    private func effectiveHealth(for coverage: AccountCoverage) -> CoverageHealth {
        flow.coverage(for: coverage.account.id) ?? coverage.health
    }

    private func accountIssueDetail(
        for presentation: ProtectionCoveragePresentation,
        health: CoverageHealth
    ) -> String {
        if presentation.state == .reconnectRequired {
            return presentation.label
        }

        switch health {
        case .noCoverage:
            return "No Monitored Calendars"
        case .checking:
            return "Checking calendar coverage…"
        case .fresh:
            return "Coverage is current"
        case .stale:
            return "Calendar data is out of date"
        case .reconnectRequired:
            return presentation.label
        case .unavailable:
            return "Refresh failed; retrying automatically"
        }
    }

    private func accountIssueHelp(
        for coverage: AccountCoverage,
        presentation: ProtectionCoveragePresentation
    ) -> String {
        if presentation.state == .reconnectRequired {
            return reconnectCoverageWarning(accountLabel: accountLabel(for: coverage))
        }
        return flow.coverageWarning(for: coverage.account.id) ?? presentation.label
    }

    private func accountLabel(for coverage: AccountCoverage) -> String {
        InterfaceCopy.connectedAccountLabel(
            email: coverage.account.email,
            displayName: coverage.account.displayName
        )
    }

    private func pause(_ duration: PauseDuration) {
        if flow.pause(for: duration) {
            announceActionResult(flow.lastActionMessage)
        }
    }

    private func reconnect(accountID: String) {
        Task {
            await flow.reconnectGoogleAccount(accountID: accountID)
        }
    }

    private func showOnboarding() {
        onboardingState.resume()
        OnboardingWindowController.shared.show {
            openWindow(id: "onboarding")
        }
    }

    private func showSettings() {
        ApplicationWindowPresenter.shared.showSettings {
            openSettings()
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
}

private struct MenuBarLabel: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var testToolsController: TestToolsController
    @EnvironmentObject private var resetCoordinator: AppManagedDataResetCoordinator
    @ObservedObject var productionFlow: CommitmentProtectionFlow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let presentation = menuBarStatusPresentation
        Label(
            testToolsController.isTestMode
                ? "TEST · \(presentation.label)"
                : presentation.label,
            systemImage: presentation.systemImage
        )
        .background {
            TestToolsCommandBridge(controller: testToolsController)
        }
        .onAppear {
            presentInitialOnboardingIfNeeded()
            updateEarlyReminderSurface()
            updateStrongAlertSurface()
            if testToolsController.recoveryReport != nil {
                showTestTools()
            }
        }
        .onChange(of: onboardingState.initialSurface) { previousSurface, surface in
            presentInitialOnboardingIfNeeded()
            guard previousSurface == .waiting, surface != .waiting else { return }
            presentResolvedInitialSurface()
        }
        .onChange(of: flow.earlyReminderCommitment) { _, commitment in
            updateEarlyReminderSurface()
        }
        .onChange(of: flow.isStrongAlertPresented) { _, isPresented in
            updateStrongAlertSurface()
        }
        .onChange(of: productionFlow.earlyReminderCommitment) { _, _ in
            updateEarlyReminderSurface()
        }
        .onChange(of: productionFlow.isStrongAlertPresented) { _, _ in
            updateStrongAlertSurface()
        }
        .onChange(of: resetCoordinator.state) { _, state in
            switch state {
            case .blocked, .unavailable:
                showTestTools()
            case .idle, .recovering, .executing, .completed:
                break
            }
        }
        .onChange(of: testToolsController.recoveryReport) { _, report in
            if report != nil {
                showTestTools()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            presentApplicationWindowAfterCurrentEvent()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .inYourFaceApplicationDidRequestReopen
        )) { _ in
            presentReopenedApplicationWindowAfterCurrentEvent()
        }
    }

    private func presentResolvedInitialSurface() {
        let triggeringWindow = NSApp.currentEvent?.window
        Task { @MainActor in
            await Task.yield()
            ApplicationWindowPresenter.shared.initialSurfaceDidResolve(
                initialSurface: onboardingState.initialSurface,
                isApplicationActive: NSApp.isActive,
                hasEarlyReminder: hasEarlyReminder,
                hasStrongAlert: hasStrongAlert,
                triggeringWindow: triggeringWindow
            ) {
                openSettings()
            }
        }
    }

    private func presentApplicationWindowAfterCurrentEvent() {
        let triggeringWindow = NSApp.currentEvent?.window
        Task { @MainActor in
            await Task.yield()
            ApplicationWindowPresenter.shared.applicationDidBecomeActive(
                initialSurface: onboardingState.initialSurface,
                hasEarlyReminder: hasEarlyReminder,
                hasStrongAlert: hasStrongAlert,
                triggeringWindow: triggeringWindow
            ) {
                openSettings()
            }
        }
    }

    private func presentReopenedApplicationWindowAfterCurrentEvent() {
        let triggeringWindow = NSApp.currentEvent?.window
        Task { @MainActor in
            await Task.yield()
            ApplicationWindowPresenter.shared.applicationDidRequestReopen(
                initialSurface: onboardingState.initialSurface,
                hasEarlyReminder: hasEarlyReminder,
                hasStrongAlert: hasStrongAlert,
                triggeringWindow: triggeringWindow
            ) {
                openSettings()
            }
        }
    }

    private func presentInitialOnboardingIfNeeded() {
        guard onboardingState.initialSurface == .onboarding else { return }
        OnboardingWindowController.shared.showAtLaunch {
            openWindow(id: "onboarding")
        }
    }

    private var alertFlow: CommitmentProtectionFlow {
        if productionHasPriorityAlert {
            return productionFlow
        }
        return flow
    }

    private var productionHasPriorityAlert: Bool {
        productionFlow.earlyReminderCommitment != nil ||
            productionFlow.isStrongAlertPresented ||
            productionFlow.strongAlertCommitment != nil
    }

    private var hasEarlyReminder: Bool {
        productionHasPriorityAlert
            ? productionFlow.earlyReminderCommitment != nil
            : flow.earlyReminderCommitment != nil
    }

    private var hasStrongAlert: Bool {
        productionHasPriorityAlert
            ? productionFlow.isStrongAlertPresented
            : flow.isStrongAlertPresented
    }

    private func updateEarlyReminderSurface() {
        guard hasEarlyReminder else {
            EarlyReminderWindowController.shared.close()
            return
        }
        openEarlyReminderIfNeeded(flow: alertFlow) {
            openWindow(id: "early-reminder")
        }
    }

    private func updateStrongAlertSurface() {
        if hasStrongAlert {
            openWindow(id: "strong-alert")
        } else {
            StrongAlertWindowController.shared.close()
        }
    }

    private func showTestTools() {
        testToolsController.testToolsDidOpen()
        openWindow(id: "test-tools")
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            await Task.yield()
            WindowRegistry.shared.window(for: .testTools)?.makeKeyAndOrderFront(nil)
        }
    }

    private var menuBarStatusPresentation: ProtectionCoveragePresentation {
        ProtectionCoveragePresentation.global(
            isRestoringConnection: flow.isRestoringConnection,
            needsSetup: onboardingState.needsSetup,
            status: flow.status,
            isCheckingCoverage: flow.isCheckingCoverage || flow.isConnectingAccount,
            isPaused: flow.isPaused(),
            hasReconnectRequiredAccount: flow.accountCoverages.contains { coverage in
                coverage.connectionState == .reconnectRequired ||
                    (flow.coverage(for: coverage.account.id) ?? coverage.health) == .reconnectRequired
            }
        )
    }
}
