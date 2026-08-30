import Foundation
import XCTest
@testable import InYourFace

final class InterfaceCopyTests: XCTestCase {
    func testCalendarCountsHandleZeroOneAndMany() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(InterfaceCopy.protectedCalendarCount(0, locale: locale), "0 calendars protected")
        XCTAssertEqual(InterfaceCopy.protectedCalendarCount(1, locale: locale), "1 calendar protected")
        XCTAssertEqual(InterfaceCopy.protectedCalendarCount(4, locale: locale), "4 calendars protected")
        XCTAssertEqual(
            InterfaceCopy.calendarSelectionSummary(selectedCount: 1, totalCount: 1, locale: locale),
            "1 of 1 calendar selected"
        )
        XCTAssertEqual(
            InterfaceCopy.calendarSelectionSummary(selectedCount: 2, totalCount: 4, locale: locale),
            "2 of 4 calendars selected"
        )
    }

    func testReconnectProgressDistinguishesSavedChoicesFromActiveProtection() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(
            InterfaceCopy.googleAccountConnectionProgress(
                connectedCount: 0,
                totalCount: 2,
                locale: locale
            ),
            "0 of 2 Google Accounts connected"
        )
        XCTAssertEqual(
            InterfaceCopy.googleAccountConnectionProgress(
                connectedCount: 1,
                totalCount: 1,
                locale: locale
            ),
            "1 of 1 Google Account connected"
        )
        XCTAssertEqual(
            InterfaceCopy.monitoredCalendarProtectionProgress(
                protectedCount: 0,
                savedCount: 2,
                locale: locale
            ),
            "0 of 2 Monitored Calendars currently protected"
        )
        XCTAssertEqual(
            InterfaceCopy.savedMonitoredCalendarCount(1, locale: locale),
            "1 Monitored Calendar saved"
        )
    }

    func testMinuteDurationsHandleZeroOneAndMany() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(InterfaceCopy.minuteDuration(0, locale: locale), "0 minutes")
        XCTAssertEqual(InterfaceCopy.minuteDuration(1, locale: locale), "1 minute")
        XCTAssertEqual(InterfaceCopy.minuteDuration(5, locale: locale), "5 minutes")
        XCTAssertEqual(InterfaceCopy.repeatEvery(1, locale: locale), "Repeat every 1 minute")
        XCTAssertEqual(InterfaceCopy.remindMeBefore(5, locale: locale), "Remind me 5 minutes before")
        XCTAssertEqual(InterfaceCopy.strongAlertRepeatTiming(5, locale: locale), "Strong Alert repeats every 5 minutes")
    }

    func testGermanLocaleKeepsExpandedDynamicCopyIntact() {
        let locale = Locale(identifier: "de_DE")

        XCTAssertEqual(
            InterfaceCopy.calendarSelectionSummary(
                selectedCount: 1_234,
                totalCount: 5_678,
                locale: locale
            ),
            "1.234 of 5.678 calendars selected"
        )
        XCTAssertEqual(
            InterfaceCopy.earlyReminderTiming(30, locale: locale),
            "Early Reminder 30 minutes before"
        )
    }

    func testSentenceFormattingPreservesEmojiCJKAndRTLText() {
        XCTAssertEqual(
            InterfaceCopy.sentences([
                "📅 カレンダーを確認してください。",
                "تعذّر الاتصال؟",
                "Erneut versuchen"
            ]),
            "📅 カレンダーを確認してください。 تعذّر الاتصال؟ Erneut versuchen."
        )
    }

    func testSentenceFormattingDoesNotDuplicateTerminalPunctuation() {
        XCTAssertEqual(InterfaceCopy.sentence("Already complete."), "Already complete.")
        XCTAssertEqual(InterfaceCopy.sentence("Try again"), "Try again.")
        XCTAssertEqual(InterfaceCopy.sentence("Are you sure?”"), "Are you sure?”")
        XCTAssertEqual(InterfaceCopy.sentence("مکمل ہو گیا۔"), "مکمل ہو گیا۔")
        XCTAssertEqual(InterfaceCopy.sentence("完了しました。』"), "完了しました。』")
        XCTAssertEqual(
            InterfaceCopy.connectionFailureAnnouncement("Google sign-in was cancelled."),
            "Google Calendar couldn’t connect. Google sign-in was cancelled. Try again."
        )
        XCTAssertEqual(
            InterfaceCopy.disconnectionFailureAnnouncement("The account is still connected."),
            "Account couldn’t disconnect. The account is still connected. Try again."
        )
        XCTAssertEqual(
            InterfaceCopy.removalFailureAnnouncement("The saved account is still available."),
            "Account couldn’t be removed. The saved account is still available. Try again."
        )
    }

    func testMeetingLinkChoicesUseProvidersWithoutExposingPrivatePaths() {
        let links = [
            URL(string: "https://zoom.us/j/123456?pwd=secret")!,
            URL(string: "https://zoom.us/j/987654?pwd=other")!,
            URL(string: "https://meet.google.com/abc-defg-hij")!
        ]

        let choices = InterfaceCopy.meetingLinkChoices(
            links,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            choices.map(\.title),
            ["Join with Zoom (1 of 2)", "Join with Zoom (2 of 2)", "Join with Google Meet"]
        )
        XCTAssertFalse(choices.map(\.title).joined().contains("123456"))
        XCTAssertFalse(choices.map(\.title).joined().contains("secret"))
    }

    func testAlertConsequencesNameScopeRecoveryAndRepeatTiming() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(
            InterfaceCopy.strongAlertRepeatConsequence(minutes: 1, locale: locale),
            "Closes this alert now. Protection stays active, and Strong Alert returns in 1 minute unless you Join, choose I joined another way, Stop reminders, or Pause All Protection."
        )
        XCTAssertEqual(
            InterfaceCopy.strongAlertRepeatConsequence(
                minutes: 1,
                canJoin: false,
                locale: locale
            ),
            "Closes this alert now. Protection stays active, and Strong Alert returns in 1 minute unless you choose I joined another way, Stop reminders, or Pause All Protection."
        )
        XCTAssertTrue(InterfaceCopy.pauseAllProtectionDetail(locale: locale).contains("every Monitored Calendar"))
        XCTAssertTrue(InterfaceCopy.stopRemindersConfirmationMessage(locale: locale).contains("Restore Protection"))
        XCTAssertTrue(InterfaceCopy.unverifiedReminderDetail(locale: locale).contains("may have changed"))
    }

    func testAccountLabelsSurviveBlankLegacyIdentityAndUnicode() {
        XCTAssertEqual(
            InterfaceCopy.connectedAccountLabel(email: "   ", displayName: "  "),
            "Google Account"
        )
        XCTAssertEqual(
            InterfaceCopy.connectedAccountLabel(email: "", displayName: "仕事 👋"),
            "仕事 👋"
        )
    }

    func testRemovingASavedAccountNamesTheLocalConsequence() {
        XCTAssertEqual(
            InterfaceCopy.removeAccountTitle("person@example.com"),
            "Remove person@example.com?"
        )
        XCTAssertEqual(
            InterfaceCopy.removeAccountMessage(hasOtherAccounts: true),
            "This saved account and its Monitored Calendar choices will be removed from Meeting Incoming. Other saved Google Accounts will remain in Meeting Incoming. Google Calendar events and RSVPs won’t change."
        )
        XCTAssertEqual(
            InterfaceCopy.removeAccountMessage(hasOtherAccounts: false),
            "This saved account and its Monitored Calendar choices will be removed from Meeting Incoming. Google Calendar events and RSVPs won’t change. You can add the account again later."
        )
    }
}
