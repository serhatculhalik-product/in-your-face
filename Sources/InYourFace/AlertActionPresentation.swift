import CommitmentProtection
import Foundation

struct AlertActionPresentation: Equatable, Sendable {
    enum Context: Equatable, Sendable {
        case earlyReminder(
            snoozeOptionsMinutes: [Int],
            canSnooze: Bool,
            actionContext: ConflictActionContext? = nil
        )
        case strongAlert(primary: StrongAlertImmediateAction, repeatIntervalMinutes: Int)
        case strongConflictCommitment(
            primary: StrongAlertImmediateAction,
            actionContext: ConflictActionContext
        )
        case strongConflictSurface(repeatIntervalMinutes: Int, canJoin: Bool)
        case conflictSelection(actionContext: ConflictActionContext)
    }

    struct ConflictActionContext: Equatable, Sendable {
        let commitmentTitle: String
        let localStartTime: String?
        let provenance: String?
        let optionPosition: String?

        init(
            commitmentTitle: String,
            localStartTime: String? = nil,
            provenance: String? = nil,
            optionPosition: String? = nil
        ) {
            self.commitmentTitle = commitmentTitle
            self.localStartTime = localStartTime
            self.provenance = provenance
            self.optionPosition = optionPosition
        }

        var accessibilityDescription: String {
            [commitmentTitle, localStartTime, provenance, optionPosition]
                .compactMap { value in
                    guard let value else { return nil }
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                .joined(separator: ", ")
        }
    }

    enum StrongAlertImmediateAction: Equatable, Sendable {
        case join(URL)
        case chooseLink([URL])
        case stopReminders

        static func resolve(
            meetingLinks: [URL],
            primaryMeetingLink: URL?
        ) -> Self {
            if meetingLinks.isEmpty {
                return .stopReminders
            }
            if let primaryMeetingLink {
                return .join(primaryMeetingLink)
            }
            if meetingLinks.count == 1, let meetingLink = meetingLinks.first {
                return .join(meetingLink)
            }
            return .chooseLink(meetingLinks)
        }
    }

    enum Role: Equatable, Hashable, Sendable {
        case closeForNow
        case snooze
        case join
        case chooseLink
        case makePrimary
        case handled
        case stopReminders
        case gotIt
        case pause
    }

    enum Scope: Equatable, Sendable {
        case occurrence
        case conflictSelection
        case surface
        case allProtection
    }

    enum Emphasis: Equatable, Sendable {
        case standard
        case accent
    }

    enum KeyActivation: Equatable, Sendable {
        case explicitOnly
        case defaultAction
    }

    enum Intent: Equatable, Sendable {
        case closeForNow
        case snooze(minutes: Int)
        case join(URL)
        case makePrimary
        case handled
        case stopReminders
        case gotIt
        case pause(PauseDuration)
    }

    enum Control: Equatable, Sendable {
        case button(Intent)
        case menu([Choice])
        case confirmation(Intent)
    }

    struct Choice: Equatable, Identifiable, Sendable {
        enum Activation: Equatable, Sendable {
            case dispatch(Intent)
            case presentCustomPause
        }

        let id: String
        let label: String
        let activation: Activation

        init(id: String, label: String, intent: Intent) {
            self.init(id: id, label: label, activation: .dispatch(intent))
        }

        init(id: String, label: String, activation: Activation) {
            self.id = id
            self.label = label
            self.activation = activation
        }
    }

    struct Action: Equatable, Identifiable, Sendable {
        var id: Role { role }

        let role: Role
        let scope: Scope
        let control: Control
        let label: String
        let consequence: String
        let accessibilityLabel: String
        let accessibilityHint: String
        let emphasis: Emphasis
        let keyActivation: KeyActivation
        let isEnabled: Bool
    }

    let actions: [Action]

    var defaultAction: Action? {
        actions.first { $0.keyActivation == .defaultAction }
    }

    init(
        context: Context,
        locale: Locale = .autoupdatingCurrent
    ) {
        switch context {
        case .earlyReminder(
            let snoozeOptionsMinutes,
            let canSnooze,
            let actionContext
        ):
            let closeConsequence = InterfaceCopy.closeForNowConsequence(locale: locale)
            let snoozeConsequence = InterfaceCopy.snoozeConsequence(locale: locale)
            let stopConsequence = InterfaceCopy.stopRemindersConsequence(locale: locale)
            actions = [
                Action(
                    role: .closeForNow,
                    scope: .surface,
                    control: .button(.closeForNow),
                    label: "Close for now",
                    consequence: closeConsequence,
                    accessibilityLabel: actionContext.map {
                        "Close \($0.accessibilityDescription) for now"
                    } ?? "Close for now",
                    accessibilityHint: closeConsequence,
                    emphasis: .accent,
                    keyActivation: .defaultAction,
                    isEnabled: true
                ),
                Action(
                    role: .snooze,
                    scope: .occurrence,
                    control: .menu(
                        snoozeOptionsMinutes.map { minutes in
                            Choice(
                                id: "snooze-\(minutes)",
                                label: InterfaceCopy.minuteDuration(minutes, locale: locale),
                                intent: .snooze(minutes: minutes)
                            )
                        }
                    ),
                    label: "Snooze",
                    consequence: snoozeConsequence,
                    accessibilityLabel: actionContext.map {
                        "Snooze \($0.accessibilityDescription)"
                    } ?? "Snooze",
                    accessibilityHint: snoozeConsequence,
                    emphasis: .standard,
                    keyActivation: .explicitOnly,
                    isEnabled: canSnooze
                ),
                Action(
                    role: .stopReminders,
                    scope: .occurrence,
                    control: .confirmation(.stopReminders),
                    label: "Stop reminders",
                    consequence: stopConsequence,
                    accessibilityLabel: actionContext.map {
                        "Stop reminders for \($0.accessibilityDescription)"
                    } ?? "Stop reminders",
                    accessibilityHint: stopConsequence,
                    emphasis: .standard,
                    keyActivation: .explicitOnly,
                    isEnabled: true
                ),
            ]
        case .strongAlert(let primary, let repeatIntervalMinutes):
            let primaryAction = Self.strongImmediateAction(
                primary,
                keyActivation: .defaultAction,
                locale: locale
            )
            var resolvedActions = [
                primaryAction,
                Self.handledAction(locale: locale),
            ]
            if primary != .stopReminders {
                resolvedActions.append(Self.stopRemindersAction(locale: locale))
            }
            resolvedActions.append(contentsOf: [
                Self.gotItAction(
                    repeatIntervalMinutes: repeatIntervalMinutes,
                    locale: locale,
                    canJoin: primary != .stopReminders
                ),
                Self.pauseAction(locale: locale),
            ])
            actions = resolvedActions
        case .strongConflictCommitment(let primary, let actionContext):
            var resolvedActions = [
                Self.strongImmediateAction(
                    primary,
                    keyActivation: .explicitOnly,
                    actionContext: actionContext,
                    locale: locale
                ),
                Self.makePrimaryAction(
                    actionContext: actionContext,
                    locale: locale
                ),
                Self.handledAction(
                    actionContext: actionContext,
                    locale: locale
                ),
            ]
            if primary != .stopReminders {
                resolvedActions.append(
                    Self.stopRemindersAction(
                        actionContext: actionContext,
                        locale: locale
                    )
                )
            }
            actions = resolvedActions
        case .strongConflictSurface(let repeatIntervalMinutes, let canJoin):
            actions = [
                Self.gotItAction(
                    repeatIntervalMinutes: repeatIntervalMinutes,
                    locale: locale,
                    canJoin: canJoin
                ),
                Self.pauseAction(locale: locale),
            ]
        case .conflictSelection(let actionContext):
            actions = [
                Self.makePrimaryAction(
                    actionContext: actionContext,
                    locale: locale
                ),
            ]
        }
    }
}

private extension AlertActionPresentation {
    static func strongImmediateAction(
        _ primary: StrongAlertImmediateAction,
        keyActivation: KeyActivation,
        actionContext: ConflictActionContext? = nil,
        locale: Locale
    ) -> Action {
        switch primary {
        case .join(let url):
            let consequence = InterfaceCopy.joinConsequence(locale: locale)
            return Action(
                role: .join,
                scope: .occurrence,
                control: .button(.join(url)),
                label: "Join",
                consequence: consequence,
                accessibilityLabel: actionContext.map {
                    "Join \($0.accessibilityDescription)"
                } ?? "Join",
                accessibilityHint: consequence,
                emphasis: .accent,
                keyActivation: keyActivation,
                isEnabled: true
            )
        case .chooseLink(let meetingLinks):
            let consequence = InterfaceCopy.joinConsequence(locale: locale)
            let meetingLinkChoices = InterfaceCopy.meetingLinkChoices(
                meetingLinks,
                locale: locale
            )
            return Action(
                role: .chooseLink,
                scope: .occurrence,
                control: .menu(
                    meetingLinkChoices.map { choice in
                        Choice(
                            id: choice.url.absoluteString,
                            label: choice.title,
                            intent: .join(choice.url)
                        )
                    }
                ),
                label: "Choose Link",
                consequence: consequence,
                accessibilityLabel: actionContext.map {
                    "Choose a meeting link for \($0.accessibilityDescription)"
                } ?? "Choose Link",
                accessibilityHint: consequence,
                emphasis: .accent,
                keyActivation: keyActivation,
                isEnabled: !meetingLinkChoices.isEmpty
            )
        case .stopReminders:
            return stopRemindersAction(
                emphasis: .accent,
                keyActivation: keyActivation,
                actionContext: actionContext,
                locale: locale
            )
        }
    }

    static func makePrimaryAction(
        actionContext: ConflictActionContext,
        locale: Locale
    ) -> Action {
        let consequence = InterfaceCopy.makePrimaryConsequence(locale: locale)
        return Action(
            role: .makePrimary,
            scope: .conflictSelection,
            control: .button(.makePrimary),
            label: "Make primary",
            consequence: consequence,
            accessibilityLabel: "Make \(actionContext.accessibilityDescription) primary",
            accessibilityHint: consequence,
            emphasis: .standard,
            keyActivation: .explicitOnly,
            isEnabled: true
        )
    }

    static func handledAction(
        actionContext: ConflictActionContext? = nil,
        locale: Locale
    ) -> Action {
        let consequence = InterfaceCopy.handledConsequence(locale: locale)
        return Action(
            role: .handled,
            scope: .occurrence,
            control: .button(.handled),
            label: "I joined another way",
            consequence: consequence,
            accessibilityLabel: actionContext.map {
                "I joined \($0.accessibilityDescription) another way"
            } ?? "I joined another way",
            accessibilityHint: consequence,
            emphasis: .standard,
            keyActivation: .explicitOnly,
            isEnabled: true
        )
    }

    static func stopRemindersAction(
        emphasis: Emphasis = .standard,
        keyActivation: KeyActivation = .explicitOnly,
        actionContext: ConflictActionContext? = nil,
        locale: Locale
    ) -> Action {
        let consequence = InterfaceCopy.stopRemindersConsequence(locale: locale)
        return Action(
            role: .stopReminders,
            scope: .occurrence,
            control: .confirmation(.stopReminders),
            label: "Stop reminders",
            consequence: consequence,
            accessibilityLabel: actionContext.map {
                "Stop reminders for \($0.accessibilityDescription)"
            } ?? "Stop reminders",
            accessibilityHint: consequence,
            emphasis: emphasis,
            keyActivation: keyActivation,
            isEnabled: true
        )
    }

    static func gotItAction(
        repeatIntervalMinutes: Int,
        locale: Locale,
        canJoin: Bool
    ) -> Action {
        let consequence = InterfaceCopy.strongAlertRepeatConsequence(
            minutes: repeatIntervalMinutes,
            canJoin: canJoin,
            locale: locale
        )
        return Action(
            role: .gotIt,
            scope: .surface,
            control: .button(.gotIt),
            label: "Got it",
            consequence: consequence,
            accessibilityLabel: "Got it",
            accessibilityHint: consequence,
            emphasis: .standard,
            keyActivation: .explicitOnly,
            isEnabled: true
        )
    }

    static func pauseAction(locale: Locale) -> Action {
        let consequence = InterfaceCopy.pauseAllProtectionDetail(locale: locale)
        return Action(
            role: .pause,
            scope: .allProtection,
            control: .menu([
                Choice(
                    id: "pause-one-hour",
                    label: "Pause all for 1 hour",
                    intent: .pause(.oneHour)
                ),
                Choice(
                    id: "pause-end-of-day",
                    label: "Pause all until end of day",
                    intent: .pause(.endOfDay)
                ),
                Choice(
                    id: "pause-custom",
                    label: "Choose when to resume all protection…",
                    activation: .presentCustomPause
                ),
            ]),
            label: "Pause All Protection",
            consequence: consequence,
            accessibilityLabel: "Pause All Protection",
            accessibilityHint: consequence,
            emphasis: .standard,
            keyActivation: .explicitOnly,
            isEnabled: true
        )
    }
}
