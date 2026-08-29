import CommitmentProtection

struct OnboardingReconnectAccountPresentation: Equatable, Identifiable {
    let id: String
    let label: String
    let savedCalendarCount: Int
    let isConnected: Bool
    let requiresReconnect: Bool
}

struct OnboardingReconnectPresentation: Equatable {
    let accounts: [OnboardingReconnectAccountPresentation]
    let connectedAccountCount: Int
    let savedCalendarCount: Int
    let activelyProtectedCalendarCount: Int
    let currentTargetAccountID: String?
    let connectionError: String?

    var savedAccountCount: Int {
        accounts.count
    }

    var reconnectRequiredAccounts: [OnboardingReconnectAccountPresentation] {
        accounts.filter(\.requiresReconnect)
    }

    var currentTarget: OnboardingReconnectAccountPresentation? {
        guard let currentTargetAccountID else { return nil }
        return accounts.first { $0.id == currentTargetAccountID }
    }

    var requiresReconnect: Bool {
        currentTarget != nil
    }

    static func make(
        coverages: [AccountCoverage],
        preferredAccountID: String?,
        connectionError: String?
    ) -> Self {
        let accounts = coverages.map { coverage in
            let requiresReconnect = coverage.connectionState == .reconnectRequired ||
                coverage.health == .reconnectRequired
            let isConnected = coverage.connectionState == .connected &&
                coverage.health != .reconnectRequired

            return OnboardingReconnectAccountPresentation(
                id: coverage.id,
                label: InterfaceCopy.connectedAccountLabel(
                    email: coverage.account.email,
                    displayName: coverage.account.displayName
                ),
                savedCalendarCount: coverage.selectedCalendarIDs.count,
                isConnected: isConnected,
                requiresReconnect: requiresReconnect
            )
        }

        let preferredTarget = accounts.first {
            $0.id == preferredAccountID && $0.requiresReconnect
        }
        let currentTarget = preferredTarget ?? accounts.first(where: \.requiresReconnect)
        let activelyProtectedCalendarCount = coverages.reduce(into: 0) { count, coverage in
            guard coverage.isProtectionConfirmed,
                  coverage.connectionState == .connected,
                  coverage.health == .fresh else {
                return
            }
            count += coverage.selectedCalendarIDs.count
        }

        return Self(
            accounts: accounts,
            connectedAccountCount: accounts.filter(\.isConnected).count,
            savedCalendarCount: accounts.reduce(0) { $0 + $1.savedCalendarCount },
            activelyProtectedCalendarCount: activelyProtectedCalendarCount,
            currentTargetAccountID: currentTarget?.id,
            connectionError: connectionError
        )
    }
}
