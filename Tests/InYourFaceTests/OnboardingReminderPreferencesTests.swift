import CommitmentProtection
import Foundation
import XCTest
@testable import InYourFace

@MainActor
final class OnboardingReminderPreferencesTests: XCTestCase {
    func testInitialDraftReadsStrongAlertDefaultAndCanDefaultLaunchAtLoginOnWithoutSideEffects() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        let draft = OnboardingReadinessPreferences(
            flow: fixture.flow,
            defaultsLaunchAtLoginToEnabled: true
        )

        XCTAssertEqual(draft.strongAlertRepeatIntervalMinutes, 1)
        XCTAssertTrue(draft.isLaunchAtLoginEnabled)
        XCTAssertFalse(fixture.flow.isLaunchAtLoginEnabled)
        XCTAssertFalse(fixture.launchAtLogin.isEnabled)
        XCTAssertEqual(fixture.launchAtLogin.enableCallCount, 0)
        XCTAssertEqual(fixture.launchAtLogin.disableCallCount, 0)
    }

    func testCommitAppliesStagedPreferencesAndUpdatesMonitoredCalendarProtectionConfirmation() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        await fixture.flow.connectGoogleAccount()
        fixture.flow.setCalendarSelected(
            true,
            calendarID: fixture.workCalendar.id,
            accountID: fixture.account.id
        )
        XCTAssertTrue(fixture.flow.confirmAllProtection())
        fixture.flow.setCalendarSelected(
            true,
            calendarID: fixture.personalCalendar.id,
            accountID: fixture.account.id
        )
        XCTAssertTrue(fixture.flow.isProtectionConfirmationRequired)

        var draft = OnboardingReadinessPreferences(
            flow: fixture.flow,
            defaultsLaunchAtLoginToEnabled: true
        )
        draft.isEarlyReminderEnabled = false
        draft.earlyReminderLeadTimeMinutes = 20
        draft.strongAlertRepeatIntervalMinutes = 5

        XCTAssertFalse(draft.isEarlyReminderEnabled)
        XCTAssertEqual(draft.earlyReminderLeadTimeMinutes, 20)
        XCTAssertEqual(draft.strongAlertRepeatIntervalMinutes, 5)
        XCTAssertTrue(draft.isLaunchAtLoginEnabled)

        XCTAssertTrue(fixture.flow.isEarlyReminderEnabled)
        XCTAssertEqual(fixture.flow.earlyReminderLeadTimeMinutes, 10)
        XCTAssertEqual(fixture.flow.strongAlertRepeatIntervalMinutes, 1)
        XCTAssertFalse(fixture.flow.isLaunchAtLoginEnabled)
        XCTAssertEqual(fixture.launchAtLogin.enableCallCount, 0)

        XCTAssertTrue(draft.commit(to: fixture.flow))

        XCTAssertFalse(fixture.flow.isEarlyReminderEnabled)
        XCTAssertEqual(fixture.flow.earlyReminderLeadTimeMinutes, 20)
        XCTAssertEqual(fixture.flow.strongAlertRepeatIntervalMinutes, 5)
        XCTAssertTrue(fixture.flow.isLaunchAtLoginEnabled)
        XCTAssertEqual(fixture.launchAtLogin.enableCallCount, 1)
        XCTAssertEqual(fixture.launchAtLogin.disableCallCount, 0)
        XCTAssertFalse(fixture.flow.isProtectionConfirmationRequired)
        XCTAssertTrue(fixture.flow.isProtectionConfirmed(for: fixture.account.id))
    }

    func testExplicitLaunchAtLoginOptOutDoesNotEnableIt() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        var draft = OnboardingReadinessPreferences(
            flow: fixture.flow,
            defaultsLaunchAtLoginToEnabled: true
        )
        draft.isLaunchAtLoginEnabled = false

        XCTAssertTrue(draft.commit(to: fixture.flow))

        XCTAssertFalse(fixture.flow.isLaunchAtLoginEnabled)
        XCTAssertFalse(fixture.launchAtLogin.isEnabled)
        XCTAssertEqual(fixture.launchAtLogin.enableCallCount, 0)
        XCTAssertEqual(fixture.launchAtLogin.disableCallCount, 0)
    }

    func testLaunchAtLoginFailureRejectsCommitWithoutApplyingReminderTiming() {
        let fixture = makeFixture(enableFailure: OnboardingLaunchAtLoginError.enableFailed)
        defer { fixture.cleanUp() }

        var draft = OnboardingReadinessPreferences(
            flow: fixture.flow,
            defaultsLaunchAtLoginToEnabled: true
        )
        draft.isEarlyReminderEnabled = false
        draft.earlyReminderLeadTimeMinutes = 20
        draft.strongAlertRepeatIntervalMinutes = 5

        XCTAssertFalse(draft.commit(to: fixture.flow))

        XCTAssertFalse(fixture.flow.isLaunchAtLoginEnabled)
        XCTAssertFalse(fixture.launchAtLogin.isEnabled)
        XCTAssertNotNil(fixture.flow.launchAtLoginError)
        XCTAssertEqual(fixture.launchAtLogin.enableCallCount, 1)
        XCTAssertEqual(fixture.launchAtLogin.disableCallCount, 0)
        XCTAssertTrue(fixture.flow.isEarlyReminderEnabled)
        XCTAssertEqual(fixture.flow.earlyReminderLeadTimeMinutes, 10)
        XCTAssertEqual(fixture.flow.strongAlertRepeatIntervalMinutes, 1)
    }

    func testLaunchAtLoginOptOutFailureRejectsCommitWithoutApplyingReminderTiming() {
        let fixture = makeFixture(
            disableFailure: OnboardingLaunchAtLoginError.disableFailed,
            isLaunchAtLoginEnabled: true
        )
        defer { fixture.cleanUp() }
        let draft = OnboardingReadinessPreferences(
            isEarlyReminderEnabled: false,
            earlyReminderLeadTimeMinutes: 20,
            strongAlertRepeatIntervalMinutes: 5,
            isLaunchAtLoginEnabled: false
        )

        XCTAssertFalse(draft.commit(to: fixture.flow))

        XCTAssertTrue(fixture.flow.isLaunchAtLoginEnabled)
        XCTAssertTrue(fixture.launchAtLogin.isEnabled)
        XCTAssertNotNil(fixture.flow.launchAtLoginError)
        XCTAssertEqual(fixture.launchAtLogin.enableCallCount, 0)
        XCTAssertEqual(fixture.launchAtLogin.disableCallCount, 1)
        XCTAssertTrue(fixture.flow.isEarlyReminderEnabled)
        XCTAssertEqual(fixture.flow.earlyReminderLeadTimeMinutes, 10)
        XCTAssertEqual(fixture.flow.strongAlertRepeatIntervalMinutes, 1)
    }

    func testContinueSetupDoesNotMutateReadinessOrProtectionState() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        await prepareConfirmedProtection(fixture)
        let onboardingState = makePendingOnboardingState(fixture)
        var draft = OnboardingReadinessPreferences(
            flow: fixture.flow,
            defaultsLaunchAtLoginToEnabled: true
        )
        draft.isEarlyReminderEnabled = false
        draft.earlyReminderLeadTimeMinutes = 20
        draft.strongAlertRepeatIntervalMinutes = 5
        draft.isLaunchAtLoginEnabled = true
        let storedState = fixture.stateStore.dictionaryRepresentation()
        let selectedCalendarIDs = fixture.flow.selectedCalendarIDs(for: fixture.account.id)
        let isProtectionConfirmed = fixture.flow.isProtectionConfirmed(for: fixture.account.id)
        let activityCount = fixture.flow.activityLog.count

        XCTAssertFalse(OnboardingReadinessOutcomeResolver.resolve(
            .continueSetup,
            preferences: draft,
            isReconnectRequired: false,
            flow: fixture.flow,
            onboardingState: onboardingState
        ))

        XCTAssertEqual(onboardingState.phase, .pending)
        XCTAssertEqual(
            fixture.flow.selectedCalendarIDs(for: fixture.account.id),
            selectedCalendarIDs
        )
        XCTAssertEqual(
            fixture.flow.isProtectionConfirmed(for: fixture.account.id),
            isProtectionConfirmed
        )
        XCTAssertEqual(fixture.flow.activityLog.count, activityCount)
        XCTAssertEqual(fixture.launchAtLogin.enableCallCount, 0)
        XCTAssertEqual(fixture.launchAtLogin.disableCallCount, 0)
        XCTAssertTrue(
            NSDictionary(dictionary: storedState).isEqual(
                to: fixture.stateStore.dictionaryRepresentation()
            )
        )
        XCTAssertEqual(draft, OnboardingReadinessPreferences(
            isEarlyReminderEnabled: false,
            earlyReminderLeadTimeMinutes: 20,
            strongAlertRepeatIntervalMinutes: 5,
            isLaunchAtLoginEnabled: true
        ))
    }

    func testFinishLaterAppliesEveryStagedValueAndResumesWithThePersistedDraft() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        await prepareConfirmedProtection(fixture)
        let onboardingState = makePendingOnboardingState(fixture)
        let draft = OnboardingReadinessPreferences(
            isEarlyReminderEnabled: false,
            earlyReminderLeadTimeMinutes: 20,
            strongAlertRepeatIntervalMinutes: 5,
            isLaunchAtLoginEnabled: false
        )

        XCTAssertTrue(OnboardingReadinessOutcomeResolver.resolve(
            .finishLater,
            preferences: draft,
            isReconnectRequired: false,
            flow: fixture.flow,
            onboardingState: onboardingState
        ))

        XCTAssertFalse(fixture.flow.isEarlyReminderEnabled)
        XCTAssertEqual(fixture.flow.earlyReminderLeadTimeMinutes, 20)
        XCTAssertEqual(fixture.flow.strongAlertRepeatIntervalMinutes, 5)
        XCTAssertFalse(fixture.flow.isLaunchAtLoginEnabled)
        XCTAssertEqual(onboardingState.phase, .deferred)
        XCTAssertTrue(onboardingState.didChooseLaunchAtLogin)
        XCTAssertTrue(onboardingState.needsSetup)

        onboardingState.resume()

        XCTAssertEqual(onboardingState.phase, .pending)
        XCTAssertEqual(onboardingState.initialSurface, .onboarding)
        XCTAssertEqual(
            OnboardingReadinessPreferences(
                flow: fixture.flow,
                defaultsLaunchAtLoginToEnabled: !onboardingState.didChooseLaunchAtLogin
            ),
            draft
        )
    }

    func testFinishLaterStillAppliesEveryStagedValueWhenReconnectIsRequired() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        await prepareConfirmedProtection(fixture)
        fixture.flow.setCalendarSelected(
            true,
            calendarID: fixture.personalCalendar.id,
            accountID: fixture.account.id
        )
        XCTAssertTrue(fixture.flow.isProtectionConfirmationRequired)
        let didDisconnect = await fixture.flow.disconnectGoogleAccount(
            accountID: fixture.account.id
        )
        XCTAssertTrue(didDisconnect)
        XCTAssertEqual(fixture.flow.connectionState, .reconnectRequired)
        XCTAssertTrue(fixture.flow.isProtectionConfirmationRequired)
        let onboardingState = makePendingOnboardingState(fixture)
        let draft = OnboardingReadinessPreferences(
            isEarlyReminderEnabled: false,
            earlyReminderLeadTimeMinutes: 30,
            strongAlertRepeatIntervalMinutes: 4,
            isLaunchAtLoginEnabled: true
        )

        XCTAssertTrue(OnboardingReadinessOutcomeResolver.resolve(
            .finishLater,
            preferences: draft,
            isReconnectRequired: true,
            flow: fixture.flow,
            onboardingState: onboardingState
        ))

        XCTAssertFalse(fixture.flow.isEarlyReminderEnabled)
        XCTAssertEqual(fixture.flow.earlyReminderLeadTimeMinutes, 30)
        XCTAssertEqual(fixture.flow.strongAlertRepeatIntervalMinutes, 4)
        XCTAssertTrue(fixture.flow.isLaunchAtLoginEnabled)
        XCTAssertEqual(fixture.launchAtLogin.enableCallCount, 1)
        XCTAssertTrue(fixture.flow.isProtectionConfirmationRequired)
        XCTAssertEqual(
            fixture.flow.selectedCalendarIDs(for: fixture.account.id),
            Set([fixture.workCalendar.id, fixture.personalCalendar.id])
        )
        XCTAssertEqual(onboardingState.phase, .deferred)
        XCTAssertTrue(onboardingState.needsSetup)
    }

    func testFinishSetupAppliesEveryStagedValueAndCompletesOnboarding() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        await prepareConfirmedProtection(fixture)
        let onboardingState = makePendingOnboardingState(fixture)
        let draft = OnboardingReadinessPreferences(
            isEarlyReminderEnabled: false,
            earlyReminderLeadTimeMinutes: 15,
            strongAlertRepeatIntervalMinutes: 3,
            isLaunchAtLoginEnabled: true
        )

        XCTAssertTrue(OnboardingReadinessOutcomeResolver.resolve(
            .finishSetup,
            preferences: draft,
            isReconnectRequired: false,
            flow: fixture.flow,
            onboardingState: onboardingState
        ))

        XCTAssertFalse(fixture.flow.isEarlyReminderEnabled)
        XCTAssertEqual(fixture.flow.earlyReminderLeadTimeMinutes, 15)
        XCTAssertEqual(fixture.flow.strongAlertRepeatIntervalMinutes, 3)
        XCTAssertTrue(fixture.flow.isLaunchAtLoginEnabled)
        XCTAssertEqual(onboardingState.phase, .completed)
        XCTAssertTrue(onboardingState.didChooseLaunchAtLogin)

        let relaunchedState = OnboardingState(stateStore: fixture.stateStore)
        relaunchedState.resolveInitialLaunch(hasConfiguredProtection: true)
        XCTAssertEqual(relaunchedState.initialSurface, .menuBarOnly)
        XCTAssertFalse(relaunchedState.needsSetup)
    }

    func testReadinessOutcomeFailureKeepsTheDraftAndPhasePending() {
        let fixture = makeFixture(enableFailure: OnboardingLaunchAtLoginError.enableFailed)
        defer { fixture.cleanUp() }
        let onboardingState = makePendingOnboardingState(fixture)
        let draft = OnboardingReadinessPreferences(
            isEarlyReminderEnabled: false,
            earlyReminderLeadTimeMinutes: 20,
            strongAlertRepeatIntervalMinutes: 5,
            isLaunchAtLoginEnabled: true
        )

        XCTAssertFalse(OnboardingReadinessOutcomeResolver.resolve(
            .finishLater,
            preferences: draft,
            isReconnectRequired: false,
            flow: fixture.flow,
            onboardingState: onboardingState
        ))

        XCTAssertEqual(onboardingState.phase, .pending)
        XCTAssertEqual(draft, OnboardingReadinessPreferences(
            isEarlyReminderEnabled: false,
            earlyReminderLeadTimeMinutes: 20,
            strongAlertRepeatIntervalMinutes: 5,
            isLaunchAtLoginEnabled: true
        ))
        XCTAssertTrue(fixture.flow.isEarlyReminderEnabled)
        XCTAssertEqual(fixture.flow.earlyReminderLeadTimeMinutes, 10)
        XCTAssertEqual(fixture.flow.strongAlertRepeatIntervalMinutes, 1)
    }

    func testMutationGateFailureDoesNotCommitOrCompleteReadiness() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let onboardingState = OnboardingState(
            stateStore: fixture.stateStore,
            allowsPreferenceMutation: { false }
        )
        let draft = OnboardingReadinessPreferences(
            isEarlyReminderEnabled: false,
            earlyReminderLeadTimeMinutes: 20,
            strongAlertRepeatIntervalMinutes: 5,
            isLaunchAtLoginEnabled: true
        )

        XCTAssertFalse(OnboardingReadinessOutcomeResolver.resolve(
            .finishSetup,
            preferences: draft,
            isReconnectRequired: false,
            flow: fixture.flow,
            onboardingState: onboardingState
        ))

        XCTAssertEqual(onboardingState.phase, .pending)
        XCTAssertFalse(onboardingState.didChooseLaunchAtLogin)
        XCTAssertTrue(fixture.flow.isEarlyReminderEnabled)
        XCTAssertEqual(fixture.flow.earlyReminderLeadTimeMinutes, 10)
        XCTAssertEqual(fixture.flow.strongAlertRepeatIntervalMinutes, 1)
        XCTAssertFalse(fixture.flow.isLaunchAtLoginEnabled)
        XCTAssertEqual(fixture.launchAtLogin.enableCallCount, 0)
    }

    func testCompletionMutationGateFailureAfterCommitDoesNotCompleteReadiness() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        var mutationCheckCount = 0
        let onboardingState = OnboardingState(
            stateStore: fixture.stateStore,
            allowsPreferenceMutation: {
                mutationCheckCount += 1
                return mutationCheckCount == 1
            }
        )
        let draft = OnboardingReadinessPreferences(
            isEarlyReminderEnabled: false,
            earlyReminderLeadTimeMinutes: 20,
            strongAlertRepeatIntervalMinutes: 5,
            isLaunchAtLoginEnabled: false
        )

        XCTAssertFalse(OnboardingReadinessOutcomeResolver.resolve(
            .finishSetup,
            preferences: draft,
            isReconnectRequired: false,
            flow: fixture.flow,
            onboardingState: onboardingState
        ))

        XCTAssertEqual(mutationCheckCount, 2)
        XCTAssertEqual(onboardingState.phase, .pending)
        XCTAssertFalse(onboardingState.didChooseLaunchAtLogin)
        XCTAssertEqual(draft, OnboardingReadinessPreferences(
            isEarlyReminderEnabled: false,
            earlyReminderLeadTimeMinutes: 20,
            strongAlertRepeatIntervalMinutes: 5,
            isLaunchAtLoginEnabled: false
        ))
    }

    func testFlowResetMutationGateRejectsReadinessCommit() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let draft = OnboardingReadinessPreferences(
            isEarlyReminderEnabled: false,
            earlyReminderLeadTimeMinutes: 20,
            strongAlertRepeatIntervalMinutes: 5,
            isLaunchAtLoginEnabled: false
        )
        fixture.flow.lockMutationsForAppManagedDataReset()
        defer { fixture.flow.unlockMutationsForAppManagedDataReset() }

        XCTAssertFalse(draft.commit(to: fixture.flow))
        XCTAssertTrue(fixture.flow.isEarlyReminderEnabled)
        XCTAssertEqual(fixture.flow.earlyReminderLeadTimeMinutes, 10)
        XCTAssertEqual(fixture.flow.strongAlertRepeatIntervalMinutes, 1)
    }

    private func prepareConfirmedProtection(
        _ fixture: OnboardingReminderPreferencesFixture
    ) async {
        await fixture.flow.connectGoogleAccount()
        fixture.flow.setCalendarSelected(
            true,
            calendarID: fixture.workCalendar.id,
            accountID: fixture.account.id
        )
        XCTAssertTrue(fixture.flow.confirmAllProtection())
    }

    private func makePendingOnboardingState(
        _ fixture: OnboardingReminderPreferencesFixture
    ) -> OnboardingState {
        let state = OnboardingState(stateStore: fixture.stateStore)
        state.resolveInitialLaunch(hasConfiguredProtection: false)
        return state
    }

    private func makeFixture(
        enableFailure: Error? = nil,
        disableFailure: Error? = nil,
        isLaunchAtLoginEnabled: Bool = false
    ) -> OnboardingReminderPreferencesFixture {
        OnboardingReminderPreferencesFixture(
            enableFailure: enableFailure,
            disableFailure: disableFailure,
            isLaunchAtLoginEnabled: isLaunchAtLoginEnabled
        )
    }
}

@MainActor
private struct OnboardingReminderPreferencesFixture {
    let suiteName: String
    let stateStore: UserDefaults
    let account: GoogleAccount
    let workCalendar: CalendarOption
    let personalCalendar: CalendarOption
    let launchAtLogin: OnboardingLaunchAtLoginController
    let flow: CommitmentProtectionFlow

    init(
        enableFailure: Error? = nil,
        disableFailure: Error? = nil,
        isLaunchAtLoginEnabled: Bool = false
    ) {
        suiteName = "OnboardingReminderPreferencesTests.\(UUID().uuidString)"
        stateStore = UserDefaults(suiteName: suiteName)!
        stateStore.removePersistentDomain(forName: suiteName)

        account = GoogleAccount(
            id: "account-1",
            email: "alex@example.com",
            displayName: "Alex"
        )
        workCalendar = CalendarOption(
            id: "calendar-work",
            name: "Work",
            accountID: account.id
        )
        personalCalendar = CalendarOption(
            id: "calendar-personal",
            name: "Personal",
            accountID: account.id
        )
        launchAtLogin = OnboardingLaunchAtLoginController(
            isEnabled: isLaunchAtLoginEnabled,
            enableFailure: enableFailure,
            disableFailure: disableFailure
        )
        flow = CommitmentProtectionFlow(
            calendarConnector: OnboardingCalendarConnector(
                connection: GoogleCalendarConnection(
                    account: account,
                    calendars: [workCalendar, personalCalendar]
                )
            ),
            launchAtLogin: launchAtLogin,
            stateStore: stateStore
        )
    }

    func cleanUp() {
        stateStore.removePersistentDomain(forName: suiteName)
    }
}

private struct OnboardingCalendarConnector: GoogleCalendarConnecting {
    let connection: GoogleCalendarConnection

    func connect() async throws -> GoogleCalendarConnection {
        connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        accountID == connection.account.id ? connection : nil
    }

    func disconnect(accountID: String) throws {}

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        []
    }
}

@MainActor
private final class OnboardingLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool
    private let enableFailure: Error?
    private let disableFailure: Error?
    private(set) var enableCallCount = 0
    private(set) var disableCallCount = 0

    init(
        isEnabled: Bool = false,
        enableFailure: Error? = nil,
        disableFailure: Error? = nil
    ) {
        self.isEnabled = isEnabled
        self.enableFailure = enableFailure
        self.disableFailure = disableFailure
    }

    func enable() throws {
        enableCallCount += 1
        if let enableFailure {
            throw enableFailure
        }
        isEnabled = true
    }

    func disable() throws {
        disableCallCount += 1
        if let disableFailure {
            throw disableFailure
        }
        isEnabled = false
    }
}

private enum OnboardingLaunchAtLoginError: Error {
    case enableFailed
    case disableFailed
}
