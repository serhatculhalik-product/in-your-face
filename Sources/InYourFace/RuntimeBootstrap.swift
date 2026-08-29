import CommitmentProtection
import Foundation
import ServiceManagement

struct RuntimeBootstrap {
    let profile: RuntimeProfile
    let router: RuntimeProfileRouter
    let stateStore: UserDefaults
    let applicationSupportDirectory: URL
    let namespace: String
    let recoveryReport: String?
    let appDataResetRecoveryAvailable: Bool
    let internalResetRecoveryAvailable: Bool
    let appDataResetJournalRequiresResume: Bool
    let internalResetJournalRequiresResume: Bool
    let resetRecoveryRequiresManualRepair: Bool
    let protectionStartupMode: CommitmentProtectionStartupMode
    let isCleanupRecovery: Bool

    @MainActor
    static func load(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> RuntimeBootstrap {
        let namespace = bundle.bundleIdentifier ?? "com.serhatculhalik.in-your-face"
        let applicationSupportDirectory = resolveApplicationSupportDirectory(fileManager: fileManager)
        let controlDirectory = applicationSupportDirectory.appendingPathComponent(
            "\(namespace).runtime-control",
            isDirectory: true
        )
        let helperRecovery = resetHelperRecoverySummary(
            applicationSupportDirectory: applicationSupportDirectory,
            namespace: namespace,
            fileManager: fileManager
        )
        let journalRecovery = resetJournalRecoverySummary(
            applicationSupportDirectory: applicationSupportDirectory,
            namespace: namespace,
            fileManager: fileManager
        )
        let protectionStartupMode = resetProtectionStartupMode(
            helperRecovery: helperRecovery,
            journalRecovery: journalRecovery
        )

        do {
            let router = try RuntimeProfileRouter(
                storageRoot: controlDirectory,
                namespace: namespace,
                productionVaultApplicationIdentifier: namespace
            )
            let cleanupExecutor = try RuntimeProfileCleanupExecutor(
                applicationSupportDirectory: applicationSupportDirectory,
                namespace: namespace,
                productionVaultApplicationIdentifier: namespace,
                productionDefaultsSuiteName: namespace,
                fileManager: fileManager
            )
            var resolution = try router.resolveForBootstrap()
            var cleanupFailures: [String] = []

            // A profile change is relaunched through a helper that first waits for
            // the old PID. Therefore this bootstrap is the first safe point at
            // which an old test generation can be deleted.
            for intent in resolution.cleanupIntents {
                do {
                    try cleanupExecutor.execute(intent)
                    resolution = try router.recordCleanupResult(.succeeded, for: intent.id)
                } catch {
                    cleanupFailures.append(
                        (error as? RuntimeProfileCleanupExecutorError)?.localizedDescription ??
                            "The previous Test Mode profile could not be removed."
                    )
                    resolution = try router.recordCleanupResult(.failed, for: intent.id)
                }
            }

            let isCleanupRecovery = resolution.profile == nil &&
                !resolution.cleanupIntents.isEmpty
            let profile = resolution.profile ?? resolution.cleanupIntents.first.map {
                RuntimeProfile.test($0.profile)
            } ?? .production(vaultApplicationIdentifier: namespace)
            let stateStore = defaults(for: profile)
            let reports = [
                helperRecovery.report,
                journalRecovery.report,
                resolution.recovery == .corruptJournalReplaced
                    ? "The Test Mode marker was damaged and was replaced. Production data was not changed."
                    : nil,
                cleanupFailures.isEmpty
                    ? nil
                    : "A previous Test Mode profile could not be fully removed. Retry from Test Tools. \(cleanupFailures.joined(separator: " "))"
            ].compactMap { $0 }

            return RuntimeBootstrap(
                profile: profile,
                router: router,
                stateStore: stateStore,
                applicationSupportDirectory: applicationSupportDirectory,
                namespace: namespace,
                recoveryReport: reports.isEmpty ? nil : reports.joined(separator: " "),
                appDataResetRecoveryAvailable: helperRecovery.appDataResetRetryAvailable,
                internalResetRecoveryAvailable: helperRecovery.internalResetRetryAvailable,
                appDataResetJournalRequiresResume: journalRecovery.appDataRequiresResume,
                internalResetJournalRequiresResume: journalRecovery.internalRequiresResume,
                resetRecoveryRequiresManualRepair: helperRecovery.requiresManualRepair ||
                    journalRecovery.requiresManualRepair,
                protectionStartupMode: protectionStartupMode,
                isCleanupRecovery: isCleanupRecovery
            )
        } catch {
            // Runtime routing must never put production preferences at risk. If
            // its durable control directory is unavailable, continue production
            // with a separate fallback router and make recovery visible.
            let fallbackRoot = fileManager.temporaryDirectory.appendingPathComponent(
                "\(namespace).runtime-control-fallback",
                isDirectory: true
            )
            let fallbackRouter = try! RuntimeProfileRouter(
                storageRoot: fallbackRoot,
                namespace: namespace,
                productionVaultApplicationIdentifier: namespace
            )
            return RuntimeBootstrap(
                profile: .production(vaultApplicationIdentifier: namespace),
                router: fallbackRouter,
                stateStore: .standard,
                applicationSupportDirectory: applicationSupportDirectory,
                namespace: namespace,
                recoveryReport: [
                    helperRecovery.report,
                    journalRecovery.report,
                    "Test Mode routing is unavailable. Production data was not changed."
                ].compactMap { $0 }.joined(separator: " "),
                appDataResetRecoveryAvailable: helperRecovery.appDataResetRetryAvailable,
                internalResetRecoveryAvailable: helperRecovery.internalResetRetryAvailable,
                appDataResetJournalRequiresResume: journalRecovery.appDataRequiresResume,
                internalResetJournalRequiresResume: journalRecovery.internalRequiresResume,
                resetRecoveryRequiresManualRepair: helperRecovery.requiresManualRepair ||
                    journalRecovery.requiresManualRepair,
                protectionStartupMode: protectionStartupMode,
                isCleanupRecovery: false
            )
        }
    }

    private struct ResetHelperReceipt: Decodable {
        struct Diagnostic: Decodable {
            let category: String
            let target: String?
            let errorDomain: String?
            let errorCode: Int?
        }

        let version: Int
        let state: String
        let failureCategory: String?
        let diagnostic: Diagnostic?
    }

    struct ResetHelperRecoverySummary: Equatable {
        let report: String?
        let appDataResetRetryAvailable: Bool
        let internalResetRetryAvailable: Bool
        let requiresManualRepair: Bool
    }

    struct ResetJournalRecoverySummary: Equatable {
        let report: String?
        let appDataRequiresResume: Bool
        let internalRequiresResume: Bool
        let requiresProtectedStorage: Bool
        let requiresManualRepair: Bool
    }

    static func resetHelperRecoveryReport(
        applicationSupportDirectory: URL,
        namespace: String,
        fileManager: FileManager
    ) -> String? {
        resetHelperRecoverySummary(
            applicationSupportDirectory: applicationSupportDirectory,
            namespace: namespace,
            fileManager: fileManager
        ).report
    }

    static func resetHelperRecoverySummary(
        applicationSupportDirectory: URL,
        namespace: String,
        fileManager: FileManager
    ) -> ResetHelperRecoverySummary {
        let supportDirectory = applicationSupportDirectory.standardizedFileURL
        let directory = supportDirectory
            .appendingPathComponent("\(namespace).reset-control", isDirectory: true)
            .standardizedFileURL
        let receiptNames = [
            "app-data-helper-result.v1.json",
            "internal-helper-result.v1.json"
        ]
        var reports: [String] = []
        var appDataResetRetryAvailable = false
        var internalResetRetryAvailable = false
        var requiresManualRepair = false

        do {
            guard isSafeNamespace(namespace),
                  directory.deletingLastPathComponent() == supportDirectory,
                  isDescendant(
                      directory.resolvingSymlinksInPath(),
                      of: supportDirectory.resolvingSymlinksInPath()
                  ),
                  try !isSymbolicLinkIfPresent(directory, fileManager: fileManager) else {
                return ResetHelperRecoverySummary(
                    report: unsafeResetHelperRecoveryReport,
                    appDataResetRetryAvailable: false,
                    internalResetRetryAvailable: false,
                    requiresManualRepair: true
                )
            }
        } catch {
            return ResetHelperRecoverySummary(
                report: unsafeResetHelperRecoveryReport,
                appDataResetRetryAvailable: false,
                internalResetRetryAvailable: false,
                requiresManualRepair: true
            )
        }

        for name in receiptNames {
            let isAppDataReceipt = name == "app-data-helper-result.v1.json"
            let retryInstruction = isAppDataReceipt
                ? "Run Erase App-Managed Data again."
                : "Run Full First Run + macOS Permissions again."
            let receiptURL = directory.appendingPathComponent(name, isDirectory: false)
            do {
                guard receiptURL.deletingLastPathComponent() == directory,
                      receiptURL.lastPathComponent == name,
                      try !isSymbolicLinkIfPresent(receiptURL, fileManager: fileManager) else {
                    reports.append(unsafeResetHelperRecoveryReport)
                    requiresManualRepair = true
                    continue
                }
                guard fileManager.fileExists(atPath: receiptURL.path) else { continue }
                let receipt = try JSONDecoder().decode(
                    ResetHelperReceipt.self,
                    from: Data(contentsOf: receiptURL)
                )
                guard receipt.version == 1 else {
                    reports.append(
                        "A reset helper left an unsupported recovery receipt. " +
                            "Use Reveal Recovery Files before starting another reset."
                    )
                    requiresManualRepair = true
                    continue
                }
                switch receipt.state {
                case "succeeded":
                    try? fileManager.removeItem(at: receiptURL)
                case "pending":
                    reports.append(
                        "A post-exit reset helper may still be running. " +
                            "Quit Meeting Incoming, wait a moment, then reopen it. " +
                            "If this message remains, use Reveal Recovery Files " +
                            "before starting another reset."
                    )
                    requiresManualRepair = true
                case "failed":
#if !INTERNAL_BUILD
                    if !isAppDataReceipt {
                        reports.append(publicBuildInternalResetHelperRecoveryReport)
                        requiresManualRepair = true
                        continue
                    }
#endif
                    if receipt.failureCategory == "reopen" {
                        let detail = helperDiagnosticDescription(receipt.diagnostic)
                            .map { " \($0)." } ?? ""
                        reports.append(
                            "Reset cleanup finished, but Meeting Incoming could not reopen automatically.\(detail)"
                        )
                        try? fileManager.removeItem(at: receiptURL)
                        continue
                    }
                    let category = helperFailureDescription(receipt.failureCategory)
                    if let diagnostic = helperDiagnosticDescription(receipt.diagnostic) {
                        reports.append("Post-exit reset cleanup was incomplete: \(diagnostic). \(retryInstruction)")
                    } else {
                        reports.append("Post-exit reset cleanup was incomplete (\(category)). \(retryInstruction)")
                    }
                    if isAppDataReceipt {
                        appDataResetRetryAvailable = true
                    } else {
                        internalResetRetryAvailable = true
                    }
                default:
                    reports.append(
                        "A reset helper left an unreadable recovery state. " +
                            "Use Reveal Recovery Files before starting another reset."
                    )
                    requiresManualRepair = true
                }
            } catch {
                reports.append(
                    "A reset helper recovery receipt could not be read. " +
                        "Use Reveal Recovery Files before starting another reset."
                )
                requiresManualRepair = true
            }
        }
        return ResetHelperRecoverySummary(
            report: reports.isEmpty ? nil : reports.joined(separator: " "),
            appDataResetRetryAvailable: requiresManualRepair
                ? false
                : appDataResetRetryAvailable,
            internalResetRetryAvailable: requiresManualRepair
                ? false
                : internalResetRetryAvailable,
            requiresManualRepair: requiresManualRepair
        )
    }

    static func resetJournalRecoverySummary(
        applicationSupportDirectory: URL,
        namespace: String,
        fileManager: FileManager
    ) -> ResetJournalRecoverySummary {
        guard isSafeNamespace(namespace) else {
            return ResetJournalRecoverySummary(
                report: unsafeResetJournalRecoveryReport,
                appDataRequiresResume: false,
                internalRequiresResume: false,
                requiresProtectedStorage: false,
                requiresManualRepair: true
            )
        }
        let directory = applicationSupportDirectory.standardizedFileURL
            .appendingPathComponent("\(namespace).reset-control", isDirectory: true)
        let appDataInspection = ResetJournal.inspectForBootstrap(
            fileURL: directory.appendingPathComponent(
                "app-managed-data-reset.v1.json",
                isDirectory: false
            ),
            expectedKind: .eraseAppManagedData,
            fileManager: fileManager
        )
        let internalInspection = ResetJournal.inspectForBootstrap(
            fileURL: directory.appendingPathComponent(
                "internal-full-first-run.v1.json",
                isDirectory: false
            ),
            expectedKind: .eraseAppManagedData,
            fileManager: fileManager
        )
#if INTERNAL_BUILD
        let resumableInspections = [appDataInspection, internalInspection]
        let internalRequiresResume = internalInspection.requiresAutomaticResume
        let publicBuildInternalJournalRequiresManualRepair = false
#else
        let resumableInspections = [appDataInspection]
        let internalRequiresResume = false
        let publicBuildInternalJournalRequiresManualRepair = internalInspection != .none
#endif
        let unsafeJournalRequiresManualRepair = resumableInspections.contains(.unsafe)
        let requiresManualRepair = unsafeJournalRequiresManualRepair ||
            publicBuildInternalJournalRequiresManualRepair
        let requiresProtectedStorage = resumableInspections.contains { inspection in
            switch inspection {
            case .recovery(let requiresProtectedStorage):
                return requiresProtectedStorage
            case .unreadable:
                return true
            case .none, .unsafe:
                return false
            }
        }
#if INTERNAL_BUILD
        let report = unsafeJournalRequiresManualRepair
            ? unsafeResetJournalRecoveryReport
            : nil
#else
        let report: String? = if unsafeJournalRequiresManualRepair {
            unsafeResetJournalRecoveryReport
        } else if publicBuildInternalJournalRequiresManualRepair {
            publicBuildInternalResetJournalRecoveryReport
        } else {
            nil
        }
#endif
        return ResetJournalRecoverySummary(
            report: report,
            appDataRequiresResume: appDataInspection.requiresAutomaticResume,
            internalRequiresResume: internalRequiresResume,
            requiresProtectedStorage: requiresProtectedStorage,
            requiresManualRepair: requiresManualRepair
        )
    }

    static func resetProtectionStartupMode(
        helperRecovery: ResetHelperRecoverySummary,
        journalRecovery: ResetJournalRecoverySummary
    ) -> CommitmentProtectionStartupMode {
        let helperRequiresQuarantine = helperRecovery.appDataResetRetryAvailable ||
            helperRecovery.internalResetRetryAvailable ||
            helperRecovery.requiresManualRepair
        if helperRequiresQuarantine || journalRecovery.requiresManualRepair {
            return .committedResetRecovery
        }
        if journalRecovery.appDataRequiresResume || journalRecovery.internalRequiresResume {
            return journalRecovery.requiresProtectedStorage
                ? .activeResetRecovery
                : .committedResetRecovery
        }
        return .normal
    }

    private static let unsafeResetHelperRecoveryReport =
        "A reset helper recovery path is unsafe. No recovery receipt was read or removed. Repair or remove the reset-control item in Application Support before trying reset again."

    private static let unsafeResetJournalRecoveryReport =
        "A reset journal path is unsafe. No journal was read or changed. Repair or remove the reset-control item in Application Support before trying reset again."

    private static let publicBuildInternalResetJournalRecoveryReport =
        "An internal-build reset journal needs attention. This public build cannot continue it. Reopen the matching internal build to finish reset, or inspect the reset-control item in Application Support before removing it."

    private static let publicBuildInternalResetHelperRecoveryReport =
        "An internal-build reset helper needs attention. This public build cannot retry it. Reopen the matching internal build to finish reset, or use Reveal Recovery Files before making manual changes."

    private static func isSafeNamespace(_ namespace: String) -> Bool {
        !namespace.isEmpty &&
            namespace != "." &&
            namespace != ".." &&
            !namespace.contains("/") &&
            !namespace.contains(":") &&
            namespace.trimmingCharacters(in: .whitespacesAndNewlines) == namespace
    }

    private static func isSymbolicLinkIfPresent(
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
            throw error
        }
    }

    private static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let directoryComponents = directory.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count > directoryComponents.count &&
            Array(candidateComponents.prefix(directoryComponents.count)) == directoryComponents
    }

    private static func helperFailureDescription(_ category: String?) -> String {
        switch category {
        case "parentWait": return "process handoff"
        case "tccReset": return "macOS permission reset"
        case "localCleanup": return "local cleanup"
        case "reopen": return "app restart"
        case "receiptPersistence": return "recovery receipt"
        case "multiple": return "multiple steps"
        default: return "unknown step"
        }
    }

    private static func helperDiagnosticDescription(
        _ diagnostic: ResetHelperReceipt.Diagnostic?
    ) -> String? {
        guard let diagnostic else { return nil }
        let target: String
        switch (diagnostic.category, diagnostic.target) {
        case ("reopenCommand", nil): target = "Meeting Incoming"
        case (_, "preferences"): target = "Preferences"
        case (_, "applicationSupport"): target = "Application Support"
        case (_, "caches"): target = "Caches"
        case (_, "httpStorages"): target = "HTTP storage"
        case (_, "savedApplicationState"): target = "Saved Application State"
        default: target = "An app-managed target"
        }

        let action: String
        switch diagnostic.category {
        case "targetInspection": action = "could not be inspected"
        case "targetRemoval": action = "could not be removed"
        case "defaultsDeletion": action = "could not be cleared"
        case "reopenCommand": action = "could not be reopened"
        default: action = "could not be processed"
        }

        let allowedDomains = [
            NSCocoaErrorDomain,
            NSPOSIXErrorDomain,
            NSOSStatusErrorDomain,
            "ProcessExitStatus"
        ]
        if let domain = diagnostic.errorDomain,
           allowedDomains.contains(domain),
           let code = diagnostic.errorCode {
            return "\(target) \(action) (\(domain) \(code))"
        }
        return "\(target) \(action)"
    }

    private static func resolveApplicationSupportDirectory(
        fileManager: FileManager
    ) -> URL {
        if let directory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return directory.standardizedFileURL
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .standardizedFileURL
    }

    private static func defaults(for profile: RuntimeProfile) -> UserDefaults {
        guard let suiteName = profile.defaultsSuiteName else { return .standard }
        // Router-generated suite names are validated before this point. Foundation
        // only returns nil for an invalid suite name.
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Validated Test Mode defaults suite is unavailable")
        }
        return defaults
    }
}

struct RuntimeProtectionComposition {
    let flow: CommitmentProtectionFlow
    let blockingPermissions: BlockingPermissionController
}

enum RuntimeProtectionCompositionPolicy {
    static func usesIsolatedTestComposition(
        profile: RuntimeProfile,
        hasResetRecovery: Bool
    ) -> Bool {
        profile.isTest && !hasResetRecovery
    }
}

@MainActor
enum RuntimeProtectionFactory {
    static func make(
        profile: RuntimeProfile,
        stateStore: UserDefaults,
        oauthConfiguration: GoogleCalendarOAuthConfiguration,
        startupMode: CommitmentProtectionStartupMode = .normal,
        productionVaultFactory: (String) throws -> EncryptedGoogleVault = {
            try EncryptedGoogleVault.production(applicationIdentifier: $0)
        }
    ) -> RuntimeProtectionComposition {
        let vaultIdentifier = profile.vaultApplicationIdentifier
        let vault: EncryptedGoogleVault?
        let storageError: String?
        let storageRequiresReset: Bool
        if startupMode == .committedResetRecovery {
            vault = nil
            storageError = "App-managed data reset recovery is in progress."
            storageRequiresReset = false
        } else {
            do {
                vault = try productionVaultFactory(vaultIdentifier)
                storageError = nil
                storageRequiresReset = false
            } catch {
                vault = nil
                storageError = safeVaultOpeningErrorDescription(error)
                switch error as? EncryptedGoogleVaultError {
                case .keyMaterialCorrupted?, .indexCorrupted?, .accountKeyCorrupted?,
                     .recordCorrupted?, .decodingFailed?:
                    storageRequiresReset = true
                default:
                    storageRequiresReset = false
                }
            }
        }

        let connector: any GoogleCalendarConnecting
        let launchAtLogin: any LaunchAtLoginControlling
        let permissionMode: BlockingPermissionController.Mode
        let recover: @Sendable () throws -> RecoveredEncryptedGoogleStorage

        switch profile {
        case .production:
            if let vault {
                connector = GoogleCalendarConnector(
                    configuration: oauthConfiguration,
                    credentialStore: EncryptedGoogleCredentialStore(vault: vault)
                )
            } else {
                connector = UnavailableGoogleCalendarConnector(
                    message: storageError ?? "Protected storage is unavailable."
                )
            }
            launchAtLogin = SystemLaunchAtLoginController()
            permissionMode = .system
            recover = {
                let replacement = try EncryptedGoogleVault.resetProduction(
                    applicationIdentifier: vaultIdentifier
                )
                let replacementConnector = GoogleCalendarConnector(
                    configuration: oauthConfiguration,
                    credentialStore: EncryptedGoogleCredentialStore(vault: replacement)
                )
                return RecoveredEncryptedGoogleStorage(
                    vault: replacement,
                    connector: replacementConnector
                )
            }
        case .test:
            connector = TestFirstRunCalendarConnector()
            launchAtLogin = SimulatedLaunchAtLoginController(stateStore: stateStore)
            permissionMode = .simulated(stateStore)
            recover = {
                let replacement = try EncryptedGoogleVault.resetProduction(
                    applicationIdentifier: vaultIdentifier
                )
                return RecoveredEncryptedGoogleStorage(
                    vault: replacement,
                    connector: TestFirstRunCalendarConnector()
                )
            }
        }

        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: launchAtLogin,
            stateStore: stateStore,
            encryptedGoogleVault: vault,
            initialEncryptedStorageError: storageError,
            initialEncryptedStorageRequiresReset: storageRequiresReset,
            recoverEncryptedGoogleStorage: recover,
            startupMode: startupMode
        )
        return RuntimeProtectionComposition(
            flow: flow,
            blockingPermissions: BlockingPermissionController(mode: permissionMode)
        )
    }

    private static func safeVaultOpeningErrorDescription(_ error: any Error) -> String {
        guard let vaultError = error as? EncryptedGoogleVaultError else {
            return "Protected storage could not be opened."
        }
        switch vaultError {
        case .secureEnclaveUnavailable:
            return "Secure Enclave is unavailable on this Mac. Protected Google data cannot be stored."
        case .invalidApplicationIdentifier:
            return "The application identifier cannot be used for protected storage."
        case .invalidAccountIdentifier:
            return "The Google account identifier is invalid."
        case .accountNotFound:
            return "The protected Google account was not found."
        case .keyMaterialCorrupted:
            return "The Secure Enclave key material cannot be restored."
        case .indexCorrupted:
            return "The protected account index is damaged or cannot be authenticated."
        case .accountKeyCorrupted:
            return "The protected account key is damaged or cannot be authenticated."
        case .recordCorrupted:
            return "The protected account record is damaged or cannot be authenticated."
        case .encodingFailed:
            return "The account record could not be encoded for protected storage."
        case .decodingFailed:
            return "The protected account record could not be decoded."
        case .storageFailed:
            return "Protected storage could not be opened."
        }
    }
}

@MainActor
final class SystemLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func enable() throws {
        try SMAppService.mainApp.register()
    }

    func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}

private struct UnavailableGoogleCalendarConnector: GoogleCalendarConnecting, Sendable {
    let message: String

    func connect() async throws -> GoogleCalendarConnection {
        throw UnavailableGoogleCalendarConnectorError(message: message)
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        throw UnavailableGoogleCalendarConnectorError(message: message)
    }

    func disconnect(accountID: String) throws {}

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        throw UnavailableGoogleCalendarConnectorError(message: message)
    }
}

private struct UnavailableGoogleCalendarConnectorError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? {
        "Protected Google storage is unavailable. \(message)"
    }
}
