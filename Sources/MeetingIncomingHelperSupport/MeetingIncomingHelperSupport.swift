import Darwin
import Foundation

package enum MeetingIncomingHelperError: Error, Equatable {
    case invalidArguments
    case operationReadFailed(String)
    case helperNotEmbeddedInApplicationBundle
    case unsupportedOperationVersion(Int)
    case invalidParentProcessIdentifier(Int32)
    case parentWaitFailed(Int32)
    case bundleIdentifierMustBeInternal(String)
    case invalidBundleIdentifier(String)
    case applicationBundleMismatch
    case homeDirectoryMismatch
    case invalidApplicationBundle
    case internalBuildMarkerMissing
    case unsafeResetTarget(String)
    case commandFailed(String, Int32)
    case fileRemovalFailed(String)
    case unsafeOperationFile(String)
    case receiptPersistenceFailed
    case resetOperationFailed(MeetingIncomingResetFailureCategory)
}

extension MeetingIncomingHelperError: LocalizedError {
    package var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: helper --operation <operation.json>"
        case .operationReadFailed:
            return "The helper operation could not be read."
        case .helperNotEmbeddedInApplicationBundle:
            return "The helper must run from an application’s Contents/Helpers directory."
        case .unsupportedOperationVersion:
            return "The helper operation version is unsupported."
        case .invalidParentProcessIdentifier:
            return "The parent process identifier is invalid."
        case .parentWaitFailed:
            return "The helper could not wait for the parent application to exit."
        case .bundleIdentifierMustBeInternal:
            return "Destructive reset is restricted to an internal application bundle."
        case .invalidBundleIdentifier:
            return "The application bundle identifier is invalid."
        case .applicationBundleMismatch:
            return "The requested application does not contain this helper."
        case .homeDirectoryMismatch:
            return "The requested home directory is not the current user’s home directory."
        case .invalidApplicationBundle:
            return "The application bundle could not be verified."
        case .internalBuildMarkerMissing:
            return "The application is not marked as an internal build."
        case .unsafeResetTarget:
            return "A reset target falls outside the allowed home directory."
        case .commandFailed(let executablePath, let status):
            return "\(executablePath) failed with status \(status)."
        case .fileRemovalFailed:
            return "An internal application state path could not be removed."
        case .unsafeOperationFile:
            return "The helper operation file is outside the allowed temporary directory."
        case .receiptPersistenceFailed:
            return "The reset helper result could not be saved."
        case .resetOperationFailed(let category):
            return "The reset helper finished with a \(category.rawValue) failure."
        }
    }
}

/// Stable, identity-free schema consumed by the app after a post-exit helper run.
/// Keep this representation intentionally small: it must never contain account IDs,
/// bundle paths, command output, or free-form provider errors.
package enum MeetingIncomingResetReceiptState: String, Codable, Equatable {
    case pending
    case succeeded
    case failed
}

package enum MeetingIncomingResetFailureCategory: String, Codable, Equatable, Hashable {
    case parentWait
    case tccReset
    case localCleanup
    case reopen
    case receiptPersistence
    case multiple
}

package enum MeetingIncomingResetTargetIdentifier: String, Codable, Equatable {
    case preferences
    case applicationSupport
    case caches
    case httpStorages
    case savedApplicationState
}

package enum MeetingIncomingResetDiagnosticCategory: String, Codable, Equatable {
    case targetInspection
    case targetRemoval
    case defaultsDeletion
    case reopenCommand
}

package enum MeetingIncomingResetErrorDomain: String, Codable, Equatable {
    case cocoa = "NSCocoaErrorDomain"
    case posix = "NSPOSIXErrorDomain"
    case osStatus = "NSOSStatusErrorDomain"
    case processExitStatus = "ProcessExitStatus"
    case other
}

/// Privacy-safe failure detail. It deliberately excludes paths, bundle identifiers,
/// localized descriptions, command output, and NSError userInfo.
package struct MeetingIncomingResetDiagnostic: Codable, Equatable {
    package let category: MeetingIncomingResetDiagnosticCategory
    package let target: MeetingIncomingResetTargetIdentifier?
    package let errorDomain: MeetingIncomingResetErrorDomain?
    package let errorCode: Int?

    package init(
        category: MeetingIncomingResetDiagnosticCategory,
        target: MeetingIncomingResetTargetIdentifier? = nil,
        errorDomain: MeetingIncomingResetErrorDomain? = nil,
        errorCode: Int? = nil
    ) {
        self.category = category
        self.target = target
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }
}

private func resetDiagnostic(
    category: MeetingIncomingResetDiagnosticCategory,
    target: MeetingIncomingResetTargetIdentifier?,
    error: any Error
) -> MeetingIncomingResetDiagnostic {
    if case .commandFailed(_, let status) = error as? MeetingIncomingHelperError {
        return MeetingIncomingResetDiagnostic(
            category: category,
            target: target,
            errorDomain: .processExitStatus,
            errorCode: Int(status)
        )
    }
    let nsError = error as NSError
    let errorDomain: MeetingIncomingResetErrorDomain
    switch nsError.domain {
    case NSCocoaErrorDomain:
        errorDomain = .cocoa
    case NSPOSIXErrorDomain:
        errorDomain = .posix
    case NSOSStatusErrorDomain:
        errorDomain = .osStatus
    default:
        return MeetingIncomingResetDiagnostic(
            category: category,
            target: target,
            errorDomain: .other
        )
    }
    return MeetingIncomingResetDiagnostic(
        category: category,
        target: target,
        errorDomain: errorDomain,
        errorCode: nsError.code
    )
}

package struct MeetingIncomingResetReceipt: Codable, Equatable {
    package static let currentVersion = 1

    package let version: Int
    package let state: MeetingIncomingResetReceiptState
    package let failureCategory: MeetingIncomingResetFailureCategory?
    package let diagnostic: MeetingIncomingResetDiagnostic?

    package init(
        state: MeetingIncomingResetReceiptState,
        failureCategory: MeetingIncomingResetFailureCategory? = nil,
        diagnostic: MeetingIncomingResetDiagnostic? = nil
    ) {
        version = Self.currentVersion
        self.state = state
        self.failureCategory = failureCategory
        self.diagnostic = diagnostic
    }
}

private enum ResetReceiptKind {
    case appData
    case internalFullReset

    var fileName: String {
        switch self {
        case .appData:
            return "app-data-helper-result.v1.json"
        case .internalFullReset:
            return "internal-helper-result.v1.json"
        }
    }
}

private struct ResetFailureAccumulator {
    private(set) var categories: Set<MeetingIncomingResetFailureCategory> = []
    private(set) var diagnostic: MeetingIncomingResetDiagnostic?

    var isEmpty: Bool { categories.isEmpty }

    mutating func record(
        _ category: MeetingIncomingResetFailureCategory,
        diagnostic: MeetingIncomingResetDiagnostic? = nil
    ) {
        categories.insert(category)
        if self.diagnostic == nil {
            self.diagnostic = diagnostic
        }
    }

    var receiptCategory: MeetingIncomingResetFailureCategory? {
        guard !categories.isEmpty else { return nil }
        return categories.count == 1 ? categories.first : .multiple
    }
}

private func resetReceiptURL(
    kind: ResetReceiptKind,
    bundleIdentifier: String,
    environment: MeetingIncomingHelperEnvironment,
    fileManager: FileManager
) throws -> URL {
    let homeURL = environment.homeDirectoryURL.standardizedFileURL
    guard homeURL.isFileURL, homeURL.path != "/", !homeURL.path.isEmpty else {
        throw MeetingIncomingHelperError.unsafeResetTarget(homeURL.path)
    }
    let controlDirectory = homeURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("\(bundleIdentifier).reset-control", isDirectory: true)
        .standardizedFileURL
    let receiptURL = controlDirectory
        .appendingPathComponent(kind.fileName, isDirectory: false)
        .standardizedFileURL
    let expectedControlComponents = homeURL.pathComponents + [
        "Library",
        "Application Support",
        "\(bundleIdentifier).reset-control"
    ]
    guard controlDirectory.pathComponents == expectedControlComponents,
          receiptURL.deletingLastPathComponent() == controlDirectory,
          receiptURL.lastPathComponent == kind.fileName,
          isDescendant(
              controlDirectory.resolvingSymlinksInPath(),
              of: homeURL.resolvingSymlinksInPath()
          ),
          try !isSymbolicLinkIfPresent(controlDirectory, fileManager: fileManager),
          try !isSymbolicLinkIfPresent(receiptURL, fileManager: fileManager) else {
        throw MeetingIncomingHelperError.unsafeResetTarget(receiptURL.path)
    }
    return receiptURL
}

private func persistPendingReceipt(
    at receiptURL: URL,
    failures: inout ResetFailureAccumulator,
    fileManager: FileManager = .default
) {
    do {
        try persistResetReceipt(
            MeetingIncomingResetReceipt(state: .pending),
            at: receiptURL,
            fileManager: fileManager
        )
    } catch {
        failures.record(.receiptPersistence)
    }
}

private func persistTerminalReceipt(
    at receiptURL: URL,
    failures: inout ResetFailureAccumulator,
    fileManager: FileManager = .default
) {
    let initialReceipt = failures.receiptCategory.map {
        MeetingIncomingResetReceipt(
            state: .failed,
            failureCategory: $0,
            diagnostic: failures.diagnostic
        )
    } ?? MeetingIncomingResetReceipt(state: .succeeded)
    do {
        try persistResetReceipt(initialReceipt, at: receiptURL, fileManager: fileManager)
    } catch {
        failures.record(.receiptPersistence)
        // A transient first write can still leave a useful terminal receipt. If this
        // retry also fails, the durable pending receipt remains the recovery signal.
        let failureReceipt = MeetingIncomingResetReceipt(
            state: .failed,
            failureCategory: failures.receiptCategory,
            diagnostic: failures.diagnostic
        )
        try? persistResetReceipt(failureReceipt, at: receiptURL, fileManager: fileManager)
    }
}

private func persistResetReceipt(
    _ receipt: MeetingIncomingResetReceipt,
    at receiptURL: URL,
    fileManager: FileManager
) throws {
    let directory = receiptURL.deletingLastPathComponent()
    do {
        guard try !isSymbolicLinkIfPresent(directory, fileManager: fileManager),
              try !isSymbolicLinkIfPresent(receiptURL, fileManager: fileManager) else {
            throw MeetingIncomingHelperError.unsafeResetTarget(receiptURL.path)
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        guard try !isSymbolicLinkIfPresent(directory, fileManager: fileManager),
              try !isSymbolicLinkIfPresent(receiptURL, fileManager: fileManager) else {
            throw MeetingIncomingHelperError.unsafeResetTarget(receiptURL.path)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(receipt)
        try data.write(to: receiptURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: receiptURL.path
        )
    } catch let error as MeetingIncomingHelperError {
        throw error
    } catch {
        throw MeetingIncomingHelperError.receiptPersistenceFailed
    }
}

private func isSymbolicLinkIfPresent(
    _ url: URL,
    fileManager: FileManager
) throws -> Bool {
    do {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink
    } catch {
        let cocoaError = error as NSError
        if cocoaError.domain == NSCocoaErrorDomain,
           cocoaError.code == NSFileNoSuchFileError ||
           cocoaError.code == NSFileReadNoSuchFileError {
            return false
        }
        throw MeetingIncomingHelperError.receiptPersistenceFailed
    }
}

private func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
    let directoryComponents = directory.standardizedFileURL.pathComponents
    let candidateComponents = candidate.standardizedFileURL.pathComponents
    return candidateComponents.count > directoryComponents.count &&
        Array(candidateComponents.prefix(directoryComponents.count)) == directoryComponents
}

package struct MeetingIncomingHelperOperation: Codable, Equatable {
    package static let currentVersion = 1

    package let version: Int
    package let parentProcessIdentifier: Int32
    package let bundleIdentifier: String
    package let applicationBundlePath: String
    package let homeDirectoryPath: String

    package init(
        version: Int = currentVersion,
        parentProcessIdentifier: Int32,
        bundleIdentifier: String,
        applicationBundlePath: String,
        homeDirectoryPath: String
    ) {
        self.version = version
        self.parentProcessIdentifier = parentProcessIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.applicationBundlePath = applicationBundlePath
        self.homeDirectoryPath = homeDirectoryPath
    }
}

package struct MeetingIncomingHelperEnvironment {
    package let containingApplicationBundleURL: URL
    package let homeDirectoryURL: URL

    package init(
        containingApplicationBundleURL: URL,
        homeDirectoryURL: URL
    ) {
        self.containingApplicationBundleURL = containingApplicationBundleURL
        self.homeDirectoryURL = homeDirectoryURL
    }
}

package struct MeetingIncomingHelperBootstrap {
    package let operation: MeetingIncomingHelperOperation
    package let environment: MeetingIncomingHelperEnvironment
    package let operationFileURL: URL

    package static func load(
        arguments: [String],
        helperExecutableURL: URL,
        homeDirectoryURL: URL,
        temporaryDirectoryURL: URL = FileManager.default.temporaryDirectory
    ) throws -> MeetingIncomingHelperBootstrap {
        guard arguments.count == 3,
              arguments[1] == "--operation",
              NSString(string: arguments[2]).isAbsolutePath else {
            throw MeetingIncomingHelperError.invalidArguments
        }
        let operationURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        let resolvedTemporaryDirectory = temporaryDirectoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let resolvedOperationURL = operationURL.resolvingSymlinksInPath()
        guard operationURL.deletingLastPathComponent().resolvingSymlinksInPath() == resolvedTemporaryDirectory,
              resolvedOperationURL.deletingLastPathComponent() == resolvedTemporaryDirectory,
              operationURL.lastPathComponent.hasPrefix("meeting-incoming-relaunch-"),
              operationURL.pathExtension == "json" else {
            throw MeetingIncomingHelperError.unsafeOperationFile(operationURL.path)
        }
        let operation: MeetingIncomingHelperOperation
        do {
            operation = try JSONDecoder().decode(
                MeetingIncomingHelperOperation.self,
                from: Data(contentsOf: operationURL)
            )
        } catch {
            throw MeetingIncomingHelperError.operationReadFailed(operationURL.path)
        }

        let helpersDirectoryURL = helperExecutableURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        let contentsDirectoryURL = helpersDirectoryURL.deletingLastPathComponent()
        let applicationBundleURL = contentsDirectoryURL.deletingLastPathComponent()
        guard helpersDirectoryURL.lastPathComponent == "Helpers",
              contentsDirectoryURL.lastPathComponent == "Contents",
              applicationBundleURL.pathExtension == "app" else {
            throw MeetingIncomingHelperError.helperNotEmbeddedInApplicationBundle
        }

        return MeetingIncomingHelperBootstrap(
            operation: operation,
            environment: MeetingIncomingHelperEnvironment(
                containingApplicationBundleURL: applicationBundleURL,
                homeDirectoryURL: homeDirectoryURL
            ),
            operationFileURL: operationURL
        )
    }
}

package protocol ParentProcessWaiting {
    func wait(for processIdentifier: Int32) throws
}

package protocol HelperCommandRunning {
    func run(executableURL: URL, arguments: [String]) throws -> Int32
}

package struct SystemParentProcessWaiter: ParentProcessWaiting {
    package init() {}

    package func wait(for processIdentifier: Int32) throws {
        guard processIdentifier > 1,
              processIdentifier != getpid() else {
            throw MeetingIncomingHelperError.invalidParentProcessIdentifier(processIdentifier)
        }
        while true {
            errno = 0
            if kill(processIdentifier, 0) == 0 || errno == EPERM {
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            if errno == ESRCH {
                return
            }
            throw MeetingIncomingHelperError.parentWaitFailed(processIdentifier)
        }
    }
}

package struct SystemHelperCommandRunner: HelperCommandRunning {
    package init() {}

    package func run(executableURL: URL, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

private struct VerifiedHelperApplication {
    static let internalBundleIdentifier = "com.serhatculhalik.in-your-face.internal"

    let bundleIdentifier: String
    let applicationBundleURL: URL
}

private func verifyHelperApplication(
    operation: MeetingIncomingHelperOperation,
    environment: MeetingIncomingHelperEnvironment,
    requiresInternalBuild: Bool
) throws -> VerifiedHelperApplication {
    guard operation.version == MeetingIncomingHelperOperation.currentVersion else {
        throw MeetingIncomingHelperError.unsupportedOperationVersion(operation.version)
    }
    guard operation.parentProcessIdentifier > 1 else {
        throw MeetingIncomingHelperError.invalidParentProcessIdentifier(
            operation.parentProcessIdentifier
        )
    }
    guard isValidBundleIdentifier(operation.bundleIdentifier) else {
        throw MeetingIncomingHelperError.invalidBundleIdentifier(
            operation.bundleIdentifier
        )
    }
    if requiresInternalBuild,
       operation.bundleIdentifier != VerifiedHelperApplication.internalBundleIdentifier {
        throw MeetingIncomingHelperError.bundleIdentifierMustBeInternal(
            operation.bundleIdentifier
        )
    }

    let expectedApplicationURL = environment.containingApplicationBundleURL
        .standardizedFileURL
        .resolvingSymlinksInPath()
    let operationApplicationURL = URL(fileURLWithPath: operation.applicationBundlePath)
        .standardizedFileURL
        .resolvingSymlinksInPath()
    guard expectedApplicationURL == operationApplicationURL,
          operationApplicationURL.pathExtension == "app" else {
        throw MeetingIncomingHelperError.applicationBundleMismatch
    }

    let expectedHomeURL = environment.homeDirectoryURL
        .standardizedFileURL
        .resolvingSymlinksInPath()
    let operationHomeURL = URL(fileURLWithPath: operation.homeDirectoryPath)
        .standardizedFileURL
        .resolvingSymlinksInPath()
    guard expectedHomeURL == operationHomeURL else {
        throw MeetingIncomingHelperError.homeDirectoryMismatch
    }

    let infoPlistURL = operationApplicationURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Info.plist", isDirectory: false)
    let infoDictionary: [String: Any]
    do {
        let data = try Data(contentsOf: infoPlistURL)
        infoDictionary = try PropertyListSerialization.propertyList(
            from: data,
            format: nil
        ) as? [String: Any] ?? [:]
    } catch {
        throw MeetingIncomingHelperError.invalidApplicationBundle
    }
    guard infoDictionary["CFBundleIdentifier"] as? String == operation.bundleIdentifier else {
        throw MeetingIncomingHelperError.invalidApplicationBundle
    }
    if requiresInternalBuild,
       infoDictionary["MeetingIncomingInternalBuild"] as? Bool != true {
        throw MeetingIncomingHelperError.internalBuildMarkerMissing
    }

    return VerifiedHelperApplication(
        bundleIdentifier: operation.bundleIdentifier,
        applicationBundleURL: operationApplicationURL
    )
}

private func isValidBundleIdentifier(_ value: String) -> Bool {
    let components = value.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count >= 2, components.allSatisfy({ !$0.isEmpty }) else {
        return false
    }
    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
    return value.unicodeScalars.allSatisfy {
        $0 == "." || allowedCharacters.contains($0)
    }
}

package struct InternalResetResult: Equatable {
    package let removedPaths: [String]
    package let relaunchedApplicationPath: String
}

package struct InternalResetRunner {
    private let environment: MeetingIncomingHelperEnvironment
    private let fileManager: FileManager
    private let parentWaiter: any ParentProcessWaiting
    private let commandRunner: any HelperCommandRunning

    package init(
        environment: MeetingIncomingHelperEnvironment,
        fileManager: FileManager,
        parentWaiter: any ParentProcessWaiting,
        commandRunner: any HelperCommandRunning
    ) {
        self.environment = environment
        self.fileManager = fileManager
        self.parentWaiter = parentWaiter
        self.commandRunner = commandRunner
    }

    package func run(
        operation: MeetingIncomingHelperOperation
    ) throws -> InternalResetResult {
        let verifiedApplication = try verifyHelperApplication(
            operation: operation,
            environment: environment,
            requiresInternalBuild: true
        )
        let receiptURL = try resetReceiptURL(
            kind: .internalFullReset,
            bundleIdentifier: verifiedApplication.bundleIdentifier,
            environment: environment,
            fileManager: fileManager
        )
        var failures = ResetFailureAccumulator()
        persistPendingReceipt(
            at: receiptURL,
            failures: &failures,
            fileManager: fileManager
        )

        let targets: ResetTargets?
        do {
            targets = try resetTargets(bundleIdentifier: verifiedApplication.bundleIdentifier)
        } catch {
            failures.record(.localCleanup)
            targets = nil
        }

        var parentExited = false
        do {
            try parentWaiter.wait(for: operation.parentProcessIdentifier)
            parentExited = true
        } catch {
            failures.record(.parentWait)
        }

        var removedPaths: [String] = []
        if parentExited {
            for service in ["Accessibility", "ListenEvent"] {
                do {
                    try requireSuccessfulCommand(
                        executablePath: "/usr/bin/tccutil",
                        arguments: ["reset", service, verifiedApplication.bundleIdentifier]
                    )
                } catch {
                    failures.record(.tccReset)
                }
            }

            if let targets {
                for target in targets.identified {
                    let targetExists: Bool
                    do {
                        targetExists = try inspectTargetPresence(at: target.url)
                    } catch {
                        failures.record(
                            .localCleanup,
                            diagnostic: resetDiagnostic(
                                category: .targetInspection,
                                target: target.identifier,
                                error: error
                            )
                        )
                        continue
                    }
                    guard targetExists else { continue }

                    if target.identifier == .preferences {
                        do {
                            try requireSuccessfulCommand(
                                executablePath: "/usr/bin/defaults",
                                arguments: ["delete", verifiedApplication.bundleIdentifier]
                            )
                        } catch {
                            failures.record(
                                .localCleanup,
                                diagnostic: resetDiagnostic(
                                    category: .defaultsDeletion,
                                    target: .preferences,
                                    error: error
                                )
                            )
                        }
                        do {
                            guard try inspectTargetPresence(at: target.url) else { continue }
                        } catch {
                            failures.record(
                                .localCleanup,
                                diagnostic: resetDiagnostic(
                                    category: .targetInspection,
                                    target: .preferences,
                                    error: error
                                )
                            )
                            continue
                        }
                    }

                    do {
                        try requireSafeTarget(target.url)
                    } catch {
                        failures.record(
                            .localCleanup,
                            diagnostic: resetDiagnostic(
                                category: .targetInspection,
                                target: target.identifier,
                                error: error
                            )
                        )
                        continue
                    }
                    do {
                        try fileManager.removeItem(at: target.url)
                        removedPaths.append(target.url.path)
                    } catch {
                        failures.record(
                            .localCleanup,
                            diagnostic: resetDiagnostic(
                                category: .targetRemoval,
                                target: target.identifier,
                                error: error
                            )
                        )
                    }
                }
            }
        }

        if parentExited, failures.isEmpty {
            do {
                let supersededPublicReceipt = try resetReceiptURL(
                    kind: .appData,
                    bundleIdentifier: verifiedApplication.bundleIdentifier,
                    environment: environment,
                    fileManager: fileManager
                )
                if try inspectTargetPresence(at: supersededPublicReceipt) {
                    try fileManager.removeItem(at: supersededPublicReceipt)
                }
            } catch {
                failures.record(.receiptPersistence)
            }
        }
        // `open` can return as the new process begins bootstrapping. Publish the
        // cleanup result first so that process never mistakes an in-flight run
        // for an abandoned pending operation. An open failure is overwritten
        // below and remains visible on the next manual launch.
        persistTerminalReceipt(
            at: receiptURL,
            failures: &failures,
            fileManager: fileManager
        )
        if parentExited {
            do {
                try requireSuccessfulCommand(
                    executablePath: "/usr/bin/open",
                    arguments: ["-F", verifiedApplication.applicationBundleURL.path]
                )
            } catch {
                failures.record(
                    .reopen,
                    diagnostic: resetDiagnostic(
                        category: .reopenCommand,
                        target: nil,
                        error: error
                    )
                )
                persistTerminalReceipt(
                    at: receiptURL,
                    failures: &failures,
                    fileManager: fileManager
                )
            }
        }
        if let category = failures.receiptCategory {
            throw MeetingIncomingHelperError.resetOperationFailed(category)
        }
        return InternalResetResult(
            removedPaths: removedPaths,
            relaunchedApplicationPath: verifiedApplication.applicationBundleURL.path
        )
    }

    private struct ResetTargets {
        let preferences: URL
        let applicationSupport: URL
        let caches: URL
        let httpStorages: URL
        let savedApplicationState: URL

        var all: [URL] {
            [
                preferences,
                applicationSupport,
                caches,
                httpStorages,
                savedApplicationState
            ]
        }

        var identified: [(
            identifier: MeetingIncomingResetTargetIdentifier,
            url: URL
        )] {
            [
                (.preferences, preferences),
                (.applicationSupport, applicationSupport),
                (.caches, caches),
                (.httpStorages, httpStorages),
                (.savedApplicationState, savedApplicationState)
            ]
        }
    }

    private func resetTargets(bundleIdentifier: String) throws -> ResetTargets {
        let homeURL = environment.homeDirectoryURL.standardizedFileURL
        let libraryURL = homeURL.appendingPathComponent("Library", isDirectory: true)
        let targets = ResetTargets(
            preferences: libraryURL
                .appendingPathComponent("Preferences", isDirectory: true)
                .appendingPathComponent("\(bundleIdentifier).plist", isDirectory: false),
            applicationSupport: libraryURL
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent(bundleIdentifier, isDirectory: true),
            caches: libraryURL
                .appendingPathComponent("Caches", isDirectory: true)
                .appendingPathComponent(bundleIdentifier, isDirectory: true),
            httpStorages: libraryURL
                .appendingPathComponent("HTTPStorages", isDirectory: true)
                .appendingPathComponent(bundleIdentifier, isDirectory: true),
            savedApplicationState: libraryURL
                .appendingPathComponent("Saved Application State", isDirectory: true)
                .appendingPathComponent("\(bundleIdentifier).savedState", isDirectory: true)
        )
        let canonicalHomeURL = homeURL.resolvingSymlinksInPath()
        for target in targets.all {
            try requireSafeTarget(target, canonicalHomeURL: canonicalHomeURL)
        }
        return targets
    }

    private func requireSafeTarget(
        _ target: URL,
        canonicalHomeURL: URL? = nil
    ) throws {
        let canonicalHomeURL = canonicalHomeURL ?? environment.homeDirectoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let canonicalTargetURL = target.resolvingSymlinksInPath()
        guard Self.isDescendant(canonicalTargetURL, of: canonicalHomeURL) else {
            throw MeetingIncomingHelperError.unsafeResetTarget(target.path)
        }
    }

    private func requireSuccessfulCommand(
        executablePath: String,
        arguments: [String]
    ) throws {
        let status = try commandRunner.run(
            executableURL: URL(fileURLWithPath: executablePath),
            arguments: arguments
        )
        guard status == 0 else {
            throw MeetingIncomingHelperError.commandFailed(executablePath, status)
        }
    }

    private func inspectTargetPresence(at target: URL) throws -> Bool {
        do {
            _ = try fileManager.attributesOfItem(atPath: target.path)
            return true
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSFileNoSuchFileError ||
               nsError.code == NSFileReadNoSuchFileError {
                return false
            }
            throw error
        }
    }

    private static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let directoryComponents = directory.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count > directoryComponents.count &&
            Array(candidateComponents.prefix(directoryComponents.count)) == directoryComponents
    }
}

package struct RelaunchResult: Equatable {
    package let relaunchedApplicationPath: String
}

package struct AppDataResetResult: Equatable {
    package let removedPaths: [String]
    package let relaunchedApplicationPath: String
}

/// Public post-exit cleanup. Unlike the internal helper, this runner has no TCC
/// authority and never invokes `tccutil`; it can remove only exact paths derived
/// from the verified containing app's bundle identifier.
package struct AppDataResetRunner {
    private let environment: MeetingIncomingHelperEnvironment
    private let fileManager: FileManager
    private let parentWaiter: any ParentProcessWaiting
    private let commandRunner: any HelperCommandRunning

    package init(
        environment: MeetingIncomingHelperEnvironment,
        fileManager: FileManager,
        parentWaiter: any ParentProcessWaiting,
        commandRunner: any HelperCommandRunning
    ) {
        self.environment = environment
        self.fileManager = fileManager
        self.parentWaiter = parentWaiter
        self.commandRunner = commandRunner
    }

    package func run(
        operation: MeetingIncomingHelperOperation
    ) throws -> AppDataResetResult {
        let verifiedApplication = try verifyHelperApplication(
            operation: operation,
            environment: environment,
            requiresInternalBuild: false
        )
        let receiptURL = try resetReceiptURL(
            kind: .appData,
            bundleIdentifier: verifiedApplication.bundleIdentifier,
            environment: environment,
            fileManager: fileManager
        )
        var failures = ResetFailureAccumulator()
        persistPendingReceipt(
            at: receiptURL,
            failures: &failures,
            fileManager: fileManager
        )

        let initialTargets: ResetTargets?
        do {
            initialTargets = try resetTargets(bundleIdentifier: verifiedApplication.bundleIdentifier)
        } catch {
            failures.record(.localCleanup)
            initialTargets = nil
        }

        var parentExited = false
        do {
            try parentWaiter.wait(for: operation.parentProcessIdentifier)
            parentExited = true
        } catch {
            failures.record(.parentWait)
        }

        let targets: ResetTargets?
        if parentExited, initialTargets != nil {
            do {
                targets = try resetTargets(bundleIdentifier: verifiedApplication.bundleIdentifier)
            } catch {
                failures.record(.localCleanup)
                targets = nil
            }
        } else {
            targets = nil
        }
        var removedPaths: [String] = []
        if let targets {
            for target in targets.identified {
                let targetExists: Bool
                do {
                    targetExists = try inspectTargetPresence(at: target.url)
                } catch {
                    failures.record(
                        .localCleanup,
                        diagnostic: resetDiagnostic(
                            category: .targetInspection,
                            target: target.identifier,
                            error: error
                        )
                    )
                    continue
                }
                guard targetExists else { continue }

                if target.identifier == .preferences {
                    do {
                        try requireSuccessfulCommand(
                            executablePath: "/usr/bin/defaults",
                            arguments: ["delete", verifiedApplication.bundleIdentifier]
                        )
                    } catch {
                        failures.record(
                            .localCleanup,
                            diagnostic: resetDiagnostic(
                                category: .defaultsDeletion,
                                target: .preferences,
                                error: error
                            )
                        )
                    }
                    do {
                        guard try inspectTargetPresence(at: target.url) else { continue }
                    } catch {
                        failures.record(
                            .localCleanup,
                            diagnostic: resetDiagnostic(
                                category: .targetInspection,
                                target: .preferences,
                                error: error
                            )
                        )
                        continue
                    }
                }

                do {
                    try requireSafeTarget(target.url)
                } catch {
                    failures.record(
                        .localCleanup,
                        diagnostic: resetDiagnostic(
                            category: .targetInspection,
                            target: target.identifier,
                            error: error
                        )
                    )
                    continue
                }
                do {
                    try fileManager.removeItem(at: target.url)
                    removedPaths.append(target.url.path)
                } catch {
                    failures.record(
                        .localCleanup,
                        diagnostic: resetDiagnostic(
                            category: .targetRemoval,
                            target: target.identifier,
                            error: error
                        )
                    )
                }
            }
        }

        // Publish before launch to avoid racing the relaunched app's bootstrap.
        persistTerminalReceipt(
            at: receiptURL,
            failures: &failures,
            fileManager: fileManager
        )
        if parentExited {
            do {
                try requireSuccessfulCommand(
                    executablePath: "/usr/bin/open",
                    arguments: ["-F", verifiedApplication.applicationBundleURL.path]
                )
            } catch {
                failures.record(
                    .reopen,
                    diagnostic: resetDiagnostic(
                        category: .reopenCommand,
                        target: nil,
                        error: error
                    )
                )
                persistTerminalReceipt(
                    at: receiptURL,
                    failures: &failures,
                    fileManager: fileManager
                )
            }
        }
        if let category = failures.receiptCategory {
            throw MeetingIncomingHelperError.resetOperationFailed(category)
        }
        return AppDataResetResult(
            removedPaths: removedPaths,
            relaunchedApplicationPath: verifiedApplication.applicationBundleURL.path
        )
    }

    private struct ResetTargets {
        let preferences: URL
        let applicationSupport: URL
        let caches: URL
        let httpStorages: URL
        let savedApplicationState: URL

        var all: [URL] {
            [preferences, applicationSupport, caches, httpStorages, savedApplicationState]
        }

        var identified: [(
            identifier: MeetingIncomingResetTargetIdentifier,
            url: URL
        )] {
            [
                (.preferences, preferences),
                (.applicationSupport, applicationSupport),
                (.caches, caches),
                (.httpStorages, httpStorages),
                (.savedApplicationState, savedApplicationState)
            ]
        }
    }

    private func resetTargets(bundleIdentifier: String) throws -> ResetTargets {
        let homeURL = environment.homeDirectoryURL.standardizedFileURL
        let libraryURL = homeURL.appendingPathComponent("Library", isDirectory: true)
        let targets = ResetTargets(
            preferences: libraryURL
                .appendingPathComponent("Preferences", isDirectory: true)
                .appendingPathComponent("\(bundleIdentifier).plist", isDirectory: false),
            applicationSupport: libraryURL
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent(bundleIdentifier, isDirectory: true),
            caches: libraryURL
                .appendingPathComponent("Caches", isDirectory: true)
                .appendingPathComponent(bundleIdentifier, isDirectory: true),
            httpStorages: libraryURL
                .appendingPathComponent("HTTPStorages", isDirectory: true)
                .appendingPathComponent(bundleIdentifier, isDirectory: true),
            savedApplicationState: libraryURL
                .appendingPathComponent("Saved Application State", isDirectory: true)
                .appendingPathComponent("\(bundleIdentifier).savedState", isDirectory: true)
        )
        let canonicalHomeURL = homeURL.resolvingSymlinksInPath()
        for target in targets.all {
            let canonicalTargetURL = target.resolvingSymlinksInPath()
            guard Self.isDescendant(canonicalTargetURL, of: canonicalHomeURL) else {
                throw MeetingIncomingHelperError.unsafeResetTarget(target.path)
            }
        }
        return targets
    }

    private func requireSafeTarget(_ target: URL) throws {
        let canonicalHomeURL = environment.homeDirectoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let canonicalTargetURL = target.resolvingSymlinksInPath()
        guard Self.isDescendant(canonicalTargetURL, of: canonicalHomeURL) else {
            throw MeetingIncomingHelperError.unsafeResetTarget(target.path)
        }
    }

    private func inspectTargetPresence(at target: URL) throws -> Bool {
        do {
            _ = try fileManager.attributesOfItem(atPath: target.path)
            return true
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSFileNoSuchFileError ||
               nsError.code == NSFileReadNoSuchFileError {
                return false
            }
            throw error
        }
    }

    private func requireSuccessfulCommand(
        executablePath: String,
        arguments: [String]
    ) throws {
        let status = try commandRunner.run(
            executableURL: URL(fileURLWithPath: executablePath),
            arguments: arguments
        )
        guard status == 0 else {
            throw MeetingIncomingHelperError.commandFailed(executablePath, status)
        }
    }

    private static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let directoryComponents = directory.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count > directoryComponents.count &&
            Array(candidateComponents.prefix(directoryComponents.count)) == directoryComponents
    }
}

package struct RelaunchRunner {
    private let environment: MeetingIncomingHelperEnvironment
    private let parentWaiter: any ParentProcessWaiting
    private let commandRunner: any HelperCommandRunning

    package init(
        environment: MeetingIncomingHelperEnvironment,
        parentWaiter: any ParentProcessWaiting,
        commandRunner: any HelperCommandRunning
    ) {
        self.environment = environment
        self.parentWaiter = parentWaiter
        self.commandRunner = commandRunner
    }

    package func run(operation: MeetingIncomingHelperOperation) throws -> RelaunchResult {
        let verifiedApplication = try verifyHelperApplication(
            operation: operation,
            environment: environment,
            requiresInternalBuild: false
        )
        try parentWaiter.wait(for: operation.parentProcessIdentifier)
        let executablePath = "/usr/bin/open"
        let status = try commandRunner.run(
            executableURL: URL(fileURLWithPath: executablePath),
            arguments: ["-F", verifiedApplication.applicationBundleURL.path]
        )
        guard status == 0 else {
            throw MeetingIncomingHelperError.commandFailed(executablePath, status)
        }
        return RelaunchResult(
            relaunchedApplicationPath: verifiedApplication.applicationBundleURL.path
        )
    }
}
