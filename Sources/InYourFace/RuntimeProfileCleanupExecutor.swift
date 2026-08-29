import Foundation

enum RuntimeProfileCleanupExecutorError: Error, Equatable, LocalizedError, Sendable {
    case invalidApplicationSupportDirectory
    case invalidNamespace
    case invalidProductionVaultApplicationIdentifier
    case invalidProductionDefaultsSuiteName
    case unmanagedDefaultsSuite
    case unmanagedVaultApplicationIdentifier
    case protectedDefaultsDomain
    case protectedVaultApplicationIdentifier
    case unsafeApplicationSupportTarget
    case defaultsSuiteUnavailable
    case applicationSupportInspectionFailed
    case applicationSupportRemovalFailed

    var errorDescription: String? {
        switch self {
        case .invalidApplicationSupportDirectory:
            return "The Application Support root is not a safe file-system directory."
        case .invalidNamespace:
            return "The runtime-profile namespace is not a safe identifier."
        case .invalidProductionVaultApplicationIdentifier:
            return "The production vault identifier is not a safe path component."
        case .invalidProductionDefaultsSuiteName:
            return "The production defaults suite is not a safe named domain."
        case .unmanagedDefaultsSuite:
            return "The cleanup intent does not name the managed test defaults suite."
        case .unmanagedVaultApplicationIdentifier:
            return "The cleanup intent does not name the managed test vault directory."
        case .protectedDefaultsDomain:
            return "Cleanup refused to remove the production defaults domain."
        case .protectedVaultApplicationIdentifier:
            return "Cleanup refused to remove the production vault directory."
        case .unsafeApplicationSupportTarget:
            return "The test-profile vault directory escapes the configured Application Support root."
        case .defaultsSuiteUnavailable:
            return "The test-profile defaults suite could not be opened."
        case .applicationSupportInspectionFailed:
            return "The test-profile Application Support directory could not be inspected."
        case .applicationSupportRemovalFailed:
            return "The test-profile Application Support directory could not be removed."
        }
    }
}

/// Deletes one router-issued test profile without inspecting or mutating production state.
///
/// Both identifiers must exactly match the names the runtime-profile router derives from
/// the intent's UUID. This makes a decoded or otherwise untrusted cleanup intent harmless:
/// a merely well-formed arbitrary defaults domain or directory is not enough to authorize
/// its deletion.
struct RuntimeProfileCleanupExecutor {
    private let applicationSupportDirectory: URL
    private let namespace: String
    private let productionVaultApplicationIdentifier: String
    private let productionDefaultsSuiteName: String?
    private let fileManager: FileManager

    init(
        applicationSupportDirectory: URL,
        namespace: String,
        productionVaultApplicationIdentifier: String,
        productionDefaultsSuiteName: String? = Bundle.main.bundleIdentifier,
        fileManager: FileManager = .default
    ) throws {
        let standardizedRoot = applicationSupportDirectory.standardizedFileURL
        guard applicationSupportDirectory.isFileURL,
              standardizedRoot.path != "/",
              !standardizedRoot.path.isEmpty else {
            throw RuntimeProfileCleanupExecutorError.invalidApplicationSupportDirectory
        }
        guard Self.isSafeIdentifier(namespace) else {
            throw RuntimeProfileCleanupExecutorError.invalidNamespace
        }
        guard Self.isSafeIdentifier(productionVaultApplicationIdentifier) else {
            throw RuntimeProfileCleanupExecutorError.invalidProductionVaultApplicationIdentifier
        }
        if let productionDefaultsSuiteName,
           !Self.isSafeIdentifier(productionDefaultsSuiteName) {
            throw RuntimeProfileCleanupExecutorError.invalidProductionDefaultsSuiteName
        }

        self.applicationSupportDirectory = standardizedRoot
        self.namespace = namespace
        self.productionVaultApplicationIdentifier = productionVaultApplicationIdentifier
        self.productionDefaultsSuiteName = productionDefaultsSuiteName
        self.fileManager = fileManager
    }

    /// Repeating a successful cleanup is safe: an absent directory and an absent
    /// persistent domain are both treated as the desired end state.
    func execute(_ intent: RuntimeProfileCleanupIntent) throws {
        let profile = intent.profile
        try validateManagedIdentifiers(for: profile)
        let targetDirectory = try validatedTargetDirectory(for: profile)

        guard let defaults = UserDefaults(suiteName: profile.defaultsSuiteName) else {
            throw RuntimeProfileCleanupExecutorError.defaultsSuiteUnavailable
        }

        if try targetExists(at: targetDirectory) {
            do {
                try fileManager.removeItem(at: targetDirectory)
            } catch {
                throw RuntimeProfileCleanupExecutorError.applicationSupportRemovalFailed
            }
        }
        defaults.removePersistentDomain(forName: profile.defaultsSuiteName)
    }

    private func targetExists(at target: URL) throws -> Bool {
        do {
            _ = try fileManager.attributesOfItem(atPath: target.path)
            return true
        } catch {
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain,
               cocoaError.code == NSFileNoSuchFileError ||
               cocoaError.code == NSFileReadNoSuchFileError {
                return false
            }
            throw RuntimeProfileCleanupExecutorError.applicationSupportInspectionFailed
        }
    }

    private func validateManagedIdentifiers(for profile: RuntimeTestProfile) throws {
        if let productionDefaultsSuiteName,
           profile.defaultsSuiteName == productionDefaultsSuiteName {
            throw RuntimeProfileCleanupExecutorError.protectedDefaultsDomain
        }
        guard profile.vaultApplicationIdentifier != productionVaultApplicationIdentifier else {
            throw RuntimeProfileCleanupExecutorError.protectedVaultApplicationIdentifier
        }

        let id = profile.id.uuidString.lowercased()
        let expectedDefaultsSuite = "\(namespace).runtime-profile.test.\(id).defaults"
        let expectedVaultIdentifier = "\(namespace).runtime-profile.test.\(id).vault"
        guard profile.defaultsSuiteName == expectedDefaultsSuite,
              Self.isSafeIdentifier(profile.defaultsSuiteName) else {
            throw RuntimeProfileCleanupExecutorError.unmanagedDefaultsSuite
        }
        guard profile.vaultApplicationIdentifier == expectedVaultIdentifier,
              Self.isSafeIdentifier(profile.vaultApplicationIdentifier) else {
            throw RuntimeProfileCleanupExecutorError.unmanagedVaultApplicationIdentifier
        }
    }

    private func validatedTargetDirectory(for profile: RuntimeTestProfile) throws -> URL {
        let target = applicationSupportDirectory
            .appendingPathComponent(profile.vaultApplicationIdentifier, isDirectory: true)
            .standardizedFileURL

        guard target.deletingLastPathComponent() == applicationSupportDirectory else {
            throw RuntimeProfileCleanupExecutorError.unsafeApplicationSupportTarget
        }

        let resolvedRoot = applicationSupportDirectory.resolvingSymlinksInPath()
        let resolvedTarget = target.resolvingSymlinksInPath()
        guard Self.isDescendant(resolvedTarget, of: resolvedRoot) else {
            throw RuntimeProfileCleanupExecutorError.unsafeApplicationSupportTarget
        }
        return target
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

    private static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let directoryComponents = directory.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count > directoryComponents.count &&
            Array(candidateComponents.prefix(directoryComponents.count)) == directoryComponents
    }
}
