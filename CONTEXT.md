# On-Time Commitment Protection

This context defines the language for a personal macOS app that helps knowledge workers arrive on time to accepted, high-stakes Google Calendar commitments. The product escalates reminders only as much as necessary while preserving user control and clear sharing behavior.

## Calendar language

**Connected Account**:
A Google account the user has authorized for calendar access. Loss of access to one connected account does not disable protection for other connected accounts.
_Avoid_: Calendar account, logged-in account

**Fresh Coverage**:
Calendar coverage whose account data was refreshed within the last fifteen minutes and is eligible to produce new reminders.
_Avoid_: Synced, up to date

**Stale Coverage**:
Calendar coverage whose account data is more than fifteen minutes old. The app warns the user and does not issue new reminders from that account until freshness returns.
_Avoid_: Offline mode, disconnected calendar

**No Coverage**:
The state in which no calendars are selected for protection. The app clearly asks the user to select a calendar and does not imply that commitments are protected.
_Avoid_: Inactive, empty calendar

**Recognized Meeting Link**:
A supported video-meeting URL that can be offered through the Join action. When an event provides a designated conference link, it is the primary link; otherwise multiple recognized links are presented as choices.
_Avoid_: Event URL, arbitrary link

**Commitment**:
A timed Google Calendar event that the app is responsible for helping the user attend on time. Its scheduled instant is authoritative across time zones; the user sees that instant in their current local time, with a time-zone label when it differs.
_Avoid_: Meeting, appointment, event (when referring to the product's responsibility)

**Accepted Event**:
A timed Google Calendar event whose RSVP status is Yes or Accepted.
_Avoid_: Confirmed meeting, active event

**Monitored Calendar**:
A calendar the user explicitly selects for commitment protection within a connected Google account. Deselecting it immediately removes its commitments from protection; selecting it immediately evaluates current commitments, including those already in their lead window or underway.
_Avoid_: Tracked calendar, active calendar

**Occurrence**:
One instance of a recurring commitment. If its scheduled time changes, the rescheduled instance receives a fresh protection decision.
_Avoid_: Recurring event (when referring to one specific instance)

**Merged Commitment**:
One real-world commitment represented by multiple accepted events across monitored accounts or calendars and protected through a single reminder flow. Entries qualify when they share a recognized meeting link and matching start time.
_Avoid_: Duplicate event, duplicate reminder

**Commitment Conflict**:
Two or more accepted commitments whose active time windows overlap. The commitment needing attention now becomes the single primary commitment, while the others remain visible in a conflict list. Commitments with the same start time are equal choices until the user selects a primary; if none is selected, the Strong Alert presents the equal choices rather than guessing.
_Avoid_: Overlap, double booking

## Reminder language

**Early Reminder**:
A visual reminder shown before a commitment starts. It can optionally stay in front of other app windows through Blocking Mode. Its global lead time ranges from five to thirty minutes and defaults to ten minutes; the reminder can also be turned off while Strong Alert protection remains active. The user can Snooze it for five minutes, choose Got it to close only the early surface, or Stop reminders to end protection for the current occurrence. Got it does not change protection at the commitment start; Stop reminders does.
_Avoid_: Warning, alert (when referring specifically to the early reminder)

**Unverified Reminder**:
A reminder retained from the last fresh calendar data after that account becomes stale. It may fire for a known commitment, keeps the normal alert and action path, and must make its unverified status visible.
_Avoid_: Cached reminder, stale reminder

**Test Alert**:
A user-initiated Strong Alert shown during onboarding so the user can verify the protection experience before relying on it for a real commitment.
_Avoid_: Demo notification, sample reminder

**Strong Alert**:
The urgent start-time intervention that presents the next action across the user's available displays. It is not suppressed by macOS Focus modes or by Full-Screen Sharing, window sharing, or app sharing; an explicit Pause still applies. Closing its surface without an explicit action does not end protection; it returns on the Repeat Interval.
_Avoid_: Notification, popup, takeover (as the canonical product term)

**Overdue Commitment**:
A commitment whose scheduled start has passed but whose scheduled end has not. It remains eligible for repeating Strong Alerts until it is handled or reaches its end, including when protection resumes after the app was unavailable.
_Avoid_: Late meeting, missed event (while the commitment is still ongoing)

**Join**:
The primary action for an accepted event with a recognized meeting link. The user's click counts as joining for the reminder lifecycle.
_Avoid_: Attend, launch, open link

**Handled**:
An occurrence-local acknowledgment that ends protection without changing the Google Calendar RSVP. The current Strong Alert uses the single user-facing Stop reminders action for this outcome; the Handled decision remains available to existing domain and test-alert flows. The decision lasts through the current occurrence even if the calendar refreshes.
_Avoid_: Complete, done

**Dismiss**:
An explicit decision to stop protection for the current occurrence without changing its Google Calendar RSVP. The decision lasts through the current occurrence even if the calendar refreshes.
_Avoid_: Decline, cancel, skip (as a calendar operation)

**Restore Protection**:
An app-level action that reverses Dismiss or Handled for the current occurrence without changing its Google Calendar RSVP. It is available until the occurrence ends.
_Avoid_: Re-accept, undo RSVP

**Snooze**:
A short five-minute delay applied before a commitment starts, always capped at the commitment's start. It is available once per occurrence and unavailable after the commitment has started.
_Avoid_: Delay, postpone

**Repeat Interval**:
The global delay between post-start Strong Alerts. It ranges from one to five minutes, defaults to one minute, and remains enabled until Join, Handled, Dismiss, or the commitment's scheduled end.
_Avoid_: Reminder frequency, retry interval

**Missed Commitment**:
A commitment that reaches its scheduled end without Join, Handled, or Dismiss. Post-start repeats stop at that boundary, including during Full-Screen Sharing, and the result is shown passively rather than as a new Strong Alert. The status remains until acknowledged or the end of the user's local day, then is discarded.
_Avoid_: Failed reminder, unattended event

**Acknowledge**:
An explicit action that clears a passive Missed Commitment status without changing the Google Calendar event.
_Avoid_: Dismiss (which applies before the occurrence ends), archive

## Privacy and control language

**Full-Screen Sharing**:
Sharing an entire display. Visual reminders remain visible during Full-Screen Sharing, window sharing, and app sharing; the app does not use sharing state to suppress or relocate a reminder. If sharing begins while a reminder is active, the reminder remains visible and protection continues.
_Avoid_: Screen sharing (when the distinction matters)

**Pause**:
A user-requested global suspension of protection until a specified time, offered as one hour, end of day, or a custom expiration. It immediately suppresses active alerts as well as future protection. When it ends, an ongoing commitment becomes overdue immediately; an already-ended commitment remains a passive missed commitment.
_Avoid_: Quiet hours, disable (unless referring to a permanent setting)

**Active Protection**:
The normal availability state in which the app starts automatically at login and is ready to protect selected calendars. No Coverage, Stale Coverage, and Pause are explicit exceptions shown to the user.
_Avoid_: Running, enabled

**Coverage Warning**:
A persistent, non-interruptive indication in the menu bar and setup surfaces that a connected account is stale or unavailable. It never becomes a Strong Alert.
_Avoid_: Calendar error notification, alarm

**Transition Support**:
A later, advisory product capability that helps the user wrap up current work and switch to an upcoming commitment without inspecting or managing their work context. It does not block the current work.
_Avoid_: Meeting preparation, productivity coach
