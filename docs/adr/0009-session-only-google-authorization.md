# Google authorization is session-only

**Status**: superseded by ADR-0010

Google OAuth access and refresh tokens are held only in memory and are discarded when In Your Face quits. Non-secret account metadata, Monitored Calendar choices, occurrence-local decisions, and Protection Activity may remain persisted. After launch or relaunch, saved accounts enter Calendar Access Required until the user explicitly reconnects each account; start at login opens the app but does not make protection active by itself.

The app does not read, write, migrate, or delete macOS Keychain items, and its package requires no Keychain entitlement or fallback. Legacy UserDefaults refresh-token entries are removed without restoring them. Credentials written to Keychain by an older build remain orphaned; removing them is a manual user action because automated cleanup would cross the no-Keychain-access boundary.

This deliberately trades automatic protection recovery after quit or relaunch for a smaller credential-storage footprint. Sleep, lock, and temporary in-session recovery continue while authorization remains valid. The interface must disclose the session boundary before connection, never report Active Protection without current authorization, and provide targeted reconnection without replaying onboarding.
