import Foundation

struct EarlyReminderPresentationState: Equatable, Sendable {
    private(set) var generation = 0
    private(set) var shouldCloseWhenWindowAppears = false

    mutating func beginPresentation() -> Int {
        generation += 1
        shouldCloseWhenWindowAppears = false
        return generation
    }

    mutating func requestCloseWhenWindowAppears() {
        generation += 1
        shouldCloseWhenWindowAppears = true
    }

    mutating func cancelPendingClose() {
        generation += 1
        shouldCloseWhenWindowAppears = false
    }

    func acceptsPresentationRequest(_ requestGeneration: Int, hasCommitment: Bool) -> Bool {
        generation == requestGeneration && hasCommitment && !shouldCloseWhenWindowAppears
    }
}

struct EarlyReminderWindowTrackingState: Equatable, Sendable {
    private(set) var trackedWindowIDs: Set<ObjectIdentifier> = []

    mutating func register(_ windowID: ObjectIdentifier) {
        trackedWindowIDs.insert(windowID)
    }

    mutating func unregister(_ windowID: ObjectIdentifier) {
        trackedWindowIDs.remove(windowID)
    }

    mutating func unregisterAll() {
        trackedWindowIDs.removeAll()
    }

    func tracks(_ windowID: ObjectIdentifier) -> Bool {
        trackedWindowIDs.contains(windowID)
    }
}
