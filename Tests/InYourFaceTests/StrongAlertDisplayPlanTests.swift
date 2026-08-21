import XCTest
import CommitmentProtection
@testable import InYourFace

final class StrongAlertDisplayPlanTests: XCTestCase {
    func testPresentationLifecycleDoesNotPresentWithoutAUsableSurface() {
        var lifecycle = AlertPresentationLifecycle()

        XCTAssertNil(
            lifecycle.present(
                surface: .strongAlert,
                displayCount: 0,
                primaryIndex: nil,
                surfaceDiscovered: true
            )
        )
        XCTAssertFalse(lifecycle.isPresented)
        XCTAssertTrue(lifecycle.requiresSurfaceRecovery)

        let recoveredPlan = lifecycle.displayTopologyChanged(displayCount: 1, primaryIndex: 0)
        XCTAssertEqual(recoveredPlan?.primaryIndex, 0)
        XCTAssertTrue(lifecycle.isPresented)
        XCTAssertFalse(lifecycle.requiresSurfaceRecovery)

        XCTAssertNil(lifecycle.displayTopologyChanged(displayCount: 0, primaryIndex: nil))
        XCTAssertFalse(lifecycle.isPresented)
        XCTAssertTrue(lifecycle.requiresSurfaceRecovery)

        lifecycle.surfaceDisappeared()
        XCTAssertFalse(lifecycle.hasDiscoveredSurface)
        XCTAssertTrue(lifecycle.requiresSurfaceCreation)

        let unavailableRecoveryPlan = lifecycle.displayTopologyChanged(displayCount: 1, primaryIndex: 0)
        XCTAssertEqual(unavailableRecoveryPlan?.primaryIndex, 0)
        XCTAssertFalse(lifecycle.isPresented)
        XCTAssertTrue(lifecycle.requiresSurfaceRecovery)

        XCTAssertNil(
            lifecycle.present(
                surface: .strongAlert,
                displayCount: 1,
                primaryIndex: 0,
                surfaceDiscovered: false
            )
        )
        XCTAssertTrue(lifecycle.requiresSurfaceCreation)
        XCTAssertTrue(lifecycle.requiresSurfaceRecovery)
    }

    func testPresentationLifecycleTracksCoverageActivationAndTopologyChanges() {
        var lifecycle = AlertPresentationLifecycle()

        let initialPlan = lifecycle.present(
            surface: .strongAlert,
            displayCount: 2,
            primaryIndex: 1,
            surfaceDiscovered: true
        )
        XCTAssertEqual(initialPlan?.primaryIndex, 1)
        XCTAssertEqual(initialPlan?.additionalIndices, [0])
        XCTAssertEqual(lifecycle.availableDisplayCount, 2)
        XCTAssertEqual(lifecycle.primaryDisplayIndex, 1)
        XCTAssertTrue(lifecycle.isPresented)
        XCTAssertTrue(lifecycle.requiresActivation)

        lifecycle.markActivated()
        XCTAssertFalse(lifecycle.requiresActivation)

        lifecycle.applicationActivationChanged()
        XCTAssertTrue(lifecycle.requiresActivation)

        let changedPlan = lifecycle.displayTopologyChanged(displayCount: 3, primaryIndex: nil)
        XCTAssertEqual(changedPlan?.primaryIndex, 0)
        XCTAssertEqual(Set(changedPlan?.allDisplayIndices ?? []), Set(0..<3))
        XCTAssertEqual(lifecycle.displayPlan?.allDisplayIndices, [0, 1, 2])
    }

    func testPresentationLifecycleKeepsRecoveryUntilAChangedSurfaceIsRecreated() {
        var lifecycle = AlertPresentationLifecycle()

        _ = lifecycle.present(
            surface: .strongAlert,
            displayCount: 2,
            primaryIndex: 1,
            surfaceDiscovered: true
        )
        lifecycle.markActivated()

        lifecycle.surfaceDisappeared()
        lifecycle.applicationActivationChanged()

        XCTAssertFalse(lifecycle.isPresented)
        XCTAssertTrue(lifecycle.requiresSurfaceCreation)
        XCTAssertTrue(lifecycle.requiresSurfaceRecovery)
        XCTAssertFalse(lifecycle.requiresActivation)

        let topologyPlan = lifecycle.displayTopologyChanged(displayCount: 3, primaryIndex: 2)
        XCTAssertEqual(Set(topologyPlan?.allDisplayIndices ?? []), Set(0..<3))
        XCTAssertFalse(lifecycle.isPresented)
        XCTAssertTrue(lifecycle.requiresSurfaceCreation)
        XCTAssertTrue(lifecycle.requiresSurfaceRecovery)

        lifecycle.surfaceReappeared(displayCount: 3, primaryIndex: 2)

        XCTAssertTrue(lifecycle.isPresented)
        XCTAssertFalse(lifecycle.requiresSurfaceCreation)
        XCTAssertFalse(lifecycle.requiresSurfaceRecovery)
        XCTAssertTrue(lifecycle.requiresActivation)

        lifecycle.markActivated()
        lifecycle.close()

        XCTAssertFalse(lifecycle.isPresented)
        XCTAssertNil(lifecycle.surface)
        XCTAssertFalse(lifecycle.requiresSurfaceRecovery)
    }

    func testPresentationLifecycleRecoversDisappearedSurfacesAndCleansUp() {
        var lifecycle = AlertPresentationLifecycle()
        _ = lifecycle.present(
            surface: .earlyReminderFallback,
            displayCount: 1,
            primaryIndex: 0,
            surfaceDiscovered: true
        )

        lifecycle.surfaceDisappeared()

        XCTAssertFalse(lifecycle.isPresented)
        XCTAssertTrue(lifecycle.requiresSurfaceCreation)
        XCTAssertTrue(lifecycle.requiresSurfaceRecovery)

        lifecycle.surfaceReappeared(displayCount: 1, primaryIndex: 0)

        XCTAssertTrue(lifecycle.isPresented)
        XCTAssertFalse(lifecycle.requiresSurfaceCreation)
        XCTAssertFalse(lifecycle.requiresSurfaceRecovery)
        XCTAssertTrue(lifecycle.requiresActivation)

        lifecycle.interactionBarrierAvailabilityChanged(true)
        XCTAssertTrue(lifecycle.isInteractionBarrierAvailable)
        lifecycle.interactionBarrierAvailabilityChanged(false)
        XCTAssertFalse(lifecycle.isInteractionBarrierAvailable)

        lifecycle.close()

        XCTAssertNil(lifecycle.surface)
        XCTAssertFalse(lifecycle.isPresented)
        XCTAssertNil(lifecycle.displayPlan)
        XCTAssertFalse(lifecycle.requiresSurfaceCreation)
        XCTAssertFalse(lifecycle.requiresSurfaceRecovery)
        XCTAssertFalse(lifecycle.requiresActivation)
    }

    func testEarlyReminderLifecycleKeepsVisualFallbackAcrossBarrierAvailabilityChanges() {
        var lifecycle = AlertPresentationLifecycle()
        _ = lifecycle.present(
            surface: .earlyReminderNormal,
            displayCount: 1,
            primaryIndex: 0,
            surfaceDiscovered: true
        )

        lifecycle.interactionBarrierAvailabilityChanged(false)
        XCTAssertTrue(lifecycle.isPresented)
        XCTAssertFalse(lifecycle.isInteractionBarrierAvailable)

        lifecycle.interactionBarrierAvailabilityChanged(true)
        XCTAssertTrue(lifecycle.isPresented)
        XCTAssertTrue(lifecycle.isInteractionBarrierAvailable)

        // A permission or event-tap loss returns to visual-only mode without
        // changing the surface lifecycle or the persisted blocking preference.
        lifecycle.interactionBarrierAvailabilityChanged(false)
        XCTAssertTrue(lifecycle.isPresented)
        XCTAssertFalse(lifecycle.isInteractionBarrierAvailable)

        lifecycle.surfaceDisappeared()
        XCTAssertFalse(lifecycle.isPresented)
        XCTAssertFalse(lifecycle.isInteractionBarrierAvailable)
        XCTAssertTrue(lifecycle.requiresSurfaceRecovery)

        lifecycle.surfaceReappeared(displayCount: 1, primaryIndex: 0)
        XCTAssertTrue(lifecycle.isPresented)
        XCTAssertFalse(lifecycle.isInteractionBarrierAvailable)

        lifecycle.close()
        XCTAssertFalse(lifecycle.isPresented)
        XCTAssertFalse(lifecycle.isInteractionBarrierAvailable)
        XCTAssertNil(lifecycle.surface)
    }

    @MainActor
    func testEarlyReminderActionHandlersKeepNormalAndFallbackCallbacksInParity() {
        var normalActions: [String] = []
        var fallbackActions: [String] = []
        let normal = EarlyReminderActionHandlers(
            clear: {
                normalActions.append("clear")
                return true
            },
            snooze: { minutes in
                normalActions.append("snooze:\(minutes)")
                return true
            },
            dismiss: {
                normalActions.append("dismiss")
                return true
            }
        )
        let fallback = EarlyReminderActionHandlers(
            clear: {
                fallbackActions.append("clear")
                return true
            },
            snooze: { minutes in
                fallbackActions.append("snooze:\(minutes)")
                return true
            },
            dismiss: {
                fallbackActions.append("dismiss")
                return true
            }
        )

        let normalClear = normal.clear()
        let normalSnooze = normal.snooze(5)
        let normalDismiss = normal.dismiss()
        let fallbackClear = fallback.clear()
        let fallbackSnooze = fallback.snooze(5)
        let fallbackDismiss = fallback.dismiss()

        XCTAssertTrue(normalClear)
        XCTAssertTrue(normalSnooze)
        XCTAssertTrue(normalDismiss)
        XCTAssertTrue(fallbackClear)
        XCTAssertTrue(fallbackSnooze)
        XCTAssertTrue(fallbackDismiss)

        XCTAssertEqual(normalActions, fallbackActions)
    }

    @MainActor
    func testEarlyReminderPresentationVariantsDelegateAllActionsToTheFlow() async {
        let normalClear = await makeEarlyReminderTestFlow()
        let fallbackClear = await makeEarlyReminderTestFlow()
        let normalClearActions = EarlyReminderActionHandlers.normal(
            flow: normalClear.flow,
            commitment: normalClear.commitment
        )
        let fallbackClearActions = EarlyReminderActionHandlers.fallback(
            flow: fallbackClear.flow,
            commitment: fallbackClear.commitment
        )
        XCTAssertEqual(normalClearActions.clear(), fallbackClearActions.clear())
        XCTAssertNil(normalClear.flow.earlyReminderCommitment)
        XCTAssertNil(fallbackClear.flow.earlyReminderCommitment)

        let normalSnooze = await makeEarlyReminderTestFlow()
        let fallbackSnooze = await makeEarlyReminderTestFlow()
        let normalSnoozeActions = EarlyReminderActionHandlers.normal(
            flow: normalSnooze.flow,
            commitment: normalSnooze.commitment
        )
        let fallbackSnoozeActions = EarlyReminderActionHandlers.fallback(
            flow: fallbackSnooze.flow,
            commitment: fallbackSnooze.commitment
        )
        XCTAssertEqual(normalSnoozeActions.snooze(5), fallbackSnoozeActions.snooze(5))
        XCTAssertNil(normalSnooze.flow.earlyReminderCommitment)
        XCTAssertNil(fallbackSnooze.flow.earlyReminderCommitment)

        let normalDismiss = await makeEarlyReminderTestFlow()
        let fallbackDismiss = await makeEarlyReminderTestFlow()
        let normalDismissActions = EarlyReminderActionHandlers.normal(
            flow: normalDismiss.flow,
            commitment: normalDismiss.commitment
        )
        let fallbackDismissActions = EarlyReminderActionHandlers.fallback(
            flow: fallbackDismiss.flow,
            commitment: fallbackDismiss.commitment
        )
        XCTAssertEqual(normalDismissActions.dismiss(), fallbackDismissActions.dismiss())
        XCTAssertNil(normalDismiss.flow.earlyReminderCommitment)
        XCTAssertNil(fallbackDismiss.flow.earlyReminderCommitment)
    }

    func testEarlyReminderInteractionBarrierRestoresItsTrackedWindowState() {
        var lifecycle = EarlyReminderInteractionBarrierLifecycle()

        XCTAssertFalse(lifecycle.isAvailable)
        XCTAssertFalse(lifecycle.isActive)
        XCTAssertFalse(lifecycle.restoresWindowInteraction)

        lifecycle.activationFailed()
        XCTAssertFalse(lifecycle.isAvailable)
        XCTAssertFalse(lifecycle.isActive)

        lifecycle.activated(restoresWindowInteraction: true)
        XCTAssertTrue(lifecycle.isAvailable)
        XCTAssertTrue(lifecycle.isActive)
        XCTAssertTrue(lifecycle.restoresWindowInteraction)

        lifecycle.disabledBySystem()
        XCTAssertFalse(lifecycle.isAvailable)
        XCTAssertFalse(lifecycle.isActive)
        XCTAssertFalse(lifecycle.restoresWindowInteraction)

        lifecycle.activated(restoresWindowInteraction: false)
        XCTAssertTrue(lifecycle.isAvailable)
        XCTAssertTrue(lifecycle.isActive)

        lifecycle.deactivated()
        XCTAssertFalse(lifecycle.isAvailable)
        XCTAssertFalse(lifecycle.isActive)
        XCTAssertFalse(lifecycle.restoresWindowInteraction)
    }

    func testStrongAlertLifecycleRecoversAfterTopologyChangeAndCleansUp() {
        var lifecycle = AlertPresentationLifecycle()

        _ = lifecycle.present(
            surface: .strongAlert,
            displayCount: 1,
            primaryIndex: 0,
            surfaceDiscovered: true
        )
        lifecycle.markActivated()

        let topologyPlan = lifecycle.displayTopologyChanged(displayCount: 3, primaryIndex: 2)
        XCTAssertEqual(Set(topologyPlan?.allDisplayIndices ?? []), Set(0..<3))
        XCTAssertTrue(lifecycle.isPresented)

        lifecycle.surfaceDisappeared()
        XCTAssertTrue(lifecycle.requiresSurfaceRecovery)

        lifecycle.surfaceReappeared(displayCount: 3, primaryIndex: 2)
        XCTAssertTrue(lifecycle.isPresented)

        lifecycle.close()
        XCTAssertFalse(lifecycle.isPresented)
        XCTAssertNil(lifecycle.displayPlan)
    }

    func testAlertPresentationVariantsShareFlowActionsAndDisplaySharingVisibility() {
        let normal = AlertPresentationContract(variant: .earlyReminderNormal)
        let fallback = AlertPresentationContract(variant: .earlyReminderFallback)
        let strongAlert = AlertPresentationContract(variant: .strongAlert)
        let conflict = AlertPresentationContract(variant: .strongAlertConflict)

        XCTAssertEqual(normal.actionSource, fallback.actionSource)
        XCTAssertEqual(strongAlert.actionSource, conflict.actionSource)
        XCTAssertTrue(normal.preservesProtectionWhenSurfaceCloses)
        XCTAssertTrue(fallback.preservesProtectionWhenSurfaceCloses)
        XCTAssertTrue(strongAlert.preservesProtectionWhenSurfaceCloses)
        XCTAssertTrue(conflict.preservesProtectionWhenSurfaceCloses)
        XCTAssertTrue(normal.remainsVisibleDuringDisplaySharing)
        XCTAssertTrue(fallback.remainsVisibleDuringDisplaySharing)
        XCTAssertTrue(strongAlert.remainsVisibleDuringDisplaySharing)
        XCTAssertTrue(conflict.remainsVisibleDuringDisplaySharing)
    }

    func testStrongAlertCoversThePrimaryAndEveryAdditionalDisplay() {
        let plan = StrongAlertDisplayPlan(displayCount: 3, primaryIndex: 1)

        XCTAssertEqual(plan?.primaryIndex, 1)
        XCTAssertEqual(Set(plan?.allDisplayIndices ?? []), Set(0..<3))
        XCTAssertEqual(plan?.additionalIndices, [0, 2])
    }

    func testStrongAlertFallsBackToTheFirstDisplayWhenPrimaryIsUnavailable() {
        let plan = StrongAlertDisplayPlan(displayCount: 2, primaryIndex: nil)
        let invalidPrimaryPlan = StrongAlertDisplayPlan(displayCount: 2, primaryIndex: 9)

        XCTAssertEqual(plan?.primaryIndex, 0)
        XCTAssertEqual(plan?.additionalIndices, [1])
        XCTAssertEqual(invalidPrimaryPlan?.primaryIndex, 0)
        XCTAssertEqual(invalidPrimaryPlan?.additionalIndices, [1])
    }

    func testStrongAlertRebuildsCoverageWhenDisplayTopologyChanges() {
        let beforeChange = StrongAlertDisplayPlan(displayCount: 2, primaryIndex: 0)
        let afterChange = StrongAlertDisplayPlan(displayCount: 3, primaryIndex: 1)

        XCTAssertEqual(Set(beforeChange?.allDisplayIndices ?? []), Set(0..<2))
        XCTAssertEqual(Set(afterChange?.allDisplayIndices ?? []), Set(0..<3))
        XCTAssertNotEqual(beforeChange, afterChange)
    }

    func testStrongAlertHasNoDisplayPlanWhenNoDisplaysAreAvailable() {
        XCTAssertNil(StrongAlertDisplayPlan(displayCount: 0, primaryIndex: nil))
    }
}

@MainActor
private func makeEarlyReminderTestFlow() async -> (flow: CommitmentProtectionFlow, commitment: CalendarEvent) {
    let account = GoogleAccount(id: "account-1", email: "alex@example.com", displayName: "Alex")
    let calendar = CalendarOption(id: "calendar-1", name: "Work", accountID: account.id)
    let now = Date(timeIntervalSince1970: 1_000_000)
    let commitment = CalendarEvent(
        id: "event-1",
        title: "Customer review",
        startDate: now.addingTimeInterval(10 * 60),
        endDate: now.addingTimeInterval(70 * 60),
        timeZoneIdentifier: nil,
        isAllDay: false,
        isAccepted: true,
        calendarID: calendar.id,
        accountID: account.id
    )
    let flow = CommitmentProtectionFlow(
        calendarConnector: StaticCalendarConnector(
            connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
            events: [commitment]
        ),
        launchAtLogin: StaticLaunchAtLoginController(),
        now: { now }
    )
    await flow.connectGoogleAccount()
    flow.setCalendarSelected(true, calendarID: calendar.id)
    _ = flow.confirmProtection()
    await flow.refreshCommitmentProtection(at: now)
    return (flow, commitment)
}

private struct StaticCalendarConnector: GoogleCalendarConnecting {
    let connection: GoogleCalendarConnection
    let events: [CalendarEvent]

    func connect() async throws -> GoogleCalendarConnection { connection }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        connection.account.id == accountID ? connection : nil
    }

    func disconnect(accountID: String) throws {}

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        events.filter {
            $0.accountID == accountID &&
                $0.calendarID == calendarID &&
                ($0.startDate ?? .distantPast) < endDate &&
                ($0.endDate ?? .distantFuture) > startDate
        }
    }
}

@MainActor
private final class StaticLaunchAtLoginController: LaunchAtLoginControlling {
    private(set) var isEnabled = false

    func enable() throws {
        isEnabled = true
    }
}
