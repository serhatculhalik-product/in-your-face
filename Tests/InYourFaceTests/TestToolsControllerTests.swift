import AppKit
import Carbon.HIToolbox
import CommitmentProtection
import Foundation
import XCTest
@testable import InYourFace

@MainActor
final class TestToolsControllerTests: XCTestCase {
    func testShortcutMatchesOnlyControlShiftCommandR() throws {
        XCTAssertTrue(
            TestToolsShortcutMonitor.matches(
                try keyEvent(keyCode: UInt16(kVK_ANSI_R), modifiers: [.command, .control, .shift])
            )
        )
        XCTAssertTrue(
            TestToolsShortcutMonitor.matches(
                try keyEvent(
                    keyCode: UInt16(kVK_ANSI_R),
                    modifiers: [.capsLock, .command, .control, .shift]
                )
            ),
            "Unrelated system flags must not make the hidden shortcut unreliable"
        )
        XCTAssertFalse(
            TestToolsShortcutMonitor.matches(
                try keyEvent(keyCode: UInt16(kVK_ANSI_R), modifiers: [.command, .shift])
            )
        )
        XCTAssertFalse(
            TestToolsShortcutMonitor.matches(
                try keyEvent(
                    keyCode: UInt16(kVK_ANSI_R),
                    modifiers: [.command, .control, .option, .shift]
                )
            )
        )
        XCTAssertFalse(
            TestToolsShortcutMonitor.matches(
                try keyEvent(keyCode: UInt16(kVK_ANSI_T), modifiers: [.command, .control, .shift])
            )
        )
    }

    func testBeginTestFirstRunPersistsTestRouteBeforeRelaunch() throws {
        let fixture = try TestToolsFixture()
        defer { fixture.cleanUp() }
        let relauncher = RecordingApplicationRelauncher()
        let controller = fixture.makeController(
            profile: fixture.productionProfile,
            relauncher: relauncher
        )

        controller.beginTestFirstRun()

        let resolution = try fixture.router.resolveForBootstrap()
        let profile = try testProfile(from: resolution)
        fixture.track(profile)
        XCTAssertEqual(relauncher.validateCallCount, 1)
        XCTAssertEqual(relauncher.relaunchCallCount, 1)
        XCTAssertEqual(resolution.profile, .test(profile))
        XCTAssertTrue(resolution.cleanupIntents.isEmpty)
        XCTAssertTrue(controller.isTransitioning)
        XCTAssertNil(controller.operationError)
    }

    func testRestartCreatesNewGenerationAndCleanupIntentBeforeRelaunch() throws {
        let fixture = try TestToolsFixture()
        defer { fixture.cleanUp() }
        let original = try testProfile(from: fixture.router.beginFreshTest())
        fixture.track(original)
        fixture.clock.advance(by: 1)
        let relauncher = RecordingApplicationRelauncher()
        let controller = fixture.makeController(profile: .test(original), relauncher: relauncher)

        controller.restartTestFirstRun()

        let resolution = try fixture.router.resolveForBootstrap()
        let replacement = try testProfile(from: resolution)
        fixture.track(replacement)
        let cleanup = try XCTUnwrap(resolution.cleanupIntents.first)
        XCTAssertNotEqual(replacement.id, original.id)
        XCTAssertEqual(cleanup.profile, original)
        XCTAssertEqual(cleanup.reason, .replacedByFreshTest)
        XCTAssertEqual(relauncher.validateCallCount, 1)
        XCTAssertEqual(relauncher.relaunchCallCount, 1)
    }

    func testExitTestModePersistsCleanupRequiredBeforeRelaunch() throws {
        let fixture = try TestToolsFixture()
        defer { fixture.cleanUp() }
        let profile = try testProfile(from: fixture.router.beginFreshTest())
        fixture.track(profile)
        let relauncher = RecordingApplicationRelauncher()
        let controller = fixture.makeController(profile: .test(profile), relauncher: relauncher)

        controller.exitTestMode()

        let resolution = try fixture.router.resolveForBootstrap()
        let cleanup = try XCTUnwrap(resolution.cleanupIntents.first)
        XCTAssertEqual(resolution.route, .cleanupRequired)
        XCTAssertEqual(cleanup.profile, profile)
        XCTAssertEqual(cleanup.reason, .exitRequested)
        XCTAssertEqual(relauncher.validateCallCount, 1)
        XCTAssertEqual(relauncher.relaunchCallCount, 1)
    }

    func testRelaunchPreflightFailureLeavesProductionRouteUnchanged() throws {
        let fixture = try TestToolsFixture()
        defer { fixture.cleanUp() }
        let relauncher = RecordingApplicationRelauncher(validationError: RelaunchFixtureError.preflight)
        let controller = fixture.makeController(
            profile: fixture.productionProfile,
            relauncher: relauncher
        )

        controller.beginTestFirstRun()

        XCTAssertEqual(
            try fixture.router.resolveForBootstrap().profile,
            fixture.productionProfile
        )
        XCTAssertEqual(relauncher.validateCallCount, 1)
        XCTAssertEqual(relauncher.relaunchCallCount, 0)
        XCTAssertFalse(controller.isTransitioning)
        XCTAssertEqual(controller.operationError, RelaunchFixtureError.preflight.localizedDescription)
    }

    func testUpcomingRealCommitmentWithinThirtyMinutesDoesNotBlockReset() async throws {
        let fixture = try TestToolsFixture()
        defer { fixture.cleanUp() }
        let commitment = fixture.makeCommitment(
            start: fixture.clock.date.addingTimeInterval(20 * 60),
            end: fixture.clock.date.addingTimeInterval(45 * 60)
        )
        let flow = fixture.makeProductionFlow(events: [commitment])
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: fixture.calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await Task.yield()
        await flow.refreshCommitmentProtection(at: fixture.clock.date)
        XCTAssertEqual(flow.upcomingCommitment, commitment)
        let relauncher = RecordingApplicationRelauncher()
        let controller = fixture.makeController(
            profile: fixture.productionProfile,
            relauncher: relauncher,
            productionFlow: flow
        )
        var eraseCount = 0
        controller.installEraseAppManagedDataAction {
            eraseCount += 1
        }

        XCTAssertNil(controller.realProtectionGuardReason)
        XCTAssertTrue(controller.canChangeRuntime)
        controller.eraseAppManagedData()
        for _ in 0..<100 where eraseCount == 0 {
            await Task.yield()
        }

        XCTAssertEqual(eraseCount, 1)
        XCTAssertFalse(controller.isEraseInProgress)
    }

    func testOngoingRealStrongAlertDoesNotBlockReset() async throws {
        let fixture = try TestToolsFixture()
        defer { fixture.cleanUp() }
        let commitment = fixture.makeCommitment(
            start: fixture.clock.date.addingTimeInterval(-5 * 60),
            end: fixture.clock.date.addingTimeInterval(45 * 60)
        )
        let flow = fixture.makeProductionFlow(events: [commitment])
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: fixture.calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        await Task.yield()
        await flow.refreshCommitmentProtection(at: fixture.clock.date)
        XCTAssertTrue(flow.isStrongAlertPresented)
        let controller = fixture.makeController(
            profile: fixture.productionProfile,
            relauncher: RecordingApplicationRelauncher(),
            productionFlow: flow
        )
        var eraseCount = 0
        controller.installEraseAppManagedDataAction {
            eraseCount += 1
        }

        XCTAssertNil(controller.realProtectionGuardReason)
        XCTAssertTrue(controller.canChangeRuntime)
        controller.eraseAppManagedData()
        for _ in 0..<100 where eraseCount == 0 {
            await Task.yield()
        }

        XCTAssertEqual(eraseCount, 1)
        XCTAssertFalse(controller.isEraseInProgress)
    }

    func testRuntimeChangesWaitForProductionInitialRestoreToFinish() throws {
        let fixture = try TestToolsFixture()
        defer { fixture.cleanUp() }
        let relauncher = RecordingApplicationRelauncher()
        let controller = fixture.makeController(
            profile: fixture.productionProfile,
            relauncher: relauncher,
            productionReady: false
        )
        var eraseCount = 0
        controller.installEraseAppManagedDataAction {
            eraseCount += 1
        }

        XCTAssertFalse(controller.canChangeRuntime)
        controller.beginTestFirstRun()
        controller.eraseAppManagedData()

        XCTAssertEqual(relauncher.relaunchCallCount, 0)
        XCTAssertEqual(eraseCount, 0)
        XCTAssertEqual(try fixture.router.resolveForBootstrap().profile, fixture.productionProfile)

        controller.productionDidFinishInitialRestore()

        XCTAssertTrue(controller.canChangeRuntime)
        controller.eraseAppManagedData()
        drainMainRunLoop(until: { eraseCount == 1 })
        XCTAssertEqual(eraseCount, 1)
        XCTAssertFalse(controller.isEraseInProgress)

        controller.beginTestFirstRun()

        let resolution = try fixture.router.resolveForBootstrap()
        let profile = try testProfile(from: resolution)
        fixture.track(profile)
        XCTAssertEqual(relauncher.relaunchCallCount, 1)
        XCTAssertEqual(resolution.profile, .test(profile))
    }

    func testBlockedResetCanRetryWithoutAllowingOtherRuntimeChanges() throws {
        let fixture = try TestToolsFixture()
        defer { fixture.cleanUp() }
        let relauncher = RecordingApplicationRelauncher()
        let controller = fixture.makeController(
            profile: fixture.productionProfile,
            relauncher: relauncher
        )
        controller.installResetBusyCheck { true }
        controller.installResetRetryableCheck { true }
        var retryCount = 0
        controller.installEraseAppManagedDataAction {
            retryCount += 1
        }

        XCTAssertFalse(controller.canChangeRuntime)
        XCTAssertTrue(controller.canRetryAppManagedDataReset)
        controller.beginTestFirstRun()
        XCTAssertEqual(relauncher.relaunchCallCount, 0)
        XCTAssertEqual(try fixture.router.resolveForBootstrap().profile, fixture.productionProfile)

        controller.retryAppManagedDataReset()
        drainMainRunLoop(until: { retryCount == 1 })

        XCTAssertEqual(retryCount, 1)
        XCTAssertFalse(controller.isEraseInProgress)
        XCTAssertFalse(controller.canChangeRuntime)
    }

    func testPostExitCleanupRecoveryOffersDirectRetry() throws {
        let fixture = try TestToolsFixture()
        defer { fixture.cleanUp() }
        let productionFlow = fixture.makeProductionFlow()
        productionFlow.lockMutationsForAppManagedDataReset()
        let controller = fixture.makeController(
            profile: fixture.productionProfile,
            relauncher: RecordingApplicationRelauncher(),
            productionFlow: productionFlow,
            recoveryReport: "Application Support could not be removed.",
            appDataResetRecoveryAvailable: true
        )
        var retryCount = 0
        controller.installEraseAppManagedDataAction {
            retryCount += 1
        }

        XCTAssertFalse(controller.canChangeRuntime)
        XCTAssertTrue(controller.canRetryRecoveredAppManagedDataReset)
        controller.clearRecoveryReport()
        XCTAssertNotNil(controller.recoveryReport)
        XCTAssertTrue(controller.appDataResetRecoveryAvailable)
        controller.retryRecoveredAppManagedDataReset()
        drainMainRunLoop(until: { retryCount == 1 })

        XCTAssertEqual(retryCount, 1)
        XCTAssertFalse(controller.isEraseInProgress)
    }

    func testClosingTestToolsDoesNotResumeAlertsWhileResetLockIsActive() throws {
        let fixture = try TestToolsFixture()
        defer { fixture.cleanUp() }
        let productionFlow = fixture.makeProductionFlow()
        productionFlow.lockMutationsForAppManagedDataReset()
        var resumeCount = 0
        let controller = fixture.makeController(
            profile: fixture.productionProfile,
            relauncher: RecordingApplicationRelauncher(),
            productionFlow: productionFlow,
            alertInteraction: TestToolsAlertInteraction(
                suspend: {},
                resume: { resumeCount += 1 }
            )
        )

        controller.testToolsDidClose()

        XCTAssertEqual(resumeCount, 0)

        productionFlow.unlockMutationsForAppManagedDataReset()
        controller.testToolsDidClose()

        XCTAssertEqual(resumeCount, 1)
    }

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "r",
                charactersIgnoringModifiers: "r",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    private func testProfile(from resolution: RuntimeProfileResolution) throws -> RuntimeTestProfile {
        guard case .test(let profile) = resolution.profile else {
            throw TestToolsFixtureError.expectedTestProfile
        }
        return profile
    }

    private func drainMainRunLoop(
        timeout: TimeInterval = 0.25,
        until condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }
}

@MainActor
private final class TestToolsFixture {
    let root: URL
    let namespace: String
    let productionVaultIdentifier: String
    let router: RuntimeProfileRouter
    let clock = TestToolsClock(date: Date(timeIntervalSince1970: 2_000_000_000))
    let account = GoogleAccount(
        id: "real-account",
        email: "real@example.com",
        displayName: "Real User"
    )
    lazy var calendar = CalendarOption(id: "real-calendar", name: "Work", accountID: account.id)

    private var defaultsSuites: Set<String> = []

    init() throws {
        let identifier = UUID().uuidString.lowercased()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TestToolsControllerTests-\(identifier)",
            isDirectory: true
        )
        namespace = "TestToolsControllerTests.\(identifier)"
        productionVaultIdentifier = "\(namespace).production"
        router = try RuntimeProfileRouter(
            storageRoot: root,
            namespace: namespace,
            productionVaultApplicationIdentifier: productionVaultIdentifier,
            now: { [clock] in clock.date }
        )
    }

    var productionProfile: RuntimeProfile {
        .production(vaultApplicationIdentifier: productionVaultIdentifier)
    }

    func makeController(
        profile: RuntimeProfile,
        relauncher: RecordingApplicationRelauncher,
        productionFlow: CommitmentProtectionFlow? = nil,
        productionReady: Bool = true,
        recoveryReport: String? = nil,
        appDataResetRecoveryAvailable: Bool = false,
        alertInteraction: TestToolsAlertInteraction = .live
    ) -> TestToolsController {
        TestToolsController(
            profile: profile,
            router: router,
            productionFlow: productionFlow ?? makeProductionFlow(),
            relauncher: relauncher,
            recoveryReport: recoveryReport,
            appDataResetRecoveryAvailable: appDataResetRecoveryAvailable,
            productionReady: productionReady,
            alertInteraction: alertInteraction
        )
    }

    func makeProductionFlow(events: [CalendarEvent] = []) -> CommitmentProtectionFlow {
        let suiteName = "\(namespace).flow.\(UUID().uuidString.lowercased())"
        defaultsSuites.insert(suiteName)
        let stateStore = UserDefaults(suiteName: suiteName)!
        stateStore.removePersistentDomain(forName: suiteName)
        return CommitmentProtectionFlow(
            calendarConnector: TestToolsCalendarConnector(
                connection: GoogleCalendarConnection(account: account, calendars: [calendar]),
                events: events
            ),
            launchAtLogin: TestToolsLaunchAtLoginController(),
            stateStore: stateStore,
            now: { [clock] in clock.date }
        )
    }

    func makeCommitment(start: Date, end: Date) -> CalendarEvent {
        CalendarEvent(
            id: "guarded-real-commitment",
            title: "Real commitment",
            startDate: start,
            endDate: end,
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            recognizedMeetingLink: URL(string: "https://meet.google.com/abc-defg-hij")
        )
    }

    func track(_ profile: RuntimeTestProfile) {
        defaultsSuites.insert(profile.defaultsSuiteName)
    }

    func cleanUp() {
        for suiteName in defaultsSuites {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class RecordingApplicationRelauncher: ApplicationRelaunching {
    private let validationError: Error?
    private(set) var validateCallCount = 0
    private(set) var relaunchCallCount = 0

    init(validationError: Error? = nil) {
        self.validationError = validationError
    }

    func validate() throws {
        validateCallCount += 1
        if let validationError {
            throw validationError
        }
    }

    func relaunch() throws {
        relaunchCallCount += 1
    }
}

private struct TestToolsCalendarConnector: GoogleCalendarConnecting {
    let connection: GoogleCalendarConnection
    let events: [CalendarEvent]

    func connect() async throws -> GoogleCalendarConnection {
        connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        accountID == connection.account.id ? connection : nil
    }

    func disconnect(accountID: String) throws {}

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        events.filter { event in
            event.accountID == accountID &&
                event.calendarID == calendarID &&
                (event.startDate ?? .distantPast) < endDate &&
                (event.endDate ?? .distantFuture) > startDate
        }
    }
}

@MainActor
private final class TestToolsLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled = false

    func enable() throws {
        isEnabled = true
    }
}

@MainActor
private final class TestToolsClock {
    private(set) var date: Date

    init(date: Date) {
        self.date = date
    }

    func advance(by interval: TimeInterval) {
        date = date.addingTimeInterval(interval)
    }
}

private enum RelaunchFixtureError: Error, LocalizedError {
    case preflight

    var errorDescription: String? {
        "Relaunch preflight failed."
    }
}

private enum TestToolsFixtureError: Error {
    case expectedTestProfile
}
