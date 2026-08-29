import AppKit
import SwiftUI

struct TestToolsCommandBridge: View {
    @ObservedObject var controller: TestToolsController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .showTestTools)) { _ in
                controller.testToolsDidOpen()
                openWindow(id: "test-tools")
                NSApp.activate(ignoringOtherApps: true)
                Task { @MainActor in
                    await Task.yield()
                    WindowRegistry.shared.window(for: .testTools)?.makeKeyAndOrderFront(nil)
                }
            }
    }
}

struct TestToolsView: View {
    @EnvironmentObject private var controller: TestToolsController
    @EnvironmentObject private var resetCoordinator: AppManagedDataResetCoordinator
#if INTERNAL_BUILD
    @ObservedObject var internalResetCoordinator: AppManagedDataResetCoordinator
#endif
    @Environment(\.dismiss) private var dismiss
    @State private var pendingConfirmation: Confirmation?
    @State private var resetConfirmationText = ""

    private enum Confirmation: String, Identifiable {
        case start
        case restart
        case exit
        case eraseAppManagedData
#if INTERNAL_BUILD
        case internalFullFirstRun
#endif

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let recoveryReport = controller.recoveryReport {
                    recoveryCard(recoveryReport)
                }
                if let operationError = controller.operationError {
                    errorCard(operationError)
                }
                if let guardReason = controller.realProtectionGuardReason {
                    protectionGuardCard(guardReason)
                }
                resetRecoveryStatus
#if INTERNAL_BUILD
                internalResetRecoveryStatus
#endif

                testFirstRunSection
                Divider()
                eraseSection
                Divider()
                residueDisclosure

                HStack {
                    Spacer()
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(24)
        }
        .frame(width: 560)
        .frame(idealHeight: 560, maxHeight: 720)
        .onAppear {
            controller.testToolsDidOpen()
        }
        .onDisappear {
            controller.testToolsDidClose()
        }
        .alert(item: $pendingConfirmation, content: confirmationAlert)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Test Tools", systemImage: "wrench.and.screwdriver")
                    .font(.title2.bold())
                Spacer()
                if controller.isTestMode {
                    TestModeBadge(title: "TEST MODE")
                }
            }
            Text("Hidden developer controls for exercising first-run and reset behavior.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var testFirstRunSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Test First Run", systemImage: "sparkles.rectangle.stack")
                .font(.headline)

            if controller.isTestMode {
                Text("This is an isolated, persistent test profile. Its calendar connection and macOS permission choices are simulated; production protection continues in the background.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if controller.requiresCleanupRecovery {
                    Button("Retry Cleanup and Exit…") {
                        pendingConfirmation = .exit
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!controller.canChangeRuntime)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            testModeButtons
                        }
                        VStack(alignment: .leading) {
                            testModeButtons
                        }
                    }
                }
            } else {
                Text("Restart into a clean first-run profile with deterministic fixture calendars. Your production preferences, accounts, and encrypted calendar data are not copied or changed.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start Test First Run…") {
                    pendingConfirmation = .start
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.canChangeRuntime)
            }
        }
    }

    @ViewBuilder
    private var testModeButtons: some View {
        Button("Restart Test First Run…") {
            pendingConfirmation = .restart
        }
        .buttonStyle(.borderedProminent)
        .disabled(!controller.canChangeRuntime)

        Button("Exit Test Mode…") {
            pendingConfirmation = .exit
        }
        .disabled(!controller.canChangeRuntime)
    }

    private var eraseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Erase App-Managed Data", systemImage: "trash")
                .font(.headline)
            Text(controller.isTestMode
                ? "This targets the PRODUCTION profile: it revokes every locally usable production Google authorization, unregisters the real Start at Login item, removes production preferences and encrypted data, exits Test Mode, then restarts. The isolated test profile is also removed."
                : "Revokes every locally usable Google authorization, unregisters Start at Login, removes Meeting Incoming’s local preferences and encrypted data, then restarts the app. The operation is journaled and resumes after an interruption.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Google revocation is project-wide and may sign this account out of other Meeting Incoming clients that use the same Google Cloud project.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Type RESET to confirm", text: $resetConfirmationText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Reset confirmation")

            Button("Erase App-Managed Data…", role: .destructive) {
                pendingConfirmation = .eraseAppManagedData
            }
            .disabled(
                resetConfirmationText != "RESET" ||
                    !controller.canChangeRuntime ||
                    controller.isEraseInProgress ||
                    resetIsBusy
            )

#if INTERNAL_BUILD
            Divider()
            Label("Internal build only", systemImage: "hammer.fill")
                .font(.caption.bold())
                .foregroundStyle(.purple)
            Button("Full First Run + macOS Permissions…", role: .destructive) {
                pendingConfirmation = .internalFullFirstRun
            }
            .disabled(
                resetConfirmationText != "RESET" ||
                    !controller.canChangeRuntime ||
                    controller.isEraseInProgress ||
                    resetIsBusy
            )
            Text("Also clears this internal bundle’s Accessibility and Input Monitoring decisions after the app exits. It never targets the public bundle.")
                .font(.caption)
                .foregroundStyle(.secondary)
#endif
        }
    }

    private var residueDisclosure: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("What this cannot make new", systemImage: "info.circle")
                .font(.headline)
            Text("macOS may retain Privacy & Security decisions, Login Items history, and browser or legacy Keychain traces. For a literally never-installed Mac, use a disposable macOS user account or virtual machine.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var resetRecoveryStatus: some View {
        switch resetCoordinator.state {
        case .idle:
            EmptyView()
        case .recovering(let recovery):
            resetProgressCard(
                title: "Reset Recovery",
                detail: "Resuming an interrupted app-managed data reset.",
                progress: recovery.progress,
                color: .orange
            )
        case .executing(let progress):
            resetProgressCard(
                title: "Erasing App-Managed Data",
                detail: resetStepDescription(progress.currentStep),
                progress: progress,
                color: .orange
            )
        case .blocked(let block):
            VStack(alignment: .leading, spacing: 8) {
                resetProgressCard(
                    title: "Reset Needs Attention",
                    detail: resetBlockDescription(block.reason),
                    progress: block.progress,
                    color: .red
                )
                Button("Retry Reset") {
                    controller.retryAppManagedDataReset()
                }
                .disabled(!controller.canRetryAppManagedDataReset)
            }
        case .completed(let progress):
            resetProgressCard(
                title: "Reset Complete",
                detail: "Meeting Incoming is restarting.",
                progress: progress,
                color: .green
            )
        case .unavailable(let problem):
            if resetCoordinator.state.allowsExplicitRetry {
                VStack(alignment: .leading, spacing: 8) {
                    statusCard(
                        title: "Reset Journal Is Unreadable",
                        systemImage: "exclamationmark.triangle.fill",
                        detail: "Retry replaces only the unreadable, non-identifying journal and reruns the idempotent reset plan.",
                        color: .red,
                        dismiss: nil
                    )
                    Button("Replace Journal and Retry Reset", role: .destructive) {
                        controller.retryAppManagedDataReset()
                    }
                    .disabled(!controller.canRetryAppManagedDataReset)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    statusCard(
                        title: "Reset Recovery Needs Manual Attention",
                        systemImage: "exclamationmark.triangle.fill",
                        detail: resetUnavailableDescription(problem),
                        color: .red,
                        dismiss: nil
                    )
                    Button("Reveal Recovery Files") {
                        revealResetRecoveryFiles()
                    }
                }
            }
        }
    }

    private var resetIsBusy: Bool {
        switch resetCoordinator.state {
        case .recovering, .executing:
            return true
        case .idle, .blocked, .completed, .unavailable:
            return false
        }
    }

#if INTERNAL_BUILD
    @ViewBuilder
    private var internalResetRecoveryStatus: some View {
        switch internalResetCoordinator.state {
        case .idle:
            EmptyView()
        case .recovering(let recovery):
            resetProgressCard(
                title: "Internal Reset Recovery",
                detail: "Resuming an interrupted full internal reset.",
                progress: recovery.progress,
                color: .purple
            )
        case .executing(let progress):
            resetProgressCard(
                title: "Running Full Internal Reset",
                detail: resetStepDescription(progress.currentStep),
                progress: progress,
                color: .purple
            )
        case .blocked(let block):
            VStack(alignment: .leading, spacing: 8) {
                resetProgressCard(
                    title: "Internal Reset Needs Attention",
                    detail: resetBlockDescription(block.reason),
                    progress: block.progress,
                    color: .red
                )
                Button("Retry Internal Reset") {
                    controller.retryFullFirstRunInternal()
                }
                .disabled(!controller.canRetryFullFirstRunInternal)
            }
        case .completed(let progress):
            resetProgressCard(
                title: "Internal Reset Complete",
                detail: "Meeting Incoming Internal is restarting.",
                progress: progress,
                color: .green
            )
        case .unavailable(let problem):
            if internalResetCoordinator.state.allowsExplicitRetry {
                VStack(alignment: .leading, spacing: 8) {
                    statusCard(
                        title: "Internal Reset Journal Is Unreadable",
                        systemImage: "exclamationmark.triangle.fill",
                        detail: "Retry replaces only the unreadable journal and reruns the internal reset.",
                        color: .red,
                        dismiss: nil
                    )
                    Button("Replace Journal and Retry Internal Reset", role: .destructive) {
                        controller.retryFullFirstRunInternal()
                    }
                    .disabled(!controller.canRetryFullFirstRunInternal)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    statusCard(
                        title: "Internal Reset Needs Manual Attention",
                        systemImage: "exclamationmark.triangle.fill",
                        detail: resetUnavailableDescription(problem),
                        color: .red,
                        dismiss: nil
                    )
                    Button("Reveal Recovery Files") {
                        revealResetRecoveryFiles()
                    }
                }
            }
        }
    }
#endif

    private func resetProgressCard(
        title: String,
        detail: String,
        progress: AppManagedDataResetProgress,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                Text("\(progress.completedStepCount)/\(progress.totalStepCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(progress.completedStepCount),
                total: Double(max(progress.totalStepCount, 1))
            )
            Text(detail)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func resetStepDescription(_ step: ResetStep?) -> String {
        switch step {
        case .revokeGoogleAuthorization(let position):
            return "Revoking Google authorization \(position + 1)…"
        case .unregisterLaunchAtLogin:
            return "Unregistering Start at Login…"
        case .eraseLocalData:
            return "Handing local cleanup to the post-exit helper…"
        case .resetTCC(let service):
            return "Resetting \(service == .accessibility ? "Accessibility" : "Input Monitoring")…"
        case .relaunch:
            return "Preparing a safe restart…"
        case nil:
            return "Preparing the next reset step…"
        }
    }

    private func resetBlockDescription(_ reason: ResetStepFailureReason) -> String {
        switch reason {
        case .transient:
            return "Google could not be reached. Local deletion stopped so remote authorization is not silently left behind."
        case .ambiguousOutcome:
            return "Google authorization could not be verified. Retry before local data is deleted."
        case .permissionDenied:
            return "A required permission was denied."
        case .unavailable:
            return "A required system operation is unavailable."
        case .ioFailure:
            return "Local app data could not be removed completely."
        case .unexpected:
            return "The reset stopped after an unexpected result."
        }
    }

    private func resetUnavailableDescription(
        _ problem: AppManagedDataResetProblem
    ) -> String {
        switch problem {
        case .journal(.writeFailed):
            return "The reset journal cannot be updated. Repair its folder permissions, quit and reopen Meeting Incoming, then retry."
        case .journal:
            return "The saved reset state cannot be replaced automatically. Keep the recovery files for diagnosis, then quit and reopen Meeting Incoming."
        case .coordinator(.unexpectedJournalPlan):
            return "The saved plan does not match this reset. Keep the recovery files for diagnosis; move the mismatched journal aside, quit and reopen, then start the reset again."
        case .coordinator:
            return "The reset coordinator cannot safely continue this saved plan. Keep the recovery files for diagnosis, then quit and reopen Meeting Incoming."
        }
    }

    private func revealResetRecoveryFiles() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let applicationSupport = FileManager.default.urls(
                  for: .applicationSupportDirectory,
                  in: .userDomainMask
              ).first else { return }
        let directory = applicationSupport.appendingPathComponent(
            "\(bundleIdentifier).reset-control",
            isDirectory: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    private func recoveryCard(_ report: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            statusCard(
                title: controller.hasResetRecoveryAvailable
                    ? "Reset Needs Attention"
                    : "Reset Recovery",
                systemImage: controller.hasResetRecoveryAvailable
                    ? "exclamationmark.triangle.fill"
                    : "arrow.clockwise.circle",
                detail: report,
                color: controller.hasResetRecoveryAvailable ? .red : .orange,
                dismiss: controller.hasResetRecoveryAvailable
                    ? nil
                    : { controller.clearRecoveryReport() }
            )
            if controller.hasResetRecoveryAvailable {
                HStack {
                    if controller.appDataResetRecoveryAvailable {
                        Button("Retry Cleanup and Restart") {
                            controller.retryRecoveredAppManagedDataReset()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!controller.canRetryRecoveredAppManagedDataReset)
                    }
#if INTERNAL_BUILD
                    if controller.internalResetRecoveryAvailable {
                        Button("Retry Full Reset and Restart") {
                            controller.retryRecoveredFullFirstRunInternal()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!controller.canRetryRecoveredFullFirstRunInternal)
                    }
#endif
                    Button("Reveal Recovery Files") {
                        revealResetRecoveryFiles()
                    }
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        statusCard(
            title: "Action Couldn’t Finish",
            systemImage: "exclamationmark.triangle.fill",
            detail: message,
            color: .red,
            dismiss: controller.clearOperationError
        )
    }

    private func protectionGuardCard(_ message: String) -> some View {
        statusCard(
            title: "Real Protection Takes Priority",
            systemImage: "checkmark.shield.fill",
            detail: message,
            color: .orange,
            dismiss: nil
        )
    }

    private func statusCard(
        title: String,
        systemImage: String,
        detail: String,
        color: Color,
        dismiss: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                if let dismiss {
                    Button("Dismiss", action: dismiss)
                        .buttonStyle(.borderless)
                }
            }
            Text(detail)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func confirmationAlert(_ confirmation: Confirmation) -> Alert {
        switch confirmation {
        case .start:
            return Alert(
                title: Text("Start Test First Run?"),
                message: Text("Meeting Incoming will restart into a clean isolated profile. Real calendar protection keeps running in the restarted process."),
                primaryButton: .default(Text("Start and Restart")) {
                    controller.beginTestFirstRun()
                },
                secondaryButton: .cancel()
            )
        case .restart:
            return Alert(
                title: Text("Restart Test First Run?"),
                message: Text("The current test profile will be deleted after this process exits and a fresh test profile will start."),
                primaryButton: .destructive(Text("Restart")) {
                    controller.restartTestFirstRun()
                },
                secondaryButton: .cancel()
            )
        case .exit:
            return Alert(
                title: Text("Exit Test Mode?"),
                message: Text("The isolated test profile will be deleted after this process exits. Meeting Incoming will restart with the untouched production profile."),
                primaryButton: .destructive(Text("Exit and Restart")) {
                    controller.exitTestMode()
                },
                secondaryButton: .cancel()
            )
        case .eraseAppManagedData:
            return Alert(
                title: Text("Erase app-managed data?"),
                message: Text(controller.isTestMode
                    ? "This permanently erases the PRODUCTION profile—not only this test profile—and revokes its Google grants. macOS and browser traces listed below may remain."
                    : "This permanently erases local Meeting Incoming data and revokes its Google grants. macOS and browser traces listed below may remain."),
                primaryButton: .destructive(Text("Erase and Restart")) {
                    resetConfirmationText = ""
                    controller.eraseAppManagedData()
                },
                secondaryButton: .cancel()
            )
#if INTERNAL_BUILD
        case .internalFullFirstRun:
            return Alert(
                title: Text("Run full internal first-run reset?"),
                message: Text("This permanently erases the INTERNAL profile, revokes its Google grants, resets Accessibility and Input Monitoring for only the internal bundle, and restarts."),
                primaryButton: .destructive(Text("Reset and Restart")) {
                    resetConfirmationText = ""
                    controller.runFullFirstRunInternal()
                },
                secondaryButton: .cancel()
            )
#endif
        }
    }

}

struct TestModeBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.bold())
            .tracking(0.6)
            .foregroundStyle(.black.opacity(0.86))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(title == "REAL PROTECTION" ? Color.green : Color.yellow)
            .clipShape(Capsule())
            .accessibilityLabel(title.capitalized)
    }
}

private struct RuntimeModeSurfaceModifier: ViewModifier {
    @ObservedObject var controller: TestToolsController
    let isRealProtection: Bool

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if controller.isTestMode {
                HStack {
                    Spacer()
                    TestModeBadge(
                        title: isRealProtection ? "REAL PROTECTION" : "TEST MODE"
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func runtimeModeSurface(
        _ controller: TestToolsController,
        isRealProtection: Bool = false
    ) -> some View {
        modifier(RuntimeModeSurfaceModifier(
            controller: controller,
            isRealProtection: isRealProtection
        ))
    }
}
