import Foundation

struct EarlyReminderInteractionBarrierLifecycle: Equatable, Sendable {
    private(set) var isAvailable = false
    private(set) var isActive = false
    private(set) var restoresWindowInteraction = false

    mutating func activated(restoresWindowInteraction: Bool) {
        isAvailable = true
        isActive = true
        self.restoresWindowInteraction = restoresWindowInteraction
    }

    mutating func activationFailed() {
        isAvailable = false
        isActive = false
        restoresWindowInteraction = false
    }

    mutating func disabledBySystem() {
        activationFailed()
    }

    mutating func deactivated() {
        isAvailable = false
        isActive = false
        restoresWindowInteraction = false
    }
}
