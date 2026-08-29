import CommitmentProtection
import Foundation

struct MenuBarAccountPresentation: Equatable {
    let id: String
    let label: String
    let connectionState: ConnectionState
    let health: CoverageHealth
}

struct MenuBarProtectionPresentation: Equatable {
    enum Tone: Equatable {
        case neutral
        case positive
        case attention
    }

    enum PrimaryAction: Equatable {
        case finishSetup
        case openSettings
        case reconnect(accountID: String)
    }

    let title: String
    let detail: String
    let systemImage: String
    let tone: Tone
    let showsProgress: Bool
    let primaryAction: PrimaryAction?

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
        if isRestoringConnection {
            return Self(
                title: "Loading Protection",
                detail: "Restoring your saved calendar choices…",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .neutral,
                showsProgress: true,
                primaryAction: nil
            )
        }

        if needsSetup {
            return Self(
                title: "Finish Setup",
                detail: "Connect Google Calendar and choose Monitored Calendars to start reminders.",
                systemImage: "shield.slash",
                tone: .attention,
                showsProgress: false,
                primaryAction: .finishSetup
            )
        }

        switch status {
        case .noCoverage:
            return Self(
                title: "No Coverage",
                detail: "Choose Monitored Calendars in Settings to start reminders.",
                systemImage: "shield.slash",
                tone: .attention,
                showsProgress: false,
                primaryAction: .openSettings
            )

        case .active:
            if isPaused {
                return Self(
                    title: "Protection Paused",
                    detail: pauseDetail,
                    systemImage: "pause.circle.fill",
                    tone: .neutral,
                    showsProgress: false,
                    primaryAction: nil
                )
            }

            let detail: String
            if !isLaunchAtLoginEnabled {
                detail = "Reminders are active, but start at login needs attention."
            } else if hasUpcomingCommitment {
                detail = "Reminders are ready for your next commitment."
            } else {
                detail = "No upcoming commitment needs your attention."
            }
            return Self(
                title: "Active Protection",
                detail: detail,
                systemImage: "checkmark.shield.fill",
                tone: .positive,
                showsProgress: false,
                primaryAction: nil
            )

        case .unavailable:
            if isCheckingCoverage {
                return Self(
                    title: "Checking Coverage",
                    detail: "Restoring your calendar coverage…",
                    systemImage: "arrow.triangle.2.circlepath",
                    tone: .neutral,
                    showsProgress: true,
                    primaryAction: nil
                )
            }

            let reconnectAccounts = accounts.filter {
                $0.connectionState == .reconnectRequired || $0.health == .reconnectRequired
            }
            if !reconnectAccounts.isEmpty {
                let detail = reconnectAccounts.count == 1
                    ? "Reconnect \(reconnectAccounts[0].label) to resume reminders. Routine relaunches keep valid authorization."
                    : "Reconnect the affected Google Accounts to resume reminders. Routine relaunches keep valid authorization."
                let action = reconnectAccounts.count == 1
                    ? PrimaryAction.reconnect(accountID: reconnectAccounts[0].id)
                    : nil
                return Self(
                    title: "Reconnect Required",
                    detail: detail,
                    systemImage: "calendar.badge.exclamationmark",
                    tone: .attention,
                    showsProgress: false,
                    primaryAction: action
                )
            }

            if accounts.contains(where: { $0.health == .stale }) {
                return Self(
                    title: "Coverage Needs Attention",
                    detail: "Calendar data is out of date. Known reminders stay unverified until refresh succeeds.",
                    systemImage: "calendar.badge.exclamationmark",
                    tone: .attention,
                    showsProgress: false,
                    primaryAction: nil
                )
            }

            return Self(
                title: "Coverage Needs Attention",
                detail: "Calendar coverage is unavailable. Meeting Incoming will retry automatically.",
                systemImage: "calendar.badge.exclamationmark",
                tone: .attention,
                showsProgress: false,
                primaryAction: nil
            )
        }
    }
}
