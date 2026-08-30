import AppKit
import CommitmentProtection
import SwiftUI
import XCTest
@testable import InYourFace

@MainActor
final class GlobalSettingsControlGrammarTests: XCTestCase {
    func testEarlyReminderOwnsNativeSwitchGrammarAcrossContainers() throws {
        let plainModel = EarlyReminderControlModel(
            isEnabled: false,
            leadTimeMinutes: 10
        )
        let formModel = EarlyReminderControlModel(
            isEnabled: false,
            leadTimeMinutes: 10
        )
        let plainHost = HostedView(
            rootView: AnyView(
                VStack(alignment: .leading) {
                    EarlyReminderControlHarness(model: plainModel)
                }
                .toggleStyle(.checkbox)
                .frame(width: 420, alignment: .leading)
            ),
            size: NSSize(width: 420, height: 100)
        )
        let formHost = HostedView(
            rootView: AnyView(
                Form {
                    EarlyReminderControlHarness(model: formModel)
                }
                .formStyle(.grouped)
                .frame(width: 420, height: 160)
            ),
            size: NSSize(width: 420, height: 160)
        )

        try assertEarlyReminderInteraction(
            model: plainModel,
            host: plainHost,
            expectsTrailingAlignment: true,
            context: "plain container"
        )
        try assertEarlyReminderInteraction(
            model: formModel,
            host: formHost,
            expectsTrailingAlignment: false,
            context: "grouped Form"
        )
    }

    func testBlockingModeOwnsNativeSwitchGrammarAcrossContainers() throws {
        let plainFixture = try makeFlowFixture()
        let formFixture = try makeFlowFixture()
        defer {
            plainFixture.defaults.removePersistentDomain(forName: plainFixture.suiteName)
            formFixture.defaults.removePersistentDomain(forName: formFixture.suiteName)
        }
        let plainHost = HostedView(
            rootView: AnyView(
                VStack(alignment: .leading) {
                    blockingModeControls(fixture: plainFixture)
                }
                .toggleStyle(.checkbox)
                .frame(width: 420, alignment: .leading)
            ),
            size: NSSize(width: 420, height: 260)
        )
        let formHost = HostedView(
            rootView: AnyView(
                Form {
                    blockingModeControls(fixture: formFixture)
                }
                .formStyle(.grouped)
                .frame(width: 420, height: 320)
            ),
            size: NSSize(width: 420, height: 320)
        )

        try assertBlockingModeInteraction(
            fixture: plainFixture,
            host: plainHost,
            expectsTrailingAlignment: true,
            context: "plain container"
        )
        try assertBlockingModeInteraction(
            fixture: formFixture,
            host: formHost,
            expectsTrailingAlignment: false,
            context: "grouped Form"
        )
    }

    func testBlockingPermissionSequenceKeepsVisualOnlyFallbackAndSupportsCancellation() throws {
        let fixture = try makeFlowFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        fixture.flow.setBlockingModeEnabled(true)
        fixture.permissions.request(.accessibility)
        XCTAssertEqual(fixture.permissions.pendingSimulation, .accessibility)
        XCTAssertFalse(fixture.permissions.hasAccessibilityPermission)
        fixture.permissions.resolveSimulation(allowed: false)

        XCTAssertNil(fixture.permissions.pendingSimulation)
        XCTAssertFalse(fixture.permissions.hasAccessibilityPermission)
        XCTAssertTrue(fixture.flow.isBlockingModeEnabled)

        fixture.permissions.request(.accessibility)
        fixture.permissions.resolveSimulation(allowed: true)
        fixture.permissions.request(.inputMonitoring)
        XCTAssertEqual(fixture.permissions.pendingSimulation, .inputMonitoring)
        fixture.permissions.resolveSimulation(allowed: false)

        XCTAssertTrue(fixture.permissions.hasAccessibilityPermission)
        XCTAssertFalse(fixture.permissions.hasInputMonitoringPermission)
        XCTAssertTrue(fixture.flow.isBlockingModeEnabled)

        fixture.permissions.request(.inputMonitoring)
        fixture.permissions.resolveSimulation(allowed: true)
        XCTAssertTrue(fixture.permissions.hasAccessibilityPermission)
        XCTAssertTrue(fixture.permissions.hasInputMonitoringPermission)

        fixture.flow.setBlockingModeEnabled(false)
        XCTAssertFalse(fixture.flow.isBlockingModeEnabled)
    }

    func testCalendarRowsKeepCheckboxGrammarAndStateAcrossSurfaces() async throws {
        let fixture = try makeFlowFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        await fixture.flow.connectGoogleAccount()
        let coverage = try XCTUnwrap(fixture.flow.accountCoverages.first)
        let selectedCalendarID = try XCTUnwrap(coverage.calendars.first?.id)

        fixture.flow.setCalendarSelected(
            true,
            calendarID: selectedCalendarID,
            accountID: coverage.account.id
        )
        XCTAssertTrue(fixture.flow.confirmProtection(for: coverage.account.id))

        let surfaces = CalendarSurface.allCases
        let host = HostedView(
            rootView: AnyView(
                VStack(spacing: 0) {
                    ForEach(surfaces, id: \.self) { surface in
                        CalendarSelectionList(
                            coverage: coverage,
                            searchText: .constant(""),
                            maximumHeight: surface.maximumHeight
                        )
                        .frame(height: surface.height)
                    }
                }
                .environmentObject(fixture.flow)
                .toggleStyle(.switch)
                .frame(width: 420, height: surfaces.reduce(0) { $0 + $1.height })
            ),
            size: NSSize(
                width: 420,
                height: surfaces.reduce(0) { $0 + $1.height }
            )
        )

        let checkboxes = nativeCheckboxes(in: host.hostingView)
        XCTAssertEqual(checkboxes.count, coverage.calendars.count * surfaces.count)
        XCTAssertTrue(nativeSwitches(in: host.hostingView).isEmpty)
        XCTAssertEqual(
            checkboxes.filter { checkboxValue($0) == true }.count,
            surfaces.count
        )
    }

    private func assertEarlyReminderInteraction(
        model: EarlyReminderControlModel,
        host: HostedView,
        expectsTrailingAlignment: Bool,
        context: String
    ) throws {
        let reminderSwitch = try XCTUnwrap(onlyNativeSwitch(in: host.hostingView))
        XCTAssertEqual(booleanAccessibilityValue(of: reminderSwitch), false, context)
        if expectsTrailingAlignment {
            XCTAssertEqual(
                reminderSwitch.convert(reminderSwitch.bounds, to: host.hostingView).maxX,
                host.hostingView.bounds.maxX,
                accuracy: 1,
                context
            )
        }

        let stepper = try XCTUnwrap(
            firstDescendant(of: NSStepper.self, in: host.hostingView)
        )
        XCTAssertFalse(stepper.isEnabled, context)

        _ = reminderSwitch.accessibilityPerformPress()
        host.settle()

        XCTAssertEqual(model.enableWrites, [true], context)
        XCTAssertTrue(model.isEnabled, context)
        XCTAssertEqual(model.leadTimeMinutes, 10, context)
        XCTAssertEqual(
            booleanAccessibilityValue(
                of: try XCTUnwrap(onlyNativeSwitch(in: host.hostingView))
            ),
            true,
            context
        )
        XCTAssertTrue(stepper.isEnabled, context)
    }

    private func assertBlockingModeInteraction(
        fixture: FlowFixture,
        host: HostedView,
        expectsTrailingAlignment: Bool,
        context: String
    ) throws {
        let blockingSwitch = try XCTUnwrap(onlyNativeSwitch(in: host.hostingView))
        XCTAssertEqual(booleanAccessibilityValue(of: blockingSwitch), false, context)
        if expectsTrailingAlignment {
            XCTAssertEqual(
                blockingSwitch.convert(blockingSwitch.bounds, to: host.hostingView).maxX,
                host.hostingView.bounds.maxX,
                accuracy: 1,
                context
            )
        }
        XCTAssertFalse(fixture.flow.isBlockingModeEnabled, context)
        XCTAssertNil(fixture.permissions.pendingSimulation, context)
        XCTAssertTrue(fixture.flow.activityLog.isEmpty, context)

        fixture.flow.setBlockingModeEnabled(true)
        host.settle()

        let enabledSwitch = try XCTUnwrap(onlyNativeSwitch(in: host.hostingView))
        XCTAssertEqual(booleanAccessibilityValue(of: enabledSwitch), true, context)

        _ = enabledSwitch.accessibilityPerformPress()
        host.settle()

        XCTAssertFalse(fixture.flow.isBlockingModeEnabled, context)
        XCTAssertNil(fixture.permissions.pendingSimulation, context)
        XCTAssertEqual(
            fixture.flow.activityLog.filter { $0.kind == .blockingModeChanged }.count,
            2,
            context
        )
        XCTAssertEqual(
            booleanAccessibilityValue(
                of: try XCTUnwrap(onlyNativeSwitch(in: host.hostingView))
            ),
            false,
            context
        )
    }

    private func blockingModeControls(fixture: FlowFixture) -> some View {
        BlockingModeControls(showsCurrentReminderStatus: false)
            .environmentObject(fixture.flow)
            .environmentObject(fixture.permissions)
    }

    private func makeFlowFixture() throws -> FlowFixture {
        let suiteName = "GlobalSettingsControlGrammarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let flow = CommitmentProtectionFlow(
            calendarConnector: TestFirstRunCalendarConnector(),
            launchAtLogin: SimulatedLaunchAtLoginController(stateStore: defaults),
            stateStore: defaults
        )
        return FlowFixture(
            suiteName: suiteName,
            defaults: defaults,
            flow: flow,
            permissions: BlockingPermissionController(mode: .simulated(defaults))
        )
    }

    private func onlyNativeSwitch(in root: NSView) -> NSView? {
        let switches = nativeSwitches(in: root)
        XCTAssertEqual(switches.count, 1)
        return switches.first
    }

    private func nativeSwitches(in root: NSView) -> [NSView] {
        descendants(of: root).filter {
            $0.accessibilityRole() == .button &&
                $0.accessibilitySubrole() == .switch
        }
    }

    private func nativeCheckboxes(in root: NSView) -> [NSButton] {
        descendants(of: root)
            .compactMap { $0 as? NSButton }
            .filter { $0.cell?.accessibilityRole() == .checkBox }
    }

    private func booleanAccessibilityValue(of element: NSView) -> Bool? {
        (element.accessibilityValue() as? NSNumber)?.boolValue
    }

    private func checkboxValue(_ checkbox: NSButton) -> Bool? {
        (checkbox.cell?.accessibilityValue() as? NSNumber)?.boolValue
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func firstDescendant<View: NSView>(
        of type: View.Type,
        in root: NSView
    ) -> View? {
        descendants(of: root).compactMap { $0 as? View }.first
    }
}

@MainActor
private final class EarlyReminderControlModel: ObservableObject {
    @Published var isEnabled: Bool
    @Published var leadTimeMinutes: Int
    private(set) var enableWrites: [Bool] = []

    init(isEnabled: Bool, leadTimeMinutes: Int) {
        self.isEnabled = isEnabled
        self.leadTimeMinutes = leadTimeMinutes
    }

    var enabledBinding: Binding<Bool> {
        Binding(
            get: { self.isEnabled },
            set: { isEnabled in
                self.enableWrites.append(isEnabled)
                self.isEnabled = isEnabled
            }
        )
    }
}

@MainActor
private struct EarlyReminderControlHarness: View {
    @ObservedObject var model: EarlyReminderControlModel

    var body: some View {
        EarlyReminderTimingControls(
            isEnabled: model.enabledBinding,
            leadTimeMinutes: $model.leadTimeMinutes
        )
    }
}

@MainActor
private final class HostedView {
    let hostingView: NSHostingView<AnyView>
    private let window: NSWindow

    init(rootView: AnyView, size: NSSize) {
        _ = NSApplication.shared
        hostingView = NSHostingView(rootView: rootView)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.frame = NSRect(origin: .zero, size: size)
        settle()
    }

    func settle() {
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        hostingView.layoutSubtreeIfNeeded()
    }
}

private enum CalendarSurface: CaseIterable, Hashable {
    case onboarding
    case settings

    var maximumHeight: CGFloat? {
        switch self {
        case .onboarding: 205
        case .settings: nil
        }
    }

    var height: CGFloat {
        switch self {
        case .onboarding: 240
        case .settings: 320
        }
    }
}

private struct FlowFixture {
    let suiteName: String
    let defaults: UserDefaults
    let flow: CommitmentProtectionFlow
    let permissions: BlockingPermissionController
}
