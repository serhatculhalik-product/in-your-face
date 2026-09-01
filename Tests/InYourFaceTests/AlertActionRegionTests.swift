import AppKit
import CommitmentProtection
import Foundation
import SwiftUI
import XCTest
@testable import InYourFace

@MainActor
final class AlertActionRegionTests: XCTestCase {
    func testLinkedStrongAlertHasOneOrderedDefaultAndSeparatedPause() throws {
        let meetingLink = try XCTUnwrap(URL(string: "https://meet.example.com/customer-review"))
        let presentation = AlertActionPresentation(
            context: .strongAlert(
                primary: .join(meetingLink),
                repeatIntervalMinutes: 1
            ),
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            presentation.actions.map(\.role),
            [.join, .handled, .stopReminders, .gotIt, .pause]
        )
        XCTAssertEqual(
            presentation.actions.filter { $0.emphasis == .accent }.map(\.role),
            [.join]
        )
        XCTAssertEqual(presentation.defaultAction?.role, .join)
        XCTAssertEqual(presentation.actions.last?.scope, .allProtection)
        XCTAssertEqual(
            presentation.actions.first { $0.role == .gotIt }?.consequence,
            "Closes this alert now. Protection stays active, and Strong Alert returns in 1 minute unless you Join, choose I joined another way, Stop reminders, or Pause All Protection."
        )
    }

    func testEarlyReminderPrioritizesCloseAndKeepsSnoozeAndStopInOneRegion() {
        let presentation = AlertActionPresentation(
            context: .earlyReminder(
                snoozeOptionsMinutes: [5, 10, 15, 30],
                canSnooze: false
            ),
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            presentation.actions.map(\.role),
            [.closeForNow, .snooze, .stopReminders]
        )
        XCTAssertEqual(presentation.defaultAction?.role, .closeForNow)
        XCTAssertEqual(
            presentation.actions.filter { $0.emphasis == .accent }.map(\.role),
            [.closeForNow]
        )
        XCTAssertEqual(
            presentation.actions.first { $0.role == .snooze }?.control,
            .menu([
                .init(id: "snooze-5", label: "5 minutes", intent: .snooze(minutes: 5)),
                .init(id: "snooze-10", label: "10 minutes", intent: .snooze(minutes: 10)),
                .init(id: "snooze-15", label: "15 minutes", intent: .snooze(minutes: 15)),
                .init(id: "snooze-30", label: "30 minutes", intent: .snooze(minutes: 30)),
            ])
        )
        XCTAssertFalse(
            presentation.actions.first { $0.role == .snooze }?.isEnabled ?? true
        )
        XCTAssertEqual(
            presentation.actions.first { $0.role == .closeForNow }?.consequence,
            "Close for now hides this Early Reminder. Strong Alert still appears when the commitment begins."
        )
        XCTAssertEqual(
            presentation.actions.first { $0.role == .snooze }?.consequence,
            "Snooze delays both reminders for this occurrence and can continue past its start time."
        )
    }

    func testEarlyConflictActionsRetainCompleteCommitmentContext() {
        let actionContext = AlertActionPresentation.ConflictActionContext(
            commitmentTitle: "Customer review",
            localStartTime: "Today at 10:00",
            provenance: "Monitored Calendar Work",
            optionPosition: "option 1 of 2"
        )
        let presentation = AlertActionPresentation(
            context: .earlyReminder(
                snoozeOptionsMinutes: [5],
                canSnooze: true,
                actionContext: actionContext
            )
        )

        XCTAssertEqual(presentation.actions.map(\.role), [
            .closeForNow,
            .snooze,
            .stopReminders,
        ])
        XCTAssertTrue(
            presentation.actions.allSatisfy {
                $0.accessibilityLabel.contains(actionContext.accessibilityDescription)
            }
        )
    }

    func testMultipleLinkStrongAlertUsesChooseLinkAsItsOnlyDefault() throws {
        let firstLink = try XCTUnwrap(URL(string: "https://zoom.us/j/first"))
        let secondLink = try XCTUnwrap(URL(string: "https://meet.google.com/second"))
        let presentation = AlertActionPresentation(
            context: .strongAlert(
                primary: .chooseLink([firstLink, secondLink]),
                repeatIntervalMinutes: 3
            )
        )

        XCTAssertEqual(presentation.actions.first?.role, .chooseLink)
        XCTAssertEqual(presentation.actions.first?.label, "Choose Link")
        XCTAssertEqual(presentation.defaultAction?.role, .chooseLink)
        XCTAssertEqual(
            presentation.actions.filter { $0.emphasis == .accent }.map(\.role),
            [.chooseLink]
        )
        XCTAssertEqual(
            presentation.actions.first?.control,
            .menu([
                .init(id: firstLink.absoluteString, label: "Join with Zoom", intent: .join(firstLink)),
                .init(id: secondLink.absoluteString, label: "Join with Google Meet", intent: .join(secondLink)),
            ])
        )
    }

    func testStrongImmediateActionResolutionUsesOneGrammarForEveryStrongAlertVariant() throws {
        let firstLink = try XCTUnwrap(URL(string: "https://zoom.us/j/first"))
        let secondLink = try XCTUnwrap(URL(string: "https://meet.google.com/second"))

        XCTAssertEqual(
            AlertActionPresentation.StrongAlertImmediateAction.resolve(
                meetingLinks: [],
                primaryMeetingLink: nil
            ),
            .stopReminders
        )
        XCTAssertEqual(
            AlertActionPresentation.StrongAlertImmediateAction.resolve(
                meetingLinks: [firstLink],
                primaryMeetingLink: nil
            ),
            .join(firstLink)
        )
        XCTAssertEqual(
            AlertActionPresentation.StrongAlertImmediateAction.resolve(
                meetingLinks: [firstLink, secondLink],
                primaryMeetingLink: secondLink
            ),
            .join(secondLink)
        )
        XCTAssertEqual(
            AlertActionPresentation.StrongAlertImmediateAction.resolve(
                meetingLinks: [firstLink, secondLink],
                primaryMeetingLink: nil
            ),
            .chooseLink([firstLink, secondLink])
        )
    }

    func testLinklessStrongAlertPromotesConfirmationProtectedStopReminders() {
        let presentation = AlertActionPresentation(
            context: .strongAlert(
                primary: .stopReminders,
                repeatIntervalMinutes: 5
            )
        )

        XCTAssertEqual(
            presentation.actions.map(\.role),
            [.stopReminders, .handled, .gotIt, .pause]
        )
        XCTAssertEqual(presentation.defaultAction?.role, .stopReminders)
        XCTAssertEqual(
            presentation.actions.first?.control,
            .confirmation(.stopReminders)
        )
        XCTAssertEqual(presentation.actions.first?.emphasis, .accent)
        XCTAssertEqual(
            presentation.actions.first?.consequence,
            InterfaceCopy.stopRemindersConsequence(
                locale: Locale(identifier: "en_US")
            )
        )
    }

    func testEqualConflictCommitmentHasLocalAccentWithoutAGlobalDefault() throws {
        let meetingLink = try XCTUnwrap(URL(string: "https://meet.example.com/conflict"))
        let actionContext = AlertActionPresentation.ConflictActionContext(
            commitmentTitle: "Customer review",
            localStartTime: "Today at 10:00",
            provenance: "Monitored Calendar Work",
            optionPosition: "option 1 of 2"
        )
        let presentation = AlertActionPresentation(
            context: .strongConflictCommitment(
                primary: .join(meetingLink),
                actionContext: actionContext
            )
        )

        XCTAssertEqual(
            presentation.actions.map(\.role),
            [.join, .makePrimary, .handled, .stopReminders]
        )
        XCTAssertEqual(
            presentation.actions.filter { $0.emphasis == .accent }.map(\.role),
            [.join]
        )
        XCTAssertNil(presentation.defaultAction)
        XCTAssertTrue(
            presentation.actions.allSatisfy { $0.keyActivation == .explicitOnly }
        )
        XCTAssertEqual(
            presentation.actions.first { $0.role == .join }?.accessibilityLabel,
            "Join \(actionContext.accessibilityDescription)"
        )
        XCTAssertEqual(
            presentation.actions.first { $0.role == .makePrimary }?.accessibilityLabel,
            "Make \(actionContext.accessibilityDescription) primary"
        )
    }

    func testEqualConflictKeepsEquivalentGrammarForEveryLinkState() throws {
        let firstLink = try XCTUnwrap(URL(string: "https://zoom.us/j/equal"))
        let secondLink = try XCTUnwrap(URL(string: "https://meet.google.com/equal"))
        let cases: [(AlertActionPresentation.StrongAlertImmediateAction, [AlertActionPresentation.Role])] = [
            (.join(firstLink), [.join, .makePrimary, .handled, .stopReminders]),
            (
                .chooseLink([firstLink, secondLink]),
                [.chooseLink, .makePrimary, .handled, .stopReminders]
            ),
            (.stopReminders, [.stopReminders, .makePrimary, .handled]),
        ]

        for (primary, expectedRoles) in cases {
            let presentation = AlertActionPresentation(
                context: .strongConflictCommitment(
                    primary: primary,
                    actionContext: .init(commitmentTitle: "Equal commitment")
                )
            )

            XCTAssertEqual(presentation.actions.map(\.role), expectedRoles)
            XCTAssertEqual(
                presentation.actions.filter { $0.emphasis == .accent }.count,
                1
            )
            XCTAssertEqual(
                presentation.actions.first { $0.role == .makePrimary }?.emphasis,
                .standard
            )
            XCTAssertNil(presentation.defaultAction)
        }
    }

    func testEqualConflictSharesOneSurfaceCloseAndOneGlobalPause() {
        let presentation = AlertActionPresentation(
            context: .strongConflictSurface(
                repeatIntervalMinutes: 1,
                canJoin: true
            ),
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(presentation.actions.map(\.role), [.gotIt, .pause])
        XCTAssertEqual(presentation.actions.map(\.scope), [.surface, .allProtection])
        XCTAssertNil(presentation.defaultAction)
        XCTAssertTrue(
            presentation.actions.allSatisfy { $0.emphasis == .standard }
        )
        XCTAssertEqual(
            presentation.actions.first?.consequence,
            "Closes this alert now. Protection stays active, and Strong Alert returns in 1 minute unless you Join, choose I joined another way, Stop reminders, or Pause All Protection."
        )
        XCTAssertEqual(
            presentation.actions.last?.control,
            .menu([
                .init(
                    id: "pause-one-hour",
                    label: "Pause all for 1 hour",
                    intent: .pause(.oneHour)
                ),
                .init(
                    id: "pause-end-of-day",
                    label: "Pause all until end of day",
                    intent: .pause(.endOfDay)
                ),
                .init(
                    id: "pause-custom",
                    label: "Choose when to resume all protection…",
                    activation: .presentCustomPause
                ),
            ])
        )
    }

    func testEarlyReminderConflictSelectionUsesTheSharedOrdinaryActionRole() {
        let presentation = AlertActionPresentation(
            context: .conflictSelection(
                actionContext: .init(commitmentTitle: "Customer review")
            )
        )

        XCTAssertEqual(presentation.actions.map(\.role), [.makePrimary])
        XCTAssertEqual(presentation.actions.first?.scope, .conflictSelection)
        XCTAssertEqual(presentation.actions.first?.emphasis, .standard)
        XCTAssertNil(presentation.defaultAction)
        XCTAssertEqual(
            presentation.actions.first?.accessibilityLabel,
            "Make Customer review primary"
        )
    }

    func testEveryActionKeepsItsConsequenceInItsAccessibilityHint() throws {
        let meetingLink = try XCTUnwrap(URL(string: "https://meet.example.com/consequence"))
        let presentations = [
            AlertActionPresentation(
                context: .earlyReminder(
                    snoozeOptionsMinutes: [5, 10, 15, 30],
                    canSnooze: true
                )
            ),
            AlertActionPresentation(
                context: .strongAlert(
                    primary: .join(meetingLink),
                    repeatIntervalMinutes: 1
                )
            ),
            AlertActionPresentation(
                context: .strongConflictCommitment(
                    primary: .join(meetingLink),
                    actionContext: .init(commitmentTitle: "Customer review")
                )
            ),
        ]

        for action in presentations.flatMap(\.actions) {
            XCTAssertEqual(
                action.accessibilityHint,
                action.consequence,
                "Visible and spoken consequences diverged for \(action.role)"
            )
        }
    }

    func testHostedRegionGivesReturnOnlyToTheDefaultAndDispatchesItsIntent() throws {
        _ = NSApplication.shared
        let presentation = AlertActionPresentation(
            context: .earlyReminder(
                snoozeOptionsMinutes: [5, 10, 15, 30],
                canSnooze: true
            )
        )
        var dispatchedIntents: [AlertActionPresentation.Intent] = []
        let hostingView = NSHostingView(
            rootView: AlertActionRegion(presentation: presentation) { intent in
                dispatchedIntents.append(intent)
                return true
            }
            .frame(width: 520)
        )
        hostingView.sizingOptions = [.intrinsicContentSize]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()

        let buttons = descendants(in: hostingView).compactMap { $0 as? NSButton }
        XCTAssertEqual(
            buttons.filter { $0.accessibilityLabel() == "Close for now" }.count,
            1
        )
        XCTAssertEqual(
            buttons.filter { $0.accessibilityLabel() == "Stop reminders" }.count,
            1
        )
        let closeButton = try XCTUnwrap(
            buttons.first { $0.accessibilityLabel() == "Close for now" }
        )
        let stopButton = try XCTUnwrap(
            buttons.first { $0.accessibilityLabel() == "Stop reminders" }
        )

        XCTAssertEqual(closeButton.keyEquivalent, "\r")
        XCTAssertTrue(stopButton.keyEquivalent.isEmpty)
        XCTAssertEqual(
            closeButton.accessibilityHelp(),
            presentation.actions.first { $0.role == .closeForNow }?.consequence
        )
        XCTAssertEqual(
            stopButton.accessibilityHelp(),
            presentation.actions.first { $0.role == .stopReminders }?.consequence
        )
        XCTAssertLessThan(closeButton.frame.width, hostingView.bounds.width / 2)
        XCTAssertLessThan(stopButton.frame.width, hostingView.bounds.width / 2)

        let returnKey = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            )
        )
        window.sendEvent(returnKey)
        settle(hostingView)

        XCTAssertEqual(dispatchedIntents, [.closeForNow])
    }

    func testHostedEqualConflictRequiresExplicitSelection() throws {
        let meetingLink = try XCTUnwrap(URL(string: "https://meet.example.com/equal"))
        let presentation = AlertActionPresentation(
            context: .strongConflictCommitment(
                primary: .join(meetingLink),
                actionContext: .init(commitmentTitle: "Customer review")
            )
        )
        var dispatchedIntents: [AlertActionPresentation.Intent] = []
        let (window, hostingView) = host(presentation: presentation) { intent in
            dispatchedIntents.append(intent)
            return true
        }
        defer { window.orderOut(nil) }

        let actionButtons = descendants(in: hostingView)
            .compactMap { $0 as? NSButton }
            .filter { $0.accessibilityLabel() != nil }

        XCTAssertFalse(actionButtons.isEmpty)
        XCTAssertTrue(actionButtons.allSatisfy { $0.keyEquivalent != "\r" })

        let returnKey = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            )
        )
        window.sendEvent(returnKey)
        settle(hostingView)
        XCTAssertTrue(dispatchedIntents.isEmpty)
    }

    func testHostedChooseLinkMenuIsTheOnlyDefaultControl() throws {
        let firstLink = try XCTUnwrap(URL(string: "https://zoom.us/j/default"))
        let secondLink = try XCTUnwrap(URL(string: "https://meet.google.com/default"))
        let presentation = AlertActionPresentation(
            context: .strongAlert(
                primary: .chooseLink([firstLink, secondLink]),
                repeatIntervalMinutes: 1
            )
        )
        var dispatchedIntents: [AlertActionPresentation.Intent] = []
        let (window, hostingView) = host(presentation: presentation) { intent in
            dispatchedIntents.append(intent)
            return true
        }
        defer { window.orderOut(nil) }

        let nativeButtons = descendants(in: hostingView).compactMap { $0 as? NSButton }
        let chooseLink = try XCTUnwrap(
            nativeButtons.first { $0.accessibilityLabel() == "Choose Link" }
                as? NSPopUpButton
        )

        XCTAssertEqual(chooseLink.keyEquivalent, "\r")
        XCTAssertTrue(
            nativeButtons
                .filter { $0 !== chooseLink }
                .allSatisfy { $0.keyEquivalent != "\r" }
        )

        chooseLink.menu?.performActionForItem(at: 1)
        settle(hostingView)
        XCTAssertEqual(dispatchedIntents, [.join(firstLink)])
    }

    func testHostedControlsStayInsideANarrowLocalizedLayout() throws {
        let meetingLink = try XCTUnwrap(URL(string: "https://meet.example.com/narrow"))
        let presentation = AlertActionPresentation(
            context: .strongAlert(
                primary: .join(meetingLink),
                repeatIntervalMinutes: 1
            )
        )
        let (window, hostingView) = host(
            presentation: presentation,
            width: 110,
            dispatch: { _ in true }
        )
        defer { window.orderOut(nil) }

        let controls = descendants(in: hostingView)
            .compactMap { $0 as? NSButton }
            .filter { $0.accessibilityLabel() != nil }
        let handled = try XCTUnwrap(
            controls.first { $0.accessibilityLabel() == "I joined another way" }
        )

        XCTAssertFalse(controls.isEmpty)
        XCTAssertTrue(controls.allSatisfy { $0.frame.width <= 110.5 })
        XCTAssertGreaterThan(handled.frame.height, 30)
    }

    func testHostedLocalizedMenuLabelWrapsWithoutLosingItsVisibleText() throws {
        let link = try XCTUnwrap(URL(string: "https://meet.example.com/lokalisiert"))
        let label = "Verfügbaren Videokonferenz-Link für diese Besprechung auswählen"
        let consequence = "Öffnet den ausgewählten Besprechungslink, ohne den Schutz für diese Verpflichtung zu beenden."
        let action = AlertActionPresentation.Action(
            role: .chooseLink,
            scope: .occurrence,
            control: .menu([
                .init(id: link.absoluteString, label: "Mit Meet teilnehmen", intent: .join(link)),
            ]),
            label: label,
            consequence: consequence,
            accessibilityLabel: label,
            accessibilityHint: consequence,
            emphasis: .accent,
            keyActivation: .defaultAction,
            isEnabled: true
        )
        let (window, hostingView) = host(
            view: AlertNativeActionMenu(
                action: action,
                choices: [
                    .init(
                        id: link.absoluteString,
                        label: "Mit Meet teilnehmen",
                        intent: .join(link)
                    ),
                ],
                perform: { _ in }
            ),
            width: 150
        )
        defer { window.orderOut(nil) }

        let menu = try XCTUnwrap(
            descendants(in: hostingView).compactMap { $0 as? NSPopUpButton }.first
        )
        XCTAssertEqual(menu.title, label)
        XCTAssertTrue(try XCTUnwrap(menu.item(at: 0)).isEnabled)
        XCTAssertEqual(menu.cell?.lineBreakMode, .byWordWrapping)
        XCTAssertTrue(menu.cell?.wraps ?? false)
        XCTAssertLessThanOrEqual(menu.frame.width, 150.5)
        XCTAssertGreaterThan(menu.frame.height, 30)
    }

    func testHostedLinkedAlertHasOneAccessibleControlPerActionInVisualOrder() throws {
        let meetingLink = try XCTUnwrap(URL(string: "https://meet.example.com/order"))
        let presentation = AlertActionPresentation(
            context: .strongAlert(
                primary: .join(meetingLink),
                repeatIntervalMinutes: 1
            )
        )
        let (window, hostingView) = host(presentation: presentation) { _ in true }
        defer { window.orderOut(nil) }

        let controls = descendants(in: hostingView)
            .compactMap { $0 as? NSButton }
            .filter { $0.accessibilityLabel() != nil }
            .sorted {
                hostingView.convert($0.bounds, from: $0).midY <
                    hostingView.convert($1.bounds, from: $1).midY
            }

        XCTAssertEqual(controls.compactMap { $0.accessibilityLabel() }, [
            "Join",
            "I joined another way",
            "Stop reminders",
            "Got it",
            "Pause All Protection",
        ])
    }

    func testHostedPauseMenuDispatchesItsSemanticDurations() throws {
        let presentation = AlertActionPresentation(
            context: .strongAlert(
                primary: .stopReminders,
                repeatIntervalMinutes: 1
            )
        )
        var dispatchedIntents: [AlertActionPresentation.Intent] = []
        let (window, hostingView) = host(presentation: presentation) { intent in
            dispatchedIntents.append(intent)
            return true
        }
        defer { window.orderOut(nil) }

        let pauseMenu = try XCTUnwrap(
            descendants(in: hostingView)
                .compactMap { $0 as? NSPopUpButton }
                .first { $0.accessibilityLabel() == "Pause All Protection" }
        )

        pauseMenu.menu?.performActionForItem(at: 1)
        pauseMenu.menu?.performActionForItem(at: 2)
        settle(hostingView)

        XCTAssertEqual(dispatchedIntents, [
            .pause(.oneHour),
            .pause(.endOfDay),
        ])
    }

    func testNativeMenuDefersSemanticReplacementWhileTracking() throws {
        let oldLink = try XCTUnwrap(URL(string: "https://meet.example.com/old"))
        let newLink = try XCTUnwrap(URL(string: "https://meet.example.com/new"))
        let oldChoice = AlertActionPresentation.Choice(
            id: oldLink.absoluteString,
            label: "Join old meeting",
            intent: .join(oldLink)
        )
        let newChoice = AlertActionPresentation.Choice(
            id: newLink.absoluteString,
            label: "Join new meeting",
            intent: .join(newLink)
        )
        var dispatchedChoices: [AlertActionPresentation.Choice] = []
        let coordinator = AlertNativeActionMenu.Coordinator { choice in
            dispatchedChoices.append(choice)
        }
        let popUpButton = NSPopUpButton(frame: .zero, pullsDown: true)
        coordinator.update(
            menu: popUpButton,
            label: "Choose Link",
            choices: [oldChoice],
            isEnabled: true,
            perform: { choice in dispatchedChoices.append(choice) }
        )
        let menu = try XCTUnwrap(popUpButton.menu)
        let staleItem = try XCTUnwrap(menu.item(at: 1))

        coordinator.menuWillOpen(menu)
        coordinator.update(
            menu: popUpButton,
            label: "Choose Link",
            choices: [newChoice],
            isEnabled: true,
            perform: { choice in dispatchedChoices.append(choice) }
        )
        coordinator.performChoice(staleItem)

        XCTAssertEqual(dispatchedChoices, [oldChoice])
        XCTAssertEqual(menu.item(at: 1)?.title, "Join old meeting")

        coordinator.menuDidClose(menu)
        XCTAssertEqual(menu.item(at: 1)?.title, "Join old meeting")
        settle(popUpButton)
        XCTAssertEqual(menu.item(at: 1)?.title, "Join new meeting")
        coordinator.performChoice(try XCTUnwrap(menu.item(at: 1)))
        XCTAssertEqual(dispatchedChoices, [oldChoice, newChoice])
    }

    func testStopRemindersDispatchesOnlyAfterNativeConfirmation() throws {
        let presentation = AlertActionPresentation(
            context: .strongAlert(
                primary: .stopReminders,
                repeatIntervalMinutes: 1
            )
        )
        var dispatchedIntents: [AlertActionPresentation.Intent] = []
        let (window, hostingView) = host(presentation: presentation) { intent in
            dispatchedIntents.append(intent)
            return true
        }
        defer { window.orderOut(nil) }

        let stopButton = try XCTUnwrap(
            descendants(in: hostingView)
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityLabel() == "Stop reminders" }
        )
        stopButton.performClick(nil)
        settle(hostingView)

        let firstSheet = try XCTUnwrap(window.attachedSheet)
        let keepButton = try XCTUnwrap(
            descendants(in: firstSheet.contentView ?? NSView())
                .compactMap { $0 as? NSButton }
                .first { $0.title == "Keep reminders" }
        )
        keepButton.performClick(nil)
        settle(hostingView)
        XCTAssertTrue(dispatchedIntents.isEmpty)

        stopButton.performClick(nil)
        settle(hostingView)
        let confirmationSheet = try XCTUnwrap(window.attachedSheet)
        let confirmButton = try XCTUnwrap(
            descendants(in: confirmationSheet.contentView ?? NSView())
                .compactMap { $0 as? NSButton }
                .first { $0.title == "Stop reminders" }
        )
        confirmButton.performClick(nil)
        settle(hostingView)

        XCTAssertEqual(dispatchedIntents, [.stopReminders])
    }

    private func host(
        presentation: AlertActionPresentation,
        width: CGFloat = 520,
        dispatch: @escaping (AlertActionPresentation.Intent) -> Bool
    ) -> (NSWindow, NSHostingView<AnyView>) {
        host(
            view: AlertActionRegion(
                presentation: presentation,
                dispatch: dispatch
            ),
            width: width
        )
    }

    private func host<Content: View>(
        view: Content,
        width: CGFloat
    ) -> (NSWindow, NSHostingView<AnyView>) {
        _ = NSApplication.shared
        let hostingView = NSHostingView(
            rootView: AnyView(
                view.frame(width: width)
            )
        )
        hostingView.sizingOptions = [.intrinsicContentSize]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 520),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.frame = window.contentView?.bounds ?? .zero
        settle(hostingView)
        return (window, hostingView)
    }

    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        view.layoutSubtreeIfNeeded()
    }

    private func descendants(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
