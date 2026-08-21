# Commitment Protection MVP

## Problem Statement

Remote and hybrid knowledge workers can spend long periods in deep work and fail to notice ordinary calendar notifications. The result is being late to accepted, high-stakes commitments or joining after the commitment has already started.

The user does not need another calendar view. They need a reliable, context-aware interruption that is strong enough to break through focus, while respecting calendar changes, explicit user intent, and the user's choice to keep reminders visible while sharing.

## Solution

Provide a personal macOS utility that protects accepted, timed Google Calendar events from user-selected calendars across multiple Connected Accounts.

The product can start with a visual Early Reminder, then presents a Strong Alert at the commitment’s start time. Optional Blocking Mode can keep the Early Reminder in front of other app windows. The Strong Alert offers the most direct next action—Join when a Recognized Meeting Link exists, or Handled otherwise—and repeats at a configurable Repeat Interval until the user takes an explicit action or the commitment reaches its scheduled end.

The experience is intentionally narrow: Google Calendar is the source of truth for calendar changes, the user chooses which calendars are protected, and the product never guesses which accepted event is important. Visual reminders remain visible during Full-Screen Sharing, window sharing, and app sharing so sharing cannot silently suppress the protection experience.

## User Stories

1. As a remote or hybrid knowledge worker, I want accepted Google Calendar commitments to be protected, so that I am less likely to arrive late after deep work.
2. As a user, I want to connect multiple Google Accounts, so that my work commitments can be protected even when they are split across accounts.
3. As a user, I want to choose the Monitored Calendars in each Connected Account, so that the app protects only the calendars I explicitly trust it to interrupt.
4. As a user, I want the app to show No Coverage when no calendars are selected, so that I never mistake an unconfigured app for Active Protection.
5. As a user, I want the app to start automatically at login, so that daily punctuality does not depend on remembering to launch it.
6. As a user, I want a Test Alert during onboarding, so that I can verify the protection experience before relying on it for a real commitment.
7. As a user, I want onboarding to confirm the monitored calendars and global reminder settings, so that I understand what the app will protect before it becomes active.
8. As a user, I want the app to protect only Accepted Events, so that invitations I have not accepted do not interrupt me.
9. As a user, I want all-day events excluded, so that an event without a specific start moment does not create a misleading punctuality alert.
10. As a user, I want recurring commitments evaluated one Occurrence at a time, so that one skipped or rescheduled occurrence does not silently change every future occurrence.
11. As a user, I want a rescheduled Occurrence to receive a fresh protection decision, so that a new commitment time is not suppressed by an old local choice.
12. As a user, I want the event’s scheduled instant to remain authoritative across time zones, so that travel does not make the app alert at the wrong moment.
13. As a user, I want times shown in my current local time with a time-zone label when needed, so that I understand exactly when the commitment occurs.
14. As a user, I want duplicate calendar representations of one commitment merged into one flow when they share a Recognized Meeting Link and matching start time, so that I do not receive duplicate alerts.
15. As a user, I want the calendar’s designated conference link to be preferred when an event has several links, so that Join opens the intended meeting.
16. As a user, I want several recognized links presented as choices when no primary link is designated, so that the app does not guess incorrectly.
17. As a user, I want the Early Reminder to appear before a commitment, so that I have time to stop my current work.
18. As a user, I want the Early Reminder to be optional and its lead time configurable from five to thirty minutes, with ten minutes as the default when enabled, so that the warning fits my transition needs without requiring complex schedules.
19. As a user, I want a Got it action to close the Early Reminder while leaving protection active, so that dismissing a passive notification does not make me late.
20. As a user, I want to Snooze the Early Reminder for five minutes, so that I can briefly finish a safe stopping point without adding another timing preference.
21. As a user, I want Snooze capped at the commitment’s start time, so that it cannot defer protection past the point when lateness begins.
22. As a user, I want Snooze available only once per Occurrence, so that repeated deferral does not undermine the safety net.
23. As a user, I want the Strong Alert to take over every available display at the commitment’s start time, so that ordinary notification blindness or screen sharing cannot make me late.
24. As a user, I want the Strong Alert to feel calm but urgent, so that it is effective without feeling hostile or theatrical.
25. As a user, I want the Strong Alert to show the commitment title, current timing state, relevant calendar or account, and the next action, so that I can act without searching.
26. As a user, I want Join to be prominent when a Recognized Meeting Link exists, so that I can enter the commitment immediately.
27. As a user, I want a Join click to count as joining for the reminder lifecycle, so that I am not repeatedly challenged to prove attendance.
28. As a user, I want Handled available when no Recognized Meeting Link exists, so that physical or otherwise linkless commitments can stop protection cleanly.
29. As a user, I want Handled available as a secondary action for any commitment, so that I can stop reminders when I joined from another device or app.
30. As a user, I want Dismiss to stop protection for only the current Occurrence without changing my Google Calendar RSVP, so that I can skip one commitment without corrupting calendar intent.
31. As a user, I want Restore Protection available after Dismiss or Handled until the Occurrence ends, so that I can reverse an accidental or changed decision.
32. As a user, I want the Strong Alert to repeat at a configurable Repeat Interval after the commitment starts, so that an alert I cannot act on immediately does not disappear forever.
33. As a user, I want the Repeat Interval configurable from one to five minutes, with one minute as the default, so that I can balance urgency and interruption.
34. As a user, I want post-start repetition to remain enabled until Join, Handled, Dismiss, or the commitment’s scheduled end, so that there is no silent opt-out at the moment punctuality matters most.
35. As a user, I want closing an Early Reminder or Strong Alert surface without an explicit action to leave protection active, so that an incidental window dismissal cannot be mistaken for a decision.
36. As a user, I want a commitment that is accepted after its start time to produce an immediate overdue Strong Alert while it is still ongoing, so that late acceptance does not hide an already-active commitment.
37. As a user, I want a commitment that becomes protected while it is within its lead window or already underway to be evaluated immediately, so that enabling a Monitored Calendar does not defer protection until tomorrow.
38. As a user, I want accepted commitments to override macOS Focus modes, so that system notification suppression does not defeat the product’s core promise.
39. As a user, I want Pause to suppress active alerts and future protection immediately, so that I have an emergency escape hatch.
40. As a user, I want Pause durations of one hour, end of day, or a custom expiration, so that every pause has a clear and temporary boundary.
41. As a user, I want protection to resume immediately when Pause ends if a commitment is still ongoing, so that Pause defers protection rather than silently erasing it.
42. As a user, I want visual reminders to remain visible during Full-Screen Sharing, so that sharing cannot silently suppress the protection experience.
43. As a user, I want visual reminders to remain visible during window or app sharing, so that every sharing mode has the same predictable alert behavior.
44. As a user, I want an active alert to remain visible if sharing starts, without clearing the underlying protection decision, so that sharing cannot turn an active commitment into a missed reminder.
45. As a user, I want the reminder to remain visible when every display is shared, so that the app keeps its punctuality promise in any sharing configuration.
50. As a user, I want the Strong Alert to cover every available display, so that I cannot miss it simply because I was working on another screen or sharing a display.
51. As a user, I want overlapping commitments represented as a Commitment Conflict, so that the app makes scheduling reality visible instead of silently choosing for me.
52. As a user, I want the commitment needing attention now to become the single primary conflict, so that the next punctuality risk is clear.
53. As a user, I want other overlapping commitments retained in a conflict list, so that I can understand the consequences of the primary choice.
54. As a user, I want same-start commitments presented as equal choices, so that the app does not infer importance from insufficient calendar data.
55. As a user, I want a same-start conflict to present all equal Join or Handled paths if I never choose a primary, so that no commitment is silently abandoned.
56. As a user, I want a stale or unavailable Connected Account to show a persistent Coverage Warning, so that I know protection is incomplete.
57. As a user, I want healthy Connected Accounts to keep working when one account fails, so that one authorization problem does not disable all protection.
58. As a user, I want account data older than fifteen minutes treated as Stale Coverage, so that the app does not present outdated calendar information as reliable.
59. As a user, I want stale coverage to suppress newly discovered reminders while retaining already-known reminders as Unverified Reminders, so that synchronization problems do not silently erase an imminent commitment.
60. As a user, I want an Unverified Reminder to retain the normal alert and action path while visibly explaining its uncertainty, so that I can still act without being misled about calendar freshness.
61. As a user, I want the app to update protection when Google Calendar cancels, reschedules, or changes a meeting link, so that stale calendar state does not continue to interrupt me.
62. As a user, I want explicit Dismiss and Handled decisions to survive routine calendar refreshes for the current Occurrence, so that a deliberate choice does not resurrect.
63. As a user, I want app recovery after an unavailable period to show an overdue Strong Alert for an ongoing commitment, so that restarting the app does not create a silent protection gap.
64. As a user, I want a commitment that has already ended when the Mac or app becomes active to appear only as a passive Missed Commitment, so that recovery does not create a useless new interruption.
65. As a user, I want Missed Commitment status to remain until I explicitly Acknowledge it or the end of my local day, so that I have closure without permanent event history.
66. As a user, I want Acknowledge to clear missed status without changing Google Calendar, so that reflection on a miss does not alter calendar intent.
67. As a user, I want locked or sleeping Macs to show an overdue alert after becoming active when the commitment is still ongoing, so that sleep does not permanently erase protection.
68. As a user, I want no new strong interruption after a commitment has reached its scheduled end, so that the app respects its lifecycle boundary.
69. As a user, I want a compact upcoming-commitment view in the menu bar, so that I can understand what the app is protecting without opening a full schedule product.
70. As a user, I want coverage, Pause, stale-account, and No Coverage states visible in the menu-bar experience, so that the app’s protection status is always understandable.
71. As a user, I want event titles and times visible in normal Strong Alerts while secondary details remain secondary, so that the alert is useful without exposing unnecessary information.
72. As a user, I want the app to retain only the data needed for upcoming protection and settings, so that the product does not create a permanent history of my calendar behavior.
73. As a user, I want keyboard access, VoiceOver support, reduced-motion behavior, and strong contrast in the alert flow, so that a high-pressure interruption remains usable with different accessibility needs.
74. As a user, I want the product to remain a personal utility rather than a team policy system, so that setup and privacy remain appropriate for individual users.
75. As a user, I want the app’s value judged by whether I am no longer late, rather than by an analytics dashboard, so that the product stays focused on behavior change.

## Implementation Decisions

- The MVP is a personal macOS product for remote and hybrid knowledge workers.
- The only calendar source in scope is Google Calendar, with multiple Connected Accounts supported.
- Users explicitly select Monitored Calendars. The product does not infer importance, monitor unselected calendars, or treat an Accepted Event outside selected calendars as protected.
- Only Accepted Events with a specific start time are eligible. All-day events are excluded.
- Google Calendar is authoritative for acceptance, cancellation, rescheduling, timing, time zones, and meeting links.
- A commitment’s scheduled instant is authoritative across time zones; presentation uses the user’s current local time and adds a time-zone label when relevant.
- Recurring events are handled by Occurrence. A rescheduled Occurrence receives a fresh protection decision.
- Duplicate representations merge only when they share a Recognized Meeting Link and matching start time.
- The Early Reminder is optional, global, configurable from five to thirty minutes when enabled, and defaults to ten minutes. Optional Blocking Mode can keep it in front of other app windows.
- The Early Reminder exposes three user actions: Snooze for five minutes, Got it to close only the early surface, and Stop reminders to end protection for the current occurrence. Handled and Dismiss remain distinct domain decisions for the Strong Alert; the Early Reminder does not expose both variants.
- The Strong Alert is the start-time intervention. It takes over every available display, is calm but urgent, overrides macOS Focus modes, and exposes the next action.
- The global Repeat Interval ranges from one to five minutes and defaults to one minute. Repetition remains enabled after start until Join, Handled, Dismiss, or scheduled end.
- Join is prominent when a Recognized Meeting Link exists. A Join click ends protection for the reminder lifecycle; the product does not need to verify attendance.
- Handled ends protection without changing Google Calendar. It is primary for linkless commitments and available as a secondary action for commitments handled elsewhere.
- Dismiss and Handled are occurrence-local decisions that persist through calendar refreshes and can be reversed by Restore Protection. Rescheduling resets them.
- Snooze is available once per Occurrence before start, offers a five-minute choice, and is capped at the start time.
- Clearing or closing an alert surface without an explicit action does not change protection.
- Pause is a global, temporary escape hatch with one-hour, end-of-day, and custom-expiration choices. It immediately suppresses active and future protection; protection resumes according to the current commitment state when it expires.
- Full-Screen Sharing, window sharing, and app sharing do not suppress or relocate visual reminders. The same reminder behavior applies regardless of sharing mode or how many displays are shared.
- Commitment Conflicts have one primary commitment at a time. Same-start commitments remain equal choices until the user chooses, and all equal choices remain available at alert time if no choice was made.
- Connected Account freshness is evaluated at a fifteen-minute boundary. Stale accounts show persistent, non-interruptive Coverage Warnings and do not create new reminders.
- Already-known reminders may fire as Unverified Reminders after coverage becomes stale, preserving the normal action path with visible uncertainty.
- Account failures are isolated: healthy accounts remain protected while the affected account is visibly uncovered.
- The app starts automatically at login and supports recovery after sleep, lock, quit, or other unavailable periods. Ongoing commitments become Overdue Commitments on recovery; ended commitments become passive Missed Commitments.
- Missed status lasts until Acknowledge or the end of the user’s local day and is not retained as event history.
- Onboarding includes account selection, Monitored Calendar selection, global timing confirmation, and a Test Alert.
- The product uses a menu-bar-first experience with a compact upcoming-commitment view rather than a full planning calendar.
- Accessibility is a baseline product requirement for the commitment protection flow.

## Testing Decisions

- Tests should verify externally observable Commitment Protection behavior rather than internal modules, state storage, timing mechanisms, or rendering implementation.
- The single highest-level seam is the user-visible Commitment Protection flow. It should accept controlled calendar state, time, app-availability, display-sharing, coverage, and user-action conditions and expose reminders, actions, coverage states, and missed status.
- The flow should be tested with controllable time so lead times, start boundaries, Repeat Intervals, scheduled ends, local-day expiry, time-zone display, Pause expiry, and recovery can be verified deterministically.
- Calendar fixtures should cover multiple Connected Accounts, selected and unselected Monitored Calendars, Accepted Events, declined or unaccepted events, all-day events, recurring Occurrences, reschedules, cancellations, changed links, duplicate representations, and same-start conflicts.
- User-visible reminder tests should cover Early Reminder, Strong Alert, Unverified Reminder, Missed Commitment, and Coverage Warning states, including their permitted and forbidden transitions.
- Action tests should verify Join, Handled, Dismiss, Restore Protection, Snooze, Acknowledge, Pause, and incidental surface clearing independently from the calendar source.
- Display tests should verify that reminders remain visible across multiple displays, Full-Screen Sharing, window sharing, app sharing, sharing beginning during an active alert, all displays being shared, and Focus-mode override behavior.
- Lifecycle tests should cover login activation, account failure, stale-to-fresh recovery, lock/sleep recovery, app recovery, late acceptance, coverage activation near a commitment, and commitment end boundaries.
- Conflict tests should verify primary selection, conflict lists, same-start equality, no-choice behavior, and transitions when one commitment is joined or handled.
- Accessibility acceptance should verify that every external alert action is keyboard reachable, VoiceOver-readable, motion-safe, and sufficiently contrasted.
- The repository currently contains no implementation or prior test suite, so there is no existing test seam or prior art to preserve. The first tests should establish this single product-flow seam rather than creating module-specific test contracts prematurely.

## Out of Scope

- Custom reminders without a Google Calendar event
- Apple Calendar, Microsoft Outlook, or other calendar providers
- Mobile, wearable, phone, or away-from-Mac fallback coverage
- Team policies, shared administration, or workplace controls
- Widgets, themes, alert marketplaces, or social sharing
- Meeting preparation automation or context inspection
- Automatic importance inference, quiet hours, or complex per-event rules
- Permanent event history, attendance analytics, or a user-facing analytics dashboard
- A full planning calendar or task-management system
- Travel-time planning or location-based departure guidance
- Verifying that a user actually joined after clicking Join
- Internal architecture, storage choices, frameworks, APIs, or implementation file structure

## Further Notes

- The product principle is: the least disruptive intervention that still reliably gets the user to the commitment on time.
- The MVP boundary and sharing behavior are captured in the ADRs for calendar-only scope, visible alerts during screen sharing, and calendar truth with occurrence-local decisions.
- The primary success outcome is behavioral: the user is no longer late. The product should not depend on a metrics dashboard to communicate value.
- Transition Support is a later, advisory capability that helps the user wrap up current work without inspecting or managing work context.
- This spec is intended to be published as a GitHub issue with the `ready-for-agent` label once the repository has a Git remote or an explicit GitHub repository is supplied.
