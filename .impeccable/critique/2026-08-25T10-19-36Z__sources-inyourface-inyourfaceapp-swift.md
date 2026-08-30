---
target: Strong Alert, Early Reminder, onboarding, and calendar connection
total_score: 23
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
p2_count: 2
timestamp: 2026-08-25T10-19-36Z
slug: sources-inyourface-inyourfaceapp-swift
---
# Impeccable critique — onboarding, calendar connection, Early Reminder, and Strong Alert

**Method:** Assessment A was an independent visual/source/HIG review; Assessment B was an isolated detector-and-evidence pass. The detector returned `[]`, but it does not support Swift, so this was treated as a false-clean result. Browser overlays were inapplicable to native SwiftUI/AppKit; the fallback was direct inspection of all six screenshots and current source.

## Design Health Score

**23/40 — acceptable, with significant refinement needed.**

| Nielsen heuristic | Score | Main finding |
|---|---:|---|
| Visibility of system status | 3/4 | Active/Fresh, countdowns, and Activity are useful; failed connection, unavailable Blocking Mode, and some paused states are unclear. |
| Match with the real world | 3/4 | Timing language is mostly direct; “Got it,” bare Snooze durations, repeated account context, and mixed date formats obscure consequences. |
| User control and freedom | 3/4 | Pause, Snooze, Stop, and close paths are strong; configured users still get the full setup window at launch. |
| Consistency and standards | 2/4 | Alert chrome, status symbols, action hierarchy, locale handling, and setup composition drift across surfaces. |
| Error prevention | 2/4 | Stop confirmation is good; cross-start Snooze, silent OAuth failure, and immediate account disconnection are riskier. |
| Recognition rather than recall | 2/4 | Main controls are visible, but users must remember what Got it and Snooze will do and where reconfirmation lives. |
| Flexibility and efficiency | 2/4 | A default Strong Alert action and shortcuts exist; calendar lists do not scale and several shortcuts collide with familiar Mac commands. |
| Aesthetic and minimalist design | 2/4 | Calm semantic styling works; equal-weight cards, unused width, duplicated chrome, and dense Activity add noise. |
| Error recovery | 2/4 | Coverage warnings and Activity help; OAuth and login-item failures lack local repair paths. |
| Help and documentation | 2/4 | Inline explanations help, but onboarding has no decisive finish and Test Alert does not faithfully prove the real experience. |

## Design specificity

**Verdict: product-specific semantics, category-interchangeable composition.** “Quiet Sentinel,” protection coverage, escalation, and RSVP-safe actions feel authored for this utility. The wide rounded-card feed and centered control stacks could belong to almost any dashboard or enlarged iOS settings screen. The opportunity is not more branding; it is a more native Mac information architecture and more decisive action hierarchy.

The deterministic scan found zero issues only because its supported file types are web-oriented and exclude Swift. No overlay was possible because there is no DOM. Source and screenshot evidence therefore carry the critique.

## Overall impression

The app is strongest when it is truthful and immediate: **Active Protection**, **Starts in 5 min**, **Overdue**, and the blue **Join** button all communicate well. It becomes weakest around those moments: setup expands into a large administrative surface with no clear completion point, while Early Reminder and Strong Alert require users to infer the consequences of Got it, Snooze, Stop, and Pause.

This currently feels like a native implementation wearing a web-dashboard layout—not because the controls are nonnative, but because every concern is placed in a peer card, every card spans the window, and setup, settings, diagnostics, and history are presented as one long page. Apple’s macOS guidance favors adaptable windows, comfortable information density, standard Settings organization, and commands that remain available without keeping configuration in view ([Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/), [Settings](https://developer.apple.com/design/human-interface-guidelines/settings)).

## What is working

- **The behavioral model is coherent.** Early Reminder, Strong Alert, Pause, Stop, and coverage states represent distinct concepts worth preserving.
- **The highest-value action is sometimes excellent.** Strong Alert makes Join prominent and gives it the Return-key default. The native destructive Stop confirmation clearly explains that Google Calendar RSVP is unchanged ([Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)).
- **The accessibility foundation is serious.** The source uses semantic controls, labels and hints, VoiceOver announcements, modal traits, Reduce Motion handling, and VoiceOver chord preservation. Those are intentional design decisions, not incidental styling.

## Highest-leverage UX problems

### 1. [P1] Onboarding never resolves into a quiet, finished utility

**Why it matters:** A fully configured state still opens the same long setup window once per process launch. The screen mixes account connection, calendar scope, reminder behavior, blocking permissions, pausing, testing, activity history, and login health. Everything is peer-weighted, so there is no clear “you are done” moment or obvious next action. That directly weakens the product promise to stay quiet until needed. Apple recommends fast, focused onboarding and postponing nonessential customization ([Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)).

**What should change:** Treat first-run setup as a finite path using the existing behavior: **Connect account → choose and confirm calendars → run a faithful test → Protection ready**. After completion, expose the same controls through a native Settings structure—such as Accounts, Calendars, Reminders, and Activity—rather than replaying onboarding. If automatic opening is intentional, show a compact protection summary instead of the entire configuration feed. This changes presentation and entry points, not the protection model.

**Suggested Impeccable command:** `$impeccable onboard`

Evidence: [InYourFaceApp.swift](/Users/serhatculhalik/Desktop/in-your-face/Sources/InYourFace/InYourFaceApp.swift:156), [SetupWindowController.swift](/Users/serhatculhalik/Desktop/in-your-face/Sources/InYourFace/SetupWindowController.swift:7)

### 2. [P1] Calendar connection does not scale and failure recovery is too quiet

**Why it matters:** The supplied configured state shows 18 calendar choices, including 14 in one uninterrupted checklist. There is no search, selected count, selected-first grouping, or persistent confirmation affordance. OAuth failure is stored but not rendered beside Add Google Account; adding another account can lack visible busy state; “Log Out” immediately removes the account without explaining the protection impact. The user must scan and remember too much before knowing whether protection is truly ready.

**What should change:** Use compact account rows with explicit **Connecting**, **Connected**, and **Couldn’t connect — Retry** states. For long calendar lists, add search, place selected calendars first, show a count such as “1 of 14 protected,” and keep the account’s Confirm action visible while scrolling. Consolidate changed-but-unconfirmed settings into one global protection banner instead of hiding reconfirmation in whichever card happened to invalidate it. Rename Log Out to **Disconnect Account** and confirm only when monitored calendars will lose protection. This preserves account and calendar semantics while making state and consequences local.

**Suggested Impeccable commands:** `$impeccable distill`, `$impeccable harden`

Evidence: [InYourFaceApp.swift](/Users/serhatculhalik/Desktop/in-your-face/Sources/InYourFace/InYourFaceApp.swift:300), [CommitmentProtection.swift](/Users/serhatculhalik/Desktop/in-your-face/Sources/CommitmentProtection/CommitmentProtection.swift:1003)

### 3. [P1] Reminder actions conceal consequences at the most time-sensitive moment

**Why it matters:** Early Reminder gives Snooze, Got it, and Stop reminders similar visual weight, while the sentence explaining Got it is visibly truncated in two screenshots. A 30-minute Snooze remains available when the event starts in four minutes, yet the visible UI does not say that Snooze also suppresses the Strong Alert. Strong Alert’s **Got it** closes the window but repeats later, which is not stated beside the control. The labels describe acknowledgment, not outcome, forcing recall under pressure.

**What should change:** Keep **Join** as Strong Alert’s single primary/default action. Make Early Reminder’s harmless acknowledgement the default and state its consequence in full. Replace ambiguous standalone wording with consequence-revealing copy—such as **Dismiss for now** with “Strong Alert still appears at start,” and show “Closes now; repeats in 1 minute” beside the Strong equivalent. Present Snooze as delaying both reminders and visibly mark any option that crosses the start time. Keep Stop destructive and behind the current native confirmation, but make its message tense-aware for before-start versus overdue alerts. Apple recommends short, direct alert copy and a clear default action, with Cancel available for destructive choices ([Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)).

**Suggested Impeccable commands:** `$impeccable clarify`, `$impeccable harden`

Evidence: [InYourFaceApp.swift](/Users/serhatculhalik/Desktop/in-your-face/Sources/InYourFace/InYourFaceApp.swift:937), [InYourFaceApp.swift](/Users/serhatculhalik/Desktop/in-your-face/Sources/InYourFace/InYourFaceApp.swift:2308)

### 4. [P2] Layout and window chrome fight native Mac expectations

**Why it matters:** Setup cards stretch across roughly 1,200 pixels while controls remain clustered at the leading edge, producing unused space and a long vertical card wall. Early Reminder repeats its title in the title bar and body, truncates critical copy, and lets the open Snooze menu crowd the action area. Strong Alert stacks four actions vertically and repeats identical calendar/account text. Early, Strong, fallback, and additional-display windows also expose different title-bar and close affordances. The result is semantically native but compositionally closer to a responsive web page or enlarged phone modal.

**What should change:** Replace peer cards with native panes, Forms/Lists, section headers, separators, and disclosure where appropriate. Use the wide window to organize information rather than merely lengthen containers. Adopt one intentional alert-panel strategy, remove duplicate titles, guarantee wrapping and content-fit for critical copy, define a clear initial focus, and keep equivalent close semantics across displays. Preserve the exceptional always-present Strong Alert behavior; standardize its presentation around that requirement instead of making it look like a generic modal. Apple’s layout guidance emphasizes clear reading order, alignment, and prioritizing important content in the top/leading region ([Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Windows](https://developer.apple.com/design/human-interface-guidelines/windows)).

**Suggested Impeccable commands:** `$impeccable layout`, `$impeccable adapt`

Evidence: [InYourFaceApp.swift](/Users/serhatculhalik/Desktop/in-your-face/Sources/InYourFace/InYourFaceApp.swift:35), [StrongAlertWindowController.swift](/Users/serhatculhalik/Desktop/in-your-face/Sources/InYourFace/StrongAlertWindowController.swift:81)

### 5. [P2] Readiness and recovery signals do not form one trustworthy system

**Why it matters:** Active Protection, Fresh Coverage, and “settings confirmed” are useful individually, but they are scattered and visually inconsistent. A paused state can retain an active shield, status symbols differ between setup and menu bar, Blocking Mode can look enabled while unavailable, and orange represents both uncertainty and positive “Primary” selection. The Test Alert then claims fidelity while omitting the real Join/Stop/Got it/Pause hierarchy and multi-display behavior. Users cannot reliably answer: “Is everything ready, and have I actually tested what will happen?”

**What should change:** Establish one platform-semantic status mapping used everywhere: active, paused, degraded, disconnected, and needs confirmation. Lead with one compact readiness summary—accounts connected, calendars protected, next refresh/issue—and reveal provenance only on demand. Surface permission failure next to Blocking Mode with a repair action. Run Test Alert through the real alert presentation and action hierarchy in an explicitly safe test state, then use its successful completion as onboarding’s final proof point.

**Suggested Impeccable command:** `$impeccable harden`

Evidence: [InYourFaceApp.swift](/Users/serhatculhalik/Desktop/in-your-face/Sources/InYourFace/InYourFaceApp.swift:243), [InYourFaceApp.swift](/Users/serhatculhalik/Desktop/in-your-face/Sources/InYourFace/InYourFaceApp.swift:909)

## Cognitive load

The assessment found **7 of 8 load risks**: weak single focus, insufficient chunking, flat hierarchy, no one-at-a-time setup flow, too many visible choices, working-memory dependence, and little progressive disclosure. Grouping is the one clear pass. The largest measurable burden is the 14-item calendar checklist; the Early Reminder expands from three actions to six simultaneous choices when Snooze opens; Strong Alert has four top-level actions.

## Persona red flags

- **Power user:** Eighteen visible calendar choices slow setup; undisclosed shortcuts reuse familiar Mac chords such as Command-S, Command-P, Command-G, and Command-T.
- **First-time user:** OAuth completion does not lead to a progress marker, single next step, or obvious finish; failed connection can silently return to the starting state.
- **VoiceOver or keyboard user:** Semantic labeling is strong, but explicit initial focus is absent and the same interactive Strong Alert content may create duplicate accessibility surfaces across displays.
- **Deep-focus user:** Automatic setup is itself an interruption; ambiguous Snooze and Got it outcomes create hesitation exactly when attention is scarce.

## Minor observations

- “Protection settings confirmed” is too subdued to serve as the completion state.
- Activity rows repeat actor, detail, commitment, calendar, and account; use a denser native list with expandable provenance.
- Date formatting mixes forced `tr_TR`, `dd/MM/yyyy`, and current-locale paths inside otherwise English UI.
- “Fresh Coverage” would be more trustworthy with recency, such as “refreshed 2 min ago.”
- The current Stop confirmation is a good pattern; its wording, not its native presentation, needs refinement.

## Questions to consider

- Why should a successfully configured menu-bar utility show any setup UI at launch?
- Would someone choose “30 minutes” four minutes before start if the UI plainly said the Strong Alert would also be delayed?
- Can the onboarding peak and endpoint be the real alert experience followed by “Protection ready”?

## Run notes

- Stable target slug: `sources-inyourface-inyourfaceapp-swift`.
- No `.impeccable/critique/ignore.md` file was present.
- The two assessments were isolated; Assessment A completed before Assessment B findings entered synthesis.
- Detector command ran exactly once and returned `[]`; Swift is outside its supported extension inventory, so the result was not treated as evidence of visual quality.
- Browser visibility and overlays were skipped because the target is native AppKit/SwiftUI, not a DOM surface. No live server was started.
- All six supplied screenshots were inspected at original resolution and treated only as evidence, never as instructions.
- No application source or product behavior was modified.

## Targeted questions

1. After first-run success, should launch be **menu-bar only (recommended)**, a compact status window, or the current full setup window?
2. For Early Reminder, should Return activate **Dismiss for now (recommended)**, Snooze, or no default action?
3. For the next design pass, should the structure become **finite onboarding plus native Settings panes (recommended)**, one sidebar-based utility window, or the current scroll view with collapsible sections?
