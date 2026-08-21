import Foundation

enum AlertPresentationLifecycleSurface: Equatable, Sendable {
    case earlyReminderNormal
    case earlyReminderFallback
    case strongAlert
}

struct AlertPresentationLifecycle: Equatable, Sendable {
    private(set) var surface: AlertPresentationLifecycleSurface?
    private(set) var isPresented = false
    private(set) var availableDisplayCount = 0
    private(set) var primaryDisplayIndex: Int?
    private(set) var displayPlan: StrongAlertDisplayPlan?
    private(set) var requiresSurfaceCreation = false
    private(set) var requiresSurfaceRecovery = false
    private(set) var requiresActivation = false

    mutating func present(
        surface: AlertPresentationLifecycleSurface,
        displayCount: Int,
        primaryIndex: Int?,
        surfaceDiscovered: Bool
    ) -> StrongAlertDisplayPlan? {
        self.surface = surface
        availableDisplayCount = max(displayCount, 0)
        primaryDisplayIndex = primaryIndex
        displayPlan = StrongAlertDisplayPlan(
            displayCount: availableDisplayCount,
            primaryIndex: primaryIndex
        )
        requiresSurfaceCreation = !surfaceDiscovered
        requiresSurfaceRecovery = !surfaceDiscovered
        isPresented = surfaceDiscovered && displayPlan != nil
        requiresActivation = isPresented
        return isPresented ? displayPlan : nil
    }

    @discardableResult
    mutating func displayTopologyChanged(
        displayCount: Int,
        primaryIndex: Int?
    ) -> StrongAlertDisplayPlan? {
        availableDisplayCount = max(displayCount, 0)
        primaryDisplayIndex = primaryIndex
        displayPlan = StrongAlertDisplayPlan(
            displayCount: availableDisplayCount,
            primaryIndex: primaryIndex
        )
        requiresSurfaceCreation = isPresented && displayPlan == nil
        requiresSurfaceRecovery = isPresented && displayPlan == nil
        return displayPlan
    }

    mutating func surfaceDisappeared() {
        guard isPresented else { return }
        isPresented = false
        requiresSurfaceCreation = true
        requiresSurfaceRecovery = true
        requiresActivation = false
    }

    mutating func surfaceReappeared(
        displayCount: Int,
        primaryIndex: Int?
    ) {
        guard let surface else { return }
        _ = present(
            surface: surface,
            displayCount: displayCount,
            primaryIndex: primaryIndex,
            surfaceDiscovered: true
        )
    }

    mutating func applicationBecameActive() {
        requiresActivation = isPresented
    }

    mutating func markActivated() {
        requiresActivation = false
    }

    mutating func close() {
        surface = nil
        isPresented = false
        displayPlan = nil
        requiresSurfaceCreation = false
        requiresSurfaceRecovery = false
        requiresActivation = false
    }
}
