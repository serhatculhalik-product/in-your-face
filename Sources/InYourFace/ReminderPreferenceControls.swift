import AppKit
import CommitmentProtection
import SwiftUI

struct EarlyReminderTimingControls: View {
    @Binding var isEnabled: Bool
    @Binding var leadTimeMinutes: Int

    var body: some View {
        Group {
            Toggle("Show Early Reminder", isOn: $isEnabled)

            Stepper(
                InterfaceCopy.remindMeBefore(leadTimeMinutes),
                value: $leadTimeMinutes,
                in: 5...30,
                step: 5
            )
            .disabled(!isEnabled)
            .accessibilityLabel("Early Reminder lead time")
            .accessibilityValue(InterfaceCopy.minuteDuration(leadTimeMinutes))
        }
    }
}

struct BlockingModeControls: View {
    @EnvironmentObject private var flow: CommitmentProtectionFlow
    @EnvironmentObject private var blockingPermissions: BlockingPermissionController
    @ObservedObject private var windowController = EarlyReminderWindowController.shared
    @State private var isBlockingExplanationPresented = false
    @State private var permissionsRevision = 0

    let showsCurrentReminderStatus: Bool

    var body: some View {
        Group {
            Toggle(
                "Block other apps while an Early Reminder is open",
                isOn: Binding(
                    get: { flow.isBlockingModeEnabled },
                    set: { isEnabled in
                        if isEnabled, !flow.isBlockingModeEnabled {
                            isBlockingExplanationPresented = true
                        } else if !isEnabled {
                            setBlockingModeEnabled(false)
                        }
                    }
                )
            )

            if flow.isBlockingModeEnabled {
                Text(blockingPermissions.isSimulated
                    ? "Test Mode simulates Accessibility and Input Monitoring choices. It never opens or modifies macOS Privacy & Security settings."
                    : "Blocking Mode needs Accessibility and Input Monitoring permissions. Without both, the Early Reminder stays visible but cannot block interaction with other apps.")
                    .foregroundStyle(.secondary)
                blockingPermissionStatus
                if showsCurrentReminderStatus, flow.earlyReminderCommitment != nil {
                    Label(
                        flow.isBlockingAvailable
                            ? "Blocking Mode is active for the current Early Reminder."
                            : "Blocking Mode is unavailable for the current Early Reminder. It remains visible in visual-only mode.",
                        systemImage: flow.isBlockingAvailable
                            ? "checkmark.circle"
                            : "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack {
                        blockingPermissionButtons
                    }
                    VStack(alignment: .leading) {
                        blockingPermissionButtons
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionsRevision &+= 1
        }
        .alert("Enable Blocking Mode?", isPresented: $isBlockingExplanationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Continue") {
                setBlockingModeEnabled(true)
                if !blockingPermissions.hasAccessibilityPermission {
                    blockingPermissions.request(.accessibility)
                }
            }
        } message: {
            Text("Blocking Mode can prevent interaction with other apps while an Early Reminder is visible. macOS requires Accessibility first, then Input Monitoring. If either permission is denied, reminders remain visual-only.")
        }
        .confirmationDialog(
            simulationTitle,
            isPresented: simulationIsPresented,
            titleVisibility: .visible
        ) {
            Button("Allow for Test Mode") {
                blockingPermissions.resolveSimulation(allowed: true)
            }
            Button("Don’t Allow", role: .cancel) {
                blockingPermissions.resolveSimulation(allowed: false)
            }
        } message: {
            Text("This changes only the isolated Test First Run profile. macOS privacy settings are not opened or modified.")
        }
    }

    @ViewBuilder
    private var blockingPermissionButtons: some View {
        let _ = permissionsRevision
        if !blockingPermissions.hasAccessibilityPermission {
            Button(blockingPermissions.isSimulated
                ? "1. Simulate Accessibility Permission"
                : "1. Open Accessibility Settings") {
                blockingPermissions.request(.accessibility)
            }
        } else if !blockingPermissions.hasInputMonitoringPermission {
            Button(blockingPermissions.isSimulated
                ? "2. Simulate Input Monitoring Permission"
                : "2. Open Input Monitoring Settings") {
                blockingPermissions.request(.inputMonitoring)
            }
        } else {
            Label("Required permissions granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var blockingPermissionStatus: some View {
        let _ = permissionsRevision
        if !blockingPermissions.hasAccessibilityPermission {
            Label("Step 1 of 2 · Accessibility required", systemImage: "1.circle")
                .foregroundStyle(.secondary)
        } else if !blockingPermissions.hasInputMonitoringPermission {
            Label("Step 2 of 2 · Input Monitoring required", systemImage: "2.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func setBlockingModeEnabled(_ isEnabled: Bool) {
        flow.setBlockingModeEnabled(isEnabled)
        windowController.setBlockingModeEnabled(isEnabled && !blockingPermissions.isSimulated)
    }

    private var simulationTitle: String {
        switch blockingPermissions.pendingSimulation {
        case .accessibility:
            return "Simulate Accessibility Permission?"
        case .inputMonitoring:
            return "Simulate Input Monitoring Permission?"
        case nil:
            return "Simulate Permission?"
        }
    }

    private var simulationIsPresented: Binding<Bool> {
        Binding(
            get: {
                blockingPermissions.isSimulated && blockingPermissions.pendingSimulation != nil
            },
            set: { isPresented in
                if !isPresented, blockingPermissions.pendingSimulation != nil {
                    blockingPermissions.resolveSimulation(allowed: false)
                }
            }
        )
    }
}
