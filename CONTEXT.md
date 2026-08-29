# Commitment Protection

This context defines the canonical language for a personal macOS app that helps knowledge workers arrive on time to accepted or self-organized, timed Google Calendar commitments. The product escalates reminders only as much as necessary while preserving user control, bounded local data, and clear sharing behavior.

**Meeting Incoming** is the provisional public working name. Use the descriptor **“Full-screen calendar alerts for Mac.”** in product exploration. Internal naming, bundle identity, and public identity clearance remain pending, so neither the name nor descriptor may be represented as a cleared or shipped brand.

## Calendar and account language

**Saved Account**:
A Google account identity and its Monitored Calendar choices retained after authorization ends. It lets the user reconnect without rebuilding setup.
_Avoid_: Logged-in account, dormant account

**Connected Account**:
A Saved Account with usable Device-Bound Google Authorization. It normally survives app relaunch, Mac restart, and app update; loss of one Connected Account does not disable healthy accounts.
_Avoid_: Current-session account, logged-in account

**Reconnect Required**:
The state in which Google protection has no usable authorization after Disconnect or an exceptional credential, protected-data, or device event. Readable Saved Account choices remain, but an unreadable device-bound store must be rebuilt; ordinary relaunch is not a cause.
_Avoid_: Calendar Access Required, Stale Coverage, disconnected calendar, No Coverage

**Disconnect**:
An account action that ends Google access and deletes current authorization and protected event data. It preserves the Saved Account, Monitored Calendar choices, and same-day Protection Activity, then enters Reconnect Required.
_Avoid_: Remove Account, log out

**Remove Account**:
An account action that ends Google access and deletes all local configuration, protection state, and Protection Activity belonging to that account. No Saved Account remains.
_Avoid_: Disconnect, hide account

**Fresh Coverage**:
Calendar coverage whose account data was refreshed within the last fifteen minutes and is eligible to produce new reminders.
_Avoid_: Synced, up to date

**Stale Coverage**:
Calendar coverage whose account data is more than fifteen minutes old. It cannot create newly discovered reminders; previously known commitments may remain Unverified Reminders only within the retained protection window.
_Avoid_: Offline mode, disconnected calendar

**No Coverage**:
The state in which no calendars are selected for protection. The app clearly asks the user to select a calendar and does not imply that commitments are protected.
_Avoid_: Inactive, empty calendar

**Recognized Meeting Link**:
A supported video-meeting URL that can be offered through Join. A designated conference link is primary and other recognized links may be choices, but a link is optional and does not determine eligibility.
_Avoid_: Event URL, arbitrary link

**Meeting Description**:
Optional Google Calendar detail shown as secondary context for a Commitment. It never changes eligibility or becomes a Recognized Meeting Link.
_Avoid_: Join link, alert instruction

**Commitment**:
An accepted or self-organized, timed Google Calendar event from a Monitored Calendar that the app is responsible for helping the user attend on time. All-day, cancelled, declined, tentative, and unanswered invitation events are excluded; out-of-office events are excluded unless Out-of-Office Protection is enabled.
_Avoid_: Meeting, appointment, event (when referring to the product's responsibility)

**Accepted Event**:
A timed Google Calendar event whose RSVP status is Yes or Accepted.
_Avoid_: Confirmed meeting, active event

**Self-Organized Event**:
A timed Google Calendar event organized by the connected Google account. It is eligible without a separate self-attendee acceptance record.
_Avoid_: Auto-accepted event

**Monitored Calendar**:
A calendar the user explicitly selects for commitment protection within a Saved Account. Deselecting it immediately ends protection for its events; selecting it evaluates eligible commitments without newly adopting one already underway.
_Avoid_: Tracked calendar, active calendar

**Occurrence**:
One instance of a recurring commitment. If its scheduled time changes, the rescheduled instance receives a fresh protection decision.
_Avoid_: Recurring event (when referring to one specific instance)

**Merged Commitment**:
One real-world commitment represented by multiple eligible events across monitored accounts or calendars and protected through a single reminder flow. Entries qualify when they share a Recognized Meeting Link and matching start time.
_Avoid_: Duplicate event, duplicate reminder

**Commitment Conflict**:
Two or more eligible commitments whose active time windows overlap. The commitment needing attention now becomes the single primary commitment, while the others remain visible in a conflict list. Commitments with the same start time are equal choices until the user selects a primary; if none is selected, the Strong Alert presents the equal choices rather than guessing.
_Avoid_: Overlap, double booking

## Reminder language

**Early Reminder**:
A visual reminder shown before a commitment starts, optionally with Blocking Mode. It offers Snooze, Close for now, and Stop reminders; only Stop reminders ends protection for the Occurrence.
_Avoid_: Warning, alert (when referring specifically to the early reminder)

**Close for now**:
The passive Early Reminder action that closes only the current surface while keeping start-time protection active for the Occurrence.
_Avoid_: Dismiss, Dismiss for now, Got it

**Unverified Reminder**:
A reminder retained from the last fresh calendar data after that account becomes stale. It keeps the normal action path and makes its uncertainty visible, but exists only within the retained protection window.
_Avoid_: Cached reminder, stale reminder

**Strong Alert**:
The urgent start-time intervention that presents the next action across the user's available displays. It is not suppressed by macOS Focus modes or by Full-Screen Sharing, window sharing, or app sharing; an explicit Pause still applies. Closing its surface without an explicit action does not end protection; it returns on the Repeat Interval.
_Avoid_: Notification, popup, takeover (as the canonical product term)

**Overdue Commitment**:
A previously protected commitment whose scheduled start has passed but whose scheduled end has not. It remains eligible for repeating Strong Alerts until it is handled or reaches its end, including when protection resumes after the app was temporarily unavailable. A commitment first discovered after it was already underway is not adopted retroactively.
_Avoid_: Late meeting (while the commitment is still ongoing)

**Join**:
The primary action for a commitment with a Recognized Meeting Link. The user's click counts as joining for the reminder lifecycle.
_Avoid_: Attend, launch, open link

**Handled**:
An occurrence-local acknowledgment that ends protection without changing the Google Calendar RSVP. The decision lasts through the current occurrence even if the calendar refreshes.
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
The global delay between post-start Strong Alerts. It ranges from one to five minutes, defaults to one minute, and remains enabled until Join, Handled, Dismiss, Pause, or the commitment's scheduled end.
_Avoid_: Reminder frequency, retry interval

**Protection Activity**:
A private, human-readable timeline of user actions and protection transitions from the current local day. It survives a same-day relaunch and Disconnect, while Remove Account deletes that account's entries; it is bounded and is not permanent calendar history or analytics.
_Avoid_: Audit log, attendance history

## Privacy and control language

**Device-Bound Google Authorization**:
Persistent Google authorization that is usable only on the Mac where the user connected the account. It normally survives relaunch, restart, and update but cannot migrate or fall back to a less protected form.
_Avoid_: Session-only access, saved login, Keychain credential

**Protected Calendar Data**:
Private Google-derived account, calendar, event, decision, and Activity data retained only while it can support current or near-term protection. Data that leaves that boundary is deleted rather than retained as hidden history.
_Avoid_: Cache (when describing the privacy promise), permanent history

**Full-Screen Sharing**:
Sharing an entire display. Visual reminders remain visible during Full-Screen Sharing, window sharing, and app sharing; the app does not use sharing state to suppress or relocate a reminder. If sharing begins while a reminder is active, the reminder remains visible and protection continues.
_Avoid_: Screen sharing (when the distinction matters)

**Blocking Mode**:
An optional, default-off Early Reminder behavior that blocks interaction with other apps while the reminder is open. The app requests no system permission until the user explicitly chooses to enable it; without the required permissions, reminders remain available in visual-only mode.
_Avoid_: Lockdown, kiosk mode

**Out-of-Office Protection**:
An explicit, default-off preference that makes timed out-of-office events eligible for both Early Reminder and Strong Alert. Enabling it does not newly adopt an Occurrence already underway.
_Avoid_: OOO alerts, absence reminder

**Launch at Login**:
An explicit, default-off preference that lets the app resume protection after login when account authorization and coverage remain valid. The user can enable or disable it during onboarding or later in Settings.
_Avoid_: Always on, automatic startup (without user choice)

**Pause**:
A user-requested global suspension of protection until a specified time, offered as one hour, end of day, or a custom expiration. It immediately suppresses active alerts as well as future protection. When it ends, an ongoing previously protected commitment becomes overdue immediately; an already-ended commitment remains quiet.
_Avoid_: Quiet hours, disable (unless referring to a permanent setting)

**Active Protection**:
The availability state in which at least one Saved Account has usable authorization and fresh selected-calendar coverage, and the app is ready to protect commitments. Reconnect Required, No Coverage, Stale Coverage, and Pause remain explicit, truthful exceptions for the affected scope.
_Avoid_: Running, enabled

**Coverage Warning**:
A persistent, non-interruptive indication in menu-bar and setup surfaces that a Saved Account's calendar coverage is stale or unavailable. It never becomes a Strong Alert.
_Avoid_: Calendar error notification, alarm

**Transition Support**:
A later, advisory product capability that helps the user wrap up current work and switch to an upcoming commitment without inspecting or managing their work context. It does not block the current work.
_Avoid_: Meeting preparation, productivity coach
