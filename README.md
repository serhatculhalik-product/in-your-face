# In Your Face

> A macOS commitment-protection utility for people who lose meetings inside deep work.

In Your Face watches the Google Calendar commitments you explicitly choose and escalates reminders only when they need your attention: an optional early nudge, followed by a clear, actionable alert when the commitment starts.

It is deliberately focused. It does not change your calendar, infer which events matter, or verify that you attended. Its job is simple: help you show up on time.

## Highlights

| Capability | What it does |
| --- | --- |
| Google Calendar | Connect one or more Google accounts through OAuth and choose exactly which calendars to monitor. |
| Early Reminder | Show a configurable visual reminder 5–30 minutes before an accepted, timed commitment. |
| Optional Blocking Mode | Keep the Early Reminder in front and block background interaction while it is open. |
| Strong Alert | At start time, present a calm but hard-to-miss alert across available displays. |
| Meeting actions | Join a recognized meeting link, choose between multiple links, or stop reminders for the current occurrence. |
| Snooze and Pause | Defer an Early Reminder once, or temporarily pause protection globally for a bounded duration. |
| Conflicts | Surface overlapping commitments and let you choose the primary one when calendar data cannot decide. |
| Coverage health | Show stale, unavailable, and unverified coverage instead of silently pretending protection is complete. |
| Recovery | Re-evaluate known ongoing commitments after relaunch, wake, unlock, or other availability gaps. |
| Menu bar workflow | See the next protected commitment, account/calendar health, pause state, and activity without opening a full calendar. |
| Accessibility | Keyboard-accessible actions, VoiceOver-friendly labels, reduced-motion behavior, and high-contrast alert surfaces. |

## How it works

1. Connect a Google Calendar account.
2. Select the calendars that deserve protection and confirm the selection.
3. In Your Face monitors accepted events with a specific start and end time. All-day, out-of-office, declined, and unaccepted events stay quiet.
4. An Early Reminder can appear before the start time. You can select Got it, snooze it, or stop reminders for that occurrence.
5. At the start time, the Strong Alert shows the commitment context and the next action. If a recognized meeting link exists, Join opens it; otherwise, the primary action is to stop reminders.
6. If the alert cannot be handled immediately, it repeats at the configured interval until the commitment is joined, handled, dismissed, paused, or ends.

## Requirements

- macOS 14 or later
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

The app requests Google Calendar read-only access. Refresh tokens are retained locally so a connected account can be restored after relaunch; disconnecting an account removes its locally stored refresh token.

## Run from source

For a local development run, export the credentials into the process environment:

```sh
export GOOGLE_OAUTH_CLIENT_ID='your-client-id'
export GOOGLE_OAUTH_CLIENT_SECRET='your-client-secret'
swift run
```

The app opens a setup window and also exposes a menu bar experience. After signing in, select at least one calendar and confirm protection.

## Build an app bundle

The repository includes a packaging script. It reads `.env`, builds the release executable, creates `.build/app/In Your Face.app`, injects the OAuth values into the app bundle, and applies an ad-hoc code signature.

```sh
cp .env.example .env       # first time only
# edit .env with your credentials
./scripts/build-app.sh
open ".build/app/In Your Face.app"
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
- Google Calendar is read-only from the app’s perspective. RSVP, event titles, times, and meeting links are never edited by In Your Face.
- Only calendars selected by the user can create protection.
- The app does not verify attendance. Clicking Join is the user’s acknowledgement that the reminder lifecycle can end.
- Protection decisions are occurrence-local, so dismissing one occurrence does not rewrite the calendar or suppress a rescheduled occurrence.
- The product is a personal utility, not a team policy, administration, or attendance-monitoring system.

## Project structure

```text
Package.swift
├── Sources/
│   ├── CommitmentProtection/   Domain flow, calendar connector, refresh and recovery logic
│   └── InYourFace/             SwiftUI app, menu bar UI, alert windows and macOS integration
├── Tests/
│   ├── CommitmentProtectionTests/
│   └── InYourFaceTests/
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

The most valuable tests describe observable behavior: accepted-event eligibility, lead-time and start-time boundaries, Join/Stop/Snooze/Pause/Restore actions, conflicts, stale coverage, recovery, display sharing, and accessibility behavior.

## Contributing

Bug reports, focused improvements, and tests are welcome. For a change:

1. Read the project context and relevant documents under `docs/agents/`, `docs/specs/`, and `docs/adr/`.
2. Keep product behavior in `CommitmentProtection` and platform presentation in `InYourFace` where possible.
3. Add or update behavior-focused tests.
4. Run `swift test` and `swift build`.
5. Open a pull request with the user-visible behavior and verification steps.

The core product principle is: use the least disruptive intervention that still reliably gets the user to the commitment on time.
