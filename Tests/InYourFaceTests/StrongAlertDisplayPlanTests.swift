import XCTest
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

    func testEarlyReminderInteractionBarrierRestoresItsTrackedWindowState() {
        var lifecycle = EarlyReminderInteractionBarrierLifecycle()

        XCTAssertFalse(lifecycle.isActive)
        XCTAssertFalse(lifecycle.restoresWindowInteraction)

        lifecycle.activated(restoresWindowInteraction: true)
        XCTAssertTrue(lifecycle.isActive)
        XCTAssertTrue(lifecycle.restoresWindowInteraction)

        lifecycle.deactivated()
        XCTAssertFalse(lifecycle.isActive)
        XCTAssertFalse(lifecycle.restoresWindowInteraction)

        lifecycle.activated(restoresWindowInteraction: false)
        lifecycle.deactivated()
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
