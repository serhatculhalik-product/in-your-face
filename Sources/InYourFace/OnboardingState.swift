import Combine
import Foundation

@MainActor
final class OnboardingState: ObservableObject {
    enum Phase: Int, Equatable {
        case deferred = -1
        case pending = 0
        case completed = 1
    }

    enum InitialSurface: Equatable {
        case waiting
        case onboarding
        case menuBarOnly
    }

    static let currentCompletionVersion = 1
    private static let completionVersionKey = "in-your-face.onboarding-completed-version"
    private static let testAlertHandledKey = "in-your-face.onboarding-test-alert-handled"

    @Published private(set) var phase: Phase
    @Published private(set) var isInitialLaunchResolved = false
    @Published private(set) var didHandleTestAlert: Bool

    private let stateStore: UserDefaults

    init(stateStore: UserDefaults = .standard) {
        self.stateStore = stateStore
        let savedValue = stateStore.object(forKey: Self.completionVersionKey) as? NSNumber
        if let savedValue, savedValue.intValue >= Self.currentCompletionVersion {
            phase = .completed
        } else {
            phase = savedValue.flatMap { Phase(rawValue: $0.intValue) } ?? .pending
        }
        didHandleTestAlert = stateStore.bool(forKey: Self.testAlertHandledKey)
    }

    var initialSurface: InitialSurface {
        guard isInitialLaunchResolved else { return .waiting }
        return phase == .pending ? .onboarding : .menuBarOnly
    }

    var isCompleted: Bool {
        phase == .completed
    }

    var needsSetup: Bool {
        isInitialLaunchResolved && !isCompleted
    }

    func resolveInitialLaunch(hasConfiguredProtection: Bool) {
        guard !isInitialLaunchResolved else { return }

        if stateStore.object(forKey: Self.completionVersionKey) == nil {
            phase = hasConfiguredProtection ? .completed : .pending
            persistPhase()
        }
        isInitialLaunchResolved = true
    }

    func resume() {
        guard isInitialLaunchResolved, !isCompleted else { return }
        phase = .pending
        persistPhase()
    }

    func deferUntilRequested() {
        guard !isCompleted else { return }
        phase = .deferred
        persistPhase()
    }

    func markTestAlertHandled() {
        didHandleTestAlert = true
        stateStore.set(true, forKey: Self.testAlertHandledKey)
    }

    @discardableResult
    func complete() -> Bool {
        guard didHandleTestAlert else { return false }
        phase = .completed
        persistPhase()
        return true
    }

    private func persistPhase() {
        let value = phase == .completed ? Self.currentCompletionVersion : phase.rawValue
        stateStore.set(value, forKey: Self.completionVersionKey)
    }
}
