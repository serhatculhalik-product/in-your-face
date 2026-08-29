# Product

<!-- impeccable:product-schema 1 -->

## Platform

Native macOS. The public-v1 target is Apple silicon on macOS 14 or later.

## Product Identity

**Meeting Incoming** is the provisional public working name. The working descriptor is **“Full-screen calendar alerts for Mac.”**

Public-name, bundle-identity, OAuth-consent-screen, and distribution clearance are still pending. The repository's existing internal names may remain until that work is complete; neither the working name nor descriptor is a claim that a public release has shipped.

## Users

The product is a personal utility for remote and hybrid knowledge workers who can miss ordinary calendar notifications during deep work. Its job is to help one Mac user arrive on time to accepted or self-organized, timed Google Calendar commitments across one or more accounts.

It is not a team policy, workplace administration, or shared-control product.

## Product Purpose

The product provides an interruption strong enough to break through focus while escalating only as much as necessary and preserving explicit user control. Success is behavioral: the user is no longer late. The product does not need an analytics dashboard to prove or communicate that value.

It is not another calendar view, planning calendar, task manager, attendance tracker, or permanent calendar archive.

## Positioning

The product protects eligible timed commitments from Monitored Calendars. It stays quiet by default, can begin with an optional Early Reminder, and escalates to a repeating start-time Strong Alert across every available display.

Google Calendar remains authoritative for calendar facts. Explicit protection decisions remain local to one Occurrence and do not alter the Google Calendar RSVP.

## Operating Context

The product is a native, menu-bar-first macOS utility with a compact upcoming-commitment and protection-status experience rather than a full schedule. A finite first-run assistant has two setup steps—connect Google Calendar and choose Monitored Calendars—followed by a readiness screen. Readiness lets the user enable or disable Early Reminder, choose its lead time, optionally choose Blocking Mode, and choose Launch at Login. After completion the app opens menu-bar-only; the same preferences and other ongoing configuration—including the default-off Out-of-Office Protection choice—live in native Settings panes for Accounts, Calendars, Reminders, and Protection Activity, while Pause remains an immediate menu-bar action.

A Connected Account uses Device-Bound Google Authorization, so valid authorization normally survives app relaunch, Mac restart, and app update. Launch at Login is an explicit, default-off preference available during onboarding and in Settings. Existing users make one explicit, user-initiated reconnect when migrating from the superseded session-only model; the app never opens a surprise browser flow.

The app recovers protection after sleep, lock, or temporary unavailability. It operates across multiple displays and Spaces, under macOS Focus modes, and during Full-Screen Sharing, window sharing, and app sharing.

Use the canonical product vocabulary in CONTEXT.md, including Saved Account, Connected Account, Reconnect Required, Disconnect, Remove Account, Commitment, Meeting Description, Accepted Event, Self-Organized Event, Monitored Calendar, Occurrence, Merged Commitment, Commitment Conflict, Early Reminder, Strong Alert, Unverified Reminder, Overdue Commitment, Join, Dismiss, Handled, Restore Protection, Snooze, Repeat Interval, Protection Activity, Blocking Mode, Out-of-Office Protection, Launch at Login, Pause, Active Protection, and Coverage Warning.

## Account and Privacy Model

- Google Calendar is the only calendar source. Multiple Connected Accounts are supported and failures are isolated per account.
- Authorization persists only for the current device. Refresh credentials are encrypted in Application Support with protection bound to the Mac's Secure Enclave; access tokens remain memory-only.
- The app creates no Keychain items, makes no SecItem calls, has no Keychain entitlement or migration, and offers no plaintext or software-only fallback. A Mac without the required Secure Enclave capability cannot connect Google, while non-Google surfaces remain usable.
- Ordinary relaunch is not a Reconnect Required condition. Definitive credential rejection, encrypted-data corruption, Secure Enclave key loss or reset, and moving the data to another Mac are reconnect conditions. A permanently unreadable store is deleted and requires account and calendar setup to be rebuilt; transient network or Google service failures retain valid authorization and offer Retry.
- Account rows expose one primary connection action at a time: Disconnect for a Connected Account or Reconnect for Reconnect Required. Remove Account remains a distinct destructive action.
- Disconnect revokes Google access and deletes the local authorization and protected event snapshot while preserving the Saved Account, Monitored Calendar choices, and same-day Protection Activity.
- Remove Account revokes Google access and deletes all local data for that account, including its Saved Account, choices, occurrence-local decisions, snapshots, and Protection Activity.
- A transient or ambiguous revocation failure makes no partial local change. If there is definitively no usable local grant because Google rejected it or its protected representation is permanently unreadable, the remaining local account data may be removed and the app provides a route to Google Account access settings.
- Persisted Google-derived data is encrypted and excluded from backups. It is not duplicated in plaintext preferences, logs, temporary files, crash metadata, or analytics.
- The protected event snapshot contains only ongoing protected Occurrences and eligible Occurrences beginning in the next twenty-four hours. It may retain a bounded plain-text Meeting Description for those Occurrences. Ended, cancelled, declined, deselected, removed-account, out-of-office after opt-out, out-of-scope, and more-than-twenty-four-hour-old data is physically deleted.
- Protection Activity is encrypted, limited to the current local day, and bounded across the app to the newest 1,000 entries or 1 MiB, whichever limit is reached first. Disconnect preserves it for that day; Remove Account deletes that account's entries immediately.

## Capabilities and Constraints

- Eligible commitments are accepted or self-organized timed events from explicitly selected Monitored Calendars. A Recognized Meeting Link is optional. All-day, cancelled, declined, tentative, unanswered, and unselected-calendar events are excluded. Timed out-of-office events are excluded by default and become eligible for both reminder stages only when the user explicitly enables Out-of-Office Protection.
- A commitment's scheduled instant remains authoritative across time zones. Times are presented in the user's current local time, with a time-zone label when relevant. Recurring events are evaluated one Occurrence at a time.
- Google Calendar is authoritative for acceptance, cancellation, rescheduling, timing, time zones, Meeting Description, and meeting links. Meeting Description is secondary inert text: it does not change eligibility, create Join actions, or get copied into Protection Activity. Dismiss and Handled persist only for the current Occurrence without changing the RSVP; rescheduling creates a fresh protection decision.
- Accepting an invitation after its scheduled start does not retroactively produce an alert, and selecting a calendar does not adopt a commitment already underway. Recovery may still surface an Overdue Commitment that was protected before the app became unavailable.
- Duplicate calendar representations merge only when they share a Recognized Meeting Link and matching start time. A designated conference link is primary; otherwise recognized links are presented as choices.
- Commitment Conflicts keep every overlapping commitment visible. The commitment needing attention now is primary; same-start commitments remain equal choices unless the user chooses a primary.
- Early Reminder is optional, global, and configurable from five to thirty minutes, with ten minutes as the default. A newly presented Early Reminder requires at least one minute before start, while an already-visible Early Reminder remains available as start approaches. Close for now closes only the current early surface; Stop reminders ends protection for the Occurrence without changing Google Calendar.
- Snooze is available once per Occurrence before start, with five-, ten-, fifteen-, and thirty-minute choices. It suppresses both Early Reminder and Strong Alert until the selected duration expires or the commitment ends.
- Blocking Mode is optional and default-off. Merely reaching readiness never triggers a permission prompt. After the user explicitly chooses to enable Blocking Mode, the app explains why Accessibility and Input Monitoring are needed and offers direct System Settings links. If either permission is missing, the Early Reminder remains available in visual-only mode and ordinary protection continues.
- Strong Alert appears at start time across every available display, remains visible during Full-Screen Sharing, window sharing, and app sharing, and is not suppressed by macOS Focus. It is calm but urgent.
- Strong Alert repeats globally every one to five minutes, defaulting to one minute, until Join, Handled, Dismiss, Pause, or the scheduled end. Closing its surface without an explicit protection decision does not end protection.
- Join is primary when a Recognized Meeting Link exists. Clicking Join ends the reminder lifecycle; the product does not verify actual attendance. **I joined another way** records Handled and ends only that Occurrence's reminder lifecycle. Linkless commitments remain protected and offer Stop reminders.
- Pause is a global, temporary suspension for one hour, until the end of the local day, or until a custom expiration. It immediately suppresses active and future protection; a previously protected ongoing commitment may become overdue when Pause expires.
- Account data older than fifteen minutes becomes Stale Coverage. The app shows a persistent, non-interruptive Coverage Warning and does not create newly discovered reminders for that account. Already-known commitments may continue as visibly uncertain Unverified Reminders only while the retained snapshot is still valid.
- First-run consists of two setup steps followed by readiness. Readiness choices do not make Early Reminder, Blocking Mode, or system permissions prerequisites for completion. Completion is presentation state, independent of calendar configuration. Later account loss, reconnect, or disconnection does not replay onboarding. Choosing Set Up Later keeps the app menu-bar-only and leaves Finish Setup available there.
- Accessibility is a baseline requirement: alert actions must be keyboard reachable and VoiceOver-readable, use strong contrast, and respect reduced-motion settings.
- UX and visual work must not silently change product scope or behavior.
- Transition Support is a later advisory capability only. It may help the user wrap up current work but must not inspect, manage, or block that work.

## Public Release Direction

The following is a target, not a statement that distribution or provider review is complete:

- Google-only and English-only for public v1.
- Minimum Apple silicon and macOS 14 because Device-Bound Google Authorization has no software fallback.
- Direct distribution as a Developer ID-signed, hardened-runtime, notarized DMG. App Sandbox is not planned because optional Blocking Mode depends on system permissions outside that boundary.
- A separate production Google OAuth project using only calendar.calendarlist.readonly and calendar.events.readonly, with the consent-screen publishing and verification work required for public users.
- No telemetry, analytics SDK, ads, or sale of calendar data.
- A free, open-source release is the current direction. Any updater must use signed releases, show release notes, and require user confirmation before installation.

## Brand Commitments

The voice is direct, calm, and clear under pressure: urgent enough to prompt action without becoming hostile or theatrical. The product stays quiet until a commitment needs the user.

No public name, logo, icon, imagery, custom typeface, domain, bundle identifier, or other binding brand asset has completed clearance.

## Evidence on Hand

- CONTEXT.md defines the canonical domain language and current product model.
- docs/specs/commitment-protection-mvp.md records the confirmed MVP scope and acceptance behavior.
- docs/adr/0001-calendar-only-mvp.md fixes the narrow Google Calendar-only MVP boundary.
- docs/adr/0003-calendar-truth-with-occurrence-local-decisions.md fixes the boundary between calendar truth and local protection decisions.
- docs/adr/0004-alerts-remain-visible-during-screen-sharing.md is the accepted sharing policy and supersedes ADR-0002.
- docs/adr/0010-persistent-device-bound-google-authorization.md supersedes ADR-0009 and fixes the persistent, Keychain-free authorization boundary.
- docs/adr/0011-encrypted-google-data-and-bounded-retention.md fixes the storage and retention boundary for Google-derived data.
- docs/adr/0012-optional-out-of-office-protection.md supersedes only ADR-0001's unconditional out-of-office exclusion and keeps that broader calendar-only boundary intact.
- Sources and tests document the current implementation. Where implementation still reflects a superseded decision, the accepted ADRs and current spec define the intended behavior.

## Product Principles

- Prefer the least disruptive intervention that still reliably gets the user to the commitment on time.
- Never imply protection when authorization, calendar selection, freshness, or Pause state makes it unavailable.
- Prefer explicit choices over inferred importance.
- Keep calendar truth in Google Calendar and occurrence-local protection decisions in the app.
- Preserve the punctuality promise during every supported sharing mode.
- Treat public identity and distribution readiness as pending until their separate clearance work is complete.

## Accessibility

The product must remain operable by keyboard, understandable with VoiceOver, legible at increased text sizes, distinguishable without color alone, and safe under reduced-motion preferences. High-pressure alert states require concise labels, visible focus, clear action hierarchy, and non-color status cues.

## Exclusions

Custom reminders, Apple Calendar, Outlook and other providers, mobile or wearable fallback, away-from-Mac coverage, team controls, widgets, themes, alert marketplaces, social sharing, automatic importance inference, quiet hours, complex per-event rules, permanent event history, attendance analytics, a full planning calendar, task management, travel-time guidance, and verification that the user actually joined are out of scope.
