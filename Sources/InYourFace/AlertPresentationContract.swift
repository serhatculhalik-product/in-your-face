enum AlertPresentationVariant: Equatable, Sendable {
    case earlyReminderNormal
    case earlyReminderFallback
    case strongAlert
    case strongAlertConflict
}

enum AlertPresentationActionSource: Equatable, Sendable {
    case commitmentProtectionFlow
}

struct AlertPresentationContract: Equatable, Sendable {
    let actionSource: AlertPresentationActionSource
    let preservesProtectionWhenSurfaceCloses: Bool
    let remainsVisibleDuringDisplaySharing: Bool

    init(variant: AlertPresentationVariant) {
        actionSource = .commitmentProtectionFlow
        preservesProtectionWhenSurfaceCloses = true
        remainsVisibleDuringDisplaySharing = true
    }
}
