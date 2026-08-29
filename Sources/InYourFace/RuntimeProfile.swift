import Foundation

enum RuntimeProfile: Equatable, Sendable {
    case production(vaultApplicationIdentifier: String)
    case test(RuntimeTestProfile)

    var defaultsSuiteName: String? {
        switch self {
        case .production:
            return nil
        case .test(let profile):
            return profile.defaultsSuiteName
        }
    }

    var vaultApplicationIdentifier: String {
        switch self {
        case .production(let identifier):
            return identifier
        case .test(let profile):
            return profile.vaultApplicationIdentifier
        }
    }

    var isTest: Bool {
        if case .test = self {
            return true
        }
        return false
    }
}

struct RuntimeTestProfile: Codable, Equatable, Sendable {
    let id: UUID
    let defaultsSuiteName: String
    let vaultApplicationIdentifier: String
    let createdAt: Date

    /// Retained in the v1 journal wire format so existing and rollback builds can
    /// decode the same profile. Current builds never use this value to expire a
    /// Test Mode session and write `Date.distantFuture` for new profiles.
    let expiresAt: Date
}

enum RuntimeProfileCleanupReason: String, Codable, Equatable, Sendable {
    case replacedByFreshTest
    case exitRequested
    /// Decodes cleanup work committed by builds that supported automatic expiry.
    case expired
}

struct RuntimeProfileCleanupIntent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let profile: RuntimeTestProfile
    let reason: RuntimeProfileCleanupReason
    let attemptCount: Int

    fileprivate init(
        id: UUID = UUID(),
        profile: RuntimeTestProfile,
        reason: RuntimeProfileCleanupReason,
        attemptCount: Int = 0
    ) {
        self.id = id
        self.profile = profile
        self.reason = reason
        self.attemptCount = attemptCount
    }

    fileprivate func recordingFailure() -> Self {
        Self(
            id: id,
            profile: profile,
            reason: reason,
            attemptCount: attemptCount + 1
        )
    }
}

enum RuntimeProfileCleanupResult: Equatable, Sendable {
    case succeeded
    case failed
}

enum RuntimeProfileRecovery: Equatable, Sendable {
    /// The marker could not be decoded or failed its managed-profile invariants.
    /// It was replaced with a valid production route without deleting any profile.
    case corruptJournalReplaced
}

struct RuntimeProfileResolution: Equatable, Sendable {
    enum Route: Equatable, Sendable {
        case ready(RuntimeProfile)
        case cleanupRequired
    }

    let route: Route
    let cleanupIntents: [RuntimeProfileCleanupIntent]
    let recovery: RuntimeProfileRecovery?

    var profile: RuntimeProfile? {
        guard case .ready(let profile) = route else { return nil }
        return profile
    }
}

enum RuntimeProfileRouterError: Error, Equatable, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case storageFailure(String)
    case cleanupIntentNotPending(UUID)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return "Runtime profile configuration is invalid: \(reason)."
        case .storageFailure(let operation):
            return "Runtime profile storage failed while \(operation)."
        case .cleanupIntentNotPending:
            return "The test-profile cleanup result no longer matches a pending cleanup."
        }
    }
}

/// Selects one coherent storage profile before app dependencies are constructed.
///
/// The router owns only its small marker journal. It never snapshots production
/// defaults and never deletes a UserDefaults suite or encrypted vault. Instead it
/// returns cleanup intents for a caller that can wait for the previous process to
/// exit before performing destructive cleanup through the appropriate adapters.
@MainActor
final class RuntimeProfileRouter {
    private static let journalVersion = 1
    private static let journalFileName = "runtime-profile-router.v1.json"

    private enum JournalMode: String, Codable {
        case normal
        case test
        case exitingTest
    }

    private struct Journal: Codable {
        let version: Int
        var mode: JournalMode
        var activeTestProfile: RuntimeTestProfile?
        var cleanupIntents: [RuntimeProfileCleanupIntent]

        static var normal: Self {
            Self(
                version: 1,
                mode: .normal,
                activeTestProfile: nil,
                cleanupIntents: []
            )
        }
    }

    private struct LoadedJournal {
        var journal: Journal
        let recovery: RuntimeProfileRecovery?
    }

    private let storageRoot: URL
    private let namespace: String
    private let productionVaultApplicationIdentifier: String
    private let now: @MainActor () -> Date
    private let fileManager: FileManager

    init(
        storageRoot: URL,
        namespace: String,
        productionVaultApplicationIdentifier: String,
        now: @escaping @MainActor () -> Date = Date.init,
        fileManager: FileManager = .default
    ) throws {
        guard storageRoot.isFileURL else {
            throw RuntimeProfileRouterError.invalidConfiguration("the journal root must be a file URL")
        }
        guard Self.isSafeIdentifier(namespace) else {
            throw RuntimeProfileRouterError.invalidConfiguration("the namespace is not a safe identifier")
        }
        guard Self.isSafeIdentifier(productionVaultApplicationIdentifier) else {
            throw RuntimeProfileRouterError.invalidConfiguration(
                "the production vault application identifier is not a safe path component"
            )
        }
        self.storageRoot = storageRoot
        self.namespace = namespace
        self.productionVaultApplicationIdentifier = productionVaultApplicationIdentifier
        self.now = now
        self.fileManager = fileManager
    }

    /// Resolves the profile that may be used to construct app dependencies.
    /// A cleanup-required result deliberately contains no profile.
    func resolveForBootstrap() throws -> RuntimeProfileResolution {
        let loaded = try loadJournal()
        return resolution(for: loaded.journal, recovery: loaded.recovery)
    }

    /// Starts Test First Run from production or replaces the current test profile
    /// with a fresh generation. Replaced generations are returned as cleanup work.
    func beginFreshTest() throws -> RuntimeProfileResolution {
        var loaded = try loadJournal()

        if loaded.journal.mode == .exitingTest {
            return resolution(for: loaded.journal, recovery: loaded.recovery)
        }

        let replacement = makeTestProfile(at: now())
        if let current = loaded.journal.activeTestProfile {
            appendCleanupIntent(
                for: current,
                reason: .replacedByFreshTest,
                to: &loaded.journal.cleanupIntents
            )
        }
        loaded.journal.mode = .test
        loaded.journal.activeTestProfile = replacement
        try persist(loaded.journal)
        return resolution(for: loaded.journal, recovery: loaded.recovery)
    }

    /// Requests exit without exposing production until every test profile that can
    /// contain local credentials has been cleaned by the caller.
    func requestExitTest() throws -> RuntimeProfileResolution {
        var loaded = try loadJournal()

        switch loaded.journal.mode {
        case .normal:
            return resolution(for: loaded.journal, recovery: loaded.recovery)
        case .test:
            guard let active = loaded.journal.activeTestProfile else {
                return try recoverCorruptJournal()
            }
            appendCleanupIntent(
                for: active,
                reason: .exitRequested,
                to: &loaded.journal.cleanupIntents
            )
            loaded.journal.mode = .exitingTest
            loaded.journal.activeTestProfile = nil
            try persist(loaded.journal)
            return resolution(for: loaded.journal, recovery: loaded.recovery)
        case .exitingTest:
            return resolution(for: loaded.journal, recovery: loaded.recovery)
        }
    }

    /// Records only the outcome. The router does not perform the cleanup itself.
    /// A failed cleanup remains durable and is returned again after relaunch.
    func recordCleanupResult(
        _ result: RuntimeProfileCleanupResult,
        for intentID: UUID
    ) throws -> RuntimeProfileResolution {
        var loaded = try loadJournal()
        guard let intentIndex = loaded.journal.cleanupIntents.firstIndex(where: { $0.id == intentID }) else {
            throw RuntimeProfileRouterError.cleanupIntentNotPending(intentID)
        }

        switch result {
        case .succeeded:
            loaded.journal.cleanupIntents.remove(at: intentIndex)
        case .failed:
            loaded.journal.cleanupIntents[intentIndex] = loaded.journal
                .cleanupIntents[intentIndex]
                .recordingFailure()
        }

        if loaded.journal.mode == .exitingTest,
           loaded.journal.cleanupIntents.isEmpty {
            loaded.journal = .normal
        }
        try persist(loaded.journal)
        return resolution(for: loaded.journal, recovery: loaded.recovery)
    }

    private func resolution(
        for journal: Journal,
        recovery: RuntimeProfileRecovery?
    ) -> RuntimeProfileResolution {
        let intents = journal.cleanupIntents.sorted { left, right in
            if left.profile.createdAt == right.profile.createdAt {
                return left.id.uuidString < right.id.uuidString
            }
            return left.profile.createdAt < right.profile.createdAt
        }

        switch journal.mode {
        case .normal:
            return RuntimeProfileResolution(
                route: .ready(.production(
                    vaultApplicationIdentifier: productionVaultApplicationIdentifier
                )),
                cleanupIntents: [],
                recovery: recovery
            )
        case .test:
            guard let active = journal.activeTestProfile else {
                assertionFailure("A validated test journal must have an active profile")
                return RuntimeProfileResolution(
                    route: .cleanupRequired,
                    cleanupIntents: intents,
                    recovery: recovery
                )
            }
            return RuntimeProfileResolution(
                route: .ready(.test(active)),
                cleanupIntents: intents,
                recovery: recovery
            )
        case .exitingTest:
            return RuntimeProfileResolution(
                route: .cleanupRequired,
                cleanupIntents: intents,
                recovery: recovery
            )
        }
    }

    private func loadJournal() throws -> LoadedJournal {
        let journalURL = storageRoot.appendingPathComponent(Self.journalFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: journalURL.path) else {
            let journal = Journal.normal
            try persist(journal)
            return LoadedJournal(journal: journal, recovery: nil)
        }

        let data: Data
        do {
            data = try Data(contentsOf: journalURL)
        } catch {
            throw RuntimeProfileRouterError.storageFailure("reading the marker journal")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let journal = try? decoder.decode(Journal.self, from: data),
              isValid(journal) else {
            return try recoverCorruptJournalLoaded()
        }
        return LoadedJournal(journal: journal, recovery: nil)
    }

    private func recoverCorruptJournal() throws -> RuntimeProfileResolution {
        let loaded = try recoverCorruptJournalLoaded()
        return resolution(for: loaded.journal, recovery: loaded.recovery)
    }

    private func recoverCorruptJournalLoaded() throws -> LoadedJournal {
        let journal = Journal.normal
        try persist(journal)
        return LoadedJournal(journal: journal, recovery: .corruptJournalReplaced)
    }

    private func persist(_ journal: Journal) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(journal)
        } catch {
            throw RuntimeProfileRouterError.storageFailure("encoding the marker journal")
        }

        do {
            try fileManager.createDirectory(
                at: storageRoot,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: storageRoot.path
            )
            let journalURL = storageRoot.appendingPathComponent(Self.journalFileName, isDirectory: false)
            try data.write(to: journalURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: journalURL.path
            )
        } catch {
            throw RuntimeProfileRouterError.storageFailure("atomically writing the marker journal")
        }
    }

    private func makeTestProfile(at date: Date) -> RuntimeTestProfile {
        let id = UUID()
        return RuntimeTestProfile(
            id: id,
            defaultsSuiteName: testDefaultsSuiteName(for: id),
            vaultApplicationIdentifier: testVaultApplicationIdentifier(for: id),
            createdAt: date,
            expiresAt: .distantFuture
        )
    }

    private func appendCleanupIntent(
        for profile: RuntimeTestProfile,
        reason: RuntimeProfileCleanupReason,
        to intents: inout [RuntimeProfileCleanupIntent]
    ) {
        guard !intents.contains(where: { $0.profile.id == profile.id }) else { return }
        intents.append(RuntimeProfileCleanupIntent(profile: profile, reason: reason))
    }

    private func isValid(_ journal: Journal) -> Bool {
        guard journal.version == Self.journalVersion else { return false }
        let cleanupIDs = journal.cleanupIntents.map(\.id)
        let cleanupProfileIDs = journal.cleanupIntents.map(\.profile.id)
        guard Set(cleanupIDs).count == cleanupIDs.count,
              Set(cleanupProfileIDs).count == cleanupProfileIDs.count,
              journal.cleanupIntents.allSatisfy({ intent in
                  intent.attemptCount >= 0 && isManagedTestProfile(intent.profile)
              }) else {
            return false
        }

        switch journal.mode {
        case .normal:
            return journal.activeTestProfile == nil && journal.cleanupIntents.isEmpty
        case .test:
            guard let active = journal.activeTestProfile,
                  isManagedTestProfile(active) else {
                return false
            }
            return !cleanupProfileIDs.contains(active.id)
        case .exitingTest:
            return journal.activeTestProfile == nil && !journal.cleanupIntents.isEmpty
        }
    }

    private func isManagedTestProfile(_ profile: RuntimeTestProfile) -> Bool {
        profile.defaultsSuiteName == testDefaultsSuiteName(for: profile.id) &&
            profile.vaultApplicationIdentifier == testVaultApplicationIdentifier(for: profile.id) &&
            profile.createdAt.timeIntervalSinceReferenceDate.isFinite &&
            profile.expiresAt.timeIntervalSinceReferenceDate.isFinite &&
            profile.expiresAt > profile.createdAt &&
            profile.vaultApplicationIdentifier != productionVaultApplicationIdentifier
    }

    private func testDefaultsSuiteName(for id: UUID) -> String {
        "\(namespace).runtime-profile.test.\(id.uuidString.lowercased()).defaults"
    }

    private func testVaultApplicationIdentifier(for id: UUID) -> String {
        "\(namespace).runtime-profile.test.\(id.uuidString.lowercased()).vault"
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty &&
            trimmed == value &&
            value != "." &&
            value != ".." &&
            !value.contains("/") &&
            !value.contains(":")
    }
}
