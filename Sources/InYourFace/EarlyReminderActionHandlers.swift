import CommitmentProtection

@MainActor
struct EarlyReminderActionHandlers {
    let clear: () -> Bool
    let snooze: (Int) -> Bool
    let dismiss: () -> Bool
    let selectPrimary: (CalendarEvent) -> Bool

    init(
        clear: @escaping () -> Bool,
        snooze: @escaping (Int) -> Bool,
        dismiss: @escaping () -> Bool,
        selectPrimary: @escaping (CalendarEvent) -> Bool
    ) {
        self.clear = clear
        self.snooze = snooze
        self.dismiss = dismiss
        self.selectPrimary = selectPrimary
    }

    init(flow: CommitmentProtectionFlow, commitment: CalendarEvent) {
        self.init(
            clear: { flow.clearEarlyReminder(for: commitment) },
            snooze: { minutes in flow.snoozeEarlyReminder(minutes: minutes, for: commitment) },
            dismiss: { flow.dismissCommitment(for: commitment) },
            selectPrimary: { conflictCommitment in flow.selectPrimary(for: conflictCommitment) }
        )
    }

    static func normal(flow: CommitmentProtectionFlow, commitment: CalendarEvent) -> Self {
        Self(flow: flow, commitment: commitment)
    }

    static func fallback(flow: CommitmentProtectionFlow, commitment: CalendarEvent) -> Self {
        Self(flow: flow, commitment: commitment)
    }
}
