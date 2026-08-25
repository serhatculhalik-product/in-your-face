import CommitmentProtection
import Foundation
import XCTest

final class CalendarEventOccurrenceIDTests: XCTestCase {
    func testProviderEventIDsRemainDistinctAcrossAccountsAndCalendars() {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let first = event(
            id: "shared-provider-id",
            startDate: startDate,
            calendarID: "calendar-a",
            accountID: "account-a"
        )
        let second = event(
            id: "shared-provider-id",
            startDate: startDate,
            calendarID: "calendar-b",
            accountID: "account-b"
        )

        XCTAssertNotEqual(first.occurrenceID, second.occurrenceID)
        XCTAssertEqual(Set([first.occurrenceID, second.occurrenceID]).count, 2)
    }

    private func event(
        id: String,
        startDate: Date,
        calendarID: String,
        accountID: String
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: "Commitment",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3_600),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendarID,
            accountID: accountID
        )
    }
}
