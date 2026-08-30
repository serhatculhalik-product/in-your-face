import CommitmentProtection
import Foundation

struct OnboardingProtectionSummary: Equatable {
    struct AccountGroup: Equatable, Identifiable {
        let standardPresentation: ProvenancePresentation.StandardGroup
        let calendarIDs: [String]
        let isActivelyProtected: Bool

        var id: String { standardPresentation.id }
        var accountText: String { standardPresentation.accountText }
        var calendarsText: String? { standardPresentation.calendarsText }
        var help: String { standardPresentation.help }
        var accessibilityDescription: String {
            standardPresentation.accessibilityDescription
        }
    }

    let accountGroups: [AccountGroup]
    let activeCalendarCount: Int

    var configuredCalendarCount: Int {
        accountGroups.reduce(0) { $0 + $1.calendarIDs.count }
    }

    static func make(coverages: [AccountCoverage]) -> Self {
        let sourceGroups = coverages.compactMap { coverage -> SourceGroup? in
            guard !coverage.confirmedCalendarIDs.isEmpty else {
                return nil
            }

            let calendarsByID = coverage.calendars.reduce(
                into: [String: CalendarOption]()
            ) { result, calendar in
                result[calendar.id] = calendar
            }
            let sources = coverage.confirmedCalendarIDs.map { calendarID in
                ProtectionProvenanceSource(
                    accountID: coverage.account.id,
                    accountEmail: coverage.account.email,
                    accountDisplayName: coverage.account.displayName,
                    calendarID: calendarID,
                    calendarName: calendarsByID[calendarID]?.name
                )
            }
            return SourceGroup(
                id: coverage.id,
                sources: sources,
                isActivelyProtected: coverage.connectionState == .connected &&
                    coverage.health == .fresh
            )
        }

        // Resolve labels and cross-account collisions once before sorting. The
        // final presentation receives the resulting deterministic order intact.
        let normalization = ProvenancePresentation(
            sources: sourceGroups.flatMap(\.sources)
        )
        let itemsByID = Dictionary(
            uniqueKeysWithValues: normalization.compactItems.map { ($0.id, $0) }
        )
        let orderedSourceGroups = sourceGroups
            .map { group in
                SourceGroup(
                    id: group.id,
                    sources: group.sources.sorted { lhs, rhs in
                        calendarPrecedes(
                            lhs,
                            rhs,
                            normalizedItems: itemsByID
                        )
                    },
                    isActivelyProtected: group.isActivelyProtected
                )
            }
            .sorted { lhs, rhs in
                accountPrecedes(lhs, rhs, normalizedItems: itemsByID)
            }

        let presentation = ProvenancePresentation(
            sources: orderedSourceGroups.flatMap(\.sources)
        )
        let calendarIDsByAccount = Dictionary(
            uniqueKeysWithValues: orderedSourceGroups.map { group in
                (group.id, group.sources.compactMap(\.calendarID))
            }
        )
        let activeAccountIDs = Set(
            orderedSourceGroups.filter(\.isActivelyProtected).map(\.id)
        )
        let accountGroups = presentation.standardGroups.map { standardGroup in
            AccountGroup(
                standardPresentation: standardGroup,
                calendarIDs: calendarIDsByAccount[standardGroup.id] ?? [],
                isActivelyProtected: activeAccountIDs.contains(standardGroup.id)
            )
        }
        let activeCalendarCount = accountGroups.reduce(0) { count, accountGroup in
            count + (accountGroup.isActivelyProtected ? accountGroup.calendarIDs.count : 0)
        }

        return Self(
            accountGroups: accountGroups,
            activeCalendarCount: activeCalendarCount
        )
    }

    private struct SourceGroup {
        let id: String
        let sources: [ProtectionProvenanceSource]
        let isActivelyProtected: Bool
    }

    private static func accountPrecedes(
        _ lhs: SourceGroup,
        _ rhs: SourceGroup,
        normalizedItems: [ProvenancePresentation.SourceID: ProvenancePresentation.CompactItem]
    ) -> Bool {
        let lhsLabel = lhs.sources.first
            .flatMap { normalizedItems[sourceID(for: $0)]?.accountLabel } ?? ""
        let rhsLabel = rhs.sources.first
            .flatMap { normalizedItems[sourceID(for: $0)]?.accountLabel } ?? ""
        let comparison = lhsLabel.localizedCaseInsensitiveCompare(rhsLabel)
        return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
    }

    private static func calendarPrecedes(
        _ lhs: ProtectionProvenanceSource,
        _ rhs: ProtectionProvenanceSource,
        normalizedItems: [ProvenancePresentation.SourceID: ProvenancePresentation.CompactItem]
    ) -> Bool {
        let lhsID = sourceID(for: lhs)
        let rhsID = sourceID(for: rhs)
        let lhsLabel = normalizedItems[lhsID]?.calendarLabel ?? ""
        let rhsLabel = normalizedItems[rhsID]?.calendarLabel ?? ""
        let comparison = lhsLabel.localizedStandardCompare(rhsLabel)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return (lhsID.calendarID ?? "") < (rhsID.calendarID ?? "")
    }

    private static func sourceID(
        for source: ProtectionProvenanceSource
    ) -> ProvenancePresentation.SourceID {
        ProvenancePresentation.SourceID(
            accountID: source.accountID,
            calendarID: source.calendarID
        )
    }
}
