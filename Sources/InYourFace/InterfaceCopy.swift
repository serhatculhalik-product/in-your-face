import Foundation

enum InterfaceCopy {
    struct MeetingLinkChoice: Equatable {
        let url: URL
        let title: String
    }

    static func protectedCalendarCount(_ count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        plainText(
            AttributedString(
                localized: "^[\(count) calendar](inflect: true) protected",
                locale: locale
            )
        )
    }

    static func calendarSelectionSummary(
        selectedCount: Int,
        totalCount: Int,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        plainText(
            AttributedString(
                localized: "\(selectedCount) of ^[\(totalCount) calendar](inflect: true) selected",
                locale: locale
            )
        )
    }

    static func minuteDuration(_ minutes: Int, locale: Locale = .autoupdatingCurrent) -> String {
        plainText(
            AttributedString(
                localized: "^[\(minutes) minute](inflect: true)",
                locale: locale
            )
        )
    }

    static func earlyReminderTiming(_ minutes: Int, locale: Locale = .autoupdatingCurrent) -> String {
        plainText(
            AttributedString(
                localized: "Early Reminder ^[\(minutes) minute](inflect: true) before",
                locale: locale
            )
        )
    }

    static func remindMeBefore(_ minutes: Int, locale: Locale = .autoupdatingCurrent) -> String {
        plainText(
            AttributedString(
                localized: "Remind me ^[\(minutes) minute](inflect: true) before",
                locale: locale
            )
        )
    }

    static func strongAlertRepeatTiming(_ minutes: Int, locale: Locale = .autoupdatingCurrent) -> String {
        plainText(
            AttributedString(
                localized: "Strong Alert repeats every ^[\(minutes) minute](inflect: true)",
                locale: locale
            )
        )
    }

    static func repeatEvery(_ minutes: Int, locale: Locale = .autoupdatingCurrent) -> String {
        plainText(
            AttributedString(
                localized: "Repeat every ^[\(minutes) minute](inflect: true)",
                locale: locale
            )
        )
    }

    static func disconnectAccountTitle(_ email: String, locale: Locale = .autoupdatingCurrent) -> String {
        plainText(
            AttributedString(
                localized: "Disconnect \(email)?",
                locale: locale
            )
        )
    }

    static func connectedAccountLabel(
        email: String,
        displayName: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty {
            return trimmedEmail
        }
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDisplayName.isEmpty {
            return trimmedDisplayName
        }
        return plainText(AttributedString(localized: "Google Account", locale: locale))
    }

    static func calendarActivityScope(
        calendarName: String,
        accountLabel: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        plainText(
            AttributedString(
                localized: "\(calendarName) · \(accountLabel)",
                locale: locale
            )
        )
    }

    static func disconnectAccountMessage(
        hasOtherConnectedAccounts: Bool,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        if hasOtherConnectedAccounts {
            return plainText(
                AttributedString(
                    localized: "Calendars in this Connected Account will no longer be protected. Other Connected Accounts will stay protected. Google Calendar events and RSVPs won’t change.",
                    locale: locale
                )
            )
        }

        return plainText(
            AttributedString(
                localized: "Calendars in this Connected Account will no longer be protected. Google Calendar events and RSVPs won’t change.",
                locale: locale
            )
        )
    }

    static func connectionFailureAnnouncement(_ message: String) -> String {
        sentences([
            "Google Calendar couldn’t connect",
            message,
            "Try again"
        ])
    }

    static func disconnectionFailureAnnouncement(_ message: String) -> String {
        sentences(["Account couldn’t disconnect", message, "Try again"])
    }

    static func strongAlertRepeatConsequence(
        minutes: Int,
        canJoin: Bool = true,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let interval = minuteDuration(minutes, locale: locale)
        let value: AttributedString
        if canJoin {
            value = AttributedString(
                localized: "Closes this alert now. Protection stays active, and Strong Alert returns in \(interval) unless you Join, Stop reminders, or Pause All Protection.",
                locale: locale
            )
        } else {
            value = AttributedString(
                localized: "Closes this alert now. Protection stays active, and Strong Alert returns in \(interval) unless you Stop reminders or Pause All Protection.",
                locale: locale
            )
        }
        return plainText(value)
    }

    static func unverifiedReminderDetail(locale: Locale = .autoupdatingCurrent) -> String {
        plainText(
            AttributedString(
                localized: "Google Calendar couldn’t verify the latest details. This commitment may have changed; new reminders for the affected Connected Account wait until coverage returns.",
                locale: locale
            )
        )
    }

    static func stopRemindersConfirmationMessage(locale: Locale = .autoupdatingCurrent) -> String {
        plainText(
            AttributedString(
                localized: "No more Early Reminders or Strong Alerts will appear for this occurrence. Your Google Calendar RSVP won’t change. You can Restore Protection from the menu bar until the commitment ends.",
                locale: locale
            )
        )
    }

    static func pauseAllProtectionDetail(locale: Locale = .autoupdatingCurrent) -> String {
        plainText(
            AttributedString(
                localized: "Pauses active and upcoming reminders for every Monitored Calendar. An ongoing commitment may alert as overdue when protection resumes.",
                locale: locale
            )
        )
    }

    static func meetingLinkChoices(
        _ links: [URL],
        locale: Locale = .autoupdatingCurrent
    ) -> [MeetingLinkChoice] {
        let providerNames = links.map(meetingProviderName)
        let providerCounts = providerNames.reduce(into: [String: Int]()) { counts, provider in
            counts[provider, default: 0] += 1
        }
        var providerIndices: [String: Int] = [:]

        return zip(links, providerNames).map { link, provider in
            providerIndices[provider, default: 0] += 1
            let title: String
            if let count = providerCounts[provider], count > 1 {
                let index = providerIndices[provider, default: 1]
                title = plainText(
                    AttributedString(
                        localized: "Join with \(provider) (\(index) of \(count))",
                        locale: locale
                    )
                )
            } else {
                title = plainText(
                    AttributedString(
                        localized: "Join with \(provider)",
                        locale: locale
                    )
                )
            }
            return MeetingLinkChoice(url: link, title: title)
        }
    }

    static func sentence(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let significantEnding = trimmed.reversed().first { !closingCharacters.contains($0) }
        guard let significantEnding, !terminalPunctuation.contains(significantEnding) else {
            return trimmed
        }
        return trimmed + "."
    }

    static func sentences(_ values: [String]) -> String {
        values
            .map(sentence)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static let terminalPunctuation: Set<Character> = [
        ".", "!", "?", "…", "。", "！", "？", "؟", "۔"
    ]

    private static let closingCharacters: Set<Character> = [
        "\"", "'", "”", "’", ")", "]", "}", "»", "›", "』", "」", "】"
    ]

    private static func meetingProviderName(for url: URL) -> String {
        guard let host = url.host?.lowercased() else { return "Meeting Link" }
        if host == "meet.google.com" {
            return "Google Meet"
        }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            return "Zoom"
        }
        if host == "teams.microsoft.com" || host.hasSuffix(".teams.microsoft.com") {
            return "Microsoft Teams"
        }
        if host == "webex.com" || host.hasSuffix(".webex.com") {
            return "Webex"
        }
        return "Meeting Link"
    }

    private static func plainText(_ value: AttributedString) -> String {
        String(value.characters)
    }
}
