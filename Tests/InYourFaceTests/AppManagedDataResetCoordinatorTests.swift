import Combine
import CommitmentProtection
import Foundation
import XCTest
@testable import InYourFace

@MainActor
final class AppManagedDataResetCoordinatorTests: XCTestCase {
    func testBeginLocksMutationsBeforePreflightAndKeepsLockUntilRelaunchTermination() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let recorder = ResetOperationRecorder(accountCount: 0)
        let coordinator = AppManagedDataResetCoordinator(
            journal: ResetJournal(fileURL: fixture.journalURL),
            operations: recorder.operations
        )

        _ = try await coordinator.begin()

        XCTAssertTrue(recorder.accountCountWasReadWhileLocked)
        XCTAssertEqual(recorder.lockCallCount, 1)
        XCTAssertEqual(recorder.unlockCallCount, 0)
        XCTAssertTrue(recorder.mutationsLocked)
    }

    func testRelaunchCommitsOnlyAfterTheJournalIsDurablyFinished() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let recorder = ResetOperationRecorder(accountCount: 0)
        var observedFinishedJournal = false
        recorder.onRelaunch = {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let snapshot = try decoder.decode(
                    ResetJournalSnapshot.self,
                    from: Data(contentsOf: fixture.journalURL)
                )
                observedFinishedJournal = snapshot.lifecycle == .finished
            } catch {
                XCTFail("Expected a readable finished journal before relaunch commit: \(error)")
            }
        }
        let coordinator = AppManagedDataResetCoordinator(
            journal: ResetJournal(fileURL: fixture.journalURL),
            operations: recorder.operations
        )

        _ = try await coordinator.begin()

        XCTAssertTrue(observedFinishedJournal)
        XCTAssertEqual(recorder.commitRelaunchCount, 1)
        XCTAssertEqual(recorder.cancelRelaunchCount, 0)
    }

    func testReadyToFinishRecoveryStagesCleanupBeforeFinishingAndCommitting() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let begun = try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [.unregisterLaunchAtLogin, .eraseLocalData, .relaunch]
        )
        _ = try await journal.markRunning(begun.entries[0].id)
        _ = try await journal.markCompleted(begun.entries[0].id)
        _ = try await journal.markSkipped(
            begun.entries[1].id,
            reason: .delegatedToPostExitHelper
        )
        _ = try await journal.markRunning(begun.entries[2].id)
        _ = try await journal.markCompleted(begun.entries[2].id)
        let recorder = ResetOperationRecorder(accountCount: 0)
        var observedActiveJournalAtStage = false
        var observedFinishedJournal = false
        recorder.onRelaunchStage = {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let snapshot = try decoder.decode(
                    ResetJournalSnapshot.self,
                    from: Data(contentsOf: fixture.journalURL)
                )
                observedActiveJournalAtStage = snapshot.lifecycle == .active
            } catch {
                XCTFail("Expected a readable active journal during relaunch stage: \(error)")
            }
        }
        recorder.onRelaunch = {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let snapshot = try decoder.decode(
                    ResetJournalSnapshot.self,
                    from: Data(contentsOf: fixture.journalURL)
                )
                observedFinishedJournal = snapshot.lifecycle == .finished
            } catch {
                XCTFail("Expected a readable finished journal before relaunch commit: \(error)")
            }
        }
        let coordinator = AppManagedDataResetCoordinator(
            journal: journal,
            operations: recorder.operations
        )

        let state = try await coordinator.resume()

        guard case .completed = state else {
            return XCTFail("Expected ready-to-finish recovery to complete")
        }
        XCTAssertEqual(recorder.events, ["stopMonitoring", "relaunch"])
        XCTAssertTrue(observedActiveJournalAtStage)
        XCTAssertTrue(observedFinishedJournal)
        XCTAssertEqual(recorder.commitRelaunchCount, 1)
        XCTAssertEqual(recorder.cancelRelaunchCount, 0)
    }

    func testReadyToFinishStageFailureCancelsAndRetryStagesAgain() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let begun = try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [.unregisterLaunchAtLogin, .eraseLocalData, .relaunch]
        )
        _ = try await journal.markRunning(begun.entries[0].id)
        _ = try await journal.markCompleted(begun.entries[0].id)
        _ = try await journal.markSkipped(
            begun.entries[1].id,
            reason: .delegatedToPostExitHelper
        )
        _ = try await journal.markRunning(begun.entries[2].id)
        _ = try await journal.markCompleted(begun.entries[2].id)
        let recorder = ResetOperationRecorder(accountCount: 0)
        recorder.relaunchStageError = RelaunchStageProbeError.failed
        recorder.relaunchStageFailuresRemaining = 1
        let coordinator = AppManagedDataResetCoordinator(
            journal: journal,
            operations: recorder.operations
        )

        let blockedState = try await coordinator.resume()

        guard case .blocked(let block) = blockedState else {
            return XCTFail("Expected ready-to-finish stage failure to remain retryable")
        }
        XCTAssertEqual(block.progress.currentStep, .relaunch)
        XCTAssertEqual(block.reason, .unavailable)
        XCTAssertTrue(coordinator.state.allowsExplicitRetry)
        XCTAssertEqual(recorder.events, ["stopMonitoring", "relaunch"])
        XCTAssertEqual(recorder.cancelRelaunchCount, 1)
        XCTAssertEqual(recorder.commitRelaunchCount, 0)
        guard case .readyToFinish = try await journal.resumeResolution() else {
            return XCTFail("Expected failed staging to preserve ready-to-finish recovery")
        }

        let completedState = try await coordinator.begin()

        guard case .completed = completedState else {
            return XCTFail("Expected ready-to-finish retry to complete")
        }
        XCTAssertEqual(
            recorder.events,
            ["stopMonitoring", "relaunch", "stopMonitoring", "relaunch"]
        )
        XCTAssertEqual(recorder.cancelRelaunchCount, 1)
        XCTAssertEqual(recorder.commitRelaunchCount, 1)
        guard case .finished(let snapshot) = try await journal.resumeResolution() else {
            return XCTFail("Expected retry to durably finish the journal")
        }
        XCTAssertEqual(snapshot.entries.last?.attemptCount, 1)
    }

    func testRelaunchStageFailureCancelsOnceAndRetriesTheSameStep() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let recorder = ResetOperationRecorder(accountCount: 0)
        recorder.relaunchStageError = RelaunchStageProbeError.failed
        recorder.relaunchStageFailuresRemaining = 1
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let coordinator = AppManagedDataResetCoordinator(
            journal: journal,
            operations: recorder.operations
        )

        let blockedState = try await coordinator.begin()

        guard case .blocked(let block) = blockedState else {
            return XCTFail("Expected the failed relaunch stage to block reset")
        }
        XCTAssertEqual(block.progress.currentStep, .relaunch)
        XCTAssertEqual(recorder.cancelRelaunchCount, 1)
        XCTAssertEqual(recorder.commitRelaunchCount, 0)
        guard case .retry(_, let failedEntry) = try await journal.resumeResolution() else {
            return XCTFail("Expected a retryable relaunch entry")
        }
        XCTAssertEqual(failedEntry.step, .relaunch)
        XCTAssertEqual(failedEntry.attemptCount, 1)

        let completedState = try await coordinator.begin()

        guard case .completed = completedState else {
            return XCTFail("Expected relaunch retry to complete")
        }
        XCTAssertEqual(recorder.cancelRelaunchCount, 1)
        XCTAssertEqual(recorder.commitRelaunchCount, 1)
        guard case .finished(let snapshot) = try await journal.resumeResolution() else {
            return XCTFail("Expected a finished journal after relaunch retry")
        }
        XCTAssertEqual(snapshot.entries.last?.attemptCount, 2)
    }

    func testResumeWithoutJournalReleasesMutationLock() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let recorder = ResetOperationRecorder(accountCount: 0)
        let coordinator = AppManagedDataResetCoordinator(
            journal: ResetJournal(fileURL: fixture.journalURL),
            operations: recorder.operations
        )

        let state = try await coordinator.resume()

        XCTAssertEqual(state, .idle)
        XCTAssertEqual(recorder.lockCallCount, 1)
        XCTAssertEqual(recorder.unlockCallCount, 1)
        XCTAssertFalse(recorder.mutationsLocked)
    }

    func testExplicitRetryReplacesOnlyPreviouslyReportedUnreadableJournal() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let corruptData = Data("{ not-a-reset-journal".utf8)
        try corruptData.write(to: fixture.journalURL)
        let recorder = ResetOperationRecorder(accountCount: 0)
        let coordinator = AppManagedDataResetCoordinator(
            journal: ResetJournal(fileURL: fixture.journalURL),
            operations: recorder.operations
        )

        do {
            _ = try await coordinator.begin()
            XCTFail("Expected the first attempt to report the unreadable journal")
        } catch {
            XCTAssertEqual(error as? ResetJournalError, .corrupted)
        }
        XCTAssertEqual(coordinator.state, .unavailable(.journal(.corrupted)))
        XCTAssertEqual(try Data(contentsOf: fixture.journalURL), corruptData)
        XCTAssertTrue(recorder.mutationsLocked)

        let retriedState = try await coordinator.begin()

        guard case .completed = retriedState else {
            return XCTFail("Expected explicit retry to recreate and finish the reset")
        }
        XCTAssertEqual(recorder.lockCallCount, 2)
        XCTAssertEqual(recorder.unlockCallCount, 0)
        XCTAssertTrue(recorder.mutationsLocked)
        XCTAssertEqual(recorder.events, ["stopMonitoring", "unregister", "relaunch"])
        guard case .finished = try await ResetJournal(fileURL: fixture.journalURL).resumeResolution() else {
            return XCTFail("Expected a newly persisted finished reset journal")
        }
    }

    func testPreflightBuildsOrderedPlanWithoutMutatingAnything() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let recorder = ResetOperationRecorder(accountCount: 2)
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let coordinator = AppManagedDataResetCoordinator(
            journal: journal,
            operations: recorder.operations
        )

        let preflight = try coordinator.preflight()

        XCTAssertEqual(preflight.accountCount, 2)
        XCTAssertEqual(
            preflight.steps,
            [
                .revokeGoogleAuthorization(position: 0),
                .revokeGoogleAuthorization(position: 1),
                .unregisterLaunchAtLogin,
                .eraseLocalData,
                .relaunch
            ]
        )
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(recorder.events.isEmpty)
        let resolution = try await journal.resumeResolution()
        XCTAssertEqual(resolution, .noJournal)
    }

    func testBeginDelegatesLocalCleanupThenFinishesEveryStepInOrder() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let recorder = ResetOperationRecorder(accountCount: 2)
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let coordinator = AppManagedDataResetCoordinator(
            journal: journal,
            operations: recorder.operations
        )

        let state = try await coordinator.begin()

        XCTAssertEqual(
            recorder.events,
            ["stopMonitoring", "revoke:0", "revoke:1", "unregister", "relaunch"]
        )
        guard case .completed(let progress) = state else {
            return XCTFail("Expected the erase operation to finish")
        }
        XCTAssertEqual(progress.completedStepCount, 5)
        XCTAssertEqual(progress.totalStepCount, 5)
        XCTAssertNil(progress.currentStep)

        guard case .finished(let snapshot) = try await journal.resumeResolution() else {
            return XCTFail("Expected a finished journal")
        }
        XCTAssertEqual(snapshot.entries.map(\.attemptCount), [1, 1, 1, 0, 1])
        XCTAssertEqual(
            snapshot.entries.map(\.status),
            [
                .completed,
                .completed,
                .completed,
                .skipped(.delegatedToPostExitHelper),
                .completed
            ]
        )
    }

    func testMissingLocalCredentialSkipsRevocationAndContinuesPostExitCleanup() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let recorder = ResetOperationRecorder(accountCount: 2)
        recorder.revocationResults = [
            0: .localCredentialMissing,
            1: .alreadyInvalid
        ]
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let coordinator = AppManagedDataResetCoordinator(
            journal: journal,
            operations: recorder.operations
        )

        _ = try await coordinator.begin()

        guard case .finished(let snapshot) = try await journal.resumeResolution() else {
            return XCTFail("Expected the local-only erase to finish")
        }
        XCTAssertEqual(snapshot.entries[0].status, .skipped(.noUsableLocalGrant))
        XCTAssertEqual(snapshot.entries[1].status, .completed)
        XCTAssertEqual(snapshot.entries[2].status, .completed)
        XCTAssertEqual(snapshot.entries[3].status, .skipped(.delegatedToPostExitHelper))
        XCTAssertEqual(snapshot.entries[4].status, .completed)
    }

    func testTransientRevocationFailureStopsThenResumeRetriesTheSameOrdinal() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let recorder = ResetOperationRecorder(accountCount: 1)
        recorder.revocationError = GoogleCalendarConnectorError.networkUnavailable
        recorder.revocationFailuresRemaining = 1
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let coordinator = AppManagedDataResetCoordinator(
            journal: journal,
            operations: recorder.operations
        )

        let blockedState = try await coordinator.begin()

        guard case .blocked(let block) = blockedState else {
            return XCTFail("Expected reset to stop at revocation")
        }
        XCTAssertTrue(recorder.mutationsLocked)
        XCTAssertEqual(recorder.unlockCallCount, 0)
        XCTAssertEqual(block.reason, .transient)
        XCTAssertEqual(block.progress.currentStep, .revokeGoogleAuthorization(position: 0))
        XCTAssertEqual(recorder.events, ["stopMonitoring", "revoke:0"])
        guard case .retry(_, let failedEntry) = try await journal.resumeResolution() else {
            return XCTFail("Expected the failed revocation to be retryable")
        }
        XCTAssertEqual(failedEntry.status, .failed(.transient))

        var observedStates: [AppManagedDataResetCoordinatorState] = []
        let observation = coordinator.$state.sink { observedStates.append($0) }
        let resumedState = try await coordinator.resume()
        withExtendedLifetime(observation) {}

        guard case .completed = resumedState else {
            return XCTFail("Expected retry to finish the reset")
        }
        XCTAssertTrue(recorder.mutationsLocked)
        XCTAssertEqual(recorder.unlockCallCount, 0)
        XCTAssertTrue(observedStates.contains { state in
            guard case .recovering(let recovery) = state else { return false }
            return recovery.kind == .retrying(.transient)
                && recovery.progress.currentStep == .revokeGoogleAuthorization(position: 0)
        })
        XCTAssertEqual(
            recorder.events,
            [
                "stopMonitoring", "revoke:0",
                "stopMonitoring", "revoke:0", "unregister", "relaunch"
            ]
        )

        guard case .finished(let snapshot) = try await journal.resumeResolution() else {
            return XCTFail("Expected a finished journal after retry")
        }
        XCTAssertEqual(snapshot.entries[0].attemptCount, 2)
    }

    func testResumeDelegatesPreviouslyFailedLocalEraseWithoutRetryingItInProcess() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let begun = try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [.unregisterLaunchAtLogin, .eraseLocalData, .relaunch]
        )
        _ = try await journal.markRunning(begun.entries[0].id)
        _ = try await journal.markCompleted(begun.entries[0].id)
        for _ in 0..<4 {
            _ = try await journal.markRunning(begun.entries[1].id)
            _ = try await journal.markFailed(begun.entries[1].id, reason: .ioFailure)
        }
        let recorder = ResetOperationRecorder(accountCount: 0)
        let coordinator = AppManagedDataResetCoordinator(
            journal: journal,
            operations: recorder.operations
        )

        let state = try await coordinator.resume()

        guard case .completed = state else {
            return XCTFail("Expected the legacy failed erase to hand off and finish")
        }
        XCTAssertEqual(recorder.events, ["stopMonitoring", "relaunch"])
        guard case .finished(let snapshot) = try await journal.resumeResolution() else {
            return XCTFail("Expected the migrated journal to finish")
        }
        XCTAssertEqual(snapshot.entries[1].attemptCount, 4)
        XCTAssertEqual(
            snapshot.entries[1].status,
            .skipped(.delegatedToPostExitHelper)
        )
    }

    func testAmbiguousRevocationFailurePersistsOnlyTypedNonIdentifyingReason() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let recorder = ResetOperationRecorder(accountCount: 1)
        recorder.revocationError = SensitiveRevocationError(
            message: "person@example.com invalid_grant provider-secret"
        )
        recorder.revocationFailuresRemaining = 1
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let coordinator = AppManagedDataResetCoordinator(
            journal: journal,
            operations: recorder.operations
        )

        let state = try await coordinator.begin()

        guard case .blocked(let block) = state else {
            return XCTFail("Expected the ambiguous result to block local deletion")
        }
        XCTAssertEqual(block.reason, .ambiguousOutcome)
        XCTAssertEqual(recorder.events, ["stopMonitoring", "revoke:0"])

        let persisted = try String(contentsOf: fixture.journalURL, encoding: .utf8)
        XCTAssertTrue(persisted.contains("ambiguousOutcome"))
        XCTAssertFalse(persisted.contains("person@example.com"))
        XCTAssertFalse(persisted.contains("provider-secret"))
        XCTAssertFalse(persisted.contains("accountID"))
    }

    func testResumeReconcilesRunningStepWithoutIncrementingItsAttemptTwice() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let begun = try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [
                .revokeGoogleAuthorization(position: 0),
                .unregisterLaunchAtLogin,
                .eraseLocalData,
                .relaunch
            ]
        )
        _ = try await journal.markRunning(begun.entries[0].id)

        let recorder = ResetOperationRecorder(accountCount: 0)
        let coordinator = AppManagedDataResetCoordinator(
            journal: journal,
            operations: recorder.operations
        )
        var observedStates: [AppManagedDataResetCoordinatorState] = []
        let observation = coordinator.$state.sink { observedStates.append($0) }

        _ = try await coordinator.resume()
        withExtendedLifetime(observation) {}

        XCTAssertTrue(observedStates.contains { state in
            guard case .recovering(let recovery) = state else { return false }
            return recovery.kind == .interrupted
                && recovery.progress.currentStep == .revokeGoogleAuthorization(position: 0)
        })
        XCTAssertEqual(
            recorder.events,
            ["stopMonitoring", "revoke:0", "unregister", "relaunch"]
        )
        guard case .finished(let snapshot) = try await journal.resumeResolution() else {
            return XCTFail("Expected reconciliation to finish")
        }
        XCTAssertEqual(snapshot.entries[0].attemptCount, 1)
    }

    func testFinishedResumeIsIdempotentAndDoesNotRepeatEffects() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let recorder = ResetOperationRecorder(accountCount: 0)
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let firstCoordinator = AppManagedDataResetCoordinator(
            journal: journal,
            operations: recorder.operations
        )
        _ = try await firstCoordinator.begin()
        recorder.events.removeAll()

        let resumedCoordinator = AppManagedDataResetCoordinator(
            journal: ResetJournal(fileURL: fixture.journalURL),
            operations: recorder.operations
        )
        let state = try await resumedCoordinator.resume()

        guard case .completed(let progress) = state else {
            return XCTFail("Expected the finished journal to remain complete")
        }
        XCTAssertEqual(progress.completedStepCount, 3)
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testResumeRefusesAnotherResetKindBeforeInvokingAnyEffect() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        _ = try await journal.begin(
            kind: .fullFirstRun,
            steps: [.unregisterLaunchAtLogin, .eraseLocalData, .relaunch]
        )
        let recorder = ResetOperationRecorder(accountCount: 0)
        let coordinator = AppManagedDataResetCoordinator(
            journal: journal,
            operations: recorder.operations
        )

        do {
            _ = try await coordinator.resume()
            XCTFail("Expected a mismatched journal kind to be rejected")
        } catch {
            XCTAssertEqual(
                error as? AppManagedDataResetCoordinatorError,
                .unexpectedJournalPlan
            )
        }
        XCTAssertEqual(
            coordinator.state,
            .unavailable(.coordinator(.unexpectedJournalPlan))
        )
        XCTAssertTrue(recorder.mutationsLocked)
        XCTAssertTrue(recorder.events.isEmpty)
    }
}

@MainActor
private final class ResetOperationRecorder {
    var accountCount: Int
    var events: [String] = []
    var revocationResults: [Int: GoogleAuthorizationRevocationResult] = [:]
    var revocationError: (any Error)?
    var revocationFailuresRemaining = 0
    var mutationsLocked = false
    var accountCountWasReadWhileLocked = false
    var lockCallCount = 0
    var unlockCallCount = 0
    var onRelaunchStage: () -> Void = {}
    var onRelaunch: () -> Void = {}
    var relaunchStageError: (any Error)?
    var relaunchStageFailuresRemaining = 0
    var commitRelaunchCount = 0
    var cancelRelaunchCount = 0

    init(accountCount: Int) {
        self.accountCount = accountCount
    }

    var operations: AppManagedDataResetOperations {
        AppManagedDataResetOperations(
            accountCount: { [unowned self] in
                accountCountWasReadWhileLocked = mutationsLocked
                return accountCount
            },
            stopMonitoring: { [unowned self] in
                events.append("stopMonitoring")
            },
            revokeAuthorization: { [unowned self] position in
                events.append("revoke:\(position)")
                if revocationFailuresRemaining > 0, let revocationError {
                    revocationFailuresRemaining -= 1
                    throw revocationError
                }
                return revocationResults[position] ?? .revoked
            },
            unregisterLaunchAtLogin: { [unowned self] in
                events.append("unregister")
            },
            stageRelaunch: { [unowned self] in
                events.append("relaunch")
                onRelaunchStage()
                if relaunchStageFailuresRemaining > 0, let relaunchStageError {
                    relaunchStageFailuresRemaining -= 1
                    throw relaunchStageError
                }
            },
            commitStagedRelaunch: { [unowned self] in
                commitRelaunchCount += 1
                onRelaunch()
            },
            cancelStagedRelaunch: { [unowned self] in
                cancelRelaunchCount += 1
            },
            lockMutations: { [unowned self] in
                lockCallCount += 1
                mutationsLocked = true
            },
            unlockMutations: { [unowned self] in
                unlockCallCount += 1
                mutationsLocked = false
            }
        )
    }
}

private struct SensitiveRevocationError: Error, LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

private enum RelaunchStageProbeError: Error {
    case failed
}

private struct AppManagedDataResetFixture {
    let directoryURL: URL
    let journalURL: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private func makeFixture() throws -> AppManagedDataResetFixture {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("AppManagedDataResetCoordinatorTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
    )
    return AppManagedDataResetFixture(
        directoryURL: directoryURL,
        journalURL: directoryURL.appendingPathComponent("reset-journal.json")
    )
}
