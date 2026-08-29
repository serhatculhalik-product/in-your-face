import AppKit
import CommitmentProtection
import Foundation
import XCTest
@testable import InYourFace

@MainActor
final class ApplicationWindowPresenterTests: XCTestCase {
    func testPackagedAppParticipatesInApplicationSwitching() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = repositoryRoot
            .appendingPathComponent("Resources/InYourFace.app/Contents/Info.plist")
        let plistData = try Data(contentsOf: infoPlistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil)
                as? [String: Any]
        )

        XCTAssertEqual(plist["LSUIElement"] as? Bool, false)
    }

    func testRepeatedSettingsRequestsForegroundTheRegisteredWindowEveryTime() {
        let registry = WindowRegistry()
        let settingsWindow = makeWindow(title: "Settings")
        var activationCount = 0
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: { activationCount += 1 },
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { nil }
        )
        registry.register(settingsWindow, for: .settings)

        presenter.showSettings { openSettingsCount += 1 }
        presenter.showSettings { openSettingsCount += 1 }

        XCTAssertEqual(openSettingsCount, 2)
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(foregroundedWindows.count, 2)
        XCTAssertTrue(foregroundedWindows.allSatisfy { $0 === settingsWindow })
    }

    func testSettingsRequestForegroundsAfterTheWindowRegisters() {
        let registry = WindowRegistry()
        let settingsWindow = makeWindow(title: "Settings")
        var activationCount = 0
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: { activationCount += 1 },
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { nil }
        )

        presenter.showSettings { openSettingsCount += 1 }

        XCTAssertEqual(openSettingsCount, 1)
        XCTAssertEqual(activationCount, 0)
        XCTAssertTrue(foregroundedWindows.isEmpty)

        registry.register(settingsWindow, for: .settings)

        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(foregroundedWindows.count, 1)
        XCTAssertTrue(foregroundedWindows.first === settingsWindow)
    }

    func testDockReopenForegroundsSettingsWhenSetupIsComplete() {
        let registry = WindowRegistry()
        let settingsWindow = makeWindow(title: "Settings")
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { nil }
        )
        registry.register(settingsWindow, for: .settings)

        presenter.applicationDidRequestReopen(
            initialSurface: .menuBarOnly,
            hasEarlyReminder: false,
            hasStrongAlert: false
        ) {
            openSettingsCount += 1
        }

        XCTAssertEqual(openSettingsCount, 0)
        XCTAssertEqual(foregroundedWindows.count, 1)
        XCTAssertTrue(foregroundedWindows.first === settingsWindow)
    }

    func testApplicationActivationDoesNotUseTheSettingsFallback() {
        let registry = WindowRegistry()
        let settingsWindow = makeWindow(title: "Settings")
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { nil },
            currentEventWindow: { nil }
        )
        registry.register(settingsWindow, for: .settings)

        presenter.applicationDidBecomeActive(
            initialSurface: .menuBarOnly,
            hasEarlyReminder: false,
            hasStrongAlert: false
        ) {
            openSettingsCount += 1
        }

        XCTAssertEqual(openSettingsCount, 0)
        XCTAssertTrue(foregroundedWindows.isEmpty)
    }

    func testStrongAlertWinsApplicationActivationPriority() {
        let registry = WindowRegistry()
        let settingsWindow = makeWindow(title: "Settings")
        let onboardingWindow = makeWindow(title: "Onboarding")
        let earlyReminderWindow = makeWindow(title: "Early Reminder")
        let strongAlertWindow = makeWindow(title: "Strong Alert")
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { nil }
        )
        registry.register(settingsWindow, for: .settings)
        registry.register(onboardingWindow, for: .onboarding)
        registry.register(earlyReminderWindow, for: .earlyReminder)
        registry.register(strongAlertWindow, for: .strongAlert)

        presenter.applicationDidBecomeActive(
            initialSurface: .onboarding,
            hasEarlyReminder: true,
            hasStrongAlert: true
        ) {
            openSettingsCount += 1
        }

        XCTAssertEqual(openSettingsCount, 0)
        XCTAssertEqual(foregroundedWindows.count, 1)
        XCTAssertTrue(foregroundedWindows.first === strongAlertWindow)
    }

    func testVisibleTestToolsWinsOverActiveAlertsOnApplicationActivation() {
        let registry = WindowRegistry()
        let testToolsWindow = makeWindow(title: "Test Tools")
        let earlyReminderWindow = makeWindow(title: "Early Reminder")
        let strongAlertWindow = makeWindow(title: "Strong Alert")
        testToolsWindow.orderFrontRegardless()
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { nil }
        )
        registry.register(testToolsWindow, for: .testTools)
        registry.register(earlyReminderWindow, for: .earlyReminder)
        registry.register(strongAlertWindow, for: .strongAlert)

        presenter.applicationDidBecomeActive(
            initialSurface: .menuBarOnly,
            hasEarlyReminder: true,
            hasStrongAlert: true
        ) {
            openSettingsCount += 1
        }

        XCTAssertEqual(openSettingsCount, 0)
        XCTAssertEqual(foregroundedWindows.count, 1)
        XCTAssertTrue(foregroundedWindows.first === testToolsWindow)
    }

    func testEarlyReminderWinsOverOnboarding() {
        let registry = WindowRegistry()
        let onboardingWindow = makeWindow(title: "Onboarding")
        let earlyReminderWindow = makeWindow(title: "Early Reminder")
        var foregroundedWindows: [NSWindow] = []
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { nil }
        )
        registry.register(onboardingWindow, for: .onboarding)
        registry.register(earlyReminderWindow, for: .earlyReminder)

        presenter.applicationDidBecomeActive(
            initialSurface: .onboarding,
            hasEarlyReminder: true,
            hasStrongAlert: false,
            using: {}
        )

        XCTAssertEqual(foregroundedWindows.count, 1)
        XCTAssertTrue(foregroundedWindows.first === earlyReminderWindow)
    }

    func testOnboardingWinsOverSettings() {
        let registry = WindowRegistry()
        let settingsWindow = makeWindow(title: "Settings")
        let onboardingWindow = makeWindow(title: "Onboarding")
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { nil }
        )
        registry.register(settingsWindow, for: .settings)
        registry.register(onboardingWindow, for: .onboarding)

        presenter.applicationDidBecomeActive(
            initialSurface: .onboarding,
            hasEarlyReminder: false,
            hasStrongAlert: false
        ) {
            openSettingsCount += 1
        }

        XCTAssertEqual(openSettingsCount, 0)
        XCTAssertEqual(foregroundedWindows.count, 1)
        XCTAssertTrue(foregroundedWindows.first === onboardingWindow)
    }

    func testActivationDoesNotOpenSettingsWhilePriorityWindowIsRegistering() {
        let registry = WindowRegistry()
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { nil }
        )

        presenter.applicationDidBecomeActive(
            initialSurface: .menuBarOnly,
            hasEarlyReminder: false,
            hasStrongAlert: true
        ) {
            openSettingsCount += 1
        }

        XCTAssertEqual(openSettingsCount, 0)
        XCTAssertTrue(foregroundedWindows.isEmpty)
    }

    func testActivationDoesNothingWhileInitialSurfaceIsWaiting() {
        let registry = WindowRegistry()
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { nil }
        )

        presenter.applicationDidBecomeActive(
            initialSurface: .waiting,
            hasEarlyReminder: false,
            hasStrongAlert: false
        ) {
            openSettingsCount += 1
        }

        XCTAssertEqual(openSettingsCount, 0)
        XCTAssertTrue(foregroundedWindows.isEmpty)
    }

    func testActivationPreservesAnUnmanagedKeyWindow() {
        let registry = WindowRegistry()
        let transientWindow = makeWindow(title: "Menu Bar Popover")
        transientWindow.orderFrontRegardless()
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { transientWindow }
        )

        presenter.applicationDidBecomeActive(
            initialSurface: .menuBarOnly,
            hasEarlyReminder: false,
            hasStrongAlert: false
        ) {
            openSettingsCount += 1
        }

        XCTAssertEqual(openSettingsCount, 0)
        XCTAssertTrue(foregroundedWindows.isEmpty)
    }

    func testActivationPreservesAnUnmanagedEventWindowBeforeItBecomesKey() {
        let registry = WindowRegistry()
        let transientWindow = makeWindow(title: "Menu Bar Popover")
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { nil },
            currentEventWindow: { transientWindow }
        )

        presenter.applicationDidBecomeActive(
            initialSurface: .menuBarOnly,
            hasEarlyReminder: false,
            hasStrongAlert: false
        ) {
            openSettingsCount += 1
        }

        XCTAssertEqual(openSettingsCount, 0)
        XCTAssertTrue(foregroundedWindows.isEmpty)
    }

    func testActivationFromAClosingManagedAlertDoesNotOpenSettings() {
        let registry = WindowRegistry()
        let strongAlertWindow = makeWindow(title: "Strong Alert")
        let settingsWindow = makeWindow(title: "Settings")
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { nil },
            currentEventWindow: { nil }
        )
        registry.register(strongAlertWindow, for: .strongAlert)
        registry.register(settingsWindow, for: .settings)

        presenter.applicationDidBecomeActive(
            initialSurface: .menuBarOnly,
            hasEarlyReminder: false,
            hasStrongAlert: false,
            triggeringWindow: strongAlertWindow
        ) {
            openSettingsCount += 1
        }

        XCTAssertEqual(openSettingsCount, 0)
        XCTAssertTrue(foregroundedWindows.isEmpty)
    }

    func testCloseForNowClosesOnlyTheEarlyReminderWithoutOpeningSettings() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let startDate = now.addingTimeInterval(10 * 60)
        let account = GoogleAccount(
            id: "account-1",
            email: "alex@example.com",
            displayName: "Alex"
        )
        let calendar = CalendarOption(
            id: "calendar-1",
            name: "Work",
            accountID: account.id
        )
        let commitment = CalendarEvent(
            id: "event-1",
            title: "Customer review",
            startDate: startDate,
            endDate: now.addingTimeInterval(70 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id
        )
        let suiteName = "ApplicationWindowPresenterTests.closeForNow.\(UUID().uuidString)"
        let stateStore = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let flow = CommitmentProtectionFlow(
            calendarConnector: PresenterTestCalendarConnector(
                connection: GoogleCalendarConnection(
                    account: account,
                    calendars: [calendar]
                ),
                events: [commitment]
            ),
            launchAtLogin: PresenterTestLaunchAtLoginController(),
            stateStore: stateStore,
            now: { now }
        )
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendar.id)
        XCTAssertTrue(flow.confirmProtection())
        for _ in 0..<10 {
            await Task.yield()
        }
        await flow.refreshCommitmentProtection(at: now)
        XCTAssertEqual(flow.earlyReminderCommitment, commitment)

        let registry = WindowRegistry()
        let earlyReminderWindow = makeWindow(title: "Early Reminder")
        let settingsWindow = makeWindow(title: "Settings")
        earlyReminderWindow.isReleasedWhenClosed = false
        settingsWindow.isReleasedWhenClosed = false
        defer {
            earlyReminderWindow.close()
            settingsWindow.close()
        }
        earlyReminderWindow.orderFrontRegardless()
        registry.register(earlyReminderWindow, for: .earlyReminder)
        registry.register(settingsWindow, for: .settings)
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { window in
                foregroundedWindows.append(window)
                window.orderFrontRegardless()
            },
            currentKeyWindow: { nil },
            currentEventWindow: { nil }
        )

        let surface = EarlyReminderSurfaceModel.normal(
            flow: flow,
            commitment: commitment
        )
        XCTAssertTrue(surface.actions.clear())
        registry.unregister(earlyReminderWindow, for: .earlyReminder)
        earlyReminderWindow.close()
        presenter.applicationDidBecomeActive(
            initialSurface: .menuBarOnly,
            hasEarlyReminder: flow.earlyReminderCommitment != nil,
            hasStrongAlert: flow.isStrongAlertPresented,
            triggeringWindow: nil
        ) {
            openSettingsCount += 1
        }

        XCTAssertFalse(earlyReminderWindow.isVisible)
        XCTAssertFalse(
            settingsWindow.isVisible,
            "Close for now must not reveal Settings after the Early Reminder closes."
        )
        XCTAssertTrue(
            foregroundedWindows.isEmpty,
            "Close for now must not foreground Settings after the Early Reminder closes."
        )
        XCTAssertEqual(openSettingsCount, 0)
        XCTAssertNil(flow.earlyReminderCommitment)
        XCTAssertTrue(flow.isProtectionConfirmed(for: account.id))
        XCTAssertEqual(flow.status, .active)
        XCTAssertEqual(flow.upcomingCommitment, commitment)

        await flow.refreshCommitmentProtection(at: startDate)

        XCTAssertEqual(flow.strongAlertCommitment, commitment)
    }

    func testActivationPreservesAManagedCurrentEventWindow() {
        let registry = WindowRegistry()
        let earlyReminderWindow = makeWindow(title: "Early Reminder")
        let settingsWindow = makeWindow(title: "Settings")
        var foregroundedWindows: [NSWindow] = []
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { foregroundedWindows.append($0) },
            currentKeyWindow: { nil },
            currentEventWindow: { earlyReminderWindow }
        )
        registry.register(earlyReminderWindow, for: .earlyReminder)
        registry.register(settingsWindow, for: .settings)

        presenter.applicationDidBecomeActive(
            initialSurface: .menuBarOnly,
            hasEarlyReminder: false,
            hasStrongAlert: false,
            using: { openSettingsCount += 1 }
        )

        XCTAssertEqual(openSettingsCount, 0)
        XCTAssertTrue(foregroundedWindows.isEmpty)
    }

    func testActiveLaunchPresentsSettingsWhenInitialStateResolves() {
        let registry = WindowRegistry()
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { _ in },
            currentKeyWindow: { nil }
        )

        presenter.initialSurfaceDidResolve(
            initialSurface: .menuBarOnly,
            isApplicationActive: true,
            hasEarlyReminder: false,
            hasStrongAlert: false
        ) {
            openSettingsCount += 1
        }

        XCTAssertEqual(openSettingsCount, 1)
    }

    func testInactiveLaunchStaysInTheMenuBarWhenInitialStateResolves() {
        let registry = WindowRegistry()
        var openSettingsCount = 0
        let presenter = ApplicationWindowPresenter(
            windowRegistry: registry,
            activateApplication: {},
            foregroundWindow: { _ in },
            currentKeyWindow: { nil }
        )

        presenter.initialSurfaceDidResolve(
            initialSurface: .menuBarOnly,
            isApplicationActive: false,
            hasEarlyReminder: false,
            hasStrongAlert: false
        ) {
            openSettingsCount += 1
        }

        XCTAssertEqual(openSettingsCount, 0)
    }

    func testApplicationDelegatePublishesDockReopenRequests() {
        let notificationCenter = NotificationCenter()
        let delegate = InYourFaceApplicationDelegate(
            notificationCenter: notificationCenter
        )
        let reopenRequest = XCTNSNotificationExpectation(
            name: .inYourFaceApplicationDidRequestReopen,
            object: nil,
            notificationCenter: notificationCenter
        )

        let shouldUseDefaultHandling = delegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: false
        )

        XCTAssertFalse(shouldUseDefaultHandling)
        wait(for: [reopenRequest], timeout: 0.1)
    }

    func testApplicationDelegateSupportsSwiftUIRuntimeInitialization() {
        XCTAssertNotNil(InYourFaceApplicationDelegate())
    }

    private func makeWindow(title: String) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = title
        return window
    }
}

private struct PresenterTestCalendarConnector: GoogleCalendarConnecting {
    let connection: GoogleCalendarConnection
    let events: [CalendarEvent]

    func connect() async throws -> GoogleCalendarConnection {
        connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        connection.account.id == accountID ? connection : nil
    }

    func disconnect(accountID: String) throws {}

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        events.filter {
            $0.accountID == accountID &&
                $0.calendarID == calendarID &&
                ($0.startDate ?? .distantPast) < endDate &&
                ($0.endDate ?? .distantFuture) > startDate
        }
    }
}

@MainActor
private final class PresenterTestLaunchAtLoginController: LaunchAtLoginControlling {
    private(set) var isEnabled = false

    func enable() throws {
        isEnabled = true
    }
}
