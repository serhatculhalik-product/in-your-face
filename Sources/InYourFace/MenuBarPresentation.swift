import CommitmentProtection
import Foundation

struct MenuBarAccountPresentation: Equatable {
    let id: String
    let label: String
    let connectionState: ConnectionState
    let health: CoverageHealth
}

struct MenuBarProtectionPresentation: Equatable {
    typealias Tone = ProtectionCoveragePresentation.Tone

    enum PrimaryAction: Equatable {
        case finishSetup
        case openSettings
        case reconnect(accountID: String)
    }

    let statusPresentation: ProtectionCoveragePresentation
    let detail: String
    let primaryAction: PrimaryAction?

    var title: String { statusPresentation.label }
    var systemImage: String { statusPresentation.systemImage }
    var tone: Tone { statusPresentation.tone }
    var showsProgress: Bool { statusPresentation.showsProgress }

    static func make(
        isRestoringConnection: Bool,
        needsSetup: Bool,
        status: ProtectionStatus,
        isCheckingCoverage: Bool,
        isPaused: Bool,
        pauseDetail: String,
        isLaunchAtLoginEnabled: Bool,
        hasUpcomingCommitment: Bool,
        accounts: [MenuBarAccountPresentation]
    ) -> Self {
        let reconnectAccounts = accounts.filter {
            $0.connectionState == .reconnectRequired || $0.health == .reconnectRequired
        }
        let statusPresentation = ProtectionCoveragePresentation.global(
            isRestoringConnection: isRestoringConnection,
            needsSetup: needsSetup,
            status: status,
            isCheckingCoverage: isCheckingCoverage,
            isPaused: isPaused,
            hasReconnectRequiredAccount: !reconnectAccounts.isEmpty
        )

        switch statusPresentation.state {
        case .loadingProtection:
            return Self(
                statusPresentation: statusPresentation,
                detail: "Restoring your saved calendar choices…",
                primaryAction: nil
            )

        case .finishSetup:
            return Self(
                statusPresentation: statusPresentation,
                detail: "Connect Google Calendar and choose Monitored Calendars to start reminders.",
                primaryAction: .finishSetup
            )

        case .noCoverage:
            return Self(
                statusPresentation: statusPresentation,
                detail: "Choose Monitored Calendars in Settings to start reminders.",
                primaryAction: .openSettings
            )

        case .protectionPaused:
            return Self(
                statusPresentation: statusPresentation,
                detail: pauseDetail,
                primaryAction: nil
            )

        case .activeProtection:
            let detail: String
            if !isLaunchAtLoginEnabled {
                detail = "Reminders are active, but start at login needs attention."
            } else if hasUpcomingCommitment {
                detail = "Reminders are ready for your next commitment."
            } else {
                detail = "No upcoming commitment needs your attention."
            }
            return Self(
                statusPresentation: statusPresentation,
                detail: detail,
                primaryAction: nil
            )

        case .checkingCoverage:
            return Self(
                statusPresentation: statusPresentation,
                detail: "Restoring your calendar coverage…",
                primaryAction: nil
            )

        case .reconnectRequired:
            let detail = reconnectAccounts.count == 1
                ? "Reconnect \(reconnectAccounts[0].label) to resume reminders. Routine relaunches keep valid authorization."
                : "Reconnect the affected Google Accounts to resume reminders. Routine relaunches keep valid authorization."
            let action = reconnectAccounts.count == 1
                ? PrimaryAction.reconnect(accountID: reconnectAccounts[0].id)
                : nil
            return Self(
                statusPresentation: statusPresentation,
                detail: detail,
                primaryAction: action
            )

        case .coverageNeedsAttention:
            if accounts.contains(where: { $0.health == .stale }) {
                return Self(
                    statusPresentation: statusPresentation,
                    detail: "Calendar data is out of date. Known reminders stay unverified until refresh succeeds.",
                    primaryAction: nil
                )
            }

            return Self(
                statusPresentation: statusPresentation,
                detail: "Calendar coverage is unavailable. Meeting Incoming will retry automatically.",
                primaryAction: nil
            )

        case .freshCoverage,
             .staleCoverage,
             .coverageUnavailable,
             .unverifiedReminder,
             .commitmentConflict,
             .primary:
            preconditionFailure("Account and occurrence states cannot be global menu-bar states.")
        }
    }
}
