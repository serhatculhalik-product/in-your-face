import AppKit
import SwiftUI

extension ProtectionCoveragePresentation.Tone {
    var color: Color {
        switch self {
        case .neutral:
            return Color(nsColor: .secondaryLabelColor)
        case .positive:
            return Color(nsColor: .systemGreen)
        case .caution:
            return Color(nsColor: .systemOrange)
        }
    }
}

struct ProtectionCoverageStatusLabel: View {
    let presentation: ProtectionCoveragePresentation

    var body: some View {
        Label(presentation.label, systemImage: presentation.systemImage)
            .foregroundStyle(presentation.tone.color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.label)
    }
}
