import Foundation

struct EarlyReminderInteractionBarrierLifecycle: Equatable, Sendable {
    private(set) var isActive = false
    private(set) var restoresWindowInteraction = false

    mutating func activated(restoresWindowInteraction: Bool) {
        isActive = true
        self.restoresWindowInteraction = restoresWindowInteraction
    }

    mutating func deactivated() {
        isActive = false
        restoresWindowInteraction = false
    }
}
