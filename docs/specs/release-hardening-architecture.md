# Release Hardening: Refresh Coordination and Alert Presentation Seams

## Problem Statement

The MVP currently protects accepted Google Calendar Commitments correctly, but the implementation has two release-hardening risks created by iterative implementation and UAT changes.

First, calendar refresh and recovery are requested from many paths: account changes, Protection Confirmation, timing-setting changes, periodic monitoring, app recovery, wake/unlock notifications, and alert actions. The current generation guard prevents an older result from replacing a newer snapshot, but several refreshes can still run concurrently and several recovery notifications can trigger the same work. This makes the refresh lifecycle harder to reason about and increases the chance of duplicate transitions, unnecessary calendar requests, or a future regression when another trigger is added.

Second, the user-visible alert promise crosses SwiftUI, AppKit windows, multi-display presentation, fallback surfaces, Display Sharing behavior, and optional Blocking Mode. The domain flow is well tested through its existing interface, but the platform presentation lifecycle is difficult to test deterministically. The areas changed most often during UAT are therefore also the areas with the weakest automated seam.

## Solution

Harden the existing architecture while limiting product behavior changes to three UAT corrections: Strong Alert native closing, Early Reminder multi-display coverage, and Early Reminder content-fit sizing.

Calendar refreshes and recovery requests should pass through one internal coordination path that serializes or coalesces overlapping work while preserving the current calendar snapshot, coverage, recovery, and alert behavior. The existing `CommitmentProtectionFlow` remains the highest external seam and continues to own the observable Commitment Protection behavior.

Alert presentation should gain a narrow internal seam for platform lifecycle concerns: display topology, window activation, fallback presentation, and Blocking Mode availability. The existing pure display-plan behavior remains the testable core for multi-display selection. AppKit remains the production adapter, while tests use deterministic stand-ins for screen and window lifecycle conditions.

The release must preserve the accepted product model: Google Calendar remains authoritative; Merged Commitments are formed before Commitment Conflicts; Strong Alerts remain visible during Full-Screen Sharing, window sharing, and app sharing; Pause and occurrence-local decisions retain their current behavior; and no passive Missed Commitment surface is reintroduced.

## User Stories

1. As a user, I want calendar changes to settle into one current protection state, so that a burst of refresh triggers cannot leave the app showing stale commitment information.
2. As a user, I want recovery after wake, unlock, app activation, or relaunch to produce one stable recovery result, so that I do not see duplicate alerts or duplicate activity transitions.
3. As a user, I want a newer calendar refresh request to win over an older in-flight request, so that a stale calendar snapshot cannot restore a canceled or changed Commitment.
4. As a user, I want a refresh request caused by a deliberate calendar or timing change to be preserved even when another refresh is already running, so that my latest settings are not silently ignored.
5. As a user, I want recovery-specific handling of known and Untracked Past Occurrences to remain unchanged, so that a previously known ongoing Commitment can become overdue while a late-discovered occurrence remains quiet.
6. As a user, I want stale-account and unavailable-account behavior to remain unchanged during refresh coordination, so that known reminders remain Unverified while new reminders are not created from stale coverage.
7. As a user, I want independent Connected Accounts to continue working when one account is slow or unavailable, so that refresh coordination does not turn an account-specific failure into a global outage.
8. As a user, I want calendar cancellation, rescheduling, changed meeting links, and RSVP changes to be reconciled using the same current snapshot rules, so that refresh coordination does not create a second interpretation of Google Calendar truth.
9. As a user, I want an Early Reminder to remain a normal visual reminder unless I explicitly enable Blocking Mode, so that refresh or presentation hardening does not change its default interruption level.
10. As a user, I want Blocking Mode to fall back to a visible visual reminder when macOS permissions or the interaction barrier are unavailable, so that missing permissions never remove the protection experience.
11. As a user, I want Blocking Mode to stop blocking when macOS or the user disables the interaction barrier, so that the app does not trap interaction after the system has withdrawn permission.
12. As a user, I want an Early Reminder to recover if its normal window disappears during presentation, so that the reminder does not silently vanish while protection remains active.
13. As a user, I want both Early Reminder and Strong Alert to cover every available display, so that display topology changes cannot leave a working display without the current reminder.
14. As a user, I want an active reminder to remain visible when the app becomes active, inactive, or another display is connected, so that ordinary window lifecycle events do not dismiss protection.
15. As a user, I want native window closing to act as Close for now only on an Early Reminder, while a Strong Alert exposes no native close control and ignores native close attempts, so that the urgent surface cannot be cleared accidentally.
16. As a user, I want Join, Stop reminders, Got it, Snooze, Pause, Restore Protection, and primary-conflict selection to continue using the same Commitment Protection decisions regardless of which presentation surface invoked them, so that fallback and normal surfaces cannot diverge in domain behavior.
17. As a user, I want Strong Alerts to remain visible during Full-Screen Sharing, window sharing, and app sharing, so that the release-hardening work does not revive the superseded sharing-privacy behavior.
18. As a user, I want same-start Commitment Conflicts to remain equal until I choose a primary, so that presentation coordination does not silently select a commitment.
19. As a user, I want the app to retain the current-day Protection Activity semantics, so that coordination changes do not create duplicate or misleading history.
20. As a maintainer, I want refresh and presentation changes to be testable through the smallest practical seams, so that future release fixes do not require modifying unrelated calendar, persistence, and UI code together.
21. As a maintainer, I want the existing user-visible Commitment Protection flow to remain the primary behavioral test seam, so that the test suite continues to describe product behavior rather than internal implementation details.
22. As a maintainer, I want this hardening work to avoid speculative abstractions, so that the release architecture remains small and understandable.

## Implementation Decisions

- `CommitmentProtectionFlow` remains the highest external seam for observable Commitment Protection behavior.
- All existing refresh triggers use one internal refresh-coordination path. This includes periodic monitoring, account connect/restore, Protection Confirmation, calendar selection changes, timing-setting changes, conflict-primary selection, app recovery, wake/unlock recovery, and other current refresh requests.
- The coordinator must preserve the current newest-result-wins behavior. A stale in-flight refresh may finish, but it must not publish a snapshot, activity transition, coverage state, or alert state after a newer request has superseded it.
- The coordinator must not drop a meaningful newer request merely because an older refresh is in flight. A follow-up refresh may be queued or the current work may be canceled, provided the final observable state reflects the newest request.
- Recovery-specific intent must remain distinguishable from an ordinary refresh where current behavior depends on that distinction, including suppression of Untracked Past Occurrences during relaunch, reconnect, and newly added coverage.
- Refresh coordination must not move Google Calendar interpretation into the UI layer. Acceptance, cancellation, rescheduling, time zones, Recognized Meeting Links, Merged Commitments, and Commitment Conflicts remain in the Commitment Protection domain flow.
- Refresh coordination must preserve account isolation. One Connected Account may fail or become stale without discarding healthy account snapshots or their reminders.
- Refresh coordination must preserve current persistence behavior and must not introduce a new configuration schema unless implementation work proves one is required.
- The existing `GoogleCalendarConnecting` interface remains the calendar Adapter seam. No additional repository or service layer is justified by this issue.
- Alert presentation receives one narrow internal platform seam for the lifecycle conditions that cannot be tested reliably through the domain flow alone: available displays, window discovery/creation, activation and reactivation, surface disappearance, and Blocking Mode availability.
- The existing pure display-plan calculation remains the authoritative rule for choosing the primary display and covering additional displays. The new seam must not duplicate display-selection rules.
- The production AppKit implementation remains the production Adapter for the platform presentation seam. Tests may provide deterministic stand-ins for display and window lifecycle conditions.
- Desired Blocking Mode setting, runtime availability, and active interaction barrier are distinct states. The interface between the flow and the presentation Adapter must make that distinction explicit, so a failed or user-disabled barrier falls back to normal visual presentation without silently changing the persisted user preference.
- Normal Early Reminder, fallback Early Reminder, normal Strong Alert, and same-start Strong Alert Conflict surfaces may remain separate presentations, but all product actions must continue to delegate to the same Commitment Protection flow decisions.
- Public product behavior changes are limited to the Strong Alert native-close correction above, extending Early Reminder coverage to every available display, and replacing its oversized fixed-height presentation with content-fit sizing bounded by the available display. The sizing correction is a layout bug fix, not a visual redesign.
- No new calendar provider, custom reminder, mobile fallback, team policy, analytics surface, or Transition Support behavior is introduced.
- No broad split of `CommitmentProtectionFlow`, no broad split of the SwiftUI application file, and no cleanup of legacy persisted fields is required for this issue.

## Testing Decisions

- Tests should assert externally observable Commitment Protection outcomes through the existing `CommitmentProtectionFlow` seam wherever possible.
- Refresh-coordination tests should use the existing calendar Adapter test doubles and controllable time. They should cover overlapping refresh requests, newer snapshots superseding older snapshots, a queued request after an in-flight refresh, recovery bursts, account-specific failure, and preservation of current activity and alert behavior.
- The existing stale-refresh race test is prior art for newest-result-wins behavior. New tests should extend that behavior rather than asserting private task counts or implementation-specific scheduler details.
- Recovery tests should cover known ongoing Commitments becoming Overdue Commitments, Untracked Past Occurrences remaining quiet, ended Commitments remaining quiet, and current Calendar state winning over saved state.
- Presentation-seam tests should use deterministic display and window lifecycle stand-ins. They should cover no displays, one display, multiple displays, invalid primary display selection, display topology changes, application activation changes, Early Reminder native Close mapping to Close for now, Strong Alert native-Close absence and veto on primary and replica displays, Got it temporary close and repeat scheduling, and unexpected or programmatic surface disappearance and recovery.
- Blocking Mode tests should cover the normal visual fallback when permissions are missing, activation when permissions become available, deactivation when the barrier is disabled by the user or system, restoration of prior window interaction state, and cleanup after close.
- Product action tests should verify that normal and fallback presentation paths produce the same observable Flow decisions for Join, Stop reminders, Got it, Snooze, Pause, Restore Protection, and same-start primary selection. Got it must close only the current Strong Alert surface while protection remains active and its repeat stays scheduled.
- Display-sharing tests should continue to verify that visual reminders remain visible during Full-Screen Sharing, window sharing, and app sharing. The test must preserve ADR-0004 rather than reintroducing ADR-0002 behavior.
- The existing `StrongAlertDisplayPlan` tests remain the pure calculation tests for display coverage across both reminder stages. They should not be replaced by AppKit-heavy tests.
- The existing Commitment Protection flow suite remains the primary regression suite. Tests must continue to avoid asserting private state storage or the number of internal modules.
- Real macOS Accessibility/Input Monitoring permissions, physical multi-display topology, Display Sharing, sleep/wake, and lock/unlock behavior remain manual release QA because they depend on the Window Server and user session.
- The final implementation must pass the existing suite and build before the issue is closed, with no implementation behavior changes outside this spec.

## Out of Scope

- New user-facing features or changes to the accepted MVP product model
- Refactoring the entire Commitment Protection domain into multiple public modules
- Replacing the existing `GoogleCalendarConnecting` Adapter seam
- Deleting legacy persisted fields, singular meeting-link compatibility, or legacy activity enum values
- Replacing UserDefaults persistence with a new storage system
- Redesigning Setup, Menu Bar, Early Reminder, Strong Alert, or Test Alert visuals; the scoped Early Reminder content-fit correction is not a redesign
- Adding additional calendar providers or network clients
- Adding analytics, attendance verification, or a passive Missed Commitment surface
- Making Blocking Mode mandatory or changing the default visual reminder behavior

## Further Notes

- This is release hardening with the three bounded UAT corrections above, not a broad feature issue. The implementation should be conservative and incremental.
- The architecture audit found the broad `CommitmentProtectionFlow` split valuable but too risky for this release. A later change may extract a pure reconciliation module behind the existing Flow seam once the product behavior is stable.
- The architecture audit found the legacy compatibility state intentional for the first release. Its removal should wait for an explicit persisted-state migration decision.
- The issue should be closed only after the observable behavior is covered by tests, platform-dependent cases have passed manual QA, and no `Sources/` or `Tests/` changes outside this scope are included.
