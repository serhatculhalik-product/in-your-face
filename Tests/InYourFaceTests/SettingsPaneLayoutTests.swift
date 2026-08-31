import AppKit
import CommitmentProtection
import SwiftUI
import XCTest
@testable import InYourFace

@MainActor
final class SettingsPaneLayoutTests: XCTestCase {
    func testFooterActionRelationshipStacksWithinTheMinimumReadableWidth() throws {
        let narrowFrames = try actionRowFrames(width: 600)
        let narrowStatus = try XCTUnwrap(narrowFrames["status"])
        let narrowAction = try XCTUnwrap(narrowFrames["action"])
        XCTAssertTrue(
            narrowStatus.maxY <= narrowAction.minY || narrowAction.maxY <= narrowStatus.minY,
            "A constrained footer should stack status before action without overlap."
        )

        let wideFrames = try actionRowFrames(width: 960)
        let wideStatus = try XCTUnwrap(wideFrames["status"])
        let wideAction = try XCTUnwrap(wideFrames["action"])
        XCTAssertLessThan(abs(wideStatus.midY - wideAction.midY), 2)
        XCTAssertLessThan(wideStatus.maxX, wideAction.minX)
    }

    func testEveryPaneUsesTheGroupedFormContentGuideAcrossWindowWidths() async throws {
        let fixture = try SettingsLayoutFixture()
        defer { fixture.cleanUp() }
        await fixture.flow.connectGoogleAccount()

        let host = SettingsRootHost(fixture: fixture, size: NSSize(width: 680, height: 560))

        for width in [640.0, 680.0, 1_000.0] {
            host.resize(to: NSSize(width: width, height: 560))

            try host.selectPane(named: "Accounts")
            let accountGuide = try host.groupedFormContentGuide()

            try host.selectPane(named: "Reminders")
            let reminderGuide = try host.groupedFormContentGuide()
            XCTAssertEqual(reminderGuide.minX, accountGuide.minX, accuracy: 1)
            XCTAssertEqual(reminderGuide.maxX, accountGuide.maxX, accuracy: 1)

            try host.selectPane(named: "Calendars")
            let calendarsGuide = try host.primaryScrollFrame()
            XCTAssertEqual(calendarsGuide.minX, accountGuide.minX, accuracy: 1)
            XCTAssertEqual(calendarsGuide.maxX, accountGuide.maxX, accuracy: 1)

            try host.selectPane(named: "Activity")
            let activityGuide = try host.primaryScrollFrame()
            XCTAssertEqual(activityGuide.minX, accountGuide.minX, accuracy: 1)
            XCTAssertEqual(activityGuide.maxX, accountGuide.maxX, accuracy: 1)
        }
    }

    func testScaffoldDoesNotNestAnyPanePrimaryScroller() async throws {
        let fixture = try SettingsLayoutFixture()
        defer { fixture.cleanUp() }
        await fixture.flow.connectGoogleAccount()

        let host = SettingsRootHost(fixture: fixture, size: NSSize(width: 640, height: 500))
        for pane in ["Accounts", "Calendars", "Reminders", "Activity"] {
            try host.selectPane(named: pane)
            let primaryScroller = try host.primaryScrollView()
            var ancestor = primaryScroller.superview

            while let view = ancestor {
                XCTAssertFalse(
                    view is NSScrollView,
                    "The \(pane) primary scroller must not sit inside a page-level scroller."
                )
                ancestor = view.superview
            }
        }
    }

    func testLongCalendarsListScrollsFromItsFirstRowToItsLastRow() async throws {
        let fixture = try SettingsLayoutFixture(
            calendarConnector: ManyCalendarsConnector(calendarCount: 40)
        )
        defer { fixture.cleanUp() }
        await fixture.flow.connectGoogleAccount()

        let host = SettingsRootHost(fixture: fixture, size: NSSize(width: 640, height: 500))
        try host.selectPane(named: "Calendars")

        let primaryScroller = try host.primaryScrollView()
        let documentView = try XCTUnwrap(primaryScroller.documentView)
        let tableView = try XCTUnwrap(
            SettingsViewTestSupport.descendants(from: primaryScroller)
                .compactMap { $0 as? NSTableView }
                .first
        )
        let firstVisibleRect = try host.scrollToStart(primaryScroller)
        XCTAssertGreaterThan(documentView.bounds.height, firstVisibleRect.height)
        XCTAssertEqual(firstVisibleRect.minY, documentView.bounds.minY, accuracy: 1)
        XCTAssertTrue(tableView.visibleRect.intersects(tableView.rect(ofRow: 0)))

        try host.scrollToEnd(primaryScroller)

        XCTAssertTrue(
            tableView.visibleRect.intersects(tableView.rect(ofRow: tableView.numberOfRows - 1)),
            "The real Calendars list should reach its final row without another scroller taking over."
        )

        let restoredVisibleRect = try host.scrollToStart(primaryScroller)
        XCTAssertEqual(
            restoredVisibleRect.minY,
            documentView.bounds.minY,
            accuracy: 1
        )
    }

    func testOverflowingRemindersFormScrollsToItsFinalSectionAndBack() throws {
        let fixture = try SettingsLayoutFixture()
        defer { fixture.cleanUp() }
        fixture.flow.setBlockingModeEnabled(true)

        let host = SettingsRootHost(fixture: fixture, size: NSSize(width: 640, height: 500))
        try host.selectPane(named: "Reminders")

        let primaryScroller = try host.primaryScrollView()
        let documentView = try XCTUnwrap(primaryScroller.documentView)
        let topVisibleRect = try host.scrollToStart(primaryScroller)
        XCTAssertGreaterThan(documentView.bounds.height, topVisibleRect.height)

        let bottomVisibleRect = try host.scrollToEnd(primaryScroller)
        XCTAssertGreaterThan(bottomVisibleRect.minY, topVisibleRect.minY)
        let finalSwitch = try XCTUnwrap(
            SettingsViewTestSupport.lastNativeSwitch(in: documentView)
        )
        XCTAssertTrue(
            bottomVisibleRect.intersects(finalSwitch.convert(finalSwitch.bounds, to: documentView)),
            "The grouped Form should reach its final switch without a nested scroll trap."
        )

        let restoredVisibleRect = try host.scrollToStart(primaryScroller)
        XCTAssertEqual(
            restoredVisibleRect.minY,
            topVisibleRect.minY,
            accuracy: 1
        )
    }

    func testMultipleAccountsFormScrollsToAvailabilityAndBack() async throws {
        let fixture = try SettingsLayoutFixture(
            calendarConnector: MultipleAccountsConnector(accountCount: 3)
        )
        defer { fixture.cleanUp() }
        for _ in 0..<3 {
            await fixture.flow.connectGoogleAccount()
        }
        XCTAssertEqual(fixture.flow.accountCoverages.count, 3)

        let host = SettingsRootHost(fixture: fixture, size: NSSize(width: 640, height: 500))
        try host.selectPane(named: "Accounts")

        let primaryScroller = try host.primaryScrollView()
        let documentView = try XCTUnwrap(primaryScroller.documentView)
        let topVisibleRect = try host.scrollToStart(primaryScroller)
        XCTAssertGreaterThan(documentView.bounds.height, topVisibleRect.height)

        let bottomVisibleRect = try host.scrollToEnd(primaryScroller)
        XCTAssertGreaterThan(bottomVisibleRect.minY, topVisibleRect.minY)
        let availabilitySwitch = try XCTUnwrap(
            SettingsViewTestSupport.lastNativeSwitch(in: documentView)
        )
        XCTAssertTrue(
            bottomVisibleRect.intersects(
                availabilitySwitch.convert(availabilitySwitch.bounds, to: documentView)
            ),
            "The Accounts Form should reach Availability through its one primary scroller."
        )

        let restoredVisibleRect = try host.scrollToStart(primaryScroller)
        XCTAssertEqual(restoredVisibleRect.minY, topVisibleRect.minY, accuracy: 1)
    }

    func testCalendarsFooterStaysFixedWhileItsRealListScrollsAtNarrowAndWideWidths() async throws {
        let fixture = try SettingsLayoutFixture(
            calendarConnector: ManyCalendarsConnector(calendarCount: 40)
        )
        defer { fixture.cleanUp() }
        await fixture.flow.connectGoogleAccount()

        let host = SettingsRootHost(fixture: fixture, size: NSSize(width: 640, height: 500))
        XCTAssertTrue(host.hostingView.isFlipped)
        let coverage = try XCTUnwrap(fixture.flow.accountCoverages.first)

        for (index, width) in [640.0, 1_000.0].enumerated() {
            fixture.flow.setCalendarSelected(
                true,
                calendarID: coverage.calendars[index].id,
                accountID: coverage.account.id
            )
            host.resize(to: NSSize(width: width, height: 500))
            try host.selectPane(named: "Calendars")

            let primaryScroller = try host.primaryScrollView()
            try host.scrollToStart(primaryScroller)

            let listFrameBeforeScroll = try host.primaryScrollFrame()
            let footerRegion = NSRect(
                x: host.contentBounds.minX,
                y: listFrameBeforeScroll.maxY,
                width: host.contentBounds.width,
                height: host.contentBounds.maxY - listFrameBeforeScroll.maxY
            )
            XCTAssertGreaterThan(footerRegion.height, 0)

            let footerBeforeScroll = try host.rasterData(in: footerRegion)

            try host.scrollToEnd(primaryScroller)

            let listFrameAfterScroll = try host.primaryScrollFrame()
            XCTAssertEqual(listFrameAfterScroll.minX, listFrameBeforeScroll.minX, accuracy: 1)
            XCTAssertEqual(listFrameAfterScroll.minY, listFrameBeforeScroll.minY, accuracy: 1)
            XCTAssertEqual(listFrameAfterScroll.width, listFrameBeforeScroll.width, accuracy: 1)
            XCTAssertEqual(listFrameAfterScroll.height, listFrameBeforeScroll.height, accuracy: 1)
            XCTAssertEqual(try host.rasterData(in: footerRegion), footerBeforeScroll)

            XCTAssertTrue(fixture.flow.confirmProtection(for: coverage.account.id))
            host.settle()
            XCTAssertNotEqual(
                try host.rasterData(in: footerRegion),
                footerBeforeScroll,
                "The footer region should contain the live pending/confirmed status and action."
            )
        }
    }

    func testActivityWithManyScopesRemainsOperableAtTheMinimumWindowSize() async throws {
        let fixture = try SettingsLayoutFixture(calendarConnector: ManyCalendarsConnector())
        defer { fixture.cleanUp() }
        await fixture.flow.connectGoogleAccount()

        let coverage = try XCTUnwrap(fixture.flow.accountCoverages.first)
        for calendar in coverage.calendars {
            fixture.flow.setCalendarSelected(
                true,
                calendarID: calendar.id,
                accountID: coverage.account.id
            )
        }
        XCTAssertTrue(fixture.flow.confirmProtection(for: coverage.account.id))

        let host = SettingsRootHost(fixture: fixture, size: NSSize(width: 640, height: 500))
        try host.selectPane(named: "Activity")

        let scrollFrames = host.visibleScrollFrames()
        XCTAssertEqual(scrollFrames.count, 2)
        for frame in scrollFrames {
            XCTAssertTrue(
                host.contentBounds.contains(frame),
                "Every Activity collection must fit inside the minimum Settings viewport."
            )
            XCTAssertGreaterThan(frame.height, 0)
        }
        let scopeFrame = try XCTUnwrap(scrollFrames.first)
        let activityFrame = try XCTUnwrap(scrollFrames.last)
        XCTAssertTrue(
            scopeFrame.intersection(activityFrame).isEmpty,
            "The scope choices and Activity feed must not overlap."
        )

        let searchField = try XCTUnwrap(
            host.visibleViews(of: NSTextField.self).first { field in
                field.placeholderString == "Search activity calendars" &&
                    field.cell?.accessibilityRole() == .textField
            }
        )
        let searchFrame = host.frame(of: searchField)
        let initialTables = host.visibleViews(of: NSTableView.self)
        XCTAssertEqual(initialTables.count, 2)
        let (initialScopeTable, initialActivityTable) = try host.activityTables(
            nearestTo: searchFrame
        )
        XCTAssertEqual(initialScopeTable.numberOfRows, 14)
        let initialActivityCount = initialActivityTable.numberOfRows
        XCTAssertGreaterThan(initialActivityCount, 1)
        let activityScroller = try XCTUnwrap(initialActivityTable.enclosingScrollView)
        let initialActivityVisibleRect = try host.scrollToStart(activityScroller)
        XCTAssertTrue(
            initialActivityTable.visibleRect.intersects(initialActivityTable.rect(ofRow: 0))
        )
        let finalActivityVisibleRect = try host.scrollToEnd(activityScroller)
        XCTAssertGreaterThan(finalActivityVisibleRect.minY, initialActivityVisibleRect.minY)
        XCTAssertTrue(
            initialActivityTable.visibleRect.intersects(
                initialActivityTable.rect(ofRow: initialActivityCount - 1)
            ),
            "Expected final Activity row \(initialActivityTable.rect(ofRow: initialActivityCount - 1)) inside \(initialActivityTable.visibleRect)."
        )
        try host.scrollToStart(activityScroller)

        searchField.stringValue = "Calendar 13"
        NotificationCenter.default.post(
            name: NSControl.textDidChangeNotification,
            object: searchField
        )
        host.settle()

        let (filteredScopeTable, unfilteredActivityTable) = try host.activityTables(
            nearestTo: searchFrame
        )
        XCTAssertEqual(filteredScopeTable.numberOfRows, 2)
        XCTAssertEqual(unfilteredActivityTable.numberOfRows, initialActivityCount)

        filteredScopeTable.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        host.settle()

        let (selectedScopeTable, filteredActivityTable) = try host.activityTables(
            nearestTo: searchFrame
        )
        XCTAssertEqual(selectedScopeTable.selectedRow, 1)
        XCTAssertEqual(filteredActivityTable.numberOfRows, 1)
    }

    private func actionRowFrames(width: CGFloat) throws -> [String: CGRect] {
        let recorder = SettingsActionRowFrameRecorder()
        let size = NSSize(width: width, height: 160)
        let hostingView = NSHostingView(
            rootView: AnyView(
                SettingsActionRowHarness(recorder: recorder)
                    .frame(width: size.width, height: size.height, alignment: .top)
            )
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        SettingsViewTestSupport.settle(hostingView)
        return recorder.frames
    }
}

@MainActor
private final class SettingsActionRowFrameRecorder {
    var frames: [String: CGRect] = [:]
}

@MainActor
private struct SettingsActionRowHarness: View {
    let recorder: SettingsActionRowFrameRecorder

    var body: some View {
        AdaptiveSettingsActionRow {
            Text("Selected calendars are not protected yet")
                .frame(minWidth: 440, alignment: .leading)
                .background(SettingsActionRowFrameReporter(id: "status"))
        } actions: {
            Button("Protect Selected Calendars") {}
                .background(SettingsActionRowFrameReporter(id: "action"))
        }
        .coordinateSpace(name: "settings-action-row-test")
        .onPreferenceChange(SettingsActionRowFramePreferenceKey.self) { frames in
            recorder.frames = frames
        }
    }
}

private struct SettingsActionRowFrameReporter: View {
    let id: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: SettingsActionRowFramePreferenceKey.self,
                value: [id: proxy.frame(in: .named("settings-action-row-test"))]
            )
        }
    }
}

private struct SettingsActionRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

@MainActor
private enum SettingsViewTestSupport {
    static func descendants(from view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap { descendants(from: $0) }
    }

    static func settle(_ hostingView: NSView) {
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()
    }

    static func lastNativeSwitch(in documentView: NSView) -> NSView? {
        descendants(from: documentView)
            .filter {
                $0.accessibilityRole() == .button &&
                    $0.accessibilitySubrole() == .switch
            }
            .max { lhs, rhs in
                lhs.convert(lhs.bounds, to: documentView).minY <
                    rhs.convert(rhs.bounds, to: documentView).minY
            }
    }
}

@MainActor
private final class SettingsRootHost {
    let hostingView: NSHostingView<AnyView>
    private let window: NSWindow

    init(fixture: SettingsLayoutFixture, size: NSSize) {
        _ = NSApplication.shared
        hostingView = NSHostingView(
            rootView: AnyView(
                SettingsRootView()
                    .environmentObject(fixture.flow)
                    .environmentObject(fixture.permissions)
                    .environmentObject(fixture.testToolsController)
                    .defaultAppStorage(fixture.defaults)
            )
        )
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.frame = NSRect(origin: .zero, size: size)
        settle()
    }

    func resize(to size: NSSize) {
        window.setContentSize(size)
        hostingView.frame = NSRect(origin: .zero, size: size)
        settle()
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

    func groupedFormContentGuide() throws -> NSRect {
        let nativeSwitch = try XCTUnwrap(
            visibleDescendants().first { view in
                view.accessibilityRole() == .button &&
                    view.accessibilitySubrole() == .switch
            }
        )
        var ancestor = nativeSwitch.superview
        var candidates: [NSRect] = []
        while let view = ancestor {
            let frame = view.convert(view.bounds, to: hostingView)
            if frame.width > hostingView.bounds.width / 2,
               frame.width < hostingView.bounds.width - 1 {
                candidates.append(frame)
            }
            ancestor = view.superview
        }
        return try XCTUnwrap(candidates.min { $0.width < $1.width })
    }

    func primaryScrollFrame() throws -> NSRect {
        let scrollView = try primaryScrollView()
        return scrollView.convert(scrollView.bounds, to: hostingView)
    }

    func primaryScrollView() throws -> NSScrollView {
        try XCTUnwrap(
            visibleDescendants()
                .compactMap { $0 as? NSScrollView }
                .max { lhs, rhs in
                    lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
                }
        )
    }

    var contentBounds: NSRect {
        hostingView.bounds
    }

    func visibleScrollFrames() -> [NSRect] {
        visibleDescendants()
            .compactMap { $0 as? NSScrollView }
            .map { $0.convert($0.bounds, to: hostingView) }
            .sorted { $0.minY < $1.minY }
    }

    func visibleViews<View: NSView>(of type: View.Type) -> [View] {
        visibleDescendants().compactMap { $0 as? View }
    }

    func frame(of view: NSView) -> NSRect {
        view.convert(view.bounds, to: hostingView)
    }

    func activityTables(nearestTo searchFrame: NSRect) throws -> (
        scope: NSTableView,
        activity: NSTableView
    ) {
        let tables = visibleViews(of: NSTableView.self)
        let scopeTable = try XCTUnwrap(tables.min { lhs, rhs in
            abs(frame(of: lhs).minY - searchFrame.maxY) <
                abs(frame(of: rhs).minY - searchFrame.maxY)
        })
        let activityTable = try XCTUnwrap(tables.first { $0 !== scopeTable })
        return (scopeTable, activityTable)
    }

    func rasterData(in rect: NSRect) throws -> Data {
        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: rect)
        )
        hostingView.cacheDisplay(in: rect, to: representation)
        let bitmapData = try XCTUnwrap(representation.bitmapData)
        let bytesPerPixel = representation.bitsPerPixel / 8
        let visibleBytesPerRow = representation.pixelsWide * bytesPerPixel
        var data = Data(capacity: visibleBytesPerRow * representation.pixelsHigh)

        for row in 0..<representation.pixelsHigh {
            data.append(
                bitmapData.advanced(by: row * representation.bytesPerRow),
                count: visibleBytesPerRow
            )
        }
        return data
    }

    @discardableResult
    func scrollToStart(_ scrollView: NSScrollView) throws -> NSRect {
        let documentView = try XCTUnwrap(scrollView.documentView)
        scroll(scrollView, to: documentView.bounds.origin)
        return scrollView.documentVisibleRect
    }

    @discardableResult
    func scrollToEnd(_ scrollView: NSScrollView) throws -> NSRect {
        for _ in 0..<4 {
            let documentView = try XCTUnwrap(scrollView.documentView)
            let visibleRect = scrollView.documentVisibleRect
            scroll(
                scrollView,
                to: NSPoint(
                    x: visibleRect.minX,
                    y: documentView.bounds.maxY - visibleRect.height
                )
            )
        }
        return scrollView.documentVisibleRect
    }

    private func scroll(_ scrollView: NSScrollView, to origin: NSPoint) {
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        settle()
    }

    private func tabGroup() -> NSCell? {
        SettingsViewTestSupport.descendants(from: window.contentView?.superview)
            .compactMap { ($0 as? NSControl)?.cell }
            .first { $0.accessibilityRole() == .radioGroup }
    }

    private func visibleDescendants() -> [NSView] {
        SettingsViewTestSupport.descendants(from: hostingView).filter { view in
            !view.isHidden &&
                !view.convert(view.bounds, to: hostingView).intersection(hostingView.bounds).isEmpty
        }
    }

    func settle() {
        SettingsViewTestSupport.settle(hostingView)
    }
}

@MainActor
private final class SettingsLayoutFixture {
    let defaults: UserDefaults
    let flow: CommitmentProtectionFlow
    let permissions: BlockingPermissionController
    let testToolsController: TestToolsController

    private let suiteName: String
    private let storageRoot: URL

    init(
        calendarConnector: any GoogleCalendarConnecting = TestFirstRunCalendarConnector()
    ) throws {
        let identifier = UUID().uuidString.lowercased()
        suiteName = "SettingsPaneLayoutTests.\(identifier)"
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
            calendarConnector: calendarConnector,
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

private struct ManyCalendarsConnector: GoogleCalendarConnecting, Sendable {
    private static let account = GoogleAccount(
        id: "many-calendars-account",
        email: "many.calendars@example.invalid",
        displayName: "Many Calendars"
    )
    private let calendars: [CalendarOption]

    init(calendarCount: Int = 13) {
        calendars = (1...calendarCount).map { index in
            CalendarOption(
                id: "calendar-\(index)",
                name: "Calendar \(index)",
                accountID: Self.account.id
            )
        }
    }

    func connect() async throws -> GoogleCalendarConnection {
        GoogleCalendarConnection(account: Self.account, calendars: calendars)
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        guard accountID == Self.account.id else { return nil }
        return GoogleCalendarConnection(account: Self.account, calendars: calendars)
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

private final class MultipleAccountsConnector: GoogleCalendarConnecting, @unchecked Sendable {
    private let state: MultipleAccountsConnectorState

    init(accountCount: Int) {
        let connections = (1...accountCount).map { index in
            let account = GoogleAccount(
                id: "account-\(index)",
                email: "person.\(index)@example.invalid",
                displayName: "Person \(index)"
            )
            return GoogleCalendarConnection(
                account: account,
                calendars: [
                    CalendarOption(
                        id: "calendar-\(index)",
                        name: "Calendar \(index)",
                        accountID: account.id
                    )
                ]
            )
        }
        state = MultipleAccountsConnectorState(connections: connections)
    }

    func connect() async throws -> GoogleCalendarConnection {
        try await state.connect()
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        await state.restore(accountID: accountID)
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

private actor MultipleAccountsConnectorState {
    private var remainingConnections: [GoogleCalendarConnection]
    private let allConnections: [GoogleCalendarConnection]

    init(connections: [GoogleCalendarConnection]) {
        remainingConnections = connections
        allConnections = connections
    }

    func connect() throws -> GoogleCalendarConnection {
        guard !remainingConnections.isEmpty else {
            throw MultipleAccountsConnectorError.noRemainingAccount
        }
        return remainingConnections.removeFirst()
    }

    func restore(accountID: String) -> GoogleCalendarConnection? {
        allConnections.first { $0.account.id == accountID }
    }
}

private enum MultipleAccountsConnectorError: Error {
    case noRemainingAccount
}
