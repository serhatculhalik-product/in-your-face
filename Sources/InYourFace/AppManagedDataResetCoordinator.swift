import Combine
import CommitmentProtection
import Foundation

struct AppManagedDataResetPreflight: Equatable, Sendable {
    let accountCount: Int
    let steps: [ResetStep]
}

struct AppManagedDataResetProgress: Equatable, Sendable {
    let operationID: UUID
    let completedStepCount: Int
    let totalStepCount: Int
    let currentStep: ResetStep?
}

enum AppManagedDataResetRecoveryKind: Equatable, Sendable {
    case pending
    case interrupted
    case retrying(ResetStepFailureReason)
    case readyToFinish
}

struct AppManagedDataResetRecovery: Equatable, Sendable {
    let kind: AppManagedDataResetRecoveryKind
    let progress: AppManagedDataResetProgress
}

struct AppManagedDataResetBlock: Equatable, Sendable {
    let progress: AppManagedDataResetProgress
    let reason: ResetStepFailureReason
}

enum AppManagedDataResetCoordinatorError: Error, Equatable, LocalizedError, Sendable {
    case invalidAccountCount
    case unexpectedJournalPlan
    case unexpected

    var errorDescription: String? {
        switch self {
        case .invalidAccountCount:
            return "The reset account count is invalid."
        case .unexpectedJournalPlan:
            return "The saved reset operation is not an app-managed data erase plan."
        case .unexpected:
            return "The app-managed data reset could not continue."
        }
    }
}

enum AppManagedDataResetProblem: Equatable, Sendable {
    case journal(ResetJournalError)
    case coordinator(AppManagedDataResetCoordinatorError)
}

enum AppManagedDataResetCoordinatorState: Equatable, Sendable {
    case idle
    case recovering(AppManagedDataResetRecovery)
    case executing(AppManagedDataResetProgress)
    case blocked(AppManagedDataResetBlock)
    case completed(AppManagedDataResetProgress)
    case unavailable(AppManagedDataResetProblem)
}

extension AppManagedDataResetCoordinatorState {
    var blocksRuntimeChanges: Bool {
        switch self {
        case .recovering, .executing, .blocked, .unavailable:
            return true
        case .idle, .completed:
            return false
        }
    }

    fileprivate var allowsUnreadableJournalRetry: Bool {
        guard case .unavailable(.journal(let error)) = self else { return false }
        return error.allowsDiscardForExplicitRetry
    }

    var allowsExplicitRetry: Bool {
        switch self {
        case .blocked:
            return true
        case .unavailable(.journal(let error)):
            return error.allowsDiscardForExplicitRetry
        case .idle, .recovering, .executing, .completed, .unavailable:
            return false
        }
    }
}

/// Main-actor effects used by the reset coordinator.
///
/// Every mutating closure must be safe to call again after an interrupted attempt.
/// `accountCount` is the read-only seam used by `preflight()`.
struct AppManagedDataResetOperations {
    let accountCount: @MainActor () -> Int
    let stopMonitoring: @MainActor () async -> Void
    let revokeAuthorization: @MainActor (Int) async throws -> GoogleAuthorizationRevocationResult
    let unregisterLaunchAtLogin: @MainActor () async throws -> Void
    let stageRelaunch: @MainActor () throws -> Void
    let commitStagedRelaunch: @MainActor () -> Void
    let cancelStagedRelaunch: @MainActor () -> Void
    let lockMutations: @MainActor () -> Void
    let unlockMutations: @MainActor () -> Void

    init(
        accountCount: @escaping @MainActor () -> Int,
        stopMonitoring: @escaping @MainActor () async -> Void,
        revokeAuthorization: @escaping @MainActor (Int) async throws
            -> GoogleAuthorizationRevocationResult,
        unregisterLaunchAtLogin: @escaping @MainActor () async throws -> Void,
        stageRelaunch: @escaping @MainActor () throws -> Void,
        commitStagedRelaunch: @escaping @MainActor () -> Void,
        cancelStagedRelaunch: @escaping @MainActor () -> Void,
        lockMutations: @escaping @MainActor () -> Void = {},
        unlockMutations: @escaping @MainActor () -> Void = {}
    ) {
        self.accountCount = accountCount
        self.stopMonitoring = stopMonitoring
        self.revokeAuthorization = revokeAuthorization
        self.unregisterLaunchAtLogin = unregisterLaunchAtLogin
        self.stageRelaunch = stageRelaunch
        self.commitStagedRelaunch = commitStagedRelaunch
        self.cancelStagedRelaunch = cancelStagedRelaunch
        self.lockMutations = lockMutations
        self.unlockMutations = unlockMutations
    }
}

/// Runs the durable, ordered erase of data owned by the app.
///
/// The journal receives only non-identifying account ordinals and typed failure
/// categories. Google identifiers and free-form provider errors never cross its seam.
@MainActor
final class AppManagedDataResetCoordinator: ObservableObject {
    @Published private(set) var state: AppManagedDataResetCoordinatorState = .idle

    private let journal: ResetJournal
    private let operations: AppManagedDataResetOperations
    private var isDriving = false
    private var hasStagedRelaunch = false

    convenience init(
        journal: ResetJournal,
        flow: CommitmentProtectionFlow,
        unregisterLaunchAtLogin: @escaping @MainActor () async throws -> Void,
        stageRelaunch: @escaping @MainActor () throws -> Void,
        commitStagedRelaunch: @escaping @MainActor () -> Void,
        cancelStagedRelaunch: @escaping @MainActor () -> Void
    ) {
        self.init(
            journal: journal,
            operations: AppManagedDataResetOperations(
                accountCount: { flow.appManagedDataResetAccountCount },
                stopMonitoring: {
                    await flow.stopMonitoringForAppManagedDataReset()
                },
                revokeAuthorization: { position in
                    try await flow.revokeAuthorizationForAppManagedDataReset(
                        accountPosition: position
                    )
                },
                unregisterLaunchAtLogin: unregisterLaunchAtLogin,
                stageRelaunch: stageRelaunch,
                commitStagedRelaunch: commitStagedRelaunch,
                cancelStagedRelaunch: cancelStagedRelaunch,
                lockMutations: {
                    flow.lockMutationsForAppManagedDataReset()
                },
                unlockMutations: {
                    flow.unlockMutationsForAppManagedDataReset()
                }
            )
        )
    }

    init(
        journal: ResetJournal,
        operations: AppManagedDataResetOperations
    ) {
        self.journal = journal
        self.operations = operations
    }

    /// Computes the exact erase plan without changing coordinator, journal, or system state.
    func preflight() throws -> AppManagedDataResetPreflight {
        let accountCount = operations.accountCount()
        guard accountCount >= 0 else {
            throw AppManagedDataResetCoordinatorError.invalidAccountCount
        }

        let revocations = (0..<accountCount).map {
            ResetStep.revokeGoogleAuthorization(position: $0)
        }
        return AppManagedDataResetPreflight(
            accountCount: accountCount,
            steps: revocations + [
                .unregisterLaunchAtLogin,
                .eraseLocalData,
                .relaunch
            ]
        )
    }

    /// Starts a new erase or continues the already-active erase idempotently.
    @discardableResult
    func begin() async throws -> AppManagedDataResetCoordinatorState {
        guard !isDriving else { return state }
        let shouldDiscardUnreadableJournal = state.allowsUnreadableJournalRetry
        isDriving = true
        operations.lockMutations()
        // Until an unreadable journal has been safely discarded, conservatively
        // treat it as a potentially committed reset and keep mutations locked if
        // the explicit recovery attempt itself fails.
        var resetWasCommitted = shouldDiscardUnreadableJournal
        defer {
            isDriving = false
            if !resetWasCommitted {
                operations.unlockMutations()
            }
        }

        do {
            if shouldDiscardUnreadableJournal {
                let didDiscard = try await journal.discardUnreadableJournalForExplicitRetry()
                resetWasCommitted = !didDiscard
            }
            let existing = try await journal.resumeResolution()
            switch existing {
            case .run(let snapshot, _),
                 .reconcile(let snapshot, _),
                 .retry(let snapshot, _),
                 .readyToFinish(let snapshot):
                resetWasCommitted = true
                try Self.validateErasePlan(snapshot)
                return try await drive(resuming: true)
            case .noJournal, .finished:
                // No active journal owns the mutation gate yet. If preflight or
                // persistence fails below, release the gate for normal app use.
                resetWasCommitted = false
                let plan = try preflight()
                _ = try await journal.begin(
                    kind: .eraseAppManagedData,
                    steps: plan.steps
                )
                resetWasCommitted = true
                return try await drive(resuming: false)
            }
        } catch {
            if let journalError = error as? ResetJournalError,
               journalError.allowsDiscardForExplicitRetry {
                resetWasCommitted = true
            }
            publishUnavailable(error)
            throw error
        }
    }

    /// Continues a persisted erase from its first non-terminal step.
    @discardableResult
    func resume() async throws -> AppManagedDataResetCoordinatorState {
        guard !isDriving else { return state }
        if case .completed = state { return state }
        isDriving = true
        operations.lockMutations()
        var resetWasCommitted = false
        defer {
            isDriving = false
            if !resetWasCommitted {
                operations.unlockMutations()
            }
        }

        do {
            let existing = try await journal.resumeResolution()
            switch existing {
            case .run(let snapshot, _),
                 .reconcile(let snapshot, _),
                 .retry(let snapshot, _),
                 .readyToFinish(let snapshot):
                resetWasCommitted = true
                try Self.validateErasePlan(snapshot)
            case .noJournal:
                break
            case .finished(let snapshot):
                try Self.validateErasePlan(snapshot)
                state = .idle
                return state
            }
            return try await drive(resuming: true)
        } catch {
            if let journalError = error as? ResetJournalError,
               journalError.allowsDiscardForExplicitRetry {
                resetWasCommitted = true
            }
            publishUnavailable(error)
            throw error
        }
    }

    private func drive(
        resuming: Bool
    ) async throws -> AppManagedDataResetCoordinatorState {
        var stoppedMonitoring = false
        var publishedRecovery = false
        defer {
            cancelStagedRelaunchIfNeeded()
        }

        while true {
            let resolution = try await journal.resumeResolution()
            switch resolution {
            case .noJournal:
                state = .idle
                return state

            case .finished(let snapshot):
                try Self.validateErasePlan(snapshot)
                state = .completed(Self.progress(for: snapshot, currentStep: nil))
                return state

            case .readyToFinish(let snapshot):
                try Self.validateErasePlan(snapshot)
                if resuming, !publishedRecovery {
                    state = .recovering(
                        AppManagedDataResetRecovery(
                            kind: .readyToFinish,
                            progress: Self.progress(for: snapshot, currentStep: nil)
                        )
                    )
                    publishedRecovery = true
                }
                if !stoppedMonitoring {
                    await operations.stopMonitoring()
                    stoppedMonitoring = true
                }
                do {
                    hasStagedRelaunch = true
                    try operations.stageRelaunch()
                    let finished = try await journal.finish()
                    state = .completed(Self.progress(for: finished, currentStep: nil))
                    commitStagedRelaunchIfNeeded()
                } catch {
                    cancelStagedRelaunchIfNeeded()
                    let reason = Self.failureReason(for: .relaunch, error: error)
                    state = .blocked(
                        AppManagedDataResetBlock(
                            progress: Self.progress(for: snapshot, currentStep: .relaunch),
                            reason: reason
                        )
                    )
                }
                return state

            case .run(let snapshot, let entry):
                try Self.validateErasePlan(snapshot)
                if resuming, !publishedRecovery {
                    publishRecovery(.pending, snapshot: snapshot, entry: entry)
                    publishedRecovery = true
                }
                if !stoppedMonitoring {
                    await operations.stopMonitoring()
                    stoppedMonitoring = true
                }
                guard try await run(entry) else { return state }

            case .reconcile(let snapshot, let entry):
                try Self.validateErasePlan(snapshot)
                if resuming, !publishedRecovery {
                    publishRecovery(.interrupted, snapshot: snapshot, entry: entry)
                    publishedRecovery = true
                }
                if !stoppedMonitoring {
                    await operations.stopMonitoring()
                    stoppedMonitoring = true
                }
                guard try await run(entry) else { return state }

            case .retry(let snapshot, let entry):
                try Self.validateErasePlan(snapshot)
                guard case .failed(let reason) = entry.status else {
                    throw AppManagedDataResetCoordinatorError.unexpectedJournalPlan
                }
                if resuming, !publishedRecovery {
                    publishRecovery(.retrying(reason), snapshot: snapshot, entry: entry)
                    publishedRecovery = true
                }
                if !stoppedMonitoring {
                    await operations.stopMonitoring()
                    stoppedMonitoring = true
                }
                guard try await run(entry) else { return state }
            }
        }
    }

    private func run(_ entry: ResetJournalEntry) async throws -> Bool {
        if entry.step == .eraseLocalData {
            let skipped = try await journal.markSkipped(
                entry.id,
                reason: .delegatedToPostExitHelper
            )
            state = .executing(Self.progress(for: skipped, currentStep: nil))
            return true
        }

        let running = try await journal.markRunning(entry.id)
        state = .executing(Self.progress(for: running, currentStep: entry.step))

        do {
            let outcome = try await perform(entry.step)
            switch outcome {
            case .completed:
                if entry.step == .relaunch {
                    let finished = try await journal.completeFinalStepAndFinish(entry.id)
                    state = .completed(Self.progress(for: finished, currentStep: nil))
                    commitStagedRelaunchIfNeeded()
                    return false
                }
                let completed = try await journal.markCompleted(entry.id)
                state = .executing(Self.progress(for: completed, currentStep: nil))
            case .skipped(let reason):
                let skipped = try await journal.markSkipped(entry.id, reason: reason)
                state = .executing(Self.progress(for: skipped, currentStep: nil))
            }
            return true
        } catch {
            cancelStagedRelaunchIfNeeded()
            let reason = Self.failureReason(for: entry.step, error: error)
            let failed = try await journal.markFailed(entry.id, reason: reason)
            state = .blocked(
                AppManagedDataResetBlock(
                    progress: Self.progress(for: failed, currentStep: entry.step),
                    reason: reason
                )
            )
            return false
        }
    }

    private enum StepOutcome {
        case completed
        case skipped(ResetStepSkipReason)
    }

    private func perform(_ step: ResetStep) async throws -> StepOutcome {
        switch step {
        case .revokeGoogleAuthorization(let position):
            switch try await operations.revokeAuthorization(position) {
            case .revoked, .alreadyInvalid:
                return .completed
            case .localCredentialMissing:
                return .skipped(.noUsableLocalGrant)
            }
        case .unregisterLaunchAtLogin:
            try await operations.unregisterLaunchAtLogin()
            return .completed
        case .eraseLocalData:
            return .skipped(.delegatedToPostExitHelper)
        case .relaunch:
            hasStagedRelaunch = true
            try operations.stageRelaunch()
            return .completed
        case .resetTCC:
            throw AppManagedDataResetCoordinatorError.unexpectedJournalPlan
        }
    }

    private func commitStagedRelaunchIfNeeded() {
        guard hasStagedRelaunch else { return }
        hasStagedRelaunch = false
        operations.commitStagedRelaunch()
    }

    private func cancelStagedRelaunchIfNeeded() {
        guard hasStagedRelaunch else { return }
        hasStagedRelaunch = false
        operations.cancelStagedRelaunch()
    }

    private func publishRecovery(
        _ kind: AppManagedDataResetRecoveryKind,
        snapshot: ResetJournalSnapshot,
        entry: ResetJournalEntry
    ) {
        state = .recovering(
            AppManagedDataResetRecovery(
                kind: kind,
                progress: Self.progress(for: snapshot, currentStep: entry.step)
            )
        )
    }

    private func publishUnavailable(_ error: any Error) {
        if let journalError = error as? ResetJournalError {
            state = .unavailable(.journal(journalError))
        } else if let coordinatorError = error as? AppManagedDataResetCoordinatorError {
            state = .unavailable(.coordinator(coordinatorError))
        } else {
            state = .unavailable(.coordinator(.unexpected))
        }
    }

    private static func progress(
        for snapshot: ResetJournalSnapshot,
        currentStep: ResetStep?
    ) -> AppManagedDataResetProgress {
        AppManagedDataResetProgress(
            operationID: snapshot.operationID,
            completedStepCount: snapshot.entries.filter {
                switch $0.status {
                case .completed, .skipped:
                    return true
                case .pending, .running, .failed:
                    return false
                }
            }.count,
            totalStepCount: snapshot.entries.count,
            currentStep: currentStep
        )
    }

    private static func failureReason(
        for step: ResetStep,
        error: any Error
    ) -> ResetStepFailureReason {
        switch step {
        case .revokeGoogleAuthorization:
            return revocationFailureReason(error)
        case .unregisterLaunchAtLogin:
            return .unavailable
        case .eraseLocalData:
            return .ioFailure
        case .relaunch:
            return .unavailable
        case .resetTCC:
            return .unexpected
        }
    }

    private static func revocationFailureReason(
        _ error: any Error
    ) -> ResetStepFailureReason {
        guard let connectorError = error as? GoogleCalendarConnectorError else {
            return .ambiguousOutcome
        }

        switch connectorError {
        case .networkUnavailable, .requestTimedOut:
            return .transient
        case .tokenRevocationFailed(let statusCode, _)
            where statusCode == 429 || (500...599).contains(statusCode):
            return .transient
        case .missingClientID,
             .unableToOpenBrowser,
             .authorizationCancelled,
             .authorizationTimedOut,
             .authorizationFailed,
             .invalidCallback,
             .tokenExchangeFailed,
             .tokenRevocationFailed,
             .missingRefreshToken,
             .asynchronousCredentialRemovalRequired,
             .unexpectedAccount,
             .calendarRequestFailed,
             .requestFailed,
             .malformedResponse:
            return .ambiguousOutcome
        }
    }

    private static func validateErasePlan(
        _ snapshot: ResetJournalSnapshot
    ) throws {
        guard snapshot.kind == .eraseAppManagedData else {
            throw AppManagedDataResetCoordinatorError.unexpectedJournalPlan
        }

        let steps = snapshot.entries.map(\.step)
        let terminalSteps: [ResetStep] = [
            .unregisterLaunchAtLogin,
            .eraseLocalData,
            .relaunch
        ]
        guard steps.count >= terminalSteps.count,
              Array(steps.suffix(terminalSteps.count)) == terminalSteps else {
            throw AppManagedDataResetCoordinatorError.unexpectedJournalPlan
        }

        let revocations = steps.dropLast(terminalSteps.count)
        for (position, step) in revocations.enumerated() {
            guard step == .revokeGoogleAuthorization(position: position) else {
                throw AppManagedDataResetCoordinatorError.unexpectedJournalPlan
            }
        }
    }
}
