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
The state in which no Monitored Calendar is currently confirmed for protection. This includes no calendars selected and selected calendars awaiting Protection Confirmation; the app clearly asks the user to select and confirm calendars and does not imply that commitments are protected.
_Avoid_: Inactive, empty calendar

**Recognized Meeting Link**:
A supported video-meeting URL that can be offered through Join. A designated conference link is primary; when no single primary can be established, multiple Recognized Meeting Links are presented as choices rather than guessed, but a link remains optional and never determines eligibility.
_Avoid_: Event URL, arbitrary link

**Meeting Description**:
Optional Google Calendar detail shown as secondary context for a Commitment. It never changes eligibility or becomes a Recognized Meeting Link.
_Avoid_: Join link, alert instruction

**Commitment**:
An accepted or self-organized Google Calendar event with a scheduled start and end from a confirmed Monitored Calendar that the app is responsible for helping the user attend on time. Its scheduled instant remains authoritative across time zones; all-day, cancelled, declined, tentative, and unanswered invitation events are excluded, while an Out-of-Office Event is eligible only when Out-of-Office Protection is enabled.
_Avoid_: Meeting, appointment, event (when referring to the product's responsibility)

**Accepted Event**:
A timed Google Calendar event whose RSVP status is Yes or Accepted. An Accepted Event can become a Commitment only when it is otherwise eligible for protection; an event first observed as unaccepted and accepted after its start is a Late Acceptance and does not create new protection.
_Avoid_: Confirmed meeting, active event

**Self-Organized Event**:
A timed Google Calendar event organized by the connected Google account. It is eligible without a separate self-attendee acceptance record.
_Avoid_: Auto-accepted event

**Monitored Calendar**:
A calendar the user explicitly selects for commitment protection within a Saved Account; it can produce protection only while that account is a Connected Account and the selection has Protection Confirmation. Deselecting it immediately ends protection for its events; initial Protection Confirmation evaluates current eligible commitments, including those already underway, whereas an Occurrence first discovered after its start through recovery, relaunch, reconnect, or coverage added after prior confirmation is an Untracked Past Occurrence and remains quiet.
_Avoid_: Tracked calendar, active calendar

**Protection Confirmation**:
The user's explicit confirmation that the selected Monitored Calendars and global reminder settings should become Active Protection. Until confirmation, the selected calendars do not produce reminders.
_Avoid_: Enable, activate (when referring to reviewing protection settings)

**Out-of-Office Event**:
A Google Calendar out-of-office block that is excluded from commitment protection by default even when accepted or self-organized. It can become a Commitment only when Out-of-Office Protection is enabled and every other eligibility condition is satisfied.
_Avoid_: Automatically protected event, absence reminder

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
One real-world commitment represented by multiple eligible calendar events across Connected Accounts or Monitored Calendars and protected through a single reminder flow. Representations qualify only when all share a Recognized Meeting Link and the same scheduled start instant; protection ends at the latest scheduled end among them.
_Avoid_: Duplicate event, duplicate reminder

**Commitment Conflict**:
Two or more distinct Commitments whose active time windows overlap after Merged Commitments have been formed. The Commitment needing attention now becomes primary while the others remain visible; same-start Commitments stay equal choices until the user selects one, and the Strong Alert does not guess when no choice exists.
_Avoid_: Overlap, double booking

## Reminder language

**Early Reminder**:
A visual reminder shown across the user's available displays before a commitment starts, optionally with Blocking Mode. It offers Snooze, Close for now, and Stop reminders; only Stop reminders ends protection for the Occurrence.
_Avoid_: Warning, alert (when referring specifically to the early reminder)

**Close for now**:
The Early Reminder-only passive action that closes the current surface while keeping start-time protection active for the Occurrence. The Early Reminder's native window Close performs this action.
_Avoid_: Dismiss, Dismiss for now, Got it

**Unverified Reminder**:
A reminder retained from the last fresh calendar data after that account becomes stale or unavailable. It may fire only for a known Commitment within the retained protection window, keeps the normal action path, and makes its uncertainty visible.
_Avoid_: Cached reminder, stale reminder

**Strong Alert**:
The urgent start-time intervention that presents the next action across the user's available displays. It is not suppressed by macOS Focus modes or by Full-Screen Sharing, window sharing, or app sharing; an explicit Pause still applies. Its native window close control is unavailable and native close attempts are ignored. The explicit Got it action closes only the current surface while protection stays active, and the Strong Alert returns on the Repeat Interval.
_Avoid_: Notification, popup, takeover (as the canonical product term)

**Overdue Commitment**:
A previously protected Commitment from a confirmed Monitored Calendar whose scheduled start has passed but whose scheduled end has not. It remains eligible for repeating Strong Alerts until handled or ended, including after Pause or temporary app or Mac unavailability; an Untracked Past Occurrence does not become overdue solely through late discovery.
_Avoid_: Late meeting (while the commitment is still ongoing)

**Join**:
The primary action for a commitment with a Recognized Meeting Link. The user's click counts as joining for the reminder lifecycle.
_Avoid_: Attend, launch, open link

**Handled**:
An occurrence-local acknowledgment that ends protection without changing the Google Calendar RSVP. The Strong Alert's I joined another way action records this outcome, and the decision survives calendar refreshes until the current Occurrence ends.
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
The global delay between post-start Strong Alerts. It ranges from one to five minutes, defaults to one minute, and can be chosen during readiness or later in Settings. Repetition remains enabled until Join, Handled, Dismiss, Pause, or the commitment's scheduled end.
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

**Display Sharing**:
Full-Screen Sharing, window sharing, or app sharing. None of these modes suppresses, relocates, or resets visual reminders.
_Avoid_: Screen sharing (when the sharing mode matters)

**Full-Screen Sharing**:
Sharing an entire display. It is one form of Display Sharing; visual reminders remain visible, and protection continues if sharing begins while a reminder is active.
_Avoid_: Private display, shared-display suppression

**Blocking Mode**:
An optional, default-off Early Reminder behavior that blocks interaction with other apps while the reminder is open. The app requests no system permission until the user explicitly chooses to enable it; without the required permissions, reminders remain available in visual-only mode.
_Avoid_: Lockdown, kiosk mode

**Out-of-Office Protection**:
An explicit, default-off preference that makes timed out-of-office events eligible for both Early Reminder and Strong Alert. Enabling it does not newly adopt an Occurrence already underway.
_Avoid_: OOO alerts, absence reminder

**Launch at Login**:
The preference that lets the app resume protection after login when account authorization and coverage remain valid. Start at Login is presented on by default during first-time readiness, but it is a staged choice: merely opening readiness does not change the macOS Login Item. Finish Setup or Finish Later applies the choice, the user can opt out before then, and the preference remains changeable in Settings.
_Avoid_: Always on, automatic startup (without user choice)

**Pause**:
A user-requested global suspension of protection until a specified time, offered as one hour, end of day, or a custom expiration. It immediately suppresses active alerts as well as future protection. When it ends, an ongoing previously protected commitment becomes overdue immediately; an already-ended commitment remains quiet.
_Avoid_: Quiet hours, disable (unless referring to a permanent setting)

**Active Protection**:
The availability state in which at least one Connected Account has usable authorization and Fresh Coverage for a confirmed Monitored Calendar, no global Pause applies, and the app is ready to protect Commitments. It may coexist with a Coverage Warning for another account; Reconnect Required, No Coverage, Stale Coverage, and Pause remain explicit, truthful exceptions for the affected scope.
_Avoid_: Running, enabled

**Coverage Warning**:
A persistent, non-interruptive indication in menu-bar and setup surfaces that a Connected Account's calendar coverage is stale or unavailable. It never becomes a Strong Alert.
_Avoid_: Calendar error notification, alarm

**Transition Support**:
A later, advisory product capability that helps the user wrap up current work and switch to an upcoming commitment without inspecting or managing their work context. It does not block the current work.
_Avoid_: Meeting preparation, productivity coach
