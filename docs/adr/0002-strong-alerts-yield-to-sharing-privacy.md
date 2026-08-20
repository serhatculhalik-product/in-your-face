# Strong alerts yield to full-screen sharing privacy

**Status**: superseded by ADR-0004

The product uses a full-screen Strong Alert at a commitment’s start time and may override macOS Focus modes, but it does not expose visual reminders on displays being shared full-screen. Non-shared displays may still show them; if every display is shared, there is no public signal by default and an optional private audio cue may be enabled. This balances the core punctuality promise against the unacceptable risk of exposing private calendar information to an audience.
