import CommitmentProtection
import Foundation

struct ProtectionActivityProvenancePresentation {
    struct Scope: Equatable, Identifiable, Sendable {
        let compactItem: ProvenancePresentation.CompactItem

        var id: ProvenancePresentation.SourceID { compactItem.id }
        var accountID: String { id.accountID }
        var calendarID: String? { id.calendarID }
        var accountLabel: String { compactItem.accountLabel }
        var calendarLabel: String { compactItem.calendarLabel ?? "" }
        var label: String { compactItem.label }
        var help: String { compactItem.help }
        var accessibilityDescription: String {
            compactItem.accessibilityDescription
        }
    }

    struct Row: Equatable, Sendable {
        let standardGroups: [ProvenancePresentation.StandardGroup]
        let help: String
        let accessibilityDescription: String
    }

    static func scopes(
        sources: [ProtectionProvenanceSource],
        locale: Locale = .autoupdatingCurrent
    ) -> [Scope] {
        ProvenancePresentation(sources: sources, locale: locale)
            .compactItems
            .compactMap { item in
                guard item.id.calendarID != nil else { return nil }
                return Scope(compactItem: item)
            }
            .sorted { lhs, rhs in
                let accountComparison = compare(
                    lhs.accountLabel,
                    rhs.accountLabel,
                    locale: locale
                )
                if accountComparison != .orderedSame {
                    return accountComparison == .orderedAscending
                }
                let calendarComparison = compare(
                    lhs.calendarLabel,
                    rhs.calendarLabel,
                    locale: locale
                )
                if calendarComparison != .orderedSame {
                    return calendarComparison == .orderedAscending
                }
                if lhs.accountID != rhs.accountID {
                    return lhs.accountID < rhs.accountID
                }
                return (lhs.calendarID ?? "") < (rhs.calendarID ?? "")
            }
    }

    static func matchingScopes(
        _ scopes: [Scope],
        query: String,
        locale: Locale = .autoupdatingCurrent
    ) -> [Scope] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scopes }
        return scopes.filter { scope in
            contains(scope.calendarLabel, query: query, locale: locale) ||
                contains(scope.accountLabel, query: query, locale: locale)
        }
    }

    static func row(
        sources: [ProtectionProvenanceSource],
        locale: Locale = .autoupdatingCurrent
    ) -> Row {
        let presentation = ProvenancePresentation(sources: sources, locale: locale)
        return Row(
            standardGroups: presentation.standardGroups,
            help: presentation.fullDescription,
            accessibilityDescription: presentation.accessibilityDescription
        )
    }

    private static func compare(
        _ lhs: String,
        _ rhs: String,
        locale: Locale
    ) -> ComparisonResult {
        lhs.compare(
            rhs,
            options: [.caseInsensitive],
            range: nil,
            locale: locale
        )
    }

    private static func contains(
        _ value: String,
        query: String,
        locale: Locale
    ) -> Bool {
        value.range(
            of: query,
            options: [.caseInsensitive],
            range: nil,
            locale: locale
        ) != nil
    }
}
