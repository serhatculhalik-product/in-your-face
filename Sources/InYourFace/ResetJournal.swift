import Foundation

enum ResetKind: String, Codable, Equatable, Sendable {
    case eraseAppManagedData
    case fullFirstRun
    case restartTestProfile
    case exitTestMode
}

enum ResetTCCService: String, Codable, Equatable, Sendable {
    case accessibility
    case inputMonitoring
}

/// One idempotent operation in a reset plan.
///
/// Google accounts are deliberately addressed by ordinal, never by account ID. The
/// coordinator resolves the ordinal against a stable, sorted account list retained
/// inside encrypted storage until every revocation step reaches a terminal state.
enum ResetStep: Codable, Equatable, Sendable {
    case revokeGoogleAuthorization(position: Int)
    case unregisterLaunchAtLogin
    /// V1 journal marker. The coordinator records delegation here; the embedded
    /// helper performs the actual filesystem cleanup after the app process exits.
    case eraseLocalData
    case resetTCC(ResetTCCService)
    case relaunch

    private enum CodingKeys: String, CodingKey {
        case type
        case position
        case service
    }

    private enum StepType: String, Codable {
        case revokeGoogleAuthorization
        case unregisterLaunchAtLogin
        case eraseLocalData
        case resetTCC
        case relaunch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(StepType.self, forKey: .type) {
        case .revokeGoogleAuthorization:
            self = .revokeGoogleAuthorization(
                position: try container.decode(Int.self, forKey: .position)
            )
        case .unregisterLaunchAtLogin:
            self = .unregisterLaunchAtLogin
        case .eraseLocalData:
            self = .eraseLocalData
        case .resetTCC:
            self = .resetTCC(
                try container.decode(ResetTCCService.self, forKey: .service)
            )
        case .relaunch:
            self = .relaunch
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .revokeGoogleAuthorization(let position):
            try container.encode(StepType.revokeGoogleAuthorization, forKey: .type)
            try container.encode(position, forKey: .position)
        case .unregisterLaunchAtLogin:
            try container.encode(StepType.unregisterLaunchAtLogin, forKey: .type)
        case .eraseLocalData:
            try container.encode(StepType.eraseLocalData, forKey: .type)
        case .resetTCC(let service):
            try container.encode(StepType.resetTCC, forKey: .type)
            try container.encode(service, forKey: .service)
        case .relaunch:
            try container.encode(StepType.relaunch, forKey: .type)
        }
    }
}

/// Safe, non-identifying failure categories suitable for plaintext journal metadata.
enum ResetStepFailureReason: String, Codable, Equatable, Sendable {
    case transient
    case ambiguousOutcome
    case permissionDenied
    case unavailable
    case ioFailure
    case unexpected
}

/// Reasons for intentionally advancing past an idempotent step.
enum ResetStepSkipReason: String, Codable, Equatable, Sendable {
    case alreadySatisfied
    case noUsableLocalGrant
    case credentialPermanentlyUnreadable
    case protectedStorePermanentlyUnreadable
    case delegatedToPostExitHelper
}

enum ResetStepStatus: Codable, Equatable, Sendable {
    case pending
    case running
    case completed
    case failed(ResetStepFailureReason)
    case skipped(ResetStepSkipReason)

    fileprivate var isTerminal: Bool {
        switch self {
        case .completed, .skipped:
            return true
        case .pending, .running, .failed:
            return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case failureReason
        case skipReason
    }

    private enum State: String, Codable {
        case pending
        case running
        case completed
        case failed
        case skipped
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .pending:
            self = .pending
        case .running:
            self = .running
        case .completed:
            self = .completed
        case .failed:
            self = .failed(
                try container.decode(ResetStepFailureReason.self, forKey: .failureReason)
            )
        case .skipped:
            self = .skipped(
                try container.decode(ResetStepSkipReason.self, forKey: .skipReason)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pending:
            try container.encode(State.pending, forKey: .state)
        case .running:
            try container.encode(State.running, forKey: .state)
        case .completed:
            try container.encode(State.completed, forKey: .state)
        case .failed(let reason):
            try container.encode(State.failed, forKey: .state)
            try container.encode(reason, forKey: .failureReason)
        case .skipped(let reason):
            try container.encode(State.skipped, forKey: .state)
            try container.encode(reason, forKey: .skipReason)
        }
    }
}

enum ResetJournalLifecycle: String, Codable, Equatable, Sendable {
    case active
    case finished
}

struct ResetJournalEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let order: Int
    let step: ResetStep
    fileprivate(set) var status: ResetStepStatus
    fileprivate(set) var attemptCount: Int
}

struct ResetJournalSnapshot: Codable, Equatable, Sendable {
    fileprivate static let currentFormatVersion = 1

    let formatVersion: Int
    let operationID: UUID
    let kind: ResetKind
    let createdAt: Date
    fileprivate(set) var updatedAt: Date
    fileprivate(set) var finishedAt: Date?
    fileprivate(set) var lifecycle: ResetJournalLifecycle
    fileprivate(set) var entries: [ResetJournalEntry]
}

enum ResetResumeResolution: Equatable, Sendable {
    case noJournal
    case run(ResetJournalSnapshot, ResetJournalEntry)
    case reconcile(ResetJournalSnapshot, ResetJournalEntry)
    case retry(ResetJournalSnapshot, ResetJournalEntry)
    case readyToFinish(ResetJournalSnapshot)
    case finished(ResetJournalSnapshot)
}

enum ResetJournalError: Error, Equatable, LocalizedError, Sendable {
    case journalAlreadyActive
    case noJournal
    case operationFinished
    case unfinished
    case invalidPlan
    case entryNotFound
    case invalidTransition
    case invalidSkipReason
    case unsupportedFormat
    case corrupted
    case readFailed
    case writeFailed

    var allowsDiscardForExplicitRetry: Bool {
        switch self {
        case .unsupportedFormat, .corrupted, .readFailed:
            return true
        case .journalAlreadyActive, .noJournal, .operationFinished, .unfinished,
             .invalidPlan, .entryNotFound, .invalidTransition, .invalidSkipReason,
             .writeFailed:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .journalAlreadyActive:
            return "A different reset operation is already active."
        case .noJournal:
            return "No reset operation has been started."
        case .operationFinished:
            return "The reset operation has already finished."
        case .unfinished:
            return "Every reset step must be completed or skipped before finishing."
        case .invalidPlan:
            return "The reset plan is invalid."
        case .entryNotFound:
            return "The reset step does not belong to this operation."
        case .invalidTransition:
            return "The reset step cannot make that state transition."
        case .invalidSkipReason:
            return "That skip reason does not apply to this reset step."
        case .unsupportedFormat:
            return "The reset journal uses an unsupported format."
        case .corrupted:
            return "The reset journal is damaged and was left untouched."
        case .readFailed:
            return "The reset journal could not be read."
        case .writeFailed:
            return "The reset journal could not be saved atomically."
        }
    }
}

enum ResetJournalBootstrapInspection: Equatable, Sendable {
    case none
    case recovery(requiresProtectedStorage: Bool)
    case unreadable
    case unsafe
}

extension ResetJournalBootstrapInspection {
    var requiresAutomaticResume: Bool {
        switch self {
        case .recovery, .unreadable:
            return true
        case .none, .unsafe:
            return false
        }
    }
}

/// Persists and validates one ordered reset operation.
///
/// Calls are serialized within this process. A coordinator handing the journal to a
/// helper must stop being a writer before the helper begins. The JSON contains only
/// non-identifying ordinals and typed reasons; callers must not add Google-derived
/// identifiers or free-form Google error text to this persistence seam.
actor ResetJournal {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    static func inspectForBootstrap(
        fileURL: URL,
        expectedKind: ResetKind,
        fileManager: FileManager = .default
    ) -> ResetJournalBootstrapInspection {
        let parentDirectory = fileURL.deletingLastPathComponent()
        do {
            let parentAttributes = try fileManager.attributesOfItem(
                atPath: parentDirectory.path
            )
            guard parentAttributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                return .unsafe
            }
        } catch {
            return Self.isMissingFileError(error) ? .none : .unreadable
        }

        do {
            let fileAttributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            guard fileAttributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                return .unsafe
            }
        } catch {
            return Self.isMissingFileError(error) ? .none : .unreadable
        }

        let snapshot: ResetJournalSnapshot
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            snapshot = try decoder.decode(
                ResetJournalSnapshot.self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            return .unreadable
        }
        guard snapshot.formatVersion == ResetJournalSnapshot.currentFormatVersion,
              snapshot.kind == expectedKind,
              !snapshot.entries.isEmpty else {
            return .unreadable
        }
        guard snapshot.lifecycle == .active else { return .none }

        let requiresProtectedStorage = snapshot.entries.contains { entry in
            guard case .revokeGoogleAuthorization = entry.step else { return false }
            return !entry.status.isTerminal
        }
        return .recovery(requiresProtectedStorage: requiresProtectedStorage)
    }

    @discardableResult
    func begin(kind: ResetKind, steps: [ResetStep]) throws -> ResetJournalSnapshot {
        let existing = try load()
        try validatePlan(steps)

        if let existing, existing.lifecycle == .active {
            guard existing.kind == kind,
                  existing.entries.map(\.step) == steps else {
                throw ResetJournalError.journalAlreadyActive
            }
            return existing
        }

        let now = Self.currentTimestamp()
        let snapshot = ResetJournalSnapshot(
            formatVersion: ResetJournalSnapshot.currentFormatVersion,
            operationID: UUID(),
            kind: kind,
            createdAt: now,
            updatedAt: now,
            finishedAt: nil,
            lifecycle: .active,
            entries: steps.enumerated().map { order, step in
                ResetJournalEntry(
                    id: UUID(),
                    order: order,
                    step: step,
                    status: .pending,
                    attemptCount: 0
                )
            }
        )
        try persist(snapshot)
        return snapshot
    }

    func nextPending() throws -> ResetJournalEntry? {
        let snapshot = try requireJournal()
        guard snapshot.lifecycle == .active else { return nil }
        guard let entry = firstUnresolvedEntry(in: snapshot) else { return nil }
        guard entry.status == .pending else { return nil }
        return entry
    }

    @discardableResult
    func markRunning(_ entryID: UUID) throws -> ResetJournalSnapshot {
        try updateEntry(entryID) { entry in
            if entry.status == .running {
                return false
            }
            switch entry.status {
            case .pending, .failed:
                entry.status = .running
                entry.attemptCount += 1
                return true
            case .running:
                return false
            case .completed, .skipped:
                throw ResetJournalError.invalidTransition
            }
        }
    }

    @discardableResult
    func markCompleted(_ entryID: UUID) throws -> ResetJournalSnapshot {
        try updateEntry(entryID) { entry in
            if entry.status == .completed {
                return false
            }
            guard entry.status == .running else {
                throw ResetJournalError.invalidTransition
            }
            entry.status = .completed
            return true
        }
    }

    @discardableResult
    func markFailed(
        _ entryID: UUID,
        reason: ResetStepFailureReason
    ) throws -> ResetJournalSnapshot {
        try updateEntry(entryID) { entry in
            if entry.status == .failed(reason) {
                return false
            }
            guard entry.status == .running else {
                throw ResetJournalError.invalidTransition
            }
            entry.status = .failed(reason)
            return true
        }
    }

    @discardableResult
    func markSkipped(
        _ entryID: UUID,
        reason: ResetStepSkipReason
    ) throws -> ResetJournalSnapshot {
        try updateEntry(entryID) { entry in
            if entry.status == .skipped(reason) {
                return false
            }
            guard Self.canSkip(entry.step, because: reason) else {
                throw ResetJournalError.invalidSkipReason
            }
            switch entry.status {
            case .pending, .running, .failed:
                entry.status = .skipped(reason)
                return true
            case .completed, .skipped:
                throw ResetJournalError.invalidTransition
            }
        }
    }

    func resumeResolution() throws -> ResetResumeResolution {
        guard let snapshot = try load() else { return .noJournal }
        if snapshot.lifecycle == .finished {
            return .finished(snapshot)
        }
        guard let entry = firstUnresolvedEntry(in: snapshot) else {
            return .readyToFinish(snapshot)
        }
        switch entry.status {
        case .pending:
            return .run(snapshot, entry)
        case .running:
            return .reconcile(snapshot, entry)
        case .failed:
            return .retry(snapshot, entry)
        case .completed, .skipped:
            preconditionFailure("Terminal entries cannot be the first unresolved entry")
        }
    }

    /// Deletes the plaintext journal only after proving it cannot be safely read.
    ///
    /// This is intentionally separate from `begin`: normal begin and recovery
    /// paths never replace a readable active journal. The coordinator calls this
    /// only after the user explicitly retries a previously reported unreadable
    /// journal.
    @discardableResult
    func discardUnreadableJournalForExplicitRetry() throws -> Bool {
        guard fileManager.fileExists(atPath: fileURL.path) else { return false }

        do {
            _ = try load()
            // The journal became readable between the reported failure and the
            // explicit retry. Preserve it so normal recovery can resume it.
            return false
        } catch let error as ResetJournalError where error.allowsDiscardForExplicitRetry {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                throw ResetJournalError.writeFailed
            }
            return true
        }
    }

    @discardableResult
    func finish() throws -> ResetJournalSnapshot {
        var snapshot = try requireJournal()
        if snapshot.lifecycle == .finished {
            return snapshot
        }
        guard snapshot.entries.allSatisfy({ $0.status.isTerminal }) else {
            throw ResetJournalError.unfinished
        }
        let now = max(Self.currentTimestamp(), snapshot.updatedAt)
        snapshot.lifecycle = .finished
        snapshot.finishedAt = now
        snapshot.updatedAt = now
        try persist(snapshot)
        return snapshot
    }

    /// Completes the last running step and the journal lifecycle in one write.
    ///
    /// Relaunch helpers are staged before this transition and committed only
    /// after it returns. Persisting both terminal changes together prevents a
    /// recoverable write failure from leaving cleanup delegated without a helper.
    @discardableResult
    func completeFinalStepAndFinish(
        _ entryID: UUID
    ) throws -> ResetJournalSnapshot {
        var snapshot = try requireJournal()
        guard snapshot.lifecycle == .active else {
            throw ResetJournalError.operationFinished
        }
        guard let index = snapshot.entries.firstIndex(where: { $0.id == entryID }) else {
            throw ResetJournalError.entryNotFound
        }
        guard index == snapshot.entries.indices.last,
              snapshot.entries[index].status == .running,
              snapshot.entries[..<index].allSatisfy({ $0.status.isTerminal }) else {
            throw ResetJournalError.invalidTransition
        }

        snapshot.entries[index].status = .completed
        let now = max(Self.currentTimestamp(), snapshot.updatedAt)
        snapshot.lifecycle = .finished
        snapshot.finishedAt = now
        snapshot.updatedAt = now
        try persist(snapshot)
        return snapshot
    }

    private func updateEntry(
        _ entryID: UUID,
        transition: (inout ResetJournalEntry) throws -> Bool
    ) throws -> ResetJournalSnapshot {
        var snapshot = try requireJournal()
        guard snapshot.lifecycle == .active else {
            throw ResetJournalError.operationFinished
        }
        guard let index = snapshot.entries.firstIndex(where: { $0.id == entryID }) else {
            throw ResetJournalError.entryNotFound
        }

        let currentStatus = snapshot.entries[index].status
        if currentStatus.isTerminal {
            var terminalEntry = snapshot.entries[index]
            let changed = try transition(&terminalEntry)
            precondition(!changed, "A terminal idempotent transition must not mutate state")
            return snapshot
        }

        guard snapshot.entries[..<index].allSatisfy({ $0.status.isTerminal }),
              index == snapshot.entries.firstIndex(where: { !$0.status.isTerminal }) else {
            throw ResetJournalError.invalidTransition
        }

        var entry = snapshot.entries[index]
        let changed = try transition(&entry)
        guard changed else { return snapshot }
        snapshot.entries[index] = entry
        snapshot.updatedAt = max(Self.currentTimestamp(), snapshot.updatedAt)
        try validate(snapshot)
        try persist(snapshot)
        return snapshot
    }

    private func requireJournal() throws -> ResetJournalSnapshot {
        guard let snapshot = try load() else {
            throw ResetJournalError.noJournal
        }
        return snapshot
    }

    private func load() throws -> ResetJournalSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ResetJournalError.readFailed
        }

        let snapshot: ResetJournalSnapshot
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            snapshot = try decoder.decode(ResetJournalSnapshot.self, from: data)
        } catch {
            throw ResetJournalError.corrupted
        }
        guard snapshot.formatVersion == ResetJournalSnapshot.currentFormatVersion else {
            throw ResetJournalError.unsupportedFormat
        }
        do {
            try validate(snapshot)
        } catch ResetJournalError.unsupportedFormat {
            throw ResetJournalError.unsupportedFormat
        } catch {
            throw ResetJournalError.corrupted
        }
        return snapshot
    }

    private func persist(_ snapshot: ResetJournalSnapshot) throws {
        try validate(snapshot)

        let parentDirectory = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: parentDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw ResetJournalError.writeFailed
        }

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(snapshot)
        } catch {
            throw ResetJournalError.writeFailed
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ResetJournalError.writeFailed
        }
    }

    private static func isMissingFileError(_ error: any Error) -> Bool {
        let cocoaError = error as NSError
        return cocoaError.domain == NSCocoaErrorDomain &&
            (cocoaError.code == NSFileNoSuchFileError ||
                cocoaError.code == NSFileReadNoSuchFileError)
    }

    private func validatePlan(_ steps: [ResetStep]) throws {
        guard !steps.isEmpty else {
            throw ResetJournalError.invalidPlan
        }
        var positions: Set<Int> = []
        for step in steps {
            guard case .revokeGoogleAuthorization(let position) = step else { continue }
            guard position >= 0, positions.insert(position).inserted else {
                throw ResetJournalError.invalidPlan
            }
        }
    }

    private func validate(_ snapshot: ResetJournalSnapshot) throws {
        guard snapshot.formatVersion == ResetJournalSnapshot.currentFormatVersion else {
            throw ResetJournalError.unsupportedFormat
        }
        guard !snapshot.entries.isEmpty,
              snapshot.updatedAt >= snapshot.createdAt,
              Set(snapshot.entries.map(\.id)).count == snapshot.entries.count else {
            throw ResetJournalError.corrupted
        }
        try validatePlan(snapshot.entries.map(\.step))

        switch snapshot.lifecycle {
        case .active:
            guard snapshot.finishedAt == nil else {
                throw ResetJournalError.corrupted
            }
        case .finished:
            guard let finishedAt = snapshot.finishedAt,
                  finishedAt >= snapshot.createdAt,
                  snapshot.entries.allSatisfy({ $0.status.isTerminal }) else {
                throw ResetJournalError.corrupted
            }
        }

        enum SequenceState {
            case terminalPrefix
            case pendingSuffix
            case blockedThenPending
        }
        var sequenceState = SequenceState.terminalPrefix

        for (expectedOrder, entry) in snapshot.entries.enumerated() {
            guard entry.order == expectedOrder, entry.attemptCount >= 0 else {
                throw ResetJournalError.corrupted
            }
            switch entry.status {
            case .completed:
                guard sequenceState == .terminalPrefix, entry.attemptCount >= 1 else {
                    throw ResetJournalError.corrupted
                }
            case .skipped:
                guard sequenceState == .terminalPrefix else {
                    throw ResetJournalError.corrupted
                }
            case .pending:
                guard entry.attemptCount == 0 else {
                    throw ResetJournalError.corrupted
                }
                switch sequenceState {
                case .terminalPrefix:
                    sequenceState = .pendingSuffix
                case .pendingSuffix, .blockedThenPending:
                    break
                }
            case .running, .failed:
                guard sequenceState == .terminalPrefix, entry.attemptCount >= 1 else {
                    throw ResetJournalError.corrupted
                }
                sequenceState = .blockedThenPending
            }
        }
    }

    private func firstUnresolvedEntry(
        in snapshot: ResetJournalSnapshot
    ) -> ResetJournalEntry? {
        snapshot.entries.first { !$0.status.isTerminal }
    }

    private static func canSkip(
        _ step: ResetStep,
        because reason: ResetStepSkipReason
    ) -> Bool {
        switch reason {
        case .alreadySatisfied:
            return true
        case .noUsableLocalGrant,
             .credentialPermanentlyUnreadable,
             .protectedStorePermanentlyUnreadable:
            if case .revokeGoogleAuthorization = step {
                return true
            }
            return false
        case .delegatedToPostExitHelper:
            return step == .eraseLocalData
        }
    }

    /// Foundation can represent a freshly-created Date more precisely than its
    /// Codable epoch value. Canonicalizing at creation makes persisted snapshots
    /// exactly equal to their decoded form, not merely equal within a tolerance.
    private static func currentTimestamp() -> Date {
        let secondsSince1970 = Date().timeIntervalSince1970
        return Date(timeIntervalSince1970: secondsSince1970)
    }
}
