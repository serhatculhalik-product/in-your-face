import AppKit

enum AlertPresentationVariant: Equatable, Sendable {
    case earlyReminderNormal
    case earlyReminderFallback
    case strongAlert
    case strongAlertConflict
}

enum AlertPresentationActionSource: Equatable, Sendable {
    case commitmentProtectionFlow
}

enum AlertPresentationSharingPolicy: Equatable, Sendable {
    case visibleDuringDisplaySharing

    var windowSharingType: NSWindow.SharingType {
        .readOnly
    }

    var remainsVisibleDuringDisplaySharing: Bool {
        self == .visibleDuringDisplaySharing
    }
}

struct AlertPresentationContract: Equatable, Sendable {
    let actionSource: AlertPresentationActionSource
    let preservesProtectionWhenSurfaceCloses: Bool
    let sharingPolicy: AlertPresentationSharingPolicy

    var remainsVisibleDuringDisplaySharing: Bool {
        sharingPolicy.remainsVisibleDuringDisplaySharing
    }

    init(variant: AlertPresentationVariant) {
        actionSource = .commitmentProtectionFlow
        preservesProtectionWhenSurfaceCloses = true
        sharingPolicy = .visibleDuringDisplaySharing
    }
}
