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
    private static let launchAtLoginChoiceKey = "in-your-face.launch-at-login-choice-recorded"

    @Published private(set) var phase: Phase
    @Published private(set) var isInitialLaunchResolved = false
    @Published private(set) var didChooseLaunchAtLogin: Bool

    private let stateStore: UserDefaults
    private let allowsPreferenceMutation: @MainActor () -> Bool

    init(
        stateStore: UserDefaults = .standard,
        allowsPreferenceMutation: @escaping @MainActor () -> Bool = { true }
    ) {
        self.stateStore = stateStore
        self.allowsPreferenceMutation = allowsPreferenceMutation
        let savedValue = stateStore.object(forKey: Self.completionVersionKey) as? NSNumber
        if let savedValue, savedValue.intValue >= Self.currentCompletionVersion {
            phase = .completed
        } else {
            phase = savedValue.flatMap { Phase(rawValue: $0.intValue) } ?? .pending
        }
        didChooseLaunchAtLogin = stateStore.bool(forKey: Self.launchAtLoginChoiceKey)
    }

    var initialSurface: InitialSurface {
        guard isInitialLaunchResolved else { return .waiting }
        if phase == .pending || (phase == .completed && !didChooseLaunchAtLogin) {
            return .onboarding
        }
        return .menuBarOnly
    }

    var isCompleted: Bool {
        phase == .completed
    }

    var needsSetup: Bool {
        isInitialLaunchResolved && (!isCompleted || !didChooseLaunchAtLogin)
    }

    var canResolveReadiness: Bool {
        allowsPreferenceMutation()
    }

    func resolveInitialLaunch(hasConfiguredProtection: Bool) {
        guard allowsPreferenceMutation() else { return }
        guard !isInitialLaunchResolved else { return }

        if stateStore.object(forKey: Self.completionVersionKey) == nil {
            phase = hasConfiguredProtection ? .completed : .pending
            persistPhase()
        }
        isInitialLaunchResolved = true
    }

    func resume() {
        guard allowsPreferenceMutation() else { return }
        guard isInitialLaunchResolved else { return }
        if isCompleted && !didChooseLaunchAtLogin {
            return
        }
        guard !isCompleted else { return }
        phase = .pending
        persistPhase()
    }

    @discardableResult
    func deferUntilRequested() -> Bool {
        guard allowsPreferenceMutation() else { return false }
        guard !isCompleted else { return false }
        phase = .deferred
        persistPhase()
        return true
    }

    @discardableResult
    func deferReadinessUntilRequested() -> Bool {
        guard allowsPreferenceMutation() else { return false }
        guard !isCompleted || !didChooseLaunchAtLogin else { return false }
        phase = .deferred
        didChooseLaunchAtLogin = true
        stateStore.set(true, forKey: Self.launchAtLoginChoiceKey)
        persistPhase()
        return true
    }

    @discardableResult
    func complete() -> Bool {
        guard allowsPreferenceMutation() else { return false }
        phase = .completed
        didChooseLaunchAtLogin = true
        stateStore.set(true, forKey: Self.launchAtLoginChoiceKey)
        persistPhase()
        return true
    }

    private func persistPhase() {
        let value = phase == .completed ? Self.currentCompletionVersion : phase.rawValue
        stateStore.set(value, forKey: Self.completionVersionKey)
    }
}
