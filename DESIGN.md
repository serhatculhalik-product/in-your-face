---
name: In Your Face
description: "The Quiet Sentinel: native macOS commitment protection that stays restrained until action is needed."
---

# Design System: In Your Face

## Overview

**Creative North Star: “The Quiet Sentinel”**

The Quiet Sentinel is calm, direct, restrained, and trustworthy. At rest, the interface should feel like a familiar macOS utility that reports protection truth without demanding attention. When a commitment needs action, urgency grows through information hierarchy, persistence, and a decisive next action—not theatrical color, ornamental effects, or alarmist styling.

The visual authority is native macOS: system typography, semantic colors, SF Symbols, platform controls, and materials chosen for a functional role. Components should feel native and decisive. Apple’s macOS Human Interface Guidelines are the source of truth for platform conventions; this document records reusable product intent without promoting accidental implementation details into design rules.

**Key Characteristics:**

- Native system vocabulary rather than a custom skin.
- Quiet at rest, unmistakable when action becomes time-critical.
- Explicit state names and symbols; color reinforces meaning but never carries it alone.
- One clearly prioritized next action, with consequential choices explained and protected.
- Compact operation in the menu bar, finite activation in onboarding, and ongoing configuration in native Settings panes.
- Loading, empty, error, recovery, and confirmation states treated as part of the normal experience.
- Keyboard, VoiceOver, contrast, localization, and Reduce Motion behavior treated as baseline design concerns.

**The Native-First Rule.** Prefer the macOS-provided control, semantic style, material, window behavior, and symbol whenever they express the required function.

**The Quiet-Until-Critical Rule.** Increase urgency through content scale, persistence, and action priority; do not make every surface look urgent.

### Baseline Classification

- **Preserve:** semantic system typography and color; native controls and SF Symbols; named, icon-plus-text status; a finite assistant with stable header, scrollable content, and fixed action footer; grouped native Settings panes; one default action per decision context; consequence copy and native confirmation; truthful loading, empty, error, retry, and saved states; menu-bar → Early Reminder → Strong Alert escalation; content wrapping and content-fit alert sizing; keyboard access, VoiceOver focus and announcements, and Reduce Motion accommodation.
- **Implementation only:** literal spacing, corner radii, line limits, search thresholds, animation durations, popover and window dimensions, fixed list heights, individual shortcut letters, exact material opacities, source-file boundaries, and small differences among primary, fallback, and additional-display alert paths.
- **Revisit before canonizing:** overloaded orange semantics; cross-surface status-symbol drift; menu-bar density and fixed width; inconsistent error emphasis and action wording; alert chrome and action placement; parity among alert paths; Protection Activity scanability; Blocking Mode permission communication; multi-display accessibility duplication; and contrast/material behavior under macOS accessibility settings.

## Colors

The palette is platform-semantic and adaptive. No fixed color values are defined because the implementation intentionally relies on macOS system roles that respond to appearance, contrast settings, and the user’s accent choice.

### Primary

- **User Accent:** The macOS accent color identifies the most likely action, selection, or clear user agency. It is functional and sparse, never decorative.

### Secondary

- **Fresh Signal:** Confirmed Fresh Coverage currently uses the system positive color, a check symbol, and an explicit label. Preserve the meaning and redundancy, not the exact hue.
- **Caution Signal:** Stale, unavailable, or unverified protection currently uses the system warning color with named states and symbols. The same hue also marks an unrelated conflict selection, so the current mapping is provisional.

### Neutral

- **Primary Label:** The system primary text role carries commitment titles, section headings, essential state, and action labels.
- **Secondary Label:** The system secondary text role carries timing context, explanations, account metadata, timestamps, and supporting status detail.
- **Quiet Fill:** System quaternary treatment may group conflicts or dense activity content without creating a competing card hierarchy.

**The State-First Rule.** A status must remain understandable without color: name it and pair it with an appropriate symbol before adding color.

**The User-Accent Rule.** Reserve accent emphasis for the most likely action or clear user agency; never spread it across competing controls.

## Typography

**Display Font:** macOS system font, SF Pro
**Body Font:** macOS system font, SF Pro
**Label Font:** macOS system font, SF Pro

**Character:** Clear, compact, and familiar. Semantic size and weight establish hierarchy while preserving native macOS text metrics and accessibility behavior.

### Hierarchy

- **Strong Alert:** The commitment uses the system Large Title relationship with bold weight; timing uses a semibold Title relationship. Alert identity remains a quieter Headline.
- **Early Reminder:** The commitment steps down to a bold Title relationship while timing remains a semibold Title relationship. This makes Early visibly calmer than Strong without changing visual language.
- **Onboarding:** The current step uses a bold Title relationship; app identity and subsection labels use Headline; progress and helper text use Callout, with progress digits aligned for stable scanning.
- **Menu bar:** The next commitment uses Headline, countdown uses semibold Subheadline, and local time or metadata uses secondary Caption.
- **Settings and Activity:** Section names and event titles use Headline or semibold Body; explanations use Body or Callout; provenance and metadata use Caption.

**The Semantic-Scale Rule.** Use macOS semantic text relationships instead of freezing point sizes. Preserve the escalation relationships, not exact rendered measurements or one-off bold treatments.

## Layout

The system has three density bands: compact glanceable status, standard configuration, and generous interruption surfaces. These relationships are durable; current literal padding, gaps, radii, and widths are not.

- **Menu bar:** The glance-and-act layer for the next commitment, Pause, restorable decisions, protection truth, account health, and app-level commands.
- **Onboarding:** Two setup steps—connect Google Calendar and choose Monitored Calendars—followed by a readiness result, with a clear route to protect another Google account before finishing. It uses stable header/content/footer bands, visible progress, one real task per setup step, scrollable variable content, and a fixed action region.
- **Settings:** The ongoing inspect-and-configure layer. Accounts, Calendars, Reminders, and Activity use native panes and surface-appropriate Form, List, and ScrollView containers rather than a feed of equal cards. Reminders owns the default-off Out-of-Office Protection choice because it changes both reminder stages and is ongoing configuration, not onboarding.
- **Alerts:** Focused interventions that center commitment, timing, state, consequence, and next action. Both reminder stages are present across every available display; Early Reminder stays calmer, while Strong Alert is larger and persistent.

Long titles, Meeting Descriptions, translated copy, user-formatted dates, diagnostic text, and conflicts must wrap without hiding actions. Onboarding keeps variable content scrollable while its footer remains stable; Settings remains resizable within useful bounds; alert windows fit content and available display space. Universal resizability is not required.

**The Responsibility Rule.** Keep glanceable protection truth and immediate actions in the menu bar, teach activation and collect only first-run readiness choices in onboarding, and keep detailed inspection and ongoing configuration in native Settings.

**The Content-Fit Rule.** Let native windows and controls adapt to content, localization, and available display space; do not promote current fixed dimensions into reusable rules.

## Elevation & Depth

Depth is structural and native. Onboarding uses planar bands separated by dividers. Settings relies on grouped Form, inset List, and ordinary pane chrome. Focused alerts may use a system material shell to separate the intervention from underlying work, while quaternary fills may group conflicts or dense local content inside that shell.

There is no custom shadow vocabulary. Preserve the layered philosophy, not current material opacities, corner values, or differences between primary, fallback, and additional-display alert containers.

**The Semantic-Material Rule.** Choose material or tonal separation for hierarchy and legibility, never for decorative translucency.

**The No-Custom-Shadow Rule.** Do not add app-specific shadows while native window elevation, dividers, and materials already communicate depth.

## Shapes

Native controls keep their system-provided geometry. Forms, lists, checkboxes, menus, text fields, pickers, alerts, and buttons must not be reskinned into a custom component kit.

Custom rounded containers are limited to focused alert shells and nested groups where they clarify a conflict, warning, or local relationship. Their current radii are implementation evidence, not a token scale. Ordinary onboarding and Settings sections remain planar or use platform containers; they do not need a surrounding card.

**The System-Shape Rule.** Let native controls own their shape; add a custom container only when it clarifies grouping, state, or foreground hierarchy.

## Components

The inventory is documented in SwiftUI/AppKit terms. The sidecar intentionally has no HTML/CSS previews because a web facsimile would misrepresent system controls and the native macOS authority.

### Buttons and Menus

Use native push buttons and semantic roles. The likely action uses prominent/default treatment; supporting actions remain quieter. Menus contain bounded alternatives such as Snooze, Pause, or multiple recognized links. Protection-ending choices include visible consequence copy and use native destructive confirmation. Invalid or in-flight actions are disabled rather than allowed to fail.

**The One-Action Rule.** Give one action visual priority within a decision context, except when product truth requires equal choices such as unresolved same-start commitments.

### Status and Feedback

Pair every state with a concise name and SF Symbol; add semantic color only as reinforcement. Use labeled ProgressView for transient work, ContentUnavailableView for genuine empty or filtered-empty results, inline error text close to its cause, and an adjacent retry when recovery is possible. Confirmation state must say what is currently protected, not merely that a control was clicked.

### Calendar Selection

The shared calendar selector uses an account menu when needed, conditional search for long collections, an inset List, checkbox Toggles, a visible selection count, selected-first ordering, native empty/search states, and consequence-aware confirmation before removing protection. Preserve this behavior pattern; the current search threshold, list height, and picker width are local implementation choices.

### Menu-Bar Surface

Order content by operational urgency: upcoming commitment or conflict; active Pause or pause controls; restorable occurrence decisions; protection and account health; then app-level commands. The window-style menu extra is appropriate for this richer interaction. Its fixed width, repeated controls, and account-level density remain open for refinement.

### Onboarding and Settings

Onboarding teaches one real action in each of two setup steps—connect Google Calendar, then choose Monitored Calendars—and ends with a truthful readiness result; it never becomes a second Settings surface. Readiness names every actively protected calendar under its Google account, and the user can protect another account before finishing. Readiness limits itself to the initial protection choices: whether Early Reminder is enabled, its lead time, the Strong Alert Repeat Interval with one minute as the default, optional Blocking Mode, and Start at Login. Start at Login is presented on by default during first-time setup but remains staged until Finish Setup or Finish Later; merely showing readiness never changes the macOS Login Item, and the user can opt out or change it later in Settings. Showing readiness also never requests system permissions. When the user explicitly chooses Blocking Mode, explain Accessibility and Input Monitoring before requesting either permission, and preserve visual-only Early Reminder behavior when either permission is missing. Onboarding discloses that Google authorization is encrypted for this Mac and normally survives relaunch. Settings uses native tabs, grouped Forms, Lists, sections, LabeledContent, and platform controls. Accounts, Calendars, Reminders, and Activity remain distinct responsibilities; Accounts provides targeted reconnection only when authorization genuinely requires it. Reminders places Out-of-Office Protection in an Event Types section with a native Toggle and concise default-off consequence copy. Both surfaces show loading, error, empty, recovery, and confirmation states in context.

### Early Reminder

Present alert identity, explicit uncertainty or conflict state, commitment title, timing, optional Meeting Description, and the consequence of the passive action before controls. Meeting Description is bounded, selectable plain text with secondary emphasis; it wraps instead of becoming an active link or competing with actions. Do not introduce a new Early Reminder during the final minute before start; an already-visible reminder may remain as the start approaches. Present one coordinated surface across every available display, with one accessible interaction tree; an action or native Close from any display applies once and closes every replica. Snooze remains a menu. **Close for now** dismisses only the current surface and makes the later Strong Alert consequence visible; the native window Close is available only on Early Reminder and invokes this action. Stop reminders applies to the occurrence and requires confirmation. Preserve semantics and hierarchy, not current chrome, dimensions, or button arrangement.

### Strong Alert

Make the commitment title and timing the strongest content, followed by concise context, an optional secondary Meeting Description, and one default next action. When Join exists, it is primary and Stop reminders is secondary. **I joined another way** remains a nearby secondary alternative that records the current Occurrence as Handled. Without a recognized meeting link, Stop reminders may become the main next action while confirmation communicates its consequence. Every primary and replica Strong Alert hides the native traffic-light controls, and native window closing is unavailable so the alert cannot be cleared accidentally. Got it remains the quieter explicit action, with repeat behavior visible; Pause stays grouped as a menu. Preserve multi-display presence, repetition, keyboard access, and VoiceOver support—not duplicated interaction trees or current panel chrome.

### Commitment Conflicts

Preserve every same-start commitment and keep choices equal until the user explicitly chooses a primary. Adapt compact summary, explanatory detail, and full choice to the menu bar, Early Reminder, and Strong Alert without silently discarding secondary commitments. The present orange Primary marker and exact conflict-card treatment are not canonical.

### Protection Activity

Show provenance in a consistent order: actor symbol, semibold event title and timestamp, You/System identity, explanation, then commitment/calendar/account metadata. Use an inset divider list, localized time, filtering, and an explicit empty state. Preserve truth and provenance while revisiting metadata density and scanability.

## Do's and Don'ts

### Do:

- **Do** use native macOS controls, semantic system typography and colors, SF Symbols, and materials with a functional role.
- **Do** express every protection state with clear text and a symbol before using color.
- **Do** keep accent emphasis scarce and reserve it for the most likely action or explicit user agency.
- **Do** keep onboarding finite, Settings inspectable, and the menu bar operationally compact.
- **Do** intensify hierarchy from onboarding and Settings to Early Reminder to Strong Alert without making routine configuration feel alarming.
- **Do** keep variable onboarding content scrollable with a stable action footer, and let Settings and alerts adapt to long content.
- **Do** preserve native action roles, default-action behavior, disabled states, keyboard reachability, VoiceOver focus and announcements, and Reduce Motion accommodation.
- **Do** validate light and dark appearances, Increase Contrast, Reduce Transparency, long content, user locale, alert content-fit, and every supported display arrangement.
- **Do** treat multi-display alert presence and product behavior as binding even when visual composition is refined.

### Don't:

- **Don't** turn literal spacing, radii, widths, heights, search thresholds, line limits, animation durations, or shortcuts into universal tokens.
- **Don't** use orange as a generic marker for anything important, or rely on color alone to distinguish state.
- **Don't** reintroduce the superseded rounded setup feed, a one-off decorative headline, hard-coded locale, or a second configuration surface disguised as onboarding.
- **Don't** wrap every Settings or onboarding group in a card, elevated container, or decorative material.
- **Don't** treat the current centered Strong Alert shell, title-bar styling, or fallback variants as final visual authority; the absence of an operable Strong Alert Close remains binding behavior.
- **Don't** translate this native macOS system into web or enlarged-iOS conventions.
- **Don't** alter product scope, reminder semantics, multi-display presence, sharing visibility, persistence, or alert lifecycle merely to simplify the visual system.

### Revisit Before Canonizing

- Cross-surface icon and color mappings for Active Protection, Pause, No Coverage, stale/unavailable coverage, uncertainty, conflict, and primary selection.
- Menu-bar width, account density, repeated commands, and information compression at longer localized strings.
- Error-stack emphasis and action wording across connection, authorization, refresh, and disconnection failures.
- Alert title-bar/chrome strategy, action-region layout, and parity among primary, fallback, conflict, and additional-display paths.
- Protection Activity metadata density, filtering clarity, and scanability at realistic event volume.
- Multi-display interaction ownership and accessibility, Blocking Mode permission communication, and contrast/material legibility under every macOS accessibility setting.
