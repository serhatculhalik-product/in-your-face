# Commitment Protection MVP

## Status

This is the active product specification. **Meeting Incoming** is the provisional public working name and **“Full-screen calendar alerts for Mac.”** is the working descriptor. Name, bundle identity, Google OAuth publishing, signing, notarization, and distribution clearance remain pending; this spec does not claim that a public release is complete.

## Problem

Ordinary calendar notifications are easy to miss during focused work. A personal macOS utility should help one user arrive on time to eligible Google Calendar commitments without becoming a planning calendar, changing calendar truth, retaining permanent history, or asking the user to reconnect after every relaunch.

## Product Boundary

- Native, menu-bar-first macOS utility for an individual user.
- Google Calendar only, with multiple accounts and explicitly selected Monitored Calendars.
- Accepted or self-organized timed commitments are eligible; a Recognized Meeting Link is optional.
- The least disruptive reminder that still protects punctuality.
- No team controls, attendance tracking, analytics dashboard, or permanent calendar archive.
- Public-v1 direction is Google-only, English-only, Apple silicon, and macOS 14 or later. This is a target rather than current release status.

## User Stories

### Accounts and coverage

1. As a user, I can connect more than one Google account and choose Monitored Calendars separately for each account.
2. As a user, I remain connected after app relaunch, Mac restart, and app update while my device-bound authorization remains valid.
3. As a user, I see Reconnect Required only after an exceptional credential, encrypted-data, or device event—not after an ordinary relaunch—and Reconnect is the one primary connection action in that state.
4. As a user with one failing account, I keep protection for my healthy accounts and see the affected account's state clearly.
5. As a user facing a transient network or Google service failure, I can Retry without losing valid authorization.
6. As an existing user moving from the superseded session-only model, I complete one explicit reconnect per Saved Account without an unexpected browser flow.
7. As a user, a Connected Account offers Disconnect as its one primary connection action, preserving its identity, Monitored Calendar choices, and same-day Protection Activity for later reconnection.
8. As a user, I can Remove Account when I want all local data for that account deleted.
9. As a user, a failed or ambiguous Google revocation does not leave me with a partially disconnected or partially removed account.
10. As a user with definitively no usable local grant, I can remove the remaining local account data and reach Google Account access settings for independent review.
11. As a user with no Monitored Calendar confirmed for protection, I see No Coverage rather than a false Active Protection state.
12. As a user with calendar data older than fifteen minutes, I see Stale Coverage and a persistent, non-interruptive Coverage Warning.
13. As a user, a stale account produces no newly discovered reminders, while a previously known commitment may remain an Unverified Reminder only within the retained snapshot window.

### Calendar truth and eligibility

14. As a user, accepted invitation events with a specific start and end time are eligible for protection.
15. As a user, timed events I organize are eligible even when Google does not provide a separate accepted self-attendee response.
16. As a user, linkless timed commitments remain protected and offer Stop reminders rather than Join.
17. As a user, all-day, cancelled, declined, tentative, unanswered, and unselected-calendar events remain quiet. Timed out-of-office events also remain quiet by default, and I can explicitly enable or disable their Early Reminder and Strong Alert protection in Settings.
18. As a user, initial Protection Confirmation evaluates eligible commitments already underway, while a calendar added to previously confirmed coverage does not retroactively adopt an Occurrence first discovered after its start.
19. As a user, accepting an invitation after its scheduled start does not retroactively create an alert.
20. As a user, a commitment protected before temporary app unavailability may return as an Overdue Commitment while it is still ongoing.
21. As a user, Google Calendar remains authoritative for acceptance, cancellation, rescheduling, timing, time zones, Meeting Description, and meeting links. When a Meeting Description exists, I see it as secondary plain text without it changing eligibility or becoming a Join action.
22. As a user, I see the commitment's scheduled instant in my current local time, with a time-zone label when relevant.
23. As a user, recurring events are evaluated by Occurrence, and a rescheduled Occurrence receives a fresh protection decision.
24. As a user, duplicate eligible representations merge only when all share a Recognized Meeting Link and the same scheduled start instant, and protection continues until the latest scheduled end among them.
25. As a user with overlapping Commitments after duplicate representations have merged, I see every distinct conflict. The Commitment needing attention now is primary, and equal same-start choices remain available unless I choose one.

### Reminder flow

26. As a user, I can enable or disable the global Early Reminder while leaving Strong Alert protection active.
27. As a user, I receive the Early Reminder across every available display and can set its lead time from five to thirty minutes, with ten minutes as the default. A newly discovered reminder appears only with at least one minute remaining, while an already-visible reminder stays available as start approaches.
28. As a user, Close for now closes only the current Early Reminder surface and leaves start-time protection active; the Early Reminder's native window Close invokes this action.
29. As a user, Stop reminders ends protection for the current Occurrence without changing my Google Calendar RSVP.
30. As a user, I can Snooze once before start for five, ten, fifteen, or thirty minutes. Snooze suppresses both reminder types until its duration or the commitment end, whichever comes first.
31. As a user, I receive a calm but urgent Strong Alert at start time across every available display.
32. As a user, macOS Focus and Full-Screen Sharing, window sharing, or app sharing do not hide or relocate visual reminders.
33. As a user, the native window close control acts as Close for now on an Early Reminder, while a Strong Alert exposes no native close control and ignores native close attempts. Got it explicitly closes only the current Strong Alert surface without ending protection.
34. As a user, Strong Alert repeats every one to five minutes, defaulting to one minute, until Join, Handled, Dismiss, Pause, or the scheduled end.
35. As a user, I can mark a Commitment Handled when I joined another way. With a Recognized Meeting Link, I can Join as the primary action; either action ends that Occurrence's reminder lifecycle without claiming to verify attendance.
36. As a user, I can Restore Protection for the current Occurrence after Dismiss or Handled until that Occurrence ends.
37. As a user, I can Pause all protection for one hour, until end of day, or until a custom expiration.
38. As a user, an ongoing previously protected commitment becomes overdue when Pause ends, while an already-ended commitment stays quiet.

### Permissions, launch, and control

39. As a first-time user, I see Start at Login on by default during readiness, can opt out before finishing, and can change it later in Settings. The staged choice does not change the macOS Login Item merely because I opened readiness; Finish Setup or Finish Later applies it.
40. As a user, enabling Launch at Login resumes protection after login when authorization and coverage remain valid; it does not conceal Reconnect Required.
41. As a user, Blocking Mode is optional and off by default.
42. As a user, I see why Accessibility and Input Monitoring are needed before I choose to enable Blocking Mode, then receive direct links to the relevant System Settings panes.
43. As a user who withholds either permission, I retain a visual-only Early Reminder and all ordinary protection behavior.
44. As a user, onboarding does not request Blocking Mode permissions before I express intent to enable that feature.
45. As a user, after connecting Google Calendar and choosing Monitored Calendars, I can protect additional Google accounts before finishing setup. From readiness I can enable or disable Early Reminder, choose its lead time, choose the Strong Alert Repeat Interval with one minute as the default, optionally choose Blocking Mode, and review the staged Start at Login choice.
46. As a user who chooses Set Up Later, I get the menu-bar experience and can return through Finish Setup without being forced through onboarding on every launch.

### Privacy and explanation

47. As a user, my Google authorization is device-bound, encrypted at rest, excluded from backup, and unavailable after migration to another Mac; on the new Mac I reconnect and select calendars again.
48. As a user, the app creates no Keychain items, invokes no SecItem API, and offers no plaintext or software-only credential fallback.
49. As a user, access tokens live only in memory and refresh credentials remain encrypted until an explicit account action or exceptional invalidation requires deletion.
50. As a user, all persisted Google-derived account, calendar, event, decision, Meeting Description, and Activity data is encrypted rather than duplicated into plaintext preferences, logs, temporary files, crash metadata, or analytics.
51. As a user, the app retains only ongoing protected Occurrences and eligible Occurrences starting in the next twenty-four hours from my Monitored Calendars.
52. As a user, ended, cancelled, declined, deselected, removed-account, out-of-office after opt-out, out-of-scope, and expired snapshot data is physically deleted rather than merely hidden.
53. As a user, Protection Activity explains actions and state changes from the current local day without becoming permanent history.
54. As a user, Protection Activity survives a same-day relaunch and Disconnect, while Remove Account deletes that account's entries and the local-day boundary deletes everything remaining.
55. As a user, Activity storage is bounded to the newest 1,000 entries or 1 MiB across the app, with the oldest entries removed first.
56. As a user, I receive truthful Active Protection, Reconnect Required, No Coverage, Stale Coverage, Pause, and per-account failure states.
57. As a keyboard or assistive-technology user, every alert action is reachable, VoiceOver-readable, distinguishable without color alone, and safe under reduced-motion settings.

## Implementation Decisions

### Authorization and accounts

- ADR-0010 supersedes the session-only model in ADR-0009.
- Each Google refresh credential is AES-GCM-encrypted in the user's Application Support directory. Encryption and wrapping material are bound to a non-exportable Secure Enclave key on the current Mac.
- Persisted authorization files use user-only permissions and are excluded from backups. Access tokens are short-lived and memory-only.
- The app has no Keychain entitlement, creates no Keychain item, makes no SecItem call, and has no Keychain migration, plaintext fallback, or software-only cryptographic fallback.
- Older plaintext refresh-token values are deleted rather than migrated. Keychain items created by older builds remain outside the app's access boundary and require manual user cleanup.
- A device without the required Secure Enclave capability cannot connect Google. Non-Google app surfaces remain usable and explain the unsupported device.
- A transient network or service failure retains the encrypted refresh credential and offers Retry. A definitive credential rejection or permanently unreadable protected representation deletes the unusable local credential and enters Reconnect Required. A permanently unreadable device-bound store deletes all affected Google-derived data and requires reconnecting and selecting calendars again.
- Disconnect and Remove Account request real Google revocation first whenever a usable local grant exists. A transient or ambiguous revocation failure makes no local mutation and offers Retry plus a route to Google Account access settings.
- Successful Disconnect deletes authorization and the protected event snapshot while preserving the Saved Account, Monitored Calendar choices, and same-day Protection Activity.
- Successful Remove Account also deletes the Saved Account, calendar choices, occurrence-local state, and account-scoped Activity. When there is definitively no usable local grant, local removal may proceed without a revocation call and the app provides a route to Google Account access settings.
- Google OAuth access is limited to calendar.calendarlist.readonly and calendar.events.readonly.

### Calendar data and retention

- ADR-0011 governs all persisted Google-derived data.
- The encrypted snapshot contains eligible events only from explicitly selected Monitored Calendars: ongoing Occurrences already under protection and eligible Occurrences starting within the next twenty-four hours.
- A retained event may include a Meeting Description only after markup, executable content, excess whitespace, control characters, and content beyond the 2,000-character display limit have been removed. The retained text stays inert and is never treated as a Recognized Meeting Link.
- Every snapshot records its refresh time and is physically discarded when more than twenty-four hours old, including during prolonged stale coverage.
- Occurrence-local decisions remain only while the Occurrence can affect protection. Deselecting a calendar removes its event and decision data; Remove Account removes all account-scoped data.
- A one-time migration may import only the minimum legacy account identifiers and Monitored Calendar choices, immediately rewrite them into encrypted storage, and delete the plaintext source. Legacy tokens, event snapshots, event titles, meeting links, and Activity are not migrated.
- Ordinary non-Google preferences, including Out-of-Office Protection, may remain in UserDefaults. Google-derived data may not.

### Calendar and reminder behavior

- Selecting or changing Monitored Calendars requires Protection Confirmation before they produce protection; deselection ends their protection immediately. Initial Protection Confirmation evaluates current eligible Commitments, including those already underway, while an Occurrence first discovered after its start through recovery, relaunch, reconnect, or coverage added after prior confirmation remains an Untracked Past Occurrence.
- Eligibility is accepted-or-owned and timed. Out-of-office is an event-type gate controlled by one default-off preference that applies to both Early Reminder and Strong Alert. A Recognized Meeting Link enables Join but is not an eligibility requirement.
- A Late Acceptance does not create a new Early Reminder or Strong Alert for the current Occurrence. A previously protected ongoing Commitment may resume as overdue after Pause or temporary unavailability, but an Untracked Past Occurrence remains quiet.
- Google Calendar is authoritative for calendar facts; Dismiss and Handled are reversible Occurrence-local app decisions that do not modify RSVP state.
- Meeting Description is normalized to bounded inert plain text at the event-model boundary, persisted only inside the encrypted event snapshot, and never copied into Protection Activity. A merged commitment uses its stable canonical representation's nonblank description, otherwise the first nonblank description in stable order; descriptions are never concatenated.
- Eligible representations form a Merged Commitment only when all share a Recognized Meeting Link and the same scheduled start instant. Merging precedes Commitment Conflict detection, and protection continues until the latest scheduled end among the representations.
- A designated Google conference link is primary. When none is designated, every recognized candidate is presented as a choice rather than guessed.
- Calendar cancellation, rescheduling, timing, and link changes update active protection. No new Strong Alert begins after the scheduled end.
- Enabling Out-of-Office Protection does not adopt an already-underway occurrence. Disabling it immediately clears its active protection state and removes those events from retained snapshots.
- A newly presented Early Reminder is suppressed when fewer than sixty seconds remain before start. An Early Reminder that is already visible remains visible inside that boundary, and exactly sixty seconds remains eligible.
- Strong Alert presents the commitment title, current timing state, relevant calendar or account, and next action; secondary details remain secondary. Every Strong Alert display omits an operable native window Close, and attempted native close requests leave the alert visible.
- I joined another way records Handled for the current Occurrence without changing its Google Calendar RSVP.
- Stop reminders is available for both linked and linkless commitments, requires confirmation, and is the only user-facing Strong Alert action that stops the current Occurrence without joining.
- Strong Alert remains visible in every supported display-sharing mode under ADR-0004.
- Alert presentation uses one internal lifecycle seam for window discovery or creation, activation, surface disappearance, display-topology changes, fallback recovery, and Blocking Mode availability. StrongAlertDisplayPlan remains the authoritative display-coverage rule for both reminder stages.
- Blocking Mode blocks interaction with other apps while the Early Reminder is open. It is permission-gated and degrades to visual-only behavior without disabling ordinary reminders.
- Start at Login is presented on by default during first-time readiness but remains a staged, reversible choice rather than an automatic side effect. Merely opening readiness does not change the macOS Login Item; Finish Setup or Finish Later applies the choice, and the user can opt out or change it later in Settings.
- The menu-bar experience provides a compact upcoming-commitment view plus truthful coverage, Pause, and account states rather than a full schedule.
- Onboarding has two setup steps—connect Google Calendar and choose Monitored Calendars—followed by readiness, with a route to protect additional Google accounts before finishing. Readiness lets the user enable or disable Early Reminder, choose its lead time, choose the Strong Alert Repeat Interval with one minute as the default, optionally choose Blocking Mode, and review the staged Start at Login choice. It requests no Blocking Mode permission until the user explicitly chooses to enable that feature.
- First-run completion is independent from account or coverage state. Later reconnect does not replay onboarding.

### Distribution direction

- The public-v1 target is Apple silicon on macOS 14 or later.
- Direct distribution is intended to use Developer ID signing, hardened runtime, notarization, and a DMG. App Sandbox is not planned because optional Blocking Mode depends on Accessibility and Input Monitoring.
- A separate production Google OAuth project must complete the publishing and verification work required for public users.
- No telemetry, analytics SDK, advertising, or sale of calendar data is in scope.
- Free and open source is the current direction. Any update mechanism must use signed releases, present release notes, and require user confirmation.
- These are release requirements, not evidence that release, provider verification, or identity clearance is complete.

## Testing Decisions

- Verify externally observable Commitment Protection behavior through a product-flow seam with controlled calendar state, time, app availability, coverage, permissions, display sharing, and user actions.
- Use controllable time for lead times, start boundaries, Repeat Intervals, scheduled ends, local-day expiry, snapshot expiry, time-zone display, Pause expiry, and recovery.
- Cover accepted invitation events, self-organized events, linkless events, every excluded response/type, default-off and opted-in out-of-office events, selected, unselected, pending-confirmation, and confirmed calendars, recurring Occurrences, reschedules, cancellations, changed links, duplicates, and same-start conflicts.
- Verify that initial Protection Confirmation can adopt an eligible ongoing Commitment, while Late Acceptance, an Occurrence introduced by a calendar added to previously confirmed coverage, and other Untracked Past Occurrences remain quiet; recovery can restore a previously protected Overdue Commitment.
- Verify Out-of-Office Protection preference persistence, opt-in behavior across both reminder stages, immediate clearing on disable, physical snapshot pruning, and non-retroactive adoption on enable.
- Verify Meeting Description decoding, markup and executable-content removal, blank normalization, length bounds, canonical/fallback merge precedence, encrypted relaunch persistence, and absence from Join extraction and Protection Activity.
- Verify first Early Reminder suppression below sixty seconds, presentation at exactly sixty seconds, and retention of an already-visible reminder below sixty seconds.
- Verify Early Reminder, Strong Alert, Unverified Reminder, Coverage Warning, Close for now, Stop reminders, Join, Dismiss, Handled, Restore Protection, Snooze, Pause, Early Reminder native closing, rejected Strong Alert native closing, and explicit Got it surface clearing.
- Verify authorization survives relaunch and simulated restart/update boundaries without a routine reconnect, while exceptional invalidation enters Reconnect Required only for the affected account.
- Verify transient refresh failures retain authorization, definitive rejection deletes it, and revocation failure makes no partial Disconnect or Remove Account mutation.
- Verify successful Disconnect and Remove Account have their distinct data-retention effects, including same-day Activity behavior.
- Verify encrypted stores contain only the permitted snapshot window and Activity bounds, and that physical pruning occurs on end, cancellation, decline, deselection, expiry, day change, and account removal.
- Verify the package and authorization path create no Keychain items, contain no Keychain entitlement, and make no SecItem calls.
- Verify onboarding has two setup steps followed by readiness, permits protecting additional Google accounts before finishing, and exposes the current Early Reminder enabled state and lead time, the Strong Alert Repeat Interval with one minute as the default, optional Blocking Mode, and staged Start at Login without making any of them completion prerequisites.
- Verify Blocking Mode explains permissions before requesting them, links to the correct System Settings panes, and preserves visual-only reminders when permission is missing.
- Verify Start at Login is presented on by default during first-time readiness, can be opted out, changes no macOS Login Item merely by opening readiness, applies on Finish Setup or Finish Later, remains changeable in Settings, and resumes protection without reconnect when authorization remains valid.
- Verify reminders remain visible across multiple displays, Full-Screen Sharing, window sharing, app sharing, sharing that begins during an alert, and macOS Focus.
- Verify presentation lifecycle behavior deterministically for window discovery or creation, activation, surface disappearance, display-topology changes, fallback recovery, and Blocking Mode availability while retaining StrongAlertDisplayPlan as the authoritative display-coverage rule.
- Verify each external alert action is keyboard reachable and VoiceOver-readable, has visible focus and non-color state cues, respects reduced motion, and remains legible at increased text sizes.

## Out of Scope

- Custom reminders without a Google Calendar event
- Apple Calendar, Microsoft Outlook, or other calendar providers
- Mobile, wearable, phone, or away-from-Mac fallback coverage
- Team policies, shared administration, or workplace controls
- Widgets, themes, alert marketplaces, or social sharing
- Meeting preparation automation or work-context inspection
- Automatic importance inference, quiet hours, or complex per-event rules
- Permanent event history, attendance analytics, telemetry, or a user-facing analytics dashboard
- A full planning calendar or task-management system
- Travel-time planning or location-based departure guidance
- Verifying that a user actually joined after clicking Join

## Further Notes

- The product principle is: the least disruptive intervention that still reliably gets the user to the commitment on time.
- ADR-0001 defines calendar-only scope, ADR-0003 calendar truth and occurrence-local decisions, ADR-0004 sharing visibility, ADR-0005 Late Acceptance, ADR-0006 passive missed-state exclusion, ADR-0007 Merged Commitment end behavior, ADR-0008 overdue recovery, ADR-0010 device-bound authorization, ADR-0011 encrypted retention, and ADR-0012 the explicit default-off Out-of-Office Protection exception to ADR-0001's original unconditional exclusion.
- ADR-0002 and ADR-0009 remain in the repository as superseded decision history.
- The primary success outcome is behavioral: the user is no longer late. The product does not depend on an analytics dashboard to communicate value.
- Transition Support is a later advisory capability that may help the user wrap up current work without inspecting, managing, or blocking that work.
- Final behavior changes made during implementation and UAT are recorded in CONTEXT.md, the accepted ADRs, and completed issue decisions.
