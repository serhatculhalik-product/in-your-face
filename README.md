# Meeting Incoming

> Full-screen calendar alerts for Mac.

Meeting Incoming watches the Google Calendar commitments you explicitly choose and escalates reminders only when they need your attention: an optional early nudge, followed by a clear, actionable alert when the commitment starts. The name and descriptor are provisional while public identity and distribution clearance remain pending.

It is deliberately focused. It does not change your calendar, infer which events matter, or verify that you attended. Its job is simple: help you show up on time.

## Highlights

| Capability | What it does |
| --- | --- |
| Google Calendar | Connect one or more Google accounts through OAuth and choose exactly which calendars to monitor. |
| Early Reminder | Show a configurable visual reminder 5–30 minutes before an accepted or self-organized timed commitment. |
| Optional Blocking Mode | Keep the Early Reminder in front and block background interaction while it is open. |
| Strong Alert | At start time, present a calm but hard-to-miss alert across available displays. |
| Meeting actions | Join a recognized meeting link, mark a commitment handled after joining another way, or stop reminders for the current occurrence. |
| Event types | Keep out-of-office events quiet by default, with one explicit option to protect them. |
| Snooze and Pause | Defer an Early Reminder once, or temporarily pause protection globally for a bounded duration. |
| Conflicts | Surface overlapping commitments and let you choose the primary one when calendar data cannot decide. |
| Coverage health | Show stale, unavailable, and unverified coverage instead of silently pretending protection is complete. |
| Recovery | Re-evaluate known ongoing commitments after relaunch, wake, unlock, or other availability gaps. |
| Menu bar workflow | See the next protected commitment, account/calendar health, pause state, and activity without opening a full calendar. |
| Accessibility | Keyboard-accessible actions, VoiceOver-friendly labels, reduced-motion behavior, and high-contrast alert surfaces. |

## How it works

1. Connect a Google Calendar account.
2. Select the calendars that deserve protection and confirm the selection.
3. Meeting Incoming monitors accepted or self-organized events with a specific start and end time. All-day, declined, tentative, unanswered, and unselected-calendar events stay quiet. Out-of-office events also stay quiet unless you explicitly enable their protection.
4. An Early Reminder can appear before the start time. You can choose Close for now, snooze it once, or stop reminders for that occurrence.
5. At the start time, the Strong Alert shows the commitment context and next action. Join opens a recognized meeting link, I joined another way records the occurrence as Handled, and Stop reminders ends its protection without changing Google Calendar.
6. If the alert cannot be handled immediately, it repeats at the configured interval until the commitment is joined, handled, dismissed, paused, or ends.

## Requirements

- An Apple silicon Mac running macOS 14 or later
- Swift 6 toolchain / Xcode with Swift 6 support
- A Google Cloud project with the Google Calendar API enabled
- OAuth credentials for the local loopback authorization flow

The current repository is source-first: it does not publish a signed or notarized release binary yet.

## Google Calendar setup

Create OAuth credentials in Google Cloud before running the app:

1. Create or select a Google Cloud project.
2. Enable the Google Calendar API.
3. Configure the OAuth consent screen for the people who will use the app.
4. Create an OAuth client suitable for a desktop/local loopback application.
5. Copy the credentials into a local `.env` file.

```sh
cp .env.example .env
```

Then replace the placeholder values in `.env`:

```dotenv
GOOGLE_OAUTH_CLIENT_ID='your-client-id'
GOOGLE_OAUTH_CLIENT_SECRET='your-client-secret'
```

`.env` is ignored by Git. Never commit real OAuth credentials.

The app requests Google Calendar read-only access. Each refresh credential is AES-GCM encrypted in Application Support with key protection bound to the current Mac's Secure Enclave, excluded from backups, and unavailable after migration to another Mac. Access tokens remain memory-only; the app creates no Keychain items or plaintext fallback. A successful Disconnect removes the local credential after requesting Google revocation.

## Run from source

For a local development run, export the credentials into the process environment:

```sh
export GOOGLE_OAUTH_CLIENT_ID='your-client-id'
export GOOGLE_OAUTH_CLIENT_SECRET='your-client-secret'
swift run InYourFace
```

The app opens a setup window and also exposes a menu bar experience. After signing in, select at least one calendar and confirm protection.

## Build an app bundle

The repository includes a packaging script. It reads `.env`, builds the arm64 release executables, creates `.build/app/Meeting Incoming.app`, injects the OAuth values into the app bundle, and applies an ad-hoc code signature by default.

```sh
cp .env.example .env       # first time only
# edit .env with your credentials
./scripts/build-app.sh
open ".build/app/Meeting Incoming.app"
```

You can provide a different output directory as the first argument:

```sh
./scripts/build-app.sh /tmp/in-your-face-app
```

## Permissions

Normal visual reminders work without special macOS permissions.

Optional Blocking Mode uses both:

- Accessibility, to keep the Early Reminder in front and manage the interaction barrier.
- Input Monitoring, to determine whether interaction is occurring inside the reminder surface.

If either permission is unavailable, the app keeps the visual reminder behavior and does not silently turn the preference off. The setup screen includes buttons to open the relevant macOS Privacy & Security settings.

## Privacy and product boundaries

- The only calendar provider currently supported is Google Calendar.
- Google Calendar is read-only from the app’s perspective. RSVP, event titles, times, descriptions, and meeting links are never edited by Meeting Incoming.
- Only selected and confirmed Monitored Calendars can create protection.
- Out-of-office events are excluded by default; Out-of-Office Protection is one global, default-off preference covering both reminder stages.
- The app does not verify attendance. Clicking Join is the user’s acknowledgement that the reminder lifecycle can end.
- I joined another way records Handled for the current occurrence; Stop reminders records a separate occurrence-local dismissal.
- Protection decisions are occurrence-local, so dismissing one occurrence does not rewrite the calendar or suppress a rescheduled occurrence.
- Launch at Login is explicit and off by default. Valid device-bound authorization otherwise survives app relaunch, Mac restart, and app update.
- The product is a personal utility, not a team policy, administration, or attendance-monitoring system.

## Project structure

```text
Package.swift
├── Sources/
│   ├── CommitmentProtection/   Domain flow, calendar connector, refresh and recovery logic
│   ├── InYourFace/             SwiftUI app, menu bar UI, alert windows and macOS integration
│   ├── MeetingIncomingHelperSupport/
│   └── MeetingIncoming*Helper/ Reset and relaunch helper executables
├── Tests/
│   ├── CommitmentProtectionTests/
│   ├── InYourFaceTests/
│   └── MeetingIncomingHelperSupportTests/
├── Resources/InYourFace.app/   App bundle metadata
└── scripts/build-app.sh        Release app-bundle packaging
```

The commitment-protection domain is kept separate from the SwiftUI and AppKit presentation layer so timing, calendar truth, recovery, conflicts, and user actions can be tested independently of window rendering.

## Verify changes

Run the full test suite and a package build before opening a pull request:

```sh
swift test
swift build
```

The most valuable tests describe observable behavior: eligibility, lead-time and start-time boundaries, Join/Handled/Stop/Snooze/Pause/Restore actions, out-of-office opt-in, encrypted persistence, conflicts, stale coverage, recovery, display sharing, and accessibility.

## Contributing

Bug reports, focused improvements, and tests are welcome. For a change:

1. Read the project context and relevant documents under `docs/agents/`, `docs/specs/`, and `docs/adr/`.
2. Keep product behavior in `CommitmentProtection` and platform presentation in `InYourFace` where possible.
3. Add or update behavior-focused tests.
4. Run `swift test` and `swift build`.
5. Open a pull request with the user-visible behavior and verification steps.

The core product principle is: use the least disruptive intervention that still reliably gets the user to the commitment on time.
