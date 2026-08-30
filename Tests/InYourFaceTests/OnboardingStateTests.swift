import Foundation
import XCTest
@testable import InYourFace

@MainActor
final class OnboardingStateTests: XCTestCase {
    func testFreshInstallWaitsForResolutionThenRequestsOnboarding() {
        withStateStore { store in
            let state = OnboardingState(stateStore: store)

            XCTAssertEqual(state.initialSurface, .waiting)
            XCTAssertFalse(state.isCompleted)
            XCTAssertFalse(state.needsSetup)

            state.resolveInitialLaunch(hasConfiguredProtection: false)

            XCTAssertEqual(state.initialSurface, .onboarding)
            XCTAssertEqual(state.phase, .pending)
            XCTAssertTrue(state.needsSetup)
        }
    }

    func testExistingConfiguredUserMakesOneTimeLaunchAtLoginChoice() {
        withStateStore { store in
            let state = OnboardingState(stateStore: store)

            XCTAssertEqual(state.initialSurface, .waiting)
            XCTAssertFalse(state.needsSetup)

            state.resume()
            state.resolveInitialLaunch(hasConfiguredProtection: true)

            XCTAssertTrue(state.isCompleted)
            XCTAssertTrue(state.needsSetup)
            XCTAssertEqual(state.initialSurface, .onboarding)
            XCTAssertTrue(state.complete())
            XCTAssertEqual(state.initialSurface, .menuBarOnly)

            let relaunchedState = OnboardingState(stateStore: store)

            XCTAssertEqual(relaunchedState.phase, .completed)
            XCTAssertEqual(relaunchedState.initialSurface, .waiting)
            XCTAssertFalse(relaunchedState.needsSetup)

            relaunchedState.resolveInitialLaunch(hasConfiguredProtection: false)

            XCTAssertTrue(relaunchedState.isCompleted)
            XCTAssertFalse(relaunchedState.needsSetup)
            XCTAssertEqual(relaunchedState.initialSurface, .menuBarOnly)
        }
    }

    func testDeferredSetupCannotResumeBeforeInitialLaunchResolution() {
        withStateStore { store in
            let state = OnboardingState(stateStore: store)
            state.resolveInitialLaunch(hasConfiguredProtection: false)
            state.deferUntilRequested()

            let relaunchedState = OnboardingState(stateStore: store)

            XCTAssertEqual(relaunchedState.phase, .deferred)
            XCTAssertEqual(relaunchedState.initialSurface, .waiting)
            XCTAssertFalse(relaunchedState.needsSetup)

            relaunchedState.resume()

            XCTAssertEqual(relaunchedState.phase, .deferred)
            XCTAssertEqual(relaunchedState.initialSurface, .waiting)

            relaunchedState.resolveInitialLaunch(hasConfiguredProtection: false)

            XCTAssertEqual(relaunchedState.phase, .deferred)
            XCTAssertEqual(relaunchedState.initialSurface, .menuBarOnly)
            XCTAssertTrue(relaunchedState.needsSetup)

            relaunchedState.resume()

            XCTAssertEqual(relaunchedState.phase, .pending)
            XCTAssertEqual(relaunchedState.initialSurface, .onboarding)
        }
    }

    func testSetUpLaterSuppressesAutomaticPresentationUntilResumed() {
        withStateStore { store in
            let state = OnboardingState(stateStore: store)
            state.resolveInitialLaunch(hasConfiguredProtection: false)
            XCTAssertTrue(state.deferUntilRequested())

            XCTAssertEqual(state.phase, .deferred)
            XCTAssertEqual(state.initialSurface, .menuBarOnly)

            let relaunchedState = OnboardingState(stateStore: store)
            relaunchedState.resolveInitialLaunch(hasConfiguredProtection: false)

            XCTAssertEqual(relaunchedState.initialSurface, .menuBarOnly)

            relaunchedState.resume()

            XCTAssertEqual(relaunchedState.phase, .pending)
            XCTAssertEqual(relaunchedState.initialSurface, .onboarding)
        }
    }

    func testReadinessFinishLaterRecordsLaunchChoiceAndRemainsResumable() {
        withStateStore { store in
            let state = OnboardingState(stateStore: store)
            state.resolveInitialLaunch(hasConfiguredProtection: false)

            XCTAssertTrue(state.deferReadinessUntilRequested())
            XCTAssertEqual(state.phase, .deferred)
            XCTAssertTrue(state.didChooseLaunchAtLogin)
            XCTAssertTrue(state.needsSetup)
            XCTAssertEqual(state.initialSurface, .menuBarOnly)

            let relaunchedState = OnboardingState(stateStore: store)
            relaunchedState.resolveInitialLaunch(hasConfiguredProtection: true)

            XCTAssertEqual(relaunchedState.phase, .deferred)
            XCTAssertTrue(relaunchedState.didChooseLaunchAtLogin)
            XCTAssertTrue(relaunchedState.needsSetup)
            XCTAssertEqual(relaunchedState.initialSurface, .menuBarOnly)

            relaunchedState.resume()

            XCTAssertEqual(relaunchedState.phase, .pending)
            XCTAssertEqual(relaunchedState.initialSurface, .onboarding)
        }
    }

    func testConfiguredUserCanFinishReadinessLaterBeforeLaunchChoiceMigrationCompletes() {
        withStateStore { store in
            let state = OnboardingState(stateStore: store)
            state.resolveInitialLaunch(hasConfiguredProtection: true)

            XCTAssertEqual(state.phase, .completed)
            XCTAssertFalse(state.didChooseLaunchAtLogin)
            XCTAssertTrue(state.deferReadinessUntilRequested())

            XCTAssertEqual(state.phase, .deferred)
            XCTAssertTrue(state.didChooseLaunchAtLogin)
            XCTAssertTrue(state.needsSetup)
            XCTAssertEqual(state.initialSurface, .menuBarOnly)
        }
    }

    func testReadinessDeferralReportsMutationGateFailure() {
        withStateStore { store in
            let state = OnboardingState(
                stateStore: store,
                allowsPreferenceMutation: { false }
            )

            XCTAssertFalse(state.canResolveReadiness)
            XCTAssertFalse(state.deferReadinessUntilRequested())
            XCTAssertEqual(state.phase, .pending)
            XCTAssertFalse(state.didChooseLaunchAtLogin)
        }
    }

    func testCompletionPersistsWithoutAnAlertPrerequisite() {
        withStateStore { store in
            let state = OnboardingState(stateStore: store)
            state.resolveInitialLaunch(hasConfiguredProtection: false)

            XCTAssertTrue(state.complete())
            XCTAssertTrue(state.isCompleted)

            let relaunchedState = OnboardingState(stateStore: store)
            relaunchedState.resolveInitialLaunch(hasConfiguredProtection: false)

            XCTAssertTrue(relaunchedState.isCompleted)
            XCTAssertEqual(relaunchedState.initialSurface, .menuBarOnly)
        }
    }

    func testLegacyTestAlertStateDoesNotAffectCompletion() {
        withStateStore { store in
            store.set(false, forKey: "in-your-face.onboarding-test-alert-handled")
            let state = OnboardingState(stateStore: store)
            state.resolveInitialLaunch(hasConfiguredProtection: false)

            XCTAssertTrue(state.complete())
        }
    }

    func testCompletionIsNotResetByLaterCoverageLoss() {
        withStateStore { store in
            let state = OnboardingState(stateStore: store)
            state.resolveInitialLaunch(hasConfiguredProtection: true)
            XCTAssertTrue(state.complete())

            let stateAfterDisconnect = OnboardingState(stateStore: store)
            stateAfterDisconnect.resolveInitialLaunch(hasConfiguredProtection: false)

            XCTAssertTrue(stateAfterDisconnect.isCompleted)
            XCTAssertFalse(stateAfterDisconnect.needsSetup)
            XCTAssertEqual(stateAfterDisconnect.initialSurface, .menuBarOnly)
        }
    }

    func testResetRecoveryQuarantineRejectsEveryOnboardingMutation() {
        withStateStore { store in
            let before = store.dictionaryRepresentation()
            let state = OnboardingState(
                stateStore: store,
                allowsPreferenceMutation: { false }
            )

            state.resolveInitialLaunch(hasConfiguredProtection: true)
            state.resume()
            state.deferUntilRequested()

            XCTAssertFalse(state.complete())
            XCTAssertEqual(state.initialSurface, .waiting)
            XCTAssertEqual(state.phase, .pending)
            XCTAssertFalse(state.didChooseLaunchAtLogin)
            XCTAssertTrue(
                NSDictionary(dictionary: before).isEqual(
                    to: store.dictionaryRepresentation()
                )
            )
        }
    }

    func testStartingResetInTheSameProcessClosesTheOnboardingMutationGate() {
        withStateStore { store in
            let gate = PreferenceMutationGate()
            let state = OnboardingState(
                stateStore: store,
                allowsPreferenceMutation: { gate.isOpen }
            )
            state.resolveInitialLaunch(hasConfiguredProtection: false)
            let before = store.dictionaryRepresentation()

            gate.isOpen = false
            state.deferUntilRequested()

            XCTAssertFalse(state.complete())
            XCTAssertEqual(state.phase, .pending)
            XCTAssertTrue(
                NSDictionary(dictionary: before).isEqual(
                    to: store.dictionaryRepresentation()
                )
            )
        }
    }

    private func withStateStore(_ body: (UserDefaults) -> Void) {
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        guard let store = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        store.removePersistentDomain(forName: suiteName)
        defer { store.removePersistentDomain(forName: suiteName) }
        body(store)
    }
}

@MainActor
private final class PreferenceMutationGate {
    var isOpen = true
}
