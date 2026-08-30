import CommitmentProtection

struct ProtectionCoveragePresentation: Equatable, Sendable {
    enum State: CaseIterable, Equatable, Sendable {
        case loadingProtection
        case finishSetup
        case checkingCoverage
        case noCoverage
        case activeProtection
        case freshCoverage
        case protectionPaused
        case staleCoverage
        case reconnectRequired
        case coverageUnavailable
        case coverageNeedsAttention
        case unverifiedReminder
        case commitmentConflict
        case primary
    }

    enum Tone: Equatable, Sendable {
        case neutral
        case positive
        case caution
    }

    let state: State
    let label: String
    let systemImage: String
    let tone: Tone
    let showsProgress: Bool

    init(state: State) {
        self.state = state
        switch state {
        case .loadingProtection:
            label = "Loading Protection"
            systemImage = "arrow.triangle.2.circlepath"
            tone = .neutral
            showsProgress = true
        case .finishSetup:
            label = "Finish Setup"
            systemImage = "shield.slash"
            tone = .neutral
            showsProgress = false
        case .checkingCoverage:
            label = "Checking Coverage"
            systemImage = "arrow.triangle.2.circlepath"
            tone = .neutral
            showsProgress = true
        case .noCoverage:
            label = "No Coverage"
            systemImage = "shield.slash"
            tone = .neutral
            showsProgress = false
        case .activeProtection:
            label = "Active Protection"
            systemImage = "checkmark.shield.fill"
            tone = .positive
            showsProgress = false
        case .freshCoverage:
            label = "Fresh Coverage"
            systemImage = "checkmark.circle.fill"
            tone = .positive
            showsProgress = false
        case .protectionPaused:
            label = "Protection Paused"
            systemImage = "pause.circle.fill"
            tone = .neutral
            showsProgress = false
        case .staleCoverage:
            label = "Stale Coverage"
            systemImage = "calendar.badge.clock"
            tone = .caution
            showsProgress = false
        case .reconnectRequired:
            label = "Reconnect Required"
            systemImage = "person.crop.circle.badge.exclamationmark"
            tone = .caution
            showsProgress = false
        case .coverageUnavailable:
            label = "Coverage Unavailable"
            systemImage = "calendar.badge.exclamationmark"
            tone = .caution
            showsProgress = false
        case .coverageNeedsAttention:
            label = "Coverage Needs Attention"
            systemImage = "calendar.badge.exclamationmark"
            tone = .caution
            showsProgress = false
        case .unverifiedReminder:
            label = "Unverified Reminder"
            systemImage = "questionmark.circle"
            tone = .caution
            showsProgress = false
        case .commitmentConflict:
            label = "Commitment Conflict"
            systemImage = "rectangle.3.group"
            tone = .neutral
            showsProgress = false
        case .primary:
            label = "Primary"
            systemImage = "checkmark.circle"
            tone = .neutral
            showsProgress = false
        }
    }

    static func account(
        _ health: CoverageHealth,
        requiresReconnect: Bool = false
    ) -> Self {
        if requiresReconnect || health == .reconnectRequired {
            return Self(state: .reconnectRequired)
        }

        switch health {
        case .noCoverage:
            return Self(state: .noCoverage)
        case .checking:
            return Self(state: .checkingCoverage)
        case .fresh:
            return Self(state: .freshCoverage)
        case .stale:
            return Self(state: .staleCoverage)
        case .reconnectRequired:
            return Self(state: .reconnectRequired)
        case .unavailable:
            return Self(state: .coverageUnavailable)
        }
    }

    static func global(
        isRestoringConnection: Bool,
        needsSetup: Bool,
        status: ProtectionStatus,
        isCheckingCoverage: Bool,
        isPaused: Bool,
        hasReconnectRequiredAccount: Bool
    ) -> Self {
        if isRestoringConnection {
            return Self(state: .loadingProtection)
        }
        if needsSetup {
            return Self(state: .finishSetup)
        }

        switch status {
        case .noCoverage:
            return Self(state: .noCoverage)
        case .active:
            return Self(state: isPaused ? .protectionPaused : .activeProtection)
        case .unavailable:
            if isCheckingCoverage {
                return Self(state: .checkingCoverage)
            }
            if hasReconnectRequiredAccount {
                return Self(state: .reconnectRequired)
            }
            return Self(state: .coverageNeedsAttention)
        }
    }
}
