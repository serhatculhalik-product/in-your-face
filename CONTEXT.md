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
The state in which no Monitored Calendar is currently confirmed for protection. This includes no calendars selected and selected calendars awaiting Protection Confirmation; the app clearly asks the user to select and confirm calendars and does not imply that commitments are protected.
_Avoid_: Inactive, empty calendar

**Recognized Meeting Link**:
A supported video-meeting URL that can be offered through the Join action. When one designated conference link is available, it is the primary link; when no single primary can be established, multiple Recognized Meeting Links are presented as choices rather than guessed.
_Avoid_: Event URL, arbitrary link

**Commitment**:
A timed Google Calendar event with a scheduled start and end that the app is responsible for helping the user attend on time. Its scheduled instant is authoritative across time zones; the user sees that instant in their current local time, with a time-zone label when it differs. An Out-of-Office Event is not a Commitment.
_Avoid_: Meeting, appointment, event (when referring to the product's responsibility)

**Accepted Event**:
A timed Google Calendar event whose RSVP status is Yes or Accepted. An Accepted Event can become a Commitment only when it is otherwise eligible for protection; an event first observed as unaccepted and accepted after its start is a Late Acceptance and does not create new protection.
_Avoid_: Confirmed meeting, active event

**Monitored Calendar**:
A calendar the user explicitly selects for commitment protection within a Connected Account. Deselecting it immediately removes its commitments from protection. Selecting or changing a selection requires Protection Confirmation before the calendar can produce protection; after initial confirmation, current eligible commitments, including those already in their lead window or underway, are evaluated. If an already confirmed calendar or account first reveals an occurrence after its scheduled start during recovery, relaunch, reconnect, or newly added coverage, that occurrence is an Untracked Past Occurrence and remains quiet.
_Avoid_: Tracked calendar, active calendar

**Protection Confirmation**:
The user's explicit confirmation that the selected Monitored Calendars and global reminder settings should become Active Protection. Until confirmation, the selected calendars do not produce reminders.
_Avoid_: Enable, activate (when referring to reviewing protection settings)

**Out-of-Office Event**:
A Google Calendar out-of-office block that is excluded from commitment protection even when its RSVP is accepted.
_Avoid_: Commitment, protected event

**Late Acceptance**:
An Accepted Event first observed as unaccepted after its scheduled start. It remains quiet for that Occurrence and does not create a new Early Reminder or Strong Alert.
_Avoid_: Overdue acceptance, late commitment

**Occurrence**:
One instance of a recurring commitment. If its scheduled time changes, the rescheduled instance receives a fresh protection decision.
_Avoid_: Recurring event (when referring to one specific instance)

**Untracked Past Occurrence**:
An otherwise eligible Occurrence first discovered after its scheduled start by an already confirmed calendar or account during recovery, relaunch, reconnect, or newly added coverage. It remains quiet for that Occurrence and is not treated as an Overdue Commitment solely because it was discovered late.
_Avoid_: Missed commitment, late commitment

**Merged Commitment**:
One real-world commitment represented by multiple Accepted Events across Connected Accounts or Monitored Calendars and protected through a single reminder flow. Entries qualify only when all representations share a Recognized Meeting Link and the same scheduled start instant; its protection ends at the latest scheduled end among those representations.
_Avoid_: Duplicate event, duplicate reminder

**Commitment Conflict**:
Two or more distinct Commitments whose active time windows overlap after Merged Commitments have been formed. The commitment needing attention now becomes the single primary commitment, while the others remain visible in a conflict list. Commitments with the same scheduled start instant are equal choices until the user selects a primary; if none is selected, the Strong Alert presents the equal Join or Stop reminders paths rather than guessing.
_Avoid_: Overlap, double booking

## Reminder language

**Early Reminder**:
A visual reminder shown before a commitment starts. It can optionally stay in front of other app windows through Blocking Mode. Its global lead time ranges from five to thirty minutes and defaults to ten minutes; the reminder can also be turned off while Strong Alert protection remains active. The user can Snooze it for a selected duration, choose Got it to close only the early surface, or Stop reminders to end protection for the current occurrence. Got it does not change protection at the commitment start; Stop reminders does.
_Avoid_: Warning, alert (when referring specifically to the early reminder)

**Blocking Mode**:
An optional Early Reminder presentation that keeps the reminder in front of other app windows and blocks background interaction while it is open. The normal visual reminder remains available without Blocking Mode.
_Avoid_: Forced mode, system lock

**Unverified Reminder**:
A reminder retained from the last fresh calendar data after that account becomes stale or unavailable. It may fire for a known commitment, keeps the normal alert and action path, and must make its unverified status visible.
_Avoid_: Cached reminder, stale reminder

**Test Alert**:
A user-initiated Strong Alert shown during onboarding so the user can verify the protection experience before relying on it for a real commitment.
_Avoid_: Demo notification, sample reminder

**Strong Alert**:
The urgent start-time intervention that presents the next action across the user's available displays. It is not suppressed by macOS Focus modes or by Full-Screen Sharing, window sharing, or app sharing; an explicit Pause still applies. Closing its surface without an explicit action does not end protection; it returns on the Repeat Interval.
_Avoid_: Notification, popup, takeover (as the canonical product term)

**Overdue Commitment**:
A previously observed Commitment from a confirmed calendar whose scheduled start has passed but whose scheduled end has not. It remains eligible for repeating Strong Alerts until it is handled or reaches its end, including when protection resumes after Pause or the app or Mac was unavailable. An Untracked Past Occurrence does not become overdue solely through late discovery.
_Avoid_: Late meeting (while the commitment is still ongoing)

**Join**:
The primary action for an accepted event with a recognized meeting link. The user's click counts as joining for the reminder lifecycle.
_Avoid_: Attend, launch, open link

**Handled**:
An occurrence-local acknowledgment that ends protection without changing the Google Calendar RSVP. A Strong Alert can record this outcome through the user-facing I joined or Stop reminders action; the Handled decision remains available to existing domain and test-alert flows. The decision lasts through the current occurrence even if the calendar refreshes.
_Avoid_: Complete, done

**Dismiss**:
An explicit decision to stop protection for the current occurrence without changing its Google Calendar RSVP. The decision lasts through the current occurrence even if the calendar refreshes.
_Avoid_: Decline, cancel, skip (as a calendar operation)

**Restore Protection**:
An app-level action that reverses Dismiss or Handled for the current occurrence without changing its Google Calendar RSVP. It is available until the occurrence ends.
_Avoid_: Re-accept, undo RSVP

**Snooze**:
A user-selected five-, ten-, fifteen-, or thirty-minute quiet period applied from the Early Reminder. It suppresses both Early Reminder and Strong Alert, even when the quiet period crosses the commitment's start; it ends at the selected duration or the commitment's scheduled end, whichever comes first. It is available once per occurrence and unavailable after the commitment has started.
_Avoid_: Delay, postpone

**Repeat Interval**:
The global delay between post-start Strong Alerts. It ranges from one to five minutes, defaults to one minute, and remains enabled until Join, Handled, Dismiss, or the commitment's scheduled end.
_Avoid_: Reminder frequency, retry interval

**Protection Activity**:
A human-readable, current-local-day timeline of user actions and system transitions that explain the app's protection behavior. It is retained through a relaunch during the same local day, remains visible after an explicit account disconnect without reconnecting the account, and is discarded at the local-day boundary. When accounts change, each entry retains its account context so activity is never ambiguous; this is not permanent calendar history or analytics.
_Avoid_: Audit log, attendance history

## Privacy and control language

**Display Sharing**:
Full-Screen Sharing, window sharing, or app sharing. None of these modes suppresses, relocates, or resets visual reminders.
_Avoid_: Screen sharing (when the sharing mode matters)

**Full-Screen Sharing**:
Sharing an entire display. It is one form of Display Sharing; visual reminders remain visible, and protection continues if sharing begins while a reminder is active.
_Avoid_: Private display, shared-display suppression

**Pause**:
A user-requested global suspension of protection until a specified time, offered as one hour, end of day, or a custom expiration. It immediately suppresses active alerts as well as future protection. When it ends, an ongoing commitment becomes overdue immediately; an already-ended commitment remains quiet.
_Avoid_: Quiet hours, disable (unless referring to a permanent setting)

**Active Protection**:
The normal availability state after Protection Confirmation in which the app starts automatically at login and is ready to protect selected calendars. It may coexist with an account-specific Coverage Warning when another Connected Account is stale or unavailable. No Coverage, Stale Coverage, and Pause are explicit exceptions shown to the user.
_Avoid_: Running, enabled

**Coverage Warning**:
A persistent, non-interruptive indication in the menu bar and setup surfaces that a connected account is stale or unavailable. It never becomes a Strong Alert.
_Avoid_: Calendar error notification, alarm

**Transition Support**:
A later, advisory product capability that helps the user wrap up current work and switch to an upcoming commitment without inspecting or managing their work context. It does not block the current work.
_Avoid_: Meeting preparation, productivity coach
