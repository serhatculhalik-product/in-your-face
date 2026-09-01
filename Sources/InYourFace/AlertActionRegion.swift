import AppKit
import CommitmentProtection
import SwiftUI

@MainActor
struct AlertActionRegion: View {
    let presentation: AlertActionPresentation
    let dispatch: (AlertActionPresentation.Intent) -> Bool

    @State private var pendingConfirmation: AlertActionPresentation.Intent?
    @State private var customPauseExpiration = Date().addingTimeInterval(60 * 60)
    @State private var isCustomPausePresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(presentation.actions) { action in
                if action.scope == .allProtection {
                    Divider()
                        .padding(.top, 2)
                }
                actionRow(action)
            }
        }
        .accessibilityElement(children: .contain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert(
            "Stop reminders for this commitment?",
            isPresented: confirmationBinding
        ) {
            Button("Keep reminders", role: .cancel) {
                pendingConfirmation = nil
            }
            Button("Stop reminders", role: .destructive) {
                guard let pendingConfirmation else { return }
                self.pendingConfirmation = nil
                _ = dispatch(pendingConfirmation)
            }
        } message: {
            Text(InterfaceCopy.stopRemindersConfirmationMessage())
        }
        .sheet(isPresented: $isCustomPausePresented) {
            CustomPauseSheet(
                expiration: $customPauseExpiration,
                pause: { duration in
                    dispatch(.pause(duration))
                }
            )
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    pendingConfirmation = nil
                }
            }
        )
    }

    @ViewBuilder
    private func actionRow(_ action: AlertActionPresentation.Action) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                actionControl(action)
                    .fixedSize(horizontal: true, vertical: false)
                consequenceText(action.consequence)
                    .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 5) {
                actionControl(action)
                consequenceText(action.consequence)
            }
        }
    }

    private func consequenceText(_ consequence: String) -> some View {
        Text(consequence)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func actionControl(_ action: AlertActionPresentation.Action) -> some View {
        switch action.control {
        case .button(let intent):
            AlertNativeActionButton(action: action) {
                _ = dispatch(intent)
            }
        case .menu(let choices):
            AlertNativeActionMenu(action: action, choices: choices) { choice in
                switch choice.activation {
                case .dispatch(let intent):
                    _ = dispatch(intent)
                case .presentCustomPause:
                    customPauseExpiration = Date().addingTimeInterval(60 * 60)
                    isCustomPausePresented = true
                }
            }
        case .confirmation(let intent):
            AlertNativeActionButton(action: action) {
                pendingConfirmation = intent
            }
        }
    }
}

@MainActor
private struct AlertNativeActionButton: NSViewRepresentable {
    let action: AlertActionPresentation.Action
    let perform: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(perform: perform)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: action.label,
            target: context.coordinator,
            action: #selector(Coordinator.performAction)
        )
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.cell?.wraps = true
        button.cell?.usesSingleLineMode = false
        button.cell?.lineBreakMode = .byWordWrapping
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.perform = perform
        configureNativeActionControl(button, action: action)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView button: NSButton,
        context: Context
    ) -> CGSize? {
        nativeActionControlSize(
            button,
            label: action.label,
            proposedWidth: proposal.width
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var perform: () -> Void

        init(perform: @escaping () -> Void) {
            self.perform = perform
        }

        @objc func performAction() {
            perform()
        }
    }
}

@MainActor
struct AlertNativeActionMenu: NSViewRepresentable {
    let action: AlertActionPresentation.Action
    let choices: [AlertActionPresentation.Choice]
    let perform: (AlertActionPresentation.Choice) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(perform: perform)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let menu = NSPopUpButton(frame: .zero, pullsDown: true)
        menu.bezelStyle = .rounded
        menu.autoenablesItems = false
        menu.cell?.wraps = true
        menu.cell?.usesSingleLineMode = false
        menu.cell?.lineBreakMode = .byWordWrapping
        return menu
    }

    func updateNSView(_ menu: NSPopUpButton, context: Context) {
        configureNativeActionControl(menu, action: action)
        menu.toolTip = action.label
        context.coordinator.update(
            menu: menu,
            label: action.label,
            choices: choices,
            isEnabled: action.isEnabled,
            perform: perform
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView menu: NSPopUpButton,
        context: Context
    ) -> CGSize? {
        nativeActionControlSize(
            menu,
            label: action.label,
            proposedWidth: proposal.width
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        private struct MenuConfiguration: Equatable {
            let label: String
            let choices: [AlertActionPresentation.Choice]
            let isEnabled: Bool
        }

        var perform: (AlertActionPresentation.Choice) -> Void
        private weak var menu: NSPopUpButton?
        private var latestConfiguration: MenuConfiguration?
        private var renderedConfiguration: MenuConfiguration?
        private var renderedChoices: [AlertActionPresentation.Choice] = []
        private var isTracking = false
        private var isDeferringMenuRebuild = false
        private var needsMenuRebuild = false

        init(perform: @escaping (AlertActionPresentation.Choice) -> Void) {
            self.perform = perform
        }

        func update(
            menu: NSPopUpButton,
            label: String,
            choices: [AlertActionPresentation.Choice],
            isEnabled: Bool,
            perform: @escaping (AlertActionPresentation.Choice) -> Void
        ) {
            let configuration = MenuConfiguration(
                label: label,
                choices: choices,
                isEnabled: isEnabled
            )
            self.menu = menu
            self.perform = perform
            latestConfiguration = configuration
            menu.menu?.delegate = self

            guard configuration != renderedConfiguration else {
                needsMenuRebuild = false
                return
            }
            guard !isTracking, !isDeferringMenuRebuild else {
                needsMenuRebuild = true
                return
            }
            rebuildMenu()
        }

        func menuWillOpen(_ menu: NSMenu) {
            isTracking = true
        }

        func menuDidClose(_ menu: NSMenu) {
            isTracking = false
            isDeferringMenuRebuild = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                isDeferringMenuRebuild = false
                if !isTracking, needsMenuRebuild {
                    rebuildMenu()
                }
            }
        }

        @objc func performChoice(_ sender: NSMenuItem) {
            guard renderedChoices.indices.contains(sender.tag) else { return }
            perform(renderedChoices[sender.tag])
        }

        private func rebuildMenu() {
            guard let menu, let configuration = latestConfiguration else { return }

            menu.removeAllItems()
            let titleItem = NSMenuItem(
                title: configuration.label,
                action: nil,
                keyEquivalent: ""
            )
            titleItem.isEnabled = configuration.isEnabled
            menu.menu?.addItem(titleItem)
            for (index, choice) in configuration.choices.enumerated() {
                let item = NSMenuItem(
                    title: choice.label,
                    action: #selector(performChoice(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.isEnabled = configuration.isEnabled
                menu.menu?.addItem(item)
            }
            menu.selectItem(at: 0)
            menu.menu?.delegate = self
            renderedChoices = configuration.choices
            renderedConfiguration = configuration
            needsMenuRebuild = false
        }
    }
}

@MainActor
private func configureNativeActionControl(
    _ control: NSButton,
    action: AlertActionPresentation.Action
) {
    control.title = action.label
    control.isEnabled = action.isEnabled
    control.keyEquivalentModifierMask = []
    control.keyEquivalent = action.keyActivation == .defaultAction ? "\r" : ""
    control.bezelColor = action.emphasis == .accent ? .controlAccentColor : nil
    control.contentTintColor = action.emphasis == .accent ? .white : nil
    control.setAccessibilityLabel(action.accessibilityLabel)
    control.setAccessibilityHelp(action.accessibilityHint)
}

@MainActor
private func nativeActionControlSize(
    _ control: NSButton,
    label: String,
    proposedWidth: CGFloat?
) -> CGSize {
    let intrinsicSize = control.intrinsicContentSize
    guard let proposedWidth,
          proposedWidth.isFinite,
          proposedWidth > 0,
          proposedWidth < intrinsicSize.width else {
        return intrinsicSize
    }
    let font = control.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let singleLineTitleSize = (label as NSString).size(withAttributes: [.font: font])
    let horizontalChrome = max(20, intrinsicSize.width - singleLineTitleSize.width)
    let verticalChrome = max(10, intrinsicSize.height - singleLineTitleSize.height)
    let titleWidth = max(1, proposedWidth - horizontalChrome)
    let titleBounds = (label as NSString).boundingRect(
        with: NSSize(width: titleWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: font]
    )
    return CGSize(
        width: proposedWidth,
        height: max(intrinsicSize.height, ceil(titleBounds.height + verticalChrome))
    )
}
