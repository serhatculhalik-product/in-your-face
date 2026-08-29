# Out-of-office protection is an explicit global opt-in

**Status**: accepted

**Supersedes**: ADR-0001's unconditional out-of-office exclusion only

Timed Google Calendar out-of-office events remain excluded by default, but one global Out-of-Office Protection preference can make accepted or self-organized occurrences eligible for both Early Reminder and Strong Alert. This supersedes only ADR-0001's unconditional out-of-office exclusion; its Google-only, timed-event, calendar-selection, acceptance, and other exclusion boundaries remain accepted. Default-off preserves the original low-surprise behavior, while one setting for both reminder stages avoids a partial state that would be hard to explain.

Enabling the preference does not newly adopt an out-of-office occurrence already underway. Disabling it immediately ends any active out-of-office protection and removes those events from retained snapshots. The preference itself is ordinary non-Google configuration and may remain in UserDefaults; event data remains governed by ADR-0011's encrypted, bounded retention boundary.
