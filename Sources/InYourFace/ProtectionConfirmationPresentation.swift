import CommitmentProtection
import Foundation
import SwiftUI

struct ProtectionConfirmationPresentation: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case empty
        case pendingInitialSelection
        case pendingAdditions
        case confirmed
    }

    let state: State
    let selectedCount: Int
    let confirmedCount: Int
    let pendingCount: Int
    let pendingAccountCount: Int
    let title: String
    let detail: String?
    let actionTitle: String?
    let systemImage: String

    var isPending: Bool {
        state == .pendingInitialSelection || state == .pendingAdditions
    }

    var showsAction: Bool {
        isPending && actionTitle != nil
    }

    var accessibilityLabel: String {
        InterfaceCopy.sentences([
            title,
            detail ?? "",
        ])
    }

    static func account(
        _ coverage: AccountCoverage,
        locale: Locale = .autoupdatingCurrent
    ) -> Self {
        let selectedIDs = coverage.selectedCalendarIDs
        let confirmedIDs = selectedIDs.intersection(coverage.confirmedCalendarIDs)
        let pendingCount = selectedIDs.subtracting(confirmedIDs).count

        return make(
            selectedCount: selectedIDs.count,
            confirmedCount: confirmedIDs.count,
            pendingCount: pendingCount,
            pendingAccountCount: pendingCount > 0 ? 1 : 0,
            includesAccountScope: false,
            locale: locale
        )
    }

    static func global(
        _ coverages: [AccountCoverage],
        locale: Locale = .autoupdatingCurrent
    ) -> Self {
        let counts = coverages.reduce(into: Counts()) { result, coverage in
            let selectedIDs = coverage.selectedCalendarIDs
            let confirmedIDs = selectedIDs.intersection(coverage.confirmedCalendarIDs)
            let accountPendingCount = selectedIDs.subtracting(confirmedIDs).count

            result.selected += selectedIDs.count
            result.confirmed += confirmedIDs.count
            result.pending += accountPendingCount
            if accountPendingCount > 0 {
                result.pendingAccounts += 1
            }
        }

        return make(
            selectedCount: counts.selected,
            confirmedCount: counts.confirmed,
            pendingCount: counts.pending,
            pendingAccountCount: counts.pendingAccounts,
            includesAccountScope: coverages.count > 1,
            locale: locale
        )
    }

    private static func make(
        selectedCount: Int,
        confirmedCount: Int,
        pendingCount: Int,
        pendingAccountCount: Int,
        includesAccountScope: Bool,
        locale: Locale
    ) -> Self {
        let state: State
        if selectedCount == 0 {
            state = .empty
        } else if pendingCount > 0 && confirmedCount == 0 {
            state = .pendingInitialSelection
        } else if pendingCount > 0 {
            state = .pendingAdditions
        } else {
            state = .confirmed
        }

        let title: String
        let detail: String?
        let actionTitle: String?
        let systemImage: String

        switch state {
        case .empty:
            title = localized("No Monitored Calendars selected", locale: locale)
            detail = localized(
                "Select at least one calendar to begin protection.",
                locale: locale
            )
            actionTitle = nil
            systemImage = "shield.slash"

        case .pendingInitialSelection:
            title = localized("Calendar selection needs confirmation", locale: locale)
            detail = pendingSelectionDetail(
                selectedCount: pendingCount,
                accountCount: pendingAccountCount,
                includesAccountScope: includesAccountScope,
                locale: locale
            )
            actionTitle = localized("Protect Selected Calendars", locale: locale)
            systemImage = "calendar.badge.plus"

        case .pendingAdditions:
            title = localized("Calendar changes need confirmation", locale: locale)
            detail = InterfaceCopy.sentences([
                pendingAdditionDetail(
                    pendingCount: pendingCount,
                    accountCount: pendingAccountCount,
                    includesAccountScope: includesAccountScope,
                    locale: locale
                ),
                existingProtectionDetail(confirmedCount: confirmedCount, locale: locale),
            ])
            actionTitle = localized("Confirm Calendar Changes", locale: locale)
            systemImage = "calendar.badge.plus"

        case .confirmed:
            title = confirmedSelectionTitle(confirmedCount: confirmedCount, locale: locale)
            detail = nil
            actionTitle = nil
            systemImage = "checkmark.circle"
        }

        return Self(
            state: state,
            selectedCount: selectedCount,
            confirmedCount: confirmedCount,
            pendingCount: pendingCount,
            pendingAccountCount: pendingAccountCount,
            title: title,
            detail: detail,
            actionTitle: actionTitle,
            systemImage: systemImage
        )
    }

    private static func pendingSelectionDetail(
        selectedCount: Int,
        accountCount: Int,
        includesAccountScope: Bool,
        locale: Locale
    ) -> String {
        if includesAccountScope {
            if accountCount == 1 {
                return plainText(
                    AttributedString(
                        localized: "Protection is pending for ^[\(selectedCount) selected calendar](inflect: true) in 1 Google Account.",
                        locale: locale
                    )
                )
            }
            return plainText(
                AttributedString(
                    localized: "Protection is pending for ^[\(selectedCount) selected calendar](inflect: true) across ^[\(accountCount) Google Account](inflect: true).",
                    locale: locale
                )
            )
        }
        return plainText(
            AttributedString(
                localized: "Protection is pending for ^[\(selectedCount) selected calendar](inflect: true).",
                locale: locale
            )
        )
    }

    private static func pendingAdditionDetail(
        pendingCount: Int,
        accountCount: Int,
        includesAccountScope: Bool,
        locale: Locale
    ) -> String {
        if includesAccountScope {
            if accountCount == 1 {
                return plainText(
                    AttributedString(
                        localized: "Protection is pending for ^[\(pendingCount) new calendar](inflect: true) in 1 Google Account.",
                        locale: locale
                    )
                )
            }
            return plainText(
                AttributedString(
                    localized: "Protection is pending for ^[\(pendingCount) new calendar](inflect: true) across ^[\(accountCount) Google Account](inflect: true).",
                    locale: locale
                )
            )
        }
        return plainText(
            AttributedString(
                localized: "Protection is pending for ^[\(pendingCount) new calendar](inflect: true).",
                locale: locale
            )
        )
    }

    private static func existingProtectionDetail(
        confirmedCount: Int,
        locale: Locale
    ) -> String {
        plainText(
            AttributedString(
                localized: "Existing confirmation already includes ^[\(confirmedCount) calendar](inflect: true).",
                locale: locale
            )
        )
    }

    private static func confirmedSelectionTitle(
        confirmedCount: Int,
        locale: Locale
    ) -> String {
        plainText(
            AttributedString(
                localized: "^[\(confirmedCount) Monitored Calendar](inflect: true) confirmed for protection",
                locale: locale
            )
        )
    }

    private static func localized(_ value: String.LocalizationValue, locale: Locale) -> String {
        String(localized: value, locale: locale)
    }

    private static func plainText(_ value: AttributedString) -> String {
        String(value.characters)
    }

    private struct Counts {
        var selected = 0
        var confirmed = 0
        var pending = 0
        var pendingAccounts = 0
    }
}

struct ProtectionConfirmationRegion: View {
    let presentation: ProtectionConfirmationPresentation
    let isActionEnabled: Bool
    let confirm: () -> Void

    var body: some View {
        if presentation.showsAction, let actionTitle = presentation.actionTitle {
            AdaptiveSettingsActionRow {
                status
            } actions: {
                Button(actionTitle, action: confirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isActionEnabled)
            }
        } else {
            status
                .foregroundStyle(.secondary)
        }
    }

    private var status: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.callout.weight(presentation.isPending ? .semibold : .regular))
                if let detail = presentation.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: presentation.systemImage)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}
