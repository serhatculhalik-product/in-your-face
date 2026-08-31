import AppKit
import CommitmentProtection
import Foundation
import SwiftUI
import XCTest
@testable import InYourFace

final class MenuBarPresentationTests: XCTestCase {
    func testEveryGlobalStateUsesOneAtomicStatusAndPreservesItsAction() {
        let cases: [(
            String,
            MenuBarProtectionPresentation,
            ProtectionCoveragePresentation.State,
            MenuBarProtectionPresentation.PrimaryAction?
        )] = [
            (
                "loading",
                makePresentation(isRestoringConnection: true),
                .loadingProtection,
                nil
            ),
            ("setup", makePresentation(needsSetup: true), .finishSetup, .finishSetup),
            ("no coverage", makePresentation(status: .noCoverage), .noCoverage, .openSettings),
            ("active", makePresentation(status: .active), .activeProtection, nil),
            (
                "paused",
                makePresentation(status: .active, isPaused: true),
                .protectionPaused,
                nil
            ),
            (
                "checking",
                makePresentation(status: .unavailable, isCheckingCoverage: true),
                .checkingCoverage,
                nil
            ),
            (
                "reconnect",
                makePresentation(
                    status: .unavailable,
                    accounts: [reconnectAccount]
                ),
                .reconnectRequired,
                .reconnect(accountID: reconnectAccount.id)
            ),
            (
                "stale",
                makePresentation(
                    status: .unavailable,
                    accounts: [staleAccount]
                ),
                .coverageNeedsAttention,
                nil
            ),
            (
                "unavailable",
                makePresentation(
                    status: .unavailable,
                    accounts: [unavailableAccount]
                ),
                .coverageNeedsAttention,
                nil
            ),
            (
                "unavailable ignores pause",
                makePresentation(
                    status: .unavailable,
                    isPaused: true,
                    accounts: [unavailableAccount]
                ),
                .coverageNeedsAttention,
                nil
            ),
        ]

        for (description, presentation, expectedState, expectedAction) in cases {
            let expectedStatus = ProtectionCoveragePresentation(state: expectedState)
            XCTAssertEqual(presentation.statusPresentation, expectedStatus, description)
            XCTAssertEqual(presentation.title, expectedStatus.label, description)
            XCTAssertEqual(presentation.systemImage, expectedStatus.systemImage, description)
            XCTAssertEqual(presentation.tone, expectedStatus.tone, description)
            XCTAssertEqual(presentation.showsProgress, expectedStatus.showsProgress, description)
            XCTAssertEqual(presentation.primaryAction, expectedAction, description)
            XCTAssertFalse(presentation.detail.isEmpty, description)
        }
    }

    func testReconnectRequiredUsesCanonicalRecoveryAndAccountSpecificAction() {
        let presentation = makePresentation(
            status: .unavailable,
            accounts: [reconnectAccount]
        )

        XCTAssertEqual(presentation.title, "Reconnect Required")
        XCTAssertTrue(presentation.detail.contains("person@example.com"))
        XCTAssertEqual(presentation.primaryAction, .reconnect(accountID: "account-1"))
        XCTAssertEqual(presentation.tone, .caution)
    }

    func testSetupDominatesAStaleSavedAccount() {
        let presentation = makePresentation(
            needsSetup: true,
            status: .unavailable,
            accounts: [reconnectAccount]
        )

        XCTAssertEqual(presentation.title, "Finish Setup")
        XCTAssertEqual(presentation.primaryAction, .finishSetup)
    }

    func testActiveAggregateStaysActiveWhenOneAccountNeedsRecovery() {
        for account in [staleAccount, reconnectAccount, unavailableAccount] {
            let presentation = makePresentation(
                status: .active,
                accounts: [account]
            )

            XCTAssertEqual(presentation.title, "Active Protection")
            XCTAssertNil(presentation.primaryAction)
            XCTAssertEqual(presentation.tone, .positive)
        }
    }

    func testMultipleReconnectAccountsUseRowsInsteadOfAnAmbiguousPrimaryAction() {
        let presentation = makePresentation(
            status: .unavailable,
            accounts: [
                reconnectAccount,
                MenuBarAccountPresentation(
                    id: "account-2",
                    label: "second@example.com",
                    connectionState: .reconnectRequired,
                    health: .reconnectRequired
                )
            ]
        )

        XCTAssertEqual(presentation.title, "Reconnect Required")
        XCTAssertNil(presentation.primaryAction)
    }

    func testReconnectConnectionStateOverridesAnUnavailableCoverageError() {
        let presentation = makePresentation(
            status: .unavailable,
            accounts: [
                MenuBarAccountPresentation(
                    id: "account-1",
                    label: "person@example.com",
                    connectionState: .reconnectRequired,
                    health: .unavailable("Protected data could not be read")
                )
            ]
        )

        XCTAssertEqual(presentation.statusPresentation.state, .reconnectRequired)
        XCTAssertTrue(presentation.detail.contains("person@example.com"))
        XCTAssertEqual(presentation.primaryAction, .reconnect(accountID: "account-1"))
    }

    private var reconnectAccount: MenuBarAccountPresentation {
        MenuBarAccountPresentation(
            id: "account-1",
            label: "person@example.com",
            connectionState: .reconnectRequired,
            health: .reconnectRequired
        )
    }

    private var staleAccount: MenuBarAccountPresentation {
        MenuBarAccountPresentation(
            id: "account-1",
            label: "person@example.com",
            connectionState: .connected,
            health: .stale
        )
    }

    private var unavailableAccount: MenuBarAccountPresentation {
        MenuBarAccountPresentation(
            id: "account-1",
            label: "person@example.com",
            connectionState: .connected,
            health: .unavailable("Refresh failed")
        )
    }

    private func makePresentation(
        isRestoringConnection: Bool = false,
        needsSetup: Bool = false,
        status: ProtectionStatus = .active,
        isCheckingCoverage: Bool = false,
        isPaused: Bool = false,
        accounts: [MenuBarAccountPresentation] = []
    ) -> MenuBarProtectionPresentation {
        MenuBarProtectionPresentation.make(
            isRestoringConnection: isRestoringConnection,
            needsSetup: needsSetup,
            status: status,
            isCheckingCoverage: isCheckingCoverage,
            isPaused: isPaused,
            pauseDetail: "All protection paused · resumes in 1 hour (11:00 PM)",
            isLaunchAtLoginEnabled: true,
            hasUpcomingCommitment: false,
            accounts: accounts,
            confirmation: .global([])
        )
    }
}

@MainActor
final class MenuBarSurfaceLayoutTests: XCTestCase {
    func testReconnectSurfaceCannotCollapseToTheUtilityFooter() async throws {
        let suiteName = "MenuBarSurfaceLayoutTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store.removePersistentDomain(forName: suiteName)
        defer { store.removePersistentDomain(forName: suiteName) }
        try installSavedAccounts(in: store)

        let flow = CommitmentProtectionFlow(
            calendarConnector: SessionOnlyCalendarConnector(),
            launchAtLogin: EnabledLaunchAtLogin(),
            stateStore: store
        )
        await flow.restoreSavedConnection()
        let onboardingState = OnboardingState(stateStore: store)
        onboardingState.resolveInitialLaunch(hasConfiguredProtection: true)

        XCTAssertEqual(flow.status, .unavailable)
        XCTAssertEqual(flow.accountCoverages.count, 2)

        let rootView = MenuBarContent()
            .environmentObject(flow)
            .environmentObject(onboardingState)
            .background(Color(nsColor: .windowBackgroundColor))
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        XCTAssertEqual(fittingSize.width, 336, accuracy: 1)
        XCTAssertGreaterThan(fittingSize.height, 180)
        XCTAssertLessThan(fittingSize.height, 420)

        if let snapshotPath = ProcessInfo.processInfo.environment["IMPECCABLE_SNAPSHOT_PATH"] {
            try writeSnapshot(of: hostingView, size: fittingSize, to: snapshotPath)
        }
    }

    func testTargetedReconnectPublishesTheConnectingAccountUntilCompletion() async {
        let account = GoogleAccount(
            id: "account-1",
            email: "person@example.com",
            displayName: "Person"
        )
        let calendar = CalendarOption(
            id: "calendar-1",
            name: "Work",
            accountID: account.id
        )
        let connection = GoogleCalendarConnection(account: account, calendars: [calendar])
        let connector = DelayedReconnectCalendarConnector(connection: connection)
        let flow = CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: EnabledLaunchAtLogin()
        )
        await flow.connectGoogleAccount()

        let reconnectTask = Task {
            await flow.reconnectGoogleAccount(accountID: account.id)
        }
        await connector.waitUntilReconnectStarts()

        XCTAssertTrue(flow.isConnectingAccount)
        XCTAssertEqual(flow.connectingAccountID, account.id)

        await connector.finishReconnect()
        await reconnectTask.value

        XCTAssertFalse(flow.isConnectingAccount)
        XCTAssertNil(flow.connectingAccountID)
    }

    private func installSavedAccounts(in store: UserDefaults) throws {
        let accounts: [[String: Any]] = [
            savedAccount(
                id: "work-account",
                email: "serhat.culhalik@getir.com",
                calendarID: "work-calendar",
                calendarName: "Work"
            ),
            savedAccount(
                id: "personal-account",
                email: "serhatculhalik@gmail.com",
                calendarID: "personal-calendar",
                calendarName: "Personal"
            )
        ]
        let data = try JSONSerialization.data(withJSONObject: ["accounts": accounts])
        store.set(data, forKey: "commitment-protection.configuration")
    }

    private func savedAccount(
        id: String,
        email: String,
        calendarID: String,
        calendarName: String
    ) -> [String: Any] {
        [
            "account": [
                "id": id,
                "email": email,
                "displayName": ""
            ],
            "calendars": [[
                "id": calendarID,
                "name": calendarName,
                "accountID": id
            ]],
            "selectedCalendarIDs": [calendarID],
            "isProtectionConfirmed": true,
            "lastFreshEvents": []
        ]
    }

    private func writeSnapshot(
        of hostingView: NSView,
        size: NSSize,
        to path: String
    ) throws {
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Could not create the menu bar snapshot bitmap.")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        let imageData = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        let outputURL = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try imageData.write(to: outputURL)
    }
}

private struct SessionOnlyCalendarConnector: GoogleCalendarConnecting {
    func connect() async throws -> GoogleCalendarConnection {
        throw MenuBarSurfaceFixtureError.unavailable
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        nil
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

private final class DelayedReconnectCalendarConnector: GoogleCalendarConnecting, @unchecked Sendable {
    private let connection: GoogleCalendarConnection
    private let state = DelayedReconnectState()

    init(connection: GoogleCalendarConnection) {
        self.connection = connection
    }

    func connect() async throws -> GoogleCalendarConnection {
        connection
    }

    func connect(expectedAccountID: String?) async throws -> GoogleCalendarConnection {
        if expectedAccountID != nil {
            await state.suspendReconnect()
        }
        return connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        nil
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

    func waitUntilReconnectStarts() async {
        await state.waitUntilReconnectStarts()
    }

    func finishReconnect() async {
        await state.finishReconnect()
    }
}

private actor DelayedReconnectState {
    private var reconnectStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func suspendReconnect() async {
        reconnectStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func waitUntilReconnectStarts() async {
        if reconnectStarted {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finishReconnect() {
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

@MainActor
private final class EnabledLaunchAtLogin: LaunchAtLoginControlling {
    var isEnabled = true

    func enable() throws {}
}

private enum MenuBarSurfaceFixtureError: Error {
    case unavailable
}
