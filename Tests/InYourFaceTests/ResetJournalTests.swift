import Foundation
import XCTest
@testable import InYourFace

final class ResetJournalTests: XCTestCase {
    func testBootstrapInspectionDistinguishesRevocationFromPostExitRecovery() async throws {
        let revocationFixture = try makeFixture()
        defer { revocationFixture.cleanup() }
        let revocationJournal = ResetJournal(fileURL: revocationFixture.journalURL)
        _ = try await revocationJournal.begin(
            kind: .eraseAppManagedData,
            steps: [
                .revokeGoogleAuthorization(position: 0),
                .unregisterLaunchAtLogin,
                .eraseLocalData,
                .relaunch
            ]
        )

        XCTAssertEqual(
            ResetJournal.inspectForBootstrap(
                fileURL: revocationFixture.journalURL,
                expectedKind: .eraseAppManagedData
            ),
            .recovery(requiresProtectedStorage: true)
        )

        let postExitFixture = try makeFixture()
        defer { postExitFixture.cleanup() }
        let postExitJournal = ResetJournal(fileURL: postExitFixture.journalURL)
        let begun = try await postExitJournal.begin(
            kind: .eraseAppManagedData,
            steps: [
                .revokeGoogleAuthorization(position: 0),
                .unregisterLaunchAtLogin,
                .eraseLocalData,
                .relaunch
            ]
        )
        _ = try await postExitJournal.markRunning(begun.entries[0].id)
        _ = try await postExitJournal.markCompleted(begun.entries[0].id)
        _ = try await postExitJournal.markRunning(begun.entries[1].id)
        _ = try await postExitJournal.markCompleted(begun.entries[1].id)
        _ = try await postExitJournal.markSkipped(
            begun.entries[2].id,
            reason: .delegatedToPostExitHelper
        )

        XCTAssertEqual(
            ResetJournal.inspectForBootstrap(
                fileURL: postExitFixture.journalURL,
                expectedKind: .eraseAppManagedData
            ),
            .recovery(requiresProtectedStorage: false)
        )
    }

    func testResumeDistinguishesNoJournalFromAPlanReadyToFinish() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)

        let emptyResolution = try await journal.resumeResolution()
        XCTAssertEqual(emptyResolution, .noJournal)

        _ = try await journal.begin(
            kind: .exitTestMode,
            steps: [.eraseLocalData, .relaunch]
        )
        try await completeRemainingSteps(in: journal)

        guard case .readyToFinish(let snapshot) = try await journal.resumeResolution() else {
            return XCTFail("Expected an all-terminal active plan to be ready to finish")
        }
        XCTAssertEqual(snapshot.lifecycle, .active)
    }

    func testBeginPersistsOrderedStepsAndResumeReturnsFirstPendingStep() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let steps: [ResetStep] = [
            .revokeGoogleAuthorization(position: 0),
            .revokeGoogleAuthorization(position: 1),
            .unregisterLaunchAtLogin,
            .eraseLocalData,
            .relaunch
        ]

        let journal = ResetJournal(fileURL: fixture.journalURL)
        let begun = try await journal.begin(kind: .eraseAppManagedData, steps: steps)

        XCTAssertEqual(begun.kind, .eraseAppManagedData)
        XCTAssertEqual(begun.entries.map(\.step), steps)
        XCTAssertEqual(begun.entries.map(\.order), Array(steps.indices))

        let relaunchedJournal = ResetJournal(fileURL: fixture.journalURL)
        let resolution = try await relaunchedJournal.resumeResolution()

        guard case .run(let restored, let entry) = resolution else {
            return XCTFail("Expected the first pending step to be runnable")
        }
        XCTAssertEqual(restored, begun)
        XCTAssertEqual(entry.step, steps[0])
        let nextPending = try await relaunchedJournal.nextPending()
        XCTAssertEqual(nextPending?.step, steps[0])
    }

    func testGoogleRevocationOrdinalRoundTripsWithoutPersistingAnAccountIdentifier() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)

        _ = try await journal.begin(
            kind: .fullFirstRun,
            steps: [
                .revokeGoogleAuthorization(position: 7),
                .eraseLocalData,
                .relaunch
            ]
        )

        let persistedJSON = try String(contentsOf: fixture.journalURL, encoding: .utf8)
        XCTAssertTrue(persistedJSON.contains("\"position\":7"))
        XCTAssertFalse(persistedJSON.contains("person@example.com"))
        XCTAssertFalse(persistedJSON.contains("accountID"))

        let restored = try await ResetJournal(fileURL: fixture.journalURL).resumeResolution()
        guard case .run(_, let entry) = restored else {
            return XCTFail("Expected the persisted ordinal step to be runnable")
        }
        XCTAssertEqual(entry.step, .revokeGoogleAuthorization(position: 7))
    }

    func testInterruptedAndFailedStepsHaveExplicitResumeResolutions() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let begun = try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [
                .revokeGoogleAuthorization(position: 0),
                .eraseLocalData,
                .relaunch
            ]
        )
        let revokeID = begun.entries[0].id

        let running = try await journal.markRunning(revokeID)
        XCTAssertEqual(running.entries[0].attemptCount, 1)
        let nextWhileRunning = try await journal.nextPending()
        XCTAssertNil(nextWhileRunning)

        let afterCrash = try await ResetJournal(fileURL: fixture.journalURL).resumeResolution()
        guard case .reconcile(_, let interrupted) = afterCrash else {
            return XCTFail("Expected an interrupted running step to require reconciliation")
        }
        XCTAssertEqual(interrupted.id, revokeID)

        _ = try await journal.markFailed(revokeID, reason: .transient)
        let afterFailure = try await journal.resumeResolution()
        guard case .retry(_, let failed) = afterFailure else {
            return XCTFail("Expected a failed step to be offered for retry")
        }
        XCTAssertEqual(failed.id, revokeID)
        XCTAssertEqual(failed.status, .failed(.transient))

        let retried = try await journal.markRunning(revokeID)
        XCTAssertEqual(retried.entries[0].attemptCount, 2)
        XCTAssertEqual(retried.entries[0].status, .running)
    }

    func testUnreadableCredentialCanSkipRevocationAndContinueWithLocalOnlyErasure() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let begun = try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [
                .revokeGoogleAuthorization(position: 0),
                .eraseLocalData,
                .relaunch
            ]
        )

        let revokeID = begun.entries[0].id
        _ = try await journal.markRunning(revokeID)
        let skipped = try await journal.markSkipped(
            revokeID,
            reason: .credentialPermanentlyUnreadable
        )

        XCTAssertEqual(
            skipped.entries[0].status,
            .skipped(.credentialPermanentlyUnreadable)
        )
        let nextAfterSkip = try await journal.nextPending()
        XCTAssertEqual(nextAfterSkip?.step, .eraseLocalData)

        try await completeRemainingSteps(in: journal)
        let finished = try await journal.finish()
        XCTAssertEqual(finished.lifecycle, .finished)
        XCTAssertNotNil(finished.finishedAt)
    }

    func testPostExitDelegationCanOnlySkipTheLocalEraseMarker() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let begun = try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [.eraseLocalData, .relaunch]
        )

        let skipped = try await journal.markSkipped(
            begun.entries[0].id,
            reason: .delegatedToPostExitHelper
        )

        XCTAssertEqual(
            skipped.entries[0].status,
            .skipped(.delegatedToPostExitHelper)
        )
        do {
            _ = try await journal.markSkipped(
                begun.entries[1].id,
                reason: .delegatedToPostExitHelper
            )
            XCTFail("Expected post-exit delegation to be limited to local cleanup")
        } catch {
            XCTAssertEqual(error as? ResetJournalError, .invalidSkipReason)
        }
    }

    func testBeginAndTerminalMarksAreIdempotent() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let steps: [ResetStep] = [.eraseLocalData, .relaunch]

        let firstBegin = try await journal.begin(kind: .fullFirstRun, steps: steps)
        let repeatedBegin = try await journal.begin(kind: .fullFirstRun, steps: steps)
        XCTAssertEqual(repeatedBegin, firstBegin)

        let firstID = firstBegin.entries[0].id
        let running = try await journal.markRunning(firstID)
        let repeatedRunning = try await journal.markRunning(firstID)
        XCTAssertEqual(repeatedRunning, running)
        XCTAssertEqual(repeatedRunning.entries[0].attemptCount, 1)

        let completed = try await journal.markCompleted(firstID)
        let repeatedCompletion = try await journal.markCompleted(firstID)
        XCTAssertEqual(repeatedCompletion, completed)
    }

    func testDifferentPlanCannotReplaceAnActiveJournal() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        _ = try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [.eraseLocalData, .relaunch]
        )

        do {
            _ = try await journal.begin(
                kind: .fullFirstRun,
                steps: [.eraseLocalData, .resetTCC(.accessibility), .relaunch]
            )
            XCTFail("Expected an active journal to reject a different reset plan")
        } catch {
            XCTAssertEqual(error as? ResetJournalError, .journalAlreadyActive)
        }
    }

    func testFinishRequiresEveryStepToBeCompletedOrSkippedAndIsIdempotent() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        _ = try await journal.begin(
            kind: .fullFirstRun,
            steps: [.eraseLocalData, .resetTCC(.inputMonitoring), .relaunch]
        )

        do {
            _ = try await journal.finish()
            XCTFail("Expected unfinished steps to prevent completion")
        } catch {
            guard case .unfinished = error as? ResetJournalError else {
                return XCTFail("Expected an unfinished journal error, got \(error)")
            }
        }

        try await completeRemainingSteps(in: journal)
        let finished = try await journal.finish()
        let repeatedFinish = try await journal.finish()

        XCTAssertEqual(repeatedFinish, finished)
        guard case .finished(let restored) = try await journal.resumeResolution() else {
            return XCTFail("Expected a durable finished resolution")
        }
        XCTAssertEqual(restored, finished)
    }

    func testCompleteFinalRunningStepAndFinishPersistsOneTerminalSnapshot() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let begun = try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [.eraseLocalData, .relaunch]
        )
        _ = try await journal.markSkipped(
            begun.entries[0].id,
            reason: .delegatedToPostExitHelper
        )
        _ = try await journal.markRunning(begun.entries[1].id)

        let finished = try await journal.completeFinalStepAndFinish(
            begun.entries[1].id
        )

        XCTAssertEqual(finished.lifecycle, .finished)
        XCTAssertEqual(finished.entries[1].status, .completed)
        XCTAssertNotNil(finished.finishedAt)
        guard case .finished(let reloaded) = try await ResetJournal(
            fileURL: fixture.journalURL
        ).resumeResolution() else {
            return XCTFail("Expected the single persisted transition to be terminal")
        }
        XCTAssertEqual(reloaded, finished)
    }

    func testFinishedJournalCanBeReplacedByANewResetOperation() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let first = try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [.eraseLocalData, .relaunch]
        )
        try await completeRemainingSteps(in: journal)
        _ = try await journal.finish()

        let second = try await journal.begin(
            kind: .restartTestProfile,
            steps: [.eraseLocalData, .relaunch]
        )

        XCTAssertNotEqual(second.operationID, first.operationID)
        XCTAssertEqual(second.lifecycle, .active)
        XCTAssertEqual(second.kind, .restartTestProfile)
    }

    func testCorruptJournalRaisesAnExplicitErrorAndIsNeverOverwritten() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let corruptData = Data("{ definitely-not-json".utf8)
        try corruptData.write(to: fixture.journalURL)
        let journal = ResetJournal(fileURL: fixture.journalURL)

        do {
            _ = try await journal.resumeResolution()
            XCTFail("Expected corrupt persistence to fail explicitly")
        } catch {
            XCTAssertEqual(error as? ResetJournalError, .corrupted)
        }

        do {
            _ = try await journal.begin(
                kind: .fullFirstRun,
                steps: [.eraseLocalData, .relaunch]
            )
            XCTFail("Expected begin not to overwrite a corrupt journal")
        } catch {
            XCTAssertEqual(error as? ResetJournalError, .corrupted)
        }

        XCTAssertEqual(try Data(contentsOf: fixture.journalURL), corruptData)
    }

    func testExplicitUnreadableDiscardPreservesReadableActiveJournal() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let begun = try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [.eraseLocalData, .relaunch]
        )

        let didDiscard = try await journal.discardUnreadableJournalForExplicitRetry()

        XCTAssertFalse(didDiscard)
        guard case .run(let restored, _) = try await journal.resumeResolution() else {
            return XCTFail("Expected the readable active journal to remain")
        }
        XCTAssertEqual(restored, begun)
    }

    func testExplicitUnreadableDiscardRemovesCorruptJournal() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try Data("{ broken".utf8).write(to: fixture.journalURL)
        let journal = ResetJournal(fileURL: fixture.journalURL)

        let didDiscard = try await journal.discardUnreadableJournalForExplicitRetry()

        XCTAssertTrue(didDiscard)
        let resolution = try await journal.resumeResolution()
        XCTAssertEqual(resolution, .noJournal)
    }

    func testInvalidTransitionDoesNotChangePersistedState() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let journal = ResetJournal(fileURL: fixture.journalURL)
        let begun = try await journal.begin(
            kind: .fullFirstRun,
            steps: [.eraseLocalData, .relaunch]
        )
        let firstID = begun.entries[0].id

        do {
            _ = try await journal.markCompleted(firstID)
            XCTFail("Expected a pending step not to complete without running")
        } catch {
            XCTAssertEqual(error as? ResetJournalError, .invalidTransition)
        }

        let restored = try await journal.resumeResolution()
        guard case .run(let snapshot, let entry) = restored else {
            return XCTFail("Expected the original pending step after a rejected transition")
        }
        XCTAssertEqual(snapshot, begun)
        XCTAssertEqual(entry.id, firstID)
    }

    private func completeRemainingSteps(in journal: ResetJournal) async throws {
        while let pending = try await journal.nextPending() {
            _ = try await journal.markRunning(pending.id)
            _ = try await journal.markCompleted(pending.id)
        }
    }

    private func makeFixture() throws -> JournalFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResetJournalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return JournalFixture(
            root: root,
            journalURL: root.appendingPathComponent("reset-journal.json")
        )
    }
}

private struct JournalFixture {
    let root: URL
    let journalURL: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
