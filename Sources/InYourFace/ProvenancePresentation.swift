import CommitmentProtection
import Foundation

struct ProvenancePresentation: Equatable, Sendable {
    struct SourceID: Equatable, Hashable, Sendable {
        let accountID: String
        let calendarID: String?
    }

    struct CompactItem: Equatable, Identifiable, Sendable {
        let id: SourceID
        let accountLabel: String
        let calendarLabel: String?
        let ordinal: String?
        let label: String
        let help: String
        let accessibilityDescription: String
    }

    struct CalendarItem: Equatable, Identifiable, Sendable {
        let id: SourceID
        let calendarLabel: String
        let ordinal: String?
        let label: String
        let text: String
        let help: String
        let accessibilityDescription: String
    }

    struct StandardGroup: Equatable, Identifiable, Sendable {
        let id: String
        let accountLabel: String
        let accountText: String
        let calendars: [CalendarItem]?
        let calendarsText: String?
        let help: String
        let accessibilityDescription: String
    }

    struct Urgent: Equatable, Sendable {
        let primaryText: String
        let secondaryText: String?
        let help: String
        let accessibilityDescription: String
    }

    let compactItems: [CompactItem]
    let standardGroups: [StandardGroup]
    let urgent: Urgent?
    let fullDescription: String
    let accessibilityDescription: String

    init(
        sources: [ProtectionProvenanceSource],
        locale: Locale = .autoupdatingCurrent
    ) {
        let normalizedSources = Self.normalized(sources, locale: locale)
        let descriptions = normalizedSources.map {
            Self.fullDescription(for: $0, locale: locale)
        }
        let fullDescription = Self.localizedList(descriptions, locale: locale)

        compactItems = normalizedSources.map { source in
            let description = Self.fullDescription(for: source, locale: locale)
            return CompactItem(
                id: source.id,
                accountLabel: source.accountLabel,
                calendarLabel: source.calendarLabel,
                ordinal: source.ordinal?.text,
                label: Self.compactLabel(for: source, locale: locale),
                help: description,
                accessibilityDescription: description
            )
        }
        standardGroups = Self.standardGroups(normalizedSources, locale: locale)
        urgent = Self.urgent(
            normalizedSources,
            fullDescription: fullDescription,
            accessibilityDescription: fullDescription,
            locale: locale
        )
        self.fullDescription = fullDescription
        accessibilityDescription = fullDescription
    }

    private struct Ordinal {
        let text: String
    }

    private struct NormalizedSource {
        let id: SourceID
        let accountLabel: String
        let calendarLabel: String?
        var ordinal: Ordinal?
    }

    private struct VisibleIdentity: Hashable {
        let accountLabel: String
        let calendarLabel: String?
    }

    private static func normalized(
        _ sources: [ProtectionProvenanceSource],
        locale: Locale
    ) -> [NormalizedSource] {
        var seen: Set<SourceID> = []
        var normalizedSources = sources.compactMap { source -> NormalizedSource? in
            let id = SourceID(accountID: source.accountID, calendarID: source.calendarID)
            guard seen.insert(id).inserted else { return nil }

            let hasCalendar = source.calendarID != nil || source.calendarName != nil
            return NormalizedSource(
                id: id,
                accountLabel: InterfaceCopy.connectedAccountLabel(
                    email: source.accountEmail,
                    displayName: source.accountDisplayName,
                    locale: locale
                ),
                calendarLabel: hasCalendar
                    ? calendarLabel(source.calendarName, locale: locale)
                    : nil,
                ordinal: nil
            )
        }

        let collisionGroups = Dictionary(grouping: normalizedSources.indices) { index in
            VisibleIdentity(
                accountLabel: normalizedSources[index].accountLabel,
                calendarLabel: normalizedSources[index].calendarLabel
            )
        }
        for indices in collisionGroups.values where indices.count > 1 {
            let stableIndices = indices.sorted {
                sourceID(normalizedSources[$0].id, precedes: normalizedSources[$1].id)
            }
            for (offset, index) in stableIndices.enumerated() {
                let position = offset + 1
                normalizedSources[index].ordinal = Ordinal(
                    text: localized("\(position) of \(stableIndices.count)", locale: locale)
                )
            }
        }
        return normalizedSources
    }

    private static func sourceID(_ lhs: SourceID, precedes rhs: SourceID) -> Bool {
        if lhs.accountID != rhs.accountID {
            return lhs.accountID < rhs.accountID
        }
        switch (lhs.calendarID, rhs.calendarID) {
        case (nil, .some):
            return true
        case (.some, nil):
            return false
        case (let lhsCalendarID?, let rhsCalendarID?):
            return lhsCalendarID < rhsCalendarID
        case (nil, nil):
            return false
        }
    }

    private static func compactLabel(
        for source: NormalizedSource,
        locale: Locale
    ) -> String {
        if let calendarLabel = source.calendarLabel {
            if let ordinal = source.ordinal?.text {
                return localized(
                    "Calendar: \(calendarLabel) · Account: \(source.accountLabel) (\(ordinal))",
                    locale: locale
                )
            }
            return localized(
                "Calendar: \(calendarLabel) · Account: \(source.accountLabel)",
                locale: locale
            )
        }
        if let ordinal = source.ordinal?.text {
            return localized(
                "Account: \(source.accountLabel) (\(ordinal))",
                locale: locale
            )
        }
        return localized("Account: \(source.accountLabel)", locale: locale)
    }

    private static func fullDescription(
        for source: NormalizedSource,
        locale: Locale
    ) -> String {
        if let calendarLabel = source.calendarLabel {
            if let ordinal = source.ordinal?.text {
                return localized(
                    "Monitored Calendar \(calendarLabel), Google Account \(source.accountLabel), \(ordinal)",
                    locale: locale
                )
            }
            return localized(
                "Monitored Calendar \(calendarLabel), Google Account \(source.accountLabel)",
                locale: locale
            )
        }
        if let ordinal = source.ordinal?.text {
            return localized(
                "Google Account \(source.accountLabel), \(ordinal)",
                locale: locale
            )
        }
        return localized("Google Account \(source.accountLabel)", locale: locale)
    }

    private static func standardGroups(
        _ sources: [NormalizedSource],
        locale: Locale
    ) -> [StandardGroup] {
        var accountOrder: [String] = []
        var groupedSources: [String: [NormalizedSource]] = [:]
        for source in sources {
            if groupedSources[source.id.accountID] == nil {
                accountOrder.append(source.id.accountID)
            }
            groupedSources[source.id.accountID, default: []].append(source)
        }

        return accountOrder.compactMap { accountID in
            guard let accountSources = groupedSources[accountID],
                  let first = accountSources.first else {
                return nil
            }
            let calendarItems = accountSources.compactMap { source -> CalendarItem? in
                guard let calendarLabel = source.calendarLabel else { return nil }
                let displayLabel = qualifiedLabel(
                    calendarLabel,
                    ordinal: source.ordinal?.text,
                    locale: locale
                )
                let description = fullDescription(for: source, locale: locale)
                return CalendarItem(
                    id: source.id,
                    calendarLabel: calendarLabel,
                    ordinal: source.ordinal?.text,
                    label: displayLabel,
                    text: localized("Monitored Calendar: \(displayLabel)", locale: locale),
                    help: description,
                    accessibilityDescription: description
                )
            }
            let calendars = calendarItems.isEmpty ? nil : calendarItems
            let calendarsText: String?
            if calendarItems.count == 1 {
                calendarsText = calendarItems[0].text
            } else if calendarItems.count > 1 {
                calendarsText = localized(
                    "Monitored Calendars: \(localizedList(calendarItems.map(\.label), locale: locale))",
                    locale: locale
                )
            } else {
                calendarsText = nil
            }

            let accountOnlyOrdinal = calendarItems.isEmpty ? first.ordinal?.text : nil
            let displayAccountLabel = qualifiedLabel(
                first.accountLabel,
                ordinal: accountOnlyOrdinal,
                locale: locale
            )
            let description = localizedList(
                accountSources.map { fullDescription(for: $0, locale: locale) },
                locale: locale
            )
            return StandardGroup(
                id: accountID,
                accountLabel: first.accountLabel,
                accountText: localized(
                    "Google Account: \(displayAccountLabel)",
                    locale: locale
                ),
                calendars: calendars,
                calendarsText: calendarsText,
                help: description,
                accessibilityDescription: description
            )
        }
    }

    private static func urgent(
        _ sources: [NormalizedSource],
        fullDescription: String,
        accessibilityDescription: String,
        locale: Locale
    ) -> Urgent? {
        let calendarSources = sources.filter { $0.calendarLabel != nil }
        guard !calendarSources.isEmpty else { return nil }

        if calendarSources.count == 1,
           let source = calendarSources.first,
           let calendarLabel = source.calendarLabel {
            return Urgent(
                primaryText: qualifiedLabel(
                    calendarLabel,
                    ordinal: source.ordinal?.text,
                    locale: locale
                ),
                secondaryText: localized("Account: \(source.accountLabel)", locale: locale),
                help: fullDescription,
                accessibilityDescription: accessibilityDescription
            )
        }

        let accountIDs = Set(calendarSources.map { $0.id.accountID })
        let primaryText = localized(
            "^[\(calendarSources.count) calendar source](inflect: true)",
            locale: locale
        )
        let secondaryText: String?
        if accountIDs.count == 1, let accountLabel = calendarSources.first?.accountLabel {
            secondaryText = localized("Account: \(accountLabel)", locale: locale)
        } else {
            secondaryText = localized(
                "Across ^[\(accountIDs.count) account](inflect: true)",
                locale: locale
            )
        }
        return Urgent(
            primaryText: primaryText,
            secondaryText: secondaryText,
            help: fullDescription,
            accessibilityDescription: accessibilityDescription
        )
    }

    private static func qualifiedLabel(
        _ label: String,
        ordinal: String?,
        locale: Locale
    ) -> String {
        guard let ordinal else { return label }
        return localized("\(label) (\(ordinal))", locale: locale)
    }

    private static func calendarLabel(_ value: String?, locale: Locale) -> String {
        guard let value else {
            return localized("Unavailable calendar", locale: locale)
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? localized("Unnamed calendar", locale: locale)
            : trimmed
    }

    private static func localized(
        _ resource: String.LocalizationValue,
        locale: Locale
    ) -> String {
        String(AttributedString(localized: resource, locale: locale).characters)
    }

    private static func localizedList(_ values: [String], locale: Locale) -> String {
        guard values.count > 1 else { return values.first ?? "" }
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: values) ?? values.joined(separator: ", ")
    }
}
