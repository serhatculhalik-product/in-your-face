import CommitmentProtection
import Foundation

struct OnboardingProtectionSummary: Equatable {
    struct AccountGroup: Equatable, Identifiable {
        struct Calendar: Equatable, Identifiable {
            let id: String
            let name: String
        }

        let id: String
        let label: String
        let calendars: [Calendar]
        let isActivelyProtected: Bool
    }

    let accountGroups: [AccountGroup]
    let activeCalendarCount: Int

    var configuredCalendarCount: Int {
        accountGroups.reduce(0) { $0 + $1.calendars.count }
    }

    static func make(coverages: [AccountCoverage]) -> Self {
        let accountGroups = coverages.compactMap { coverage -> AccountGroup? in
            guard !coverage.confirmedCalendarIDs.isEmpty else {
                return nil
            }

            var calendarNamesByID: [String: String] = [:]
            for calendar in coverage.calendars {
                let trimmedName = calendar.name.trimmingCharacters(in: .whitespacesAndNewlines)
                calendarNamesByID[calendar.id] = trimmedName.isEmpty ? "Unnamed calendar" : trimmedName
            }

            let calendars = coverage.confirmedCalendarIDs
                .map { calendarID in
                    AccountGroup.Calendar(
                        id: calendarID,
                        name: calendarNamesByID[calendarID] ?? "Unavailable calendar"
                    )
                }
                .sorted { lhs, rhs in
                    let comparison = lhs.name.localizedStandardCompare(rhs.name)
                    return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
                }

            return AccountGroup(
                id: coverage.id,
                label: InterfaceCopy.connectedAccountLabel(
                    email: coverage.account.email,
                    displayName: coverage.account.displayName
                ),
                calendars: calendars,
                isActivelyProtected: coverage.connectionState == .connected &&
                    coverage.health == .fresh
            )
        }
        .sorted { lhs, rhs in
            let comparison = lhs.label.localizedCaseInsensitiveCompare(rhs.label)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }

        let activeCalendarCount = accountGroups.reduce(0) { count, accountGroup in
            count + (accountGroup.isActivelyProtected ? accountGroup.calendars.count : 0)
        }

        return Self(
            accountGroups: accountGroups,
            activeCalendarCount: activeCalendarCount
        )
    }
}
