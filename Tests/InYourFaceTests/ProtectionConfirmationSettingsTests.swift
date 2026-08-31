import AppKit
import CommitmentProtection
import SwiftUI
import XCTest
@testable import InYourFace

@MainActor
final class ProtectionConfirmationSettingsTests: XCTestCase {
    func testSettingsJourneyRendersPendingActionsAndQuietSettledStates() async throws {
        let fixture = try ProtectionConfirmationSettingsFixture()
        defer { fixture.cleanUp() }

        await fixture.flow.connectGoogleAccount()
        let accountID = ProtectionConfirmationSettingsConnector.account.id
        let initialCalendar = ProtectionConfirmationSettingsConnector.calendars[0]
        let additionalCalendar = ProtectionConfirmationSettingsConnector.calendars[1]

        let host = ProtectionConfirmationSettingsHost(
            fixture: fixture,
            size: NSSize(width: 900, height: 600)
        )
        defer { host.cleanUp() }

        XCTAssertEqual(
            try host.tabLabels(),
            ["Accounts", "Calendars", "Reminders", "Activity"]
        )

        try host.selectPane(named: "Calendars")
        let emptyPresentation = ProtectionConfirmationPresentation.account(
            try coverage(in: fixture.flow, accountID: accountID),
            locale: englishLocale
        )
        XCTAssertEqual(emptyPresentation.state, .empty)
        XCTAssertFalse(emptyPresentation.showsAction)
        XCTAssertNil(emptyPresentation.actionTitle)
        let emptyFooter = try host.calendarFooterRaster()

        fixture.flow.setCalendarSelected(
            true,
            calendarID: initialCalendar.id,
            accountID: accountID
        )
        host.settle()
        let initialPresentation = ProtectionConfirmationPresentation.account(
            try coverage(in: fixture.flow, accountID: accountID),
            locale: englishLocale
        )
        XCTAssertEqual(initialPresentation.state, .pendingInitialSelection)
        XCTAssertEqual(initialPresentation.pendingCount, 1)
        XCTAssertEqual(initialPresentation.actionTitle, "Protect Selected Calendars")
        XCTAssertFalse(fixture.flow.isGoogleAccountOperationInProgress)
        XCTAssertEqual(
            initialPresentation.accessibilityLabel,
            "Calendar selection needs confirmation. " +
                "Protection is pending for 1 selected calendar."
        )
        let initialPendingFooter = try host.calendarFooterRaster()
        XCTAssertNotEqual(emptyFooter, initialPendingFooter)
        let initialPendingRaster = try host.fullRaster()
        try host.writeSnapshotIfRequested(
            initialPendingRaster,
            named: "01-calendars-initial-pending.png"
        )

        try host.pressCalendarConfirmationAction()
        let settledPresentation = ProtectionConfirmationPresentation.account(
            try coverage(in: fixture.flow, accountID: accountID),
            locale: englishLocale
        )
        XCTAssertEqual(settledPresentation.state, .confirmed)
        XCTAssertFalse(settledPresentation.showsAction)
        XCTAssertNil(settledPresentation.actionTitle)
        let settledFooter = try host.calendarFooterRaster()
        let settledRaster = try host.fullRaster()
        XCTAssertNotEqual(
            initialPendingFooter,
            settledFooter,
            "Confirming protection should replace the prominent pending action with a quiet settled state."
        )
        try host.writeSnapshotIfRequested(
            settledRaster,
            named: "03-calendars-settled.png"
        )

        fixture.flow.setCalendarSelected(
            true,
            calendarID: additionalCalendar.id,
            accountID: accountID
        )
        host.settle()
        let pendingAddition = ProtectionConfirmationPresentation.account(
            try coverage(in: fixture.flow, accountID: accountID),
            locale: englishLocale
        )
        XCTAssertEqual(pendingAddition.state, .pendingAdditions)
        XCTAssertEqual(pendingAddition.confirmedCount, 1)
        XCTAssertEqual(pendingAddition.pendingCount, 1)
        XCTAssertEqual(pendingAddition.actionTitle, "Confirm Calendar Changes")
        XCTAssertEqual(
            pendingAddition.accessibilityLabel,
            "Calendar changes need confirmation. " +
                "Protection is pending for 1 new calendar. " +
                "Existing confirmation already includes 1 calendar."
        )
        let pendingAdditionFooter = try host.calendarFooterRaster()
        let pendingAdditionRaster = try host.fullRaster()
        XCTAssertNotEqual(settledFooter, pendingAdditionFooter)
        try host.writeSnapshotIfRequested(
            pendingAdditionRaster,
            named: "02-calendars-pending-addition.png"
        )

        try host.selectPane(named: "Accounts")
        let accountSummary = ProtectionConfirmationPresentation.global(
            fixture.flow.accountCoverages,
            locale: englishLocale
        )
        XCTAssertEqual(accountSummary.state, .pendingAdditions)
        XCTAssertEqual(accountSummary.pendingCount, 1)
        XCTAssertEqual(accountSummary.confirmedCount, 1)

        try host.selectPane(named: "Reminders")
        let remindersPendingRaster = try host.fullRaster()
        try host.writeSnapshotIfRequested(
            remindersPendingRaster,
            named: "04-reminders-pending.png"
        )

        try host.pressRemindersConfirmationAction()
        XCTAssertTrue(
            fixture.flow.accountCoverages.allSatisfy {
                !$0.selectedCalendarIDs.isEmpty &&
                    $0.selectedCalendarIDs == $0.confirmedCalendarIDs
            }
        )
        let remindersSettledRaster = try host.fullRaster()
        XCTAssertNotEqual(
            remindersPendingRaster,
            remindersSettledRaster,
            "The Reminders confirmation region should disappear once there is no pending calendar scope."
        )

        let settledCoverage = try coverage(in: fixture.flow, accountID: accountID)
        let settledSelectedIDs = settledCoverage.selectedCalendarIDs
        let settledConfirmedIDs = settledCoverage.confirmedCalendarIDs

        fixture.flow.setEarlyReminderEnabled(!fixture.flow.isEarlyReminderEnabled)
        host.settle()
        XCTAssertFalse(fixture.flow.isProtectionConfirmationRequired)

        fixture.flow.setOutOfOfficeProtectionEnabled(
            !fixture.flow.isOutOfOfficeProtectionEnabled
        )
        host.settle()
        XCTAssertFalse(fixture.flow.isProtectionConfirmationRequired)

        fixture.flow.setBlockingModeEnabled(!fixture.flow.isBlockingModeEnabled)
        host.settle()
        XCTAssertFalse(fixture.flow.isProtectionConfirmationRequired)

        let newLeadTime = fixture.flow.earlyReminderLeadTimeMinutes == 15 ? 20 : 15
        fixture.flow.setEarlyReminderLeadTime(minutes: newLeadTime)
        host.settle()
        XCTAssertEqual(fixture.flow.earlyReminderLeadTimeMinutes, newLeadTime)
        XCTAssertFalse(fixture.flow.isProtectionConfirmationRequired)

        let newRepeatInterval = fixture.flow.strongAlertRepeatIntervalMinutes == 2 ? 3 : 2
        fixture.flow.setStrongAlertRepeatInterval(minutes: newRepeatInterval)
        host.settle()
        XCTAssertEqual(fixture.flow.strongAlertRepeatIntervalMinutes, newRepeatInterval)
        XCTAssertFalse(fixture.flow.isProtectionConfirmationRequired)
        XCTAssertFalse(
            ProtectionConfirmationPresentation.global(
                fixture.flow.accountCoverages,
                locale: englishLocale
            ).showsAction,
            "Timing changes alone must not create a calendar confirmation action."
        )
        let coverageAfterPreferenceChanges = try coverage(
            in: fixture.flow,
            accountID: accountID
        )
        XCTAssertEqual(coverageAfterPreferenceChanges.selectedCalendarIDs, settledSelectedIDs)
        XCTAssertEqual(coverageAfterPreferenceChanges.confirmedCalendarIDs, settledConfirmedIDs)
    }

    private var englishLocale: Locale {
        Locale(identifier: "en_US")
    }

    private func coverage(
        in flow: CommitmentProtectionFlow,
        accountID: String
    ) throws -> AccountCoverage {
        try XCTUnwrap(flow.accountCoverages.first { $0.account.id == accountID })
    }
}

@MainActor
private final class ProtectionConfirmationSettingsHost {
    let hostingView: NSHostingView<AnyView>

    private let window: NSWindow

    init(fixture: ProtectionConfirmationSettingsFixture, size: NSSize) {
        _ = NSApplication.shared
        hostingView = NSHostingView(
            rootView: AnyView(
                SettingsRootView()
                    .environmentObject(fixture.flow)
                    .environmentObject(fixture.permissions)
                    .environmentObject(fixture.testToolsController)
                    .defaultAppStorage(fixture.defaults)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
        )
        hostingView.appearance = NSAppearance(named: .aqua)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.setContentSize(size)
        hostingView.frame = NSRect(origin: .zero, size: size)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settle()
    }

    func cleanUp() {
        window.orderOut(nil)
    }

    func tabLabels() throws -> [String] {
        let group = try XCTUnwrap(tabGroup())
        return (group.accessibilityChildren() ?? []).compactMap {
            ($0 as AnyObject).accessibilityLabel?()
        }
    }

    func selectPane(named name: String) throws {
        let group = try XCTUnwrap(tabGroup())
        let segment = try XCTUnwrap(group.accessibilityChildren()?.first { child in
            (child as AnyObject).accessibilityLabel?() == name
        })
        _ = (segment as? NSObject)?.perform(
            NSSelectorFromString("accessibilityPerformAction:"),
            with: NSAccessibility.Action.press.rawValue
        )
        settle()

        let selectedLabel = (group.accessibilityValue() as AnyObject?)?.accessibilityLabel?()
        XCTAssertEqual(selectedLabel, name)
    }

    func fullRaster() throws -> Data {
        try raster(in: hostingView.bounds)
    }

    func pressCalendarConfirmationAction() throws {
        try click(
            at: NSPoint(
                x: hostingView.bounds.midX + 250,
                y: hostingView.isFlipped
                    ? hostingView.bounds.maxY - 34
                    : hostingView.bounds.minY + 34
            )
        )
    }

    func pressRemindersConfirmationAction() throws {
        try click(
            at: NSPoint(
                x: hostingView.bounds.midX + 250,
                y: hostingView.isFlipped
                    ? hostingView.bounds.minY + 82
                    : hostingView.bounds.maxY - 82
            )
        )
    }

    func calendarFooterRaster() throws -> Data {
        let height = min(100, hostingView.bounds.height)
        let y = hostingView.isFlipped
            ? hostingView.bounds.maxY - height
            : hostingView.bounds.minY
        return try raster(
            in: NSRect(
                x: hostingView.bounds.minX,
                y: y,
                width: hostingView.bounds.width,
                height: height
            )
        )
    }

    private func raster(in rect: NSRect) throws -> Data {
        settle()
        hostingView.displayIfNeeded()
        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: rect)
        )
        hostingView.cacheDisplay(in: rect, to: representation)
        return try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
    }

    private func click(at point: NSPoint) throws {
        let windowPoint = hostingView.convert(point, to: nil)
        let eventTypes: [NSEvent.EventType] = [.leftMouseDown, .leftMouseUp]
        for eventType in eventTypes {
            let event = try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: eventType,
                    location: windowPoint,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: eventType == .leftMouseDown ? 1 : 0
                )
            )
            window.sendEvent(event)
        }
        settle()
    }

    func writeSnapshotIfRequested(_ data: Data, named filename: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["UX006_SNAPSHOT_DIR"],
              !directory.isEmpty else { return }

        let outputDirectory = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try data.write(
            to: outputDirectory.appendingPathComponent(filename),
            options: .atomic
        )
    }

    func settle() {
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        hostingView.layoutSubtreeIfNeeded()
    }

    private func tabGroup() -> NSCell? {
        descendants(from: window.contentView?.superview)
            .compactMap { ($0 as? NSControl)?.cell }
            .first { $0.accessibilityRole() == .radioGroup }
    }

    private func descendants(from view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap { descendants(from: $0) }
    }
}

@MainActor
private final class ProtectionConfirmationSettingsFixture {
    let defaults: UserDefaults
    let flow: CommitmentProtectionFlow
    let permissions: BlockingPermissionController
    let testToolsController: TestToolsController

    private let suiteName: String
    private let storageRoot: URL

    init() throws {
        let identifier = UUID().uuidString.lowercased()
        suiteName = "ProtectionConfirmationSettingsTests.\(identifier)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        storageRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            suiteName,
            isDirectory: true
        )
        let vaultIdentifier = "\(suiteName).production"
        let router = try RuntimeProfileRouter(
            storageRoot: storageRoot,
            namespace: suiteName,
            productionVaultApplicationIdentifier: vaultIdentifier
        )
        flow = CommitmentProtectionFlow(
            calendarConnector: ProtectionConfirmationSettingsConnector(),
            launchAtLogin: SimulatedLaunchAtLoginController(stateStore: defaults),
            stateStore: defaults
        )
        permissions = BlockingPermissionController(mode: .simulated(defaults))
        testToolsController = TestToolsController(
            profile: .production(vaultApplicationIdentifier: vaultIdentifier),
            router: router,
            productionFlow: flow
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: storageRoot)
    }
}

private struct ProtectionConfirmationSettingsConnector: GoogleCalendarConnecting, Sendable {
    static let account = GoogleAccount(
        id: "protection-confirmation-settings-account",
        email: "settings@example.invalid",
        displayName: "Settings Fixture"
    )

    static let calendars = [
        CalendarOption(
            id: "settings-work-calendar",
            name: "Work",
            accountID: account.id
        ),
        CalendarOption(
            id: "settings-personal-calendar",
            name: "Personal",
            accountID: account.id
        ),
    ]

    func connect() async throws -> GoogleCalendarConnection {
        GoogleCalendarConnection(account: Self.account, calendars: Self.calendars)
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        guard accountID == Self.account.id else { return nil }
        return GoogleCalendarConnection(account: Self.account, calendars: Self.calendars)
    }

    func disconnect(accountID: String) throws {}

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        []
    }
}
