# Calendar-only commitment protection for the MVP

**Status**: accepted

**Out-of-office exclusion superseded by**: ADR-0012

The MVP protects accepted or self-organized, timed Google Calendar events from user-selected, confirmed Monitored Calendars across one or more Connected Accounts. A Recognized Meeting Link is optional: linkless timed Commitments remain eligible and use Stop reminders instead of Join. All-day, cancelled, declined, tentative, and unanswered invitation events remain outside protection. Out-of-office events are excluded by default and may be included only through the explicit preference defined by ADR-0012.

The MVP does not include custom reminders, mobile coverage, team policies, or inferred importance. This keeps the product promise narrow and testable: helping an individual Mac user arrive on time to commitments already represented in their calendar.
