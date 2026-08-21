import CommitmentProtection

@MainActor
struct EarlyReminderActionHandlers {
    let clear: () -> Bool
    let snooze: (Int) -> Bool
    let dismiss: () -> Bool

    init(
        clear: @escaping () -> Bool,
        snooze: @escaping (Int) -> Bool,
        dismiss: @escaping () -> Bool
    ) {
        self.clear = clear
        self.snooze = snooze
        self.dismiss = dismiss
    }

    init(flow: CommitmentProtectionFlow, commitment: CalendarEvent) {
        self.init(
            clear: { flow.clearEarlyReminder(for: commitment) },
            snooze: { minutes in flow.snoozeEarlyReminder(minutes: minutes, for: commitment) },
            dismiss: { flow.dismissCommitment(for: commitment) }
        )
    }
}
