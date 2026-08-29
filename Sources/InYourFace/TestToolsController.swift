import AppKit
import Carbon.HIToolbox
import Combine
import CommitmentProtection
import Foundation

extension Notification.Name {
    static let showTestTools = Notification.Name("MeetingIncoming.showTestTools")
}

@MainActor
protocol ApplicationRelaunching {
    func validate() throws
    func relaunch() throws
    func stageRelaunch() throws
    func commitStagedRelaunch()
    func cancelStagedRelaunch()
}

extension ApplicationRelaunching {
    func stageRelaunch() throws {
        try relaunch()
    }

    func commitStagedRelaunch() {}
    func cancelStagedRelaunch() {}
}

enum ApplicationRelaunchError: Error, LocalizedError, Equatable {
    case applicationBundleUnavailable
    case bundleIdentifierUnavailable
    case helperUnavailable
    case operationWriteFailed
    case helperLaunchFailed

    var errorDescription: String? {
        switch self {
        case .applicationBundleUnavailable:
            return "Meeting Incoming must be running from its application bundle to restart."
        case .bundleIdentifierUnavailable:
            return "The running application identity could not be verified."
        case .helperUnavailable:
            return "The bundled restart helper is unavailable. Rebuild or reinstall Meeting Incoming."
        case .operationWriteFailed:
            return "The restart handoff could not be saved."
        case .helperLaunchFailed:
            return "The restart helper could not be launched. Quit and reopen Meeting Incoming to finish the prepared change."
        }
    }
}

/// Performs a process handoff without letting two application processes use the
/// same persistence profile concurrently. The embedded helper validates its app,
/// waits for this PID to exit, and only then asks LaunchServices to reopen it.
@MainActor
final class EmbeddedApplicationRelauncher: ApplicationRelaunching {
    private struct Operation: Encodable {
        let version = 1
        let parentProcessIdentifier: Int32
        let bundleIdentifier: String
        let applicationBundlePath: String
        let homeDirectoryPath: String
    }

    private struct PendingResetReceipt: Encodable {
        let version = 1
        let state = "pending"
        let failureCategory: String? = nil
    }

    private let bundle: Bundle
    private let fileManager: FileManager
    private let processIdentifier: Int32
    private let helperExecutableName: String
    private var stagedProcess: Process?
    private var stagedOperationURL: URL?
    private var stagedResetReceiptURL: URL?

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        helperExecutableName: String = "MeetingIncomingRelaunchHelper"
    ) {
        self.bundle = bundle
        self.fileManager = fileManager
        self.processIdentifier = processIdentifier
        self.helperExecutableName = helperExecutableName
    }

    func validate() throws {
        _ = try verifiedInputs()
    }

    func relaunch() throws {
        try stageRelaunch()
        commitStagedRelaunch()
    }

    func stageRelaunch() throws {
        let inputs = try verifiedInputs()
        let operation = Operation(
            parentProcessIdentifier: processIdentifier,
            bundleIdentifier: inputs.bundleIdentifier,
            applicationBundlePath: inputs.applicationBundleURL.path,
            homeDirectoryPath: fileManager.homeDirectoryForCurrentUser.path
        )
        let operationURL = fileManager.temporaryDirectory.appendingPathComponent(
            "meeting-incoming-relaunch-\(UUID().uuidString.lowercased()).json",
            isDirectory: false
        )
        do {
            let data = try JSONEncoder().encode(operation)
            try data.write(to: operationURL, options: [.atomic, .completeFileProtection])
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: operationURL.path
            )
        } catch {
            throw ApplicationRelaunchError.operationWriteFailed
        }

        let resetReceiptURL: URL?
        do {
            resetReceiptURL = try prepareResetReceiptIfNeeded(
                bundleIdentifier: inputs.bundleIdentifier
            )
        } catch {
            try? fileManager.removeItem(at: operationURL)
            throw ApplicationRelaunchError.operationWriteFailed
        }

        let process = Process()
        process.executableURL = inputs.helperURL
        process.arguments = ["--operation", operationURL.path]
        do {
            try process.run()
        } catch {
            try? fileManager.removeItem(at: operationURL)
            if let resetReceiptURL {
                try? fileManager.removeItem(at: resetReceiptURL)
            }
            throw ApplicationRelaunchError.helperLaunchFailed
        }

        stagedProcess = process
        stagedOperationURL = operationURL
        stagedResetReceiptURL = resetReceiptURL
    }

    func commitStagedRelaunch() {
        stagedProcess = nil
        stagedOperationURL = nil
        stagedResetReceiptURL = nil
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    func cancelStagedRelaunch() {
        stagedProcess?.terminate()
        if let stagedOperationURL {
            try? fileManager.removeItem(at: stagedOperationURL)
        }
        if let stagedResetReceiptURL {
            try? fileManager.removeItem(at: stagedResetReceiptURL)
        }
        stagedProcess = nil
        stagedOperationURL = nil
        stagedResetReceiptURL = nil
    }

    private func verifiedInputs() throws -> (
        applicationBundleURL: URL,
        bundleIdentifier: String,
        helperURL: URL
    ) {
        let applicationBundleURL = bundle.bundleURL.standardizedFileURL
        guard applicationBundleURL.pathExtension == "app" else {
            throw ApplicationRelaunchError.applicationBundleUnavailable
        }
        guard let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            throw ApplicationRelaunchError.bundleIdentifierUnavailable
        }
        let helperURL = applicationBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(helperExecutableName, isDirectory: false)
            .standardizedFileURL
        guard helperURL.path.hasPrefix(
            applicationBundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true).path + "/"
        ), fileManager.isExecutableFile(atPath: helperURL.path) else {
            throw ApplicationRelaunchError.helperUnavailable
        }
        return (applicationBundleURL, bundleIdentifier, helperURL)
    }

    private func prepareResetReceiptIfNeeded(
        bundleIdentifier: String
    ) throws -> URL? {
        let allowedBundleCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: ".-")
        )
        let bundleComponents = bundleIdentifier.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard bundleComponents.count >= 2,
              bundleComponents.allSatisfy({ !$0.isEmpty }),
              bundleIdentifier.unicodeScalars.allSatisfy({
                  allowedBundleCharacters.contains($0)
              }) else {
            throw ApplicationRelaunchError.bundleIdentifierUnavailable
        }
        let fileName: String
        switch helperExecutableName {
        case "MeetingIncomingAppDataResetHelper":
            fileName = "app-data-helper-result.v1.json"
        case "MeetingIncomingInternalResetHelper":
            fileName = "internal-helper-result.v1.json"
        default:
            return nil
        }

        let homeURL = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        guard homeURL.path != "/", !homeURL.path.isEmpty else {
            throw ApplicationRelaunchError.operationWriteFailed
        }
        let directory = homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("\(bundleIdentifier).reset-control", isDirectory: true)
            .standardizedFileURL
        let receiptURL = directory.appendingPathComponent(fileName, isDirectory: false)
        let resolvedHome = homeURL.resolvingSymlinksInPath()
        let resolvedDirectory = directory.resolvingSymlinksInPath()
        guard receiptURL.deletingLastPathComponent() == directory,
              isDescendant(resolvedDirectory, of: resolvedHome),
              try !isSymbolicLinkIfPresent(directory),
              try !isSymbolicLinkIfPresent(receiptURL) else {
            throw ApplicationRelaunchError.operationWriteFailed
        }
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            guard try !isSymbolicLinkIfPresent(directory),
                  try !isSymbolicLinkIfPresent(receiptURL) else {
                throw ApplicationRelaunchError.operationWriteFailed
            }
            let data = try JSONEncoder().encode(PendingResetReceipt())
            try data.write(to: receiptURL, options: [.atomic, .completeFileProtection])
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: receiptURL.path
            )
            return receiptURL
        } catch {
            throw ApplicationRelaunchError.operationWriteFailed
        }
    }

    private func isSymbolicLinkIfPresent(_ url: URL) throws -> Bool {
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
            throw ApplicationRelaunchError.operationWriteFailed
        }
    }

    private func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let directoryComponents = directory.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count > directoryComponents.count &&
            Array(candidateComponents.prefix(directoryComponents.count)) == directoryComponents
    }
}

@MainActor
final class TestToolsShortcutMonitor {
    static let shared = TestToolsShortcutMonitor()

    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.isActive, Self.matches(event) else { return event }
            NotificationCenter.default.post(name: .showTestTools, object: nil)
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    static func matches(_ event: NSEvent) -> Bool {
        let relevantFlags = event.modifierFlags.intersection([
            .command,
            .control,
            .shift,
            .option
        ])
        return event.keyCode == UInt16(kVK_ANSI_R) &&
            relevantFlags == [.command, .control, .shift]
    }
}

@MainActor
struct TestToolsAlertInteraction {
    let suspend: @MainActor () -> Void
    let resume: @MainActor () -> Void

    static let live = TestToolsAlertInteraction(
        suspend: {
            EarlyReminderWindowController.shared.suspendInteractionForTestTools()
            StrongAlertWindowController.shared.suspendInteractionForTestTools()
        },
        resume: {
            EarlyReminderWindowController.shared.resumeInteractionAfterTestTools()
            StrongAlertWindowController.shared.resumeInteractionAfterTestTools()
        }
    )
}

@MainActor
final class TestToolsController: ObservableObject {
    @Published private(set) var profile: RuntimeProfile
    @Published private(set) var recoveryReport: String?
    @Published private(set) var appDataResetRecoveryAvailable: Bool
    @Published private(set) var internalResetRecoveryAvailable: Bool
    @Published private(set) var resetRecoveryRequiresManualRepair: Bool
    @Published private(set) var operationError: String?
    @Published private(set) var isTransitioning = false
    @Published private(set) var isEraseInProgress = false
    @Published private(set) var productionReady: Bool

    private let router: RuntimeProfileRouter
    private let productionFlow: CommitmentProtectionFlow
    private let relauncher: any ApplicationRelaunching
    private let isCleanupRecovery: Bool
    private let alertInteraction: TestToolsAlertInteraction
    private var productionFlowObservation: AnyCancellable?
    private var eraseAppManagedDataAction: (@MainActor () async throws -> Void)?
    private var isResetBusy: @MainActor () -> Bool = { false }
    private var isResetRetryable: @MainActor () -> Bool = { false }
#if INTERNAL_BUILD
    private var fullFirstRunInternalAction: (@MainActor () async throws -> Void)?
    private var isInternalResetRetryable: @MainActor () -> Bool = { false }
#endif

    init(
        profile: RuntimeProfile,
        router: RuntimeProfileRouter,
        productionFlow: CommitmentProtectionFlow,
        relauncher: any ApplicationRelaunching = EmbeddedApplicationRelauncher(),
        recoveryReport: String? = nil,
        appDataResetRecoveryAvailable: Bool = false,
        internalResetRecoveryAvailable: Bool = false,
        resetRecoveryRequiresManualRepair: Bool = false,
        isCleanupRecovery: Bool = false,
        productionReady: Bool = true,
        alertInteraction: TestToolsAlertInteraction = .live
    ) {
        self.profile = profile
        self.router = router
        self.productionFlow = productionFlow
        self.relauncher = relauncher
        self.recoveryReport = recoveryReport
        self.appDataResetRecoveryAvailable = appDataResetRecoveryAvailable
        self.internalResetRecoveryAvailable = internalResetRecoveryAvailable
        self.resetRecoveryRequiresManualRepair = resetRecoveryRequiresManualRepair
        self.isCleanupRecovery = isCleanupRecovery
        self.productionReady = productionReady
        self.alertInteraction = alertInteraction
        productionFlowObservation = productionFlow.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    var isTestMode: Bool { profile.isTest }
    var requiresCleanupRecovery: Bool { isCleanupRecovery }
    var hasResetRecoveryAvailable: Bool {
        appDataResetRecoveryAvailable ||
            internalResetRecoveryAvailable ||
            resetRecoveryRequiresManualRepair
    }

    var realProtectionGuardReason: String? {
        guard productionReady, !productionFlow.isRestoringConnection else {
            return "Real protection is still restoring. Test and reset changes will be available when account recovery finishes."
        }
        if productionFlow.isGoogleAccountOperationInProgress &&
            !productionFlow.isAppManagedDataResetInProgress {
            return "A real Google account operation is in progress. Test and reset changes will be available when it finishes."
        }
        return nil
    }

    var canChangeRuntime: Bool {
        !isTransitioning &&
            !isEraseInProgress &&
            !productionFlow.isAppManagedDataResetInProgress &&
            !isResetBusy() &&
            realProtectionGuardReason == nil
    }

    var canRetryAppManagedDataReset: Bool {
        !isTransitioning &&
            !isEraseInProgress &&
            isResetRetryable() &&
            realProtectionGuardReason == nil
    }

    var canRetryRecoveredAppManagedDataReset: Bool {
        appDataResetRecoveryAvailable && canRetryCommittedResetRecovery
    }

    func start() {
        TestToolsShortcutMonitor.shared.start()
    }

    func testToolsDidOpen() {
        alertInteraction.suspend()
    }

    func testToolsDidClose() {
        guard !productionFlow.isAppManagedDataResetInProgress else { return }
        alertInteraction.resume()
    }

    func beginTestFirstRun() {
        guard !isTestMode else {
            restartTestFirstRun()
            return
        }
        transition {
            try router.beginFreshTest()
        }
    }

    func restartTestFirstRun() {
        guard isTestMode else {
            beginTestFirstRun()
            return
        }
        transition {
            try router.beginFreshTest()
        }
    }

    func exitTestMode() {
        guard isTestMode else { return }
        transition {
            try router.requestExitTest()
        }
    }

    func clearOperationError() {
        operationError = nil
    }

    func clearRecoveryReport() {
        guard !hasResetRecoveryAvailable else { return }
        recoveryReport = nil
    }

    func installEraseAppManagedDataAction(
        _ action: @escaping @MainActor () async throws -> Void
    ) {
        eraseAppManagedDataAction = action
    }

    func installResetBusyCheck(_ check: @escaping @MainActor () -> Bool) {
        isResetBusy = check
    }

    func installResetRetryableCheck(_ check: @escaping @MainActor () -> Bool) {
        isResetRetryable = check
    }

    func productionDidFinishInitialRestore() {
        productionReady = true
    }

    func eraseAppManagedData() {
        guard canChangeRuntime, !isEraseInProgress else { return }
        performAppManagedDataReset()
    }

    func retryAppManagedDataReset() {
        guard canRetryAppManagedDataReset else { return }
        performAppManagedDataReset()
    }

    func retryRecoveredAppManagedDataReset() {
        guard canRetryRecoveredAppManagedDataReset else { return }
        performAppManagedDataReset()
    }

    private func performAppManagedDataReset() {
        guard let eraseAppManagedDataAction else {
            operationError = "The app-managed data reset service is unavailable."
            return
        }
        isEraseInProgress = true
        operationError = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await eraseAppManagedDataAction()
                isEraseInProgress = false
            } catch {
                operationError = error.localizedDescription
                isEraseInProgress = false
            }
        }
    }

#if INTERNAL_BUILD
    func installFullFirstRunInternalAction(
        _ action: @escaping @MainActor () async throws -> Void
    ) {
        fullFirstRunInternalAction = action
    }

    func installInternalResetRetryableCheck(
        _ check: @escaping @MainActor () -> Bool
    ) {
        isInternalResetRetryable = check
    }

    var canRetryFullFirstRunInternal: Bool {
        !isTransitioning &&
            !isEraseInProgress &&
            isInternalResetRetryable() &&
            realProtectionGuardReason == nil
    }

    var canRetryRecoveredFullFirstRunInternal: Bool {
        internalResetRecoveryAvailable && canRetryCommittedResetRecovery
    }

    func runFullFirstRunInternal() {
        guard canChangeRuntime, !isEraseInProgress else { return }
        performFullFirstRunInternal()
    }

    func retryFullFirstRunInternal() {
        guard canRetryFullFirstRunInternal else { return }
        performFullFirstRunInternal()
    }

    func retryRecoveredFullFirstRunInternal() {
        guard canRetryRecoveredFullFirstRunInternal else { return }
        performFullFirstRunInternal()
    }

    private func performFullFirstRunInternal() {
        guard let fullFirstRunInternalAction else {
            operationError = "The internal full-reset service is unavailable."
            return
        }
        isEraseInProgress = true
        operationError = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await fullFirstRunInternalAction()
                isEraseInProgress = false
            } catch {
                operationError = error.localizedDescription
                isEraseInProgress = false
            }
        }
    }
#endif

    private var canRetryCommittedResetRecovery: Bool {
        !isTransitioning &&
            !isEraseInProgress &&
            !isResetBusy() &&
            realProtectionGuardReason == nil
    }

    private func transition(
        routeChange: () throws -> RuntimeProfileResolution
    ) {
        guard canChangeRuntime else { return }
        isTransitioning = true
        operationError = nil
        do {
            try relauncher.validate()
            try relauncher.stageRelaunch()
            do {
                _ = try routeChange()
            } catch {
                relauncher.cancelStagedRelaunch()
                throw error
            }
            relauncher.commitStagedRelaunch()
        } catch {
            operationError = error.localizedDescription
            isTransitioning = false
        }
    }
}
