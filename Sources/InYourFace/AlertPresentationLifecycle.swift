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
    private(set) var isInteractionBarrierAvailable = false
    private(set) var hasDiscoveredSurface = false

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
        hasDiscoveredSurface = surfaceDiscovered
        requiresSurfaceCreation = !surfaceDiscovered
        requiresSurfaceRecovery = !surfaceDiscovered || displayPlan == nil
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
        if displayPlan == nil {
            isPresented = false
            requiresActivation = false
            requiresSurfaceCreation = hasDiscoveredSurface
            requiresSurfaceRecovery = true
        } else if hasDiscoveredSurface {
            isPresented = true
            requiresSurfaceCreation = false
            requiresSurfaceRecovery = false
            requiresActivation = true
        } else {
            requiresSurfaceCreation = !hasDiscoveredSurface || displayPlan == nil
            requiresSurfaceRecovery = !hasDiscoveredSurface || displayPlan == nil
        }
        return displayPlan
    }

    mutating func surfaceDisappeared() {
        isPresented = false
        hasDiscoveredSurface = false
        requiresSurfaceCreation = true
        requiresSurfaceRecovery = true
        requiresActivation = false
        isInteractionBarrierAvailable = false
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

    mutating func applicationActivationChanged() {
        requiresActivation = isPresented
    }

    mutating func markActivated() {
        requiresActivation = false
    }

    mutating func interactionBarrierAvailabilityChanged(_ isAvailable: Bool) {
        isInteractionBarrierAvailable = isAvailable
    }

    mutating func close() {
        surface = nil
        isPresented = false
        hasDiscoveredSurface = false
        displayPlan = nil
        requiresSurfaceCreation = false
        requiresSurfaceRecovery = false
        requiresActivation = false
        isInteractionBarrierAvailable = false
    }
}
