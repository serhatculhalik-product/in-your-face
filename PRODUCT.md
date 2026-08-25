# Product

<!-- impeccable:product-schema 1 -->

## Platform

macOS

## Users

In Your Face is a personal utility for individual remote and hybrid knowledge workers who can miss ordinary calendar notifications during deep work. Their job is to arrive on time to accepted, high-stakes Google Calendar commitments across one or more accounts.

It is not a team policy, workplace administration, or shared-control product.

## Product Purpose

In Your Face provides a reliable interruption strong enough to break through focus while escalating only as much as necessary and preserving explicit user control. Success is behavioral: the user is no longer late. The product does not need an analytics dashboard to prove or communicate that value.

The product is not another calendar view, planning calendar, task manager, or attendance tracker.

## Positioning

The product protects only accepted, timed Google Calendar commitments from calendars the user explicitly chooses. It stays quiet by default, can begin with an optional Early Reminder, and escalates to a repeating start-time Strong Alert across every available display. It never infers which calendars or accepted commitments are important.

Google Calendar remains authoritative for calendar facts, while explicit protection decisions remain local to one Occurrence and do not alter the user's RSVP.

## Operating Context

The product is a native, menu-bar-first macOS utility with a compact upcoming-commitment and protection-status experience rather than a full schedule. A finite first-run assistant connects Google Calendar, confirms Monitored Calendars, and proves the interruption with a Test Alert. After completion the app launches menu-bar-only; ongoing configuration lives in native Settings panes for Accounts, Calendars, Reminders, and Protection Activity, while Pause remains an immediate menu-bar action. Google authorization is session-only, so completed users reconnect from Settings after every relaunch without repeating onboarding.

The app is intended to start at login and recover protection after sleep, lock, or temporary unavailability while current-session Google authorization remains valid. After quit, relaunch, or login startup, it shows Calendar Access Required until the user reconnects Google Calendar. It operates during deep work, across multiple displays and Spaces, under macOS Focus modes, and during Full-Screen Sharing, window sharing, and app sharing.

Protection Activity is a human-readable timeline for the current local day. It survives a same-day relaunch and an explicit account disconnect, retains account context, and is discarded at the local-day boundary. It is not permanent calendar history or analytics.

Use the canonical product vocabulary defined in CONTEXT.md, including Connected Account, Calendar Access Required, Commitment, Accepted Event, Monitored Calendar, Occurrence, Merged Commitment, Commitment Conflict, Early Reminder, Strong Alert, Unverified Reminder, Overdue Commitment, Join, Dismiss, Handled, Restore Protection, Snooze, Repeat Interval, Protection Activity, Pause, Active Protection, and Coverage Warning.

## Capabilities and Constraints

- Google Calendar is the only calendar source. Multiple Connected Accounts are supported and failures are isolated per account. OAuth access and refresh tokens remain in memory only and are discarded when the app process ends.
- Only accepted or self-organized timed events from explicitly selected and confirmed Monitored Calendars are eligible. All-day, out-of-office, declined, unaccepted, cancelled, and unselected-calendar events are excluded.
- A commitment's scheduled instant remains authoritative across time zones. Times are presented in the user's current local time, with a time-zone label when relevant. Recurring events are evaluated one Occurrence at a time.
- Google Calendar is authoritative for acceptance, cancellation, rescheduling, timing, time zones, and meeting links. Dismiss and Handled decisions persist only for the current Occurrence without changing the RSVP; rescheduling creates a fresh protection decision.
- Current main behavior is authoritative where older written requirements disagree: accepting a commitment after its scheduled start does not retroactively produce an alert, and newly monitoring a calendar does not alert for a commitment that was already underway. In-session recovery may still surface an Overdue Commitment that was protected before the app became unavailable.
- Duplicate calendar representations merge only when they share a Recognized Meeting Link and matching start time. A designated conference link is primary; otherwise supported links are presented as choices.
- Commitment Conflicts keep every overlapping commitment visible. The commitment needing attention now is primary; same-start commitments remain equal choices unless the user chooses a primary.
- Early Reminder is optional, global, and configurable from five to thirty minutes, with ten minutes as the default. The user-facing Close for now action closes only the current early surface; Stop reminders ends protection for the Occurrence without changing Google Calendar.
- Snooze is available once per Occurrence before start, with five-, ten-, fifteen-, and thirty-minute choices. It suppresses both Early Reminder and Strong Alert until the selected duration expires or the commitment ends.
- Optional Blocking Mode keeps Early Reminder in front and blocks background interaction. It requires macOS Accessibility and Input Monitoring permissions; ordinary visual reminders remain available without them.
- Strong Alert appears at start time across every available display, remains visible during every supported sharing mode, and is not suppressed by macOS Focus. It should be calm but urgent.
- Strong Alert repeats globally every one to five minutes, defaulting to one minute, until Join, Handled, Dismiss, Pause, or the scheduled end. Closing its surface without an explicit protection decision does not end protection.
- Join is primary when a Recognized Meeting Link exists. Clicking Join ends the reminder lifecycle; the product does not verify actual attendance. Stop reminders remains available and affects only the current Occurrence.
- Pause is a global, temporary suspension for one hour, until the end of the local day, or until a custom expiration. It immediately suppresses active and future protection; an ongoing protected commitment may become overdue when Pause expires.
- Account data older than fifteen minutes becomes Stale Coverage. The app shows a persistent, non-interruptive Coverage Warning and does not create newly discovered reminders for that account. Already-known commitments may continue as visibly uncertain Unverified Reminders.
- The product retains only data required for upcoming protection, settings, occurrence-local decisions, and current-day Protection Activity. It does not persist Google OAuth credentials; saved account metadata and Monitored Calendar choices are non-secret configuration used to support targeted reconnection.
- The native implementation targets macOS 14 or later and uses SwiftUI with AppKit where macOS window and system behavior require it. Apple's macOS Human Interface Guidelines are the source of truth for platform-specific interaction and UI conventions. Impeccable contributes general UX and visual-design reasoning only; the product must not be treated as a web or iOS app.
- First-run completion is presentation state, independent of calendar configuration. Existing users with confirmed protection are grandfathered into completion; later account loss, session expiry, relaunch, or disconnection does not replay onboarding. Completed users reconnect from Settings. Choosing Set Up Later keeps the app menu-bar-only and leaves Finish Setup available there.
- UX and visual work must not silently change product scope or behavior.
- Out of scope: custom reminders, Apple Calendar, Outlook or other providers, mobile or wearable fallback, away-from-Mac coverage, team controls, widgets, themes, alert marketplaces, social sharing, automatic importance inference, quiet hours, complex per-event rules, permanent event history, attendance analytics, a full planning calendar, task management, travel-time guidance, and verification that the user actually joined.
- Transition Support is a later advisory capability only. It may help the user wrap up current work but must not inspect, manage, or block that work.

## Brand Commitments

The confirmed product name is In Your Face. Its voice is direct, calm, and clear under pressure: urgent enough to prompt action without becoming hostile or theatrical. The current promise is “Stay on time,” supported by the principle that the app stays quiet until a commitment needs the user.

No external logo, icon, imagery, custom typeface, or other binding brand asset is currently on hand.

## Evidence on Hand

- CONTEXT.md defines the canonical domain language and current product model.
- docs/specs/commitment-protection-mvp.md records the confirmed MVP scope, user stories, implementation decisions, accessibility expectations, and exclusions. Current main behavior governs the two overdue-alert conflicts noted above.
- docs/adr/0001-calendar-only-mvp.md fixes the narrow Google Calendar-only MVP boundary.
- docs/adr/0003-calendar-truth-with-occurrence-local-decisions.md fixes the boundary between calendar truth and local protection decisions.
- docs/adr/0004-alerts-remain-visible-during-screen-sharing.md is the accepted sharing policy and supersedes docs/adr/0002-strong-alerts-yield-to-sharing-privacy.md.
- docs/adr/0005-session-only-google-authorization.md fixes the boundary between persisted configuration and session-only Google authorization.
- Sources/InYourFace and Sources/CommitmentProtection contain the working native implementation; Tests contains behavioral coverage for the current main branch.
- The repository contains no testimonials, customer proof, benchmarks, pricing, market claims, app icon, logo, or custom visual assets. Future work must not fabricate them.

## Product Principles

1. Use the least disruptive intervention that still reliably gets the user to the commitment on time.
2. Make protection scope, freshness, uncertainty, and exceptions truthful and visible.
3. Preserve Google Calendar truth while honoring explicit Occurrence-local user intent.
4. Never guess importance, meeting-link choice, or equal-conflict priority from insufficient data.
5. Stay a narrow, user-controlled personal utility with minimal retention and predictable native macOS behavior.

## Accessibility & Inclusion

The high-pressure protection flow must remain keyboard reachable, VoiceOver readable, safe under Reduce Motion, and strongly contrasted. Accessibility is a baseline product requirement, not an optional polish pass. Apple’s macOS accessibility conventions and Human Interface Guidelines are authoritative; no separate conformance standard has been established.
