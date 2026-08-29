import CryptoKit
import Foundation
import XCTest
@testable import CommitmentProtection

@MainActor
final class EncryptedPersistenceLifecycleTests: XCTestCase {
    func testEncryptedAccountStateAndAuthorizationSurviveRelaunch() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }

        let firstVault = try makeVault(at: vaultRoot)
        let firstConnector = LifecycleCalendarConnector(
            connection: fixture.connection,
            events: [fixture.event],
            credentialStore: EncryptedGoogleCredentialStore(vault: firstVault)
        )
        let firstLaunch = makeFlow(
            connector: firstConnector,
            defaults: defaults,
            vault: firstVault,
            now: currentDate
        )

        await connectAndProtect(firstLaunch, calendarID: fixture.calendar.id, at: currentDate)

        XCTAssertNotNil(try firstVault.loadData(as: .credential, for: fixture.account.id))
        XCTAssertNotNil(try firstVault.loadData(as: .configuration, for: fixture.account.id))
        XCTAssertNotNil(try firstVault.loadData(as: .eventSnapshot, for: fixture.account.id))
        XCTAssertNotNil(try firstVault.loadData(as: .activity, for: fixture.account.id))
        XCTAssertNil(defaults.data(forKey: "commitment-protection.configuration"))
        XCTAssertNil(defaults.data(forKey: "commitment-protection.activity-log"))

        let relaunchedVault = try makeVault(at: vaultRoot)
        let relaunchedConnector = LifecycleCalendarConnector(
            connection: fixture.connection,
            events: [fixture.event],
            credentialStore: EncryptedGoogleCredentialStore(vault: relaunchedVault)
        )
        let relaunch = makeFlow(
            connector: relaunchedConnector,
            defaults: defaults,
            vault: relaunchedVault,
            now: currentDate
        )

        await relaunch.restoreSavedConnection()

        XCTAssertEqual(relaunchedConnector.connectCallCount, 0)
        XCTAssertEqual(relaunchedConnector.restoreCallCount, 1)
        XCTAssertEqual(relaunch.connectedAccount, fixture.account)
        XCTAssertEqual(relaunch.connectionState, .connected)
        XCTAssertEqual(relaunch.selectedCalendarIDs(for: fixture.account.id), [fixture.calendar.id])
        XCTAssertTrue(relaunch.isProtectionConfirmed(for: fixture.account.id))
        XCTAssertEqual(relaunch.upcomingCommitment, fixture.event)
        XCTAssertTrue(relaunch.activityLog.contains {
            $0.kind == .accountConnected && $0.accountID == fixture.account.id
        })
    }

    func testEncryptedEventSnapshotPreservesMeetingDescriptionAcrossRelaunch() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(
            now: currentDate,
            eventStartOffset: 5 * 60,
            meetingDescription: "Review launch readiness & open risks."
        )
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }

        let firstVault = try makeVault(at: vaultRoot)
        let firstLaunch = makeFlow(
            connector: LifecycleCalendarConnector(
                connection: fixture.connection,
                events: [fixture.event],
                credentialStore: EncryptedGoogleCredentialStore(vault: firstVault)
            ),
            defaults: defaults,
            vault: firstVault,
            now: currentDate
        )
        await connectAndProtect(firstLaunch, calendarID: fixture.calendar.id, at: currentDate)

        let snapshotData = try XCTUnwrap(
            firstVault.loadData(as: .eventSnapshot, for: fixture.account.id)
        )
        let snapshot = try JSONDecoder().decode(LifecycleEventSnapshot.self, from: snapshotData)
        XCTAssertEqual(
            snapshot.events.first?.meetingDescription,
            fixture.event.meetingDescription
        )

        let relaunchedVault = try makeVault(at: vaultRoot)
        let relaunch = makeFlow(
            connector: LifecycleCalendarConnector(
                connection: fixture.connection,
                events: [],
                credentialStore: EncryptedGoogleCredentialStore(vault: relaunchedVault),
                restoreMode: .transientFailure
            ),
            defaults: defaults,
            vault: relaunchedVault,
            now: currentDate
        )

        await relaunch.restoreSavedConnection()

        XCTAssertEqual(
            relaunch.upcomingCommitment?.meetingDescription,
            fixture.event.meetingDescription
        )
        XCTAssertTrue(relaunch.isEarlyReminderUnverified)
    }

    func testDisablingOutOfOfficeProtectionPrunesItsEncryptedEventSnapshot() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(
            now: currentDate,
            eventStartOffset: 5 * 60,
            eventType: .outOfOffice
        )
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }

        let vault = try makeVault(at: vaultRoot)
        let flow = makeFlow(
            connector: LifecycleCalendarConnector(
                connection: fixture.connection,
                events: [fixture.event],
                credentialStore: EncryptedGoogleCredentialStore(vault: vault)
            ),
            defaults: defaults,
            vault: vault,
            now: currentDate
        )
        flow.setOutOfOfficeProtectionEnabled(true)
        await connectAndProtect(flow, calendarID: fixture.calendar.id, at: currentDate)

        let enabledSnapshotData = try XCTUnwrap(
            vault.loadData(as: .eventSnapshot, for: fixture.account.id)
        )
        let enabledSnapshot = try JSONDecoder().decode(
            LifecycleEventSnapshot.self,
            from: enabledSnapshotData
        )
        XCTAssertEqual(enabledSnapshot.events, [fixture.event])

        flow.setOutOfOfficeProtectionEnabled(false)
        await settleScheduledRefreshes()

        let disabledSnapshotData = try XCTUnwrap(
            vault.loadData(as: .eventSnapshot, for: fixture.account.id)
        )
        let disabledSnapshot = try JSONDecoder().decode(
            LifecycleEventSnapshot.self,
            from: disabledSnapshotData
        )
        XCTAssertTrue(disabledSnapshot.events.isEmpty)
        XCTAssertNil(flow.upcomingCommitment)
        XCTAssertNil(flow.earlyReminderCommitment)
    }

    func testTransientRestoreKeepsCachedReminderButMarksItUnverified() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }

        let firstVault = try makeVault(at: vaultRoot)
        let firstLaunch = makeFlow(
            connector: LifecycleCalendarConnector(
                connection: fixture.connection,
                events: [fixture.event],
                credentialStore: EncryptedGoogleCredentialStore(vault: firstVault)
            ),
            defaults: defaults,
            vault: firstVault,
            now: currentDate
        )
        firstLaunch.setEarlyReminderLeadTime(minutes: 30)
        await connectAndProtect(firstLaunch, calendarID: fixture.calendar.id, at: currentDate)
        XCTAssertEqual(firstLaunch.earlyReminderCommitment, fixture.event)

        let relaunchedVault = try makeVault(at: vaultRoot)
        let relaunchedConnector = LifecycleCalendarConnector(
            connection: fixture.connection,
            events: [],
            credentialStore: EncryptedGoogleCredentialStore(vault: relaunchedVault),
            restoreMode: .transientFailure
        )
        let relaunch = makeFlow(
            connector: relaunchedConnector,
            defaults: defaults,
            vault: relaunchedVault,
            now: currentDate
        )

        await relaunch.restoreSavedConnection()

        XCTAssertEqual(relaunchedConnector.connectCallCount, 0)
        XCTAssertEqual(relaunchedConnector.restoreCallCount, 1)
        guard case .failed = relaunch.connectionState else {
            return XCTFail("Expected a transient restore failure to leave the account unavailable.")
        }
        guard case .unavailable = relaunch.coverage(for: fixture.account.id) else {
            return XCTFail("Expected unavailable coverage after a transient restore failure.")
        }
        XCTAssertEqual(relaunch.earlyReminderCommitment, fixture.event)
        XCTAssertTrue(relaunch.isEarlyReminderUnverified)
        XCTAssertNotNil(try relaunchedVault.loadData(as: .credential, for: fixture.account.id))
        XCTAssertNotNil(try relaunchedVault.loadData(as: .eventSnapshot, for: fixture.account.id))
    }

    func testInvalidCredentialRestoreRequiresReconnectAndPrunesCachedOccurrenceState() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }

        let firstVault = try makeVault(at: vaultRoot)
        let firstLaunch = makeFlow(
            connector: LifecycleCalendarConnector(
                connection: fixture.connection,
                events: [fixture.event],
                credentialStore: EncryptedGoogleCredentialStore(vault: firstVault)
            ),
            defaults: defaults,
            vault: firstVault,
            now: currentDate
        )
        await connectAndProtect(firstLaunch, calendarID: fixture.calendar.id, at: currentDate)
        XCTAssertEqual(firstLaunch.upcomingCommitment, fixture.event)
        XCTAssertTrue(firstLaunch.dismissCommitment(at: currentDate))
        XCTAssertEqual(firstLaunch.currentCommitmentDecision, .dismissed)
        XCTAssertTrue(firstLaunch.canRestoreProtection)
        XCTAssertNotNil(try firstVault.loadData(as: .eventSnapshot, for: fixture.account.id))

        let relaunchedVault = try makeVault(at: vaultRoot)
        let relaunchedConnector = LifecycleCalendarConnector(
            connection: fixture.connection,
            events: [],
            credentialStore: EncryptedGoogleCredentialStore(vault: relaunchedVault),
            restoreMode: .invalidCredential
        )
        let relaunch = makeFlow(
            connector: relaunchedConnector,
            defaults: defaults,
            vault: relaunchedVault,
            now: currentDate
        )

        await relaunch.restoreSavedConnection()

        XCTAssertEqual(relaunchedConnector.connectCallCount, 0)
        XCTAssertEqual(relaunchedConnector.restoreCallCount, 1)
        XCTAssertEqual(relaunch.connectionState, .reconnectRequired)
        XCTAssertEqual(relaunch.coverage(for: fixture.account.id), .reconnectRequired)
        XCTAssertEqual(relaunch.selectedCalendarIDs(for: fixture.account.id), [fixture.calendar.id])
        XCTAssertTrue(relaunch.isProtectionConfirmed(for: fixture.account.id))
        XCTAssertNil(try relaunchedVault.loadData(as: .eventSnapshot, for: fixture.account.id))
        XCTAssertNil(relaunch.upcomingCommitment)
        XCTAssertNil(relaunch.earlyReminderCommitment)
        XCTAssertNil(relaunch.strongAlertCommitment)
        XCTAssertFalse(relaunch.isStrongAlertPresented)
        XCTAssertNil(relaunch.currentCommitmentDecision)
        XCTAssertNil(relaunch.decisionCommitment)
        XCTAssertFalse(relaunch.canRestoreProtection)
        XCTAssertNil(relaunch.lastActionMessage)
        XCTAssertNil(relaunch.actionResultMessage(for: fixture.event))
    }

    func testVolatileTestStoreSurvivesFlowRecreationWithoutWritingGoogleDataToDefaults() async {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        defer { defaultsFixture.cleanUp() }
        let connector = LifecycleCalendarConnector(
            connection: fixture.connection,
            events: [fixture.event]
        )
        let firstLaunch = makeFlow(
            connector: connector,
            defaults: defaults,
            vault: nil,
            now: currentDate
        )

        await connectAndProtect(firstLaunch, calendarID: fixture.calendar.id, at: currentDate)

        let relaunch = makeFlow(
            connector: connector,
            defaults: defaults,
            vault: nil,
            now: currentDate
        )
        await relaunch.restoreSavedConnection()

        XCTAssertEqual(connector.connectCallCount, 1)
        XCTAssertEqual(connector.restoreCallCount, 1)
        XCTAssertEqual(relaunch.selectedCalendarIDs(for: fixture.account.id), [fixture.calendar.id])
        XCTAssertEqual(relaunch.upcomingCommitment, fixture.event)
        XCTAssertNil(defaults.data(forKey: "commitment-protection.configuration"))
        XCTAssertNil(defaults.data(forKey: "commitment-protection.activity-log"))
    }

    func testPersistedEventSnapshotKeepsOnlyOngoingAndNext24HourEvents() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let ongoing = CalendarEvent(
            id: "ongoing-event",
            title: "Ongoing review",
            startDate: currentDate.addingTimeInterval(-10 * 60),
            endDate: currentDate.addingTimeInterval(20 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: fixture.calendar.id,
            accountID: fixture.account.id
        )
        let nearHorizon = CalendarEvent(
            id: "near-horizon-event",
            title: "Tomorrow review",
            startDate: currentDate.addingTimeInterval(23 * 60 * 60),
            endDate: currentDate.addingTimeInterval(24 * 60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: fixture.calendar.id,
            accountID: fixture.account.id
        )
        let outsideHorizon = CalendarEvent(
            id: "outside-horizon-event",
            title: "Later review",
            startDate: currentDate.addingTimeInterval(25 * 60 * 60),
            endDate: currentDate.addingTimeInterval(26 * 60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: fixture.calendar.id,
            accountID: fixture.account.id
        )
        let ended = CalendarEvent(
            id: "ended-event",
            title: "Ended review",
            startDate: currentDate.addingTimeInterval(-60 * 60),
            endDate: currentDate.addingTimeInterval(-30 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: fixture.calendar.id,
            accountID: fixture.account.id
        )
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let vault = try makeVault(at: vaultRoot)
        let connector = LifecycleCalendarConnector(
            connection: fixture.connection,
            events: [outsideHorizon, ended, nearHorizon, ongoing],
            credentialStore: EncryptedGoogleCredentialStore(vault: vault),
            honorsRequestedWindow: false
        )
        let flow = makeFlow(
            connector: connector,
            defaults: defaults,
            vault: vault,
            now: currentDate
        )

        await connectAndProtect(flow, calendarID: fixture.calendar.id, at: currentDate)

        let snapshotData = try XCTUnwrap(
            vault.loadData(as: .eventSnapshot, for: fixture.account.id)
        )
        let snapshot = try JSONDecoder().decode(LifecycleEventSnapshot.self, from: snapshotData)
        XCTAssertEqual(Set(snapshot.events.map(\.id)), [ongoing.id, nearHorizon.id])
    }

    func testEventSnapshotIsPhysicallyDiscardedAfter24Hours() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let longCommitment = CalendarEvent(
            id: "long-event",
            title: "Long-running workshop",
            startDate: currentDate.addingTimeInterval(60 * 60),
            endDate: currentDate.addingTimeInterval(48 * 60 * 60),
            timeZoneIdentifier: nil,
            isAllDay: false,
            isAccepted: true,
            calendarID: fixture.calendar.id,
            accountID: fixture.account.id
        )
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let firstVault = try makeVault(at: vaultRoot)
        let firstConnector = LifecycleCalendarConnector(
            connection: fixture.connection,
            events: [longCommitment],
            credentialStore: EncryptedGoogleCredentialStore(vault: firstVault)
        )
        let firstLaunch = makeFlow(
            connector: firstConnector,
            defaults: defaults,
            vault: firstVault,
            now: currentDate
        )
        await connectAndProtect(firstLaunch, calendarID: fixture.calendar.id, at: currentDate)
        XCTAssertNotNil(try firstVault.loadData(as: .eventSnapshot, for: fixture.account.id))

        let afterRetentionWindow = currentDate.addingTimeInterval(24 * 60 * 60 + 1)
        let relaunchedVault = try makeVault(at: vaultRoot)
        let relaunch = makeFlow(
            connector: LifecycleCalendarConnector(
                connection: fixture.connection,
                events: [],
                credentialStore: EncryptedGoogleCredentialStore(vault: relaunchedVault),
                restoreMode: .transientFailure
            ),
            defaults: defaults,
            vault: relaunchedVault,
            now: afterRetentionWindow
        )

        await relaunch.restoreSavedConnection()

        XCTAssertNil(relaunch.upcomingCommitment)
        XCTAssertNil(relaunch.strongAlertCommitment)
        XCTAssertNil(try relaunchedVault.loadData(as: .eventSnapshot, for: fixture.account.id))
    }

    func testEventSnapshotLimitProducesUnavailableCoverageAndStoresNoPartialSnapshot() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let events = (0...2_000).map { index in
            let startDate = currentDate.addingTimeInterval(60 + Double(index * 40))
            return CalendarEvent(
                id: "event-\(index)",
                title: "Review \(index)",
                startDate: startDate,
                endDate: startDate.addingTimeInterval(5),
                timeZoneIdentifier: nil,
                isAllDay: false,
                isAccepted: true,
                calendarID: fixture.calendar.id,
                accountID: fixture.account.id
            )
        }
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let vault = try makeVault(at: vaultRoot)
        let connector = LifecycleCalendarConnector(
            connection: fixture.connection,
            events: events,
            credentialStore: EncryptedGoogleCredentialStore(vault: vault)
        )
        let flow = makeFlow(
            connector: connector,
            defaults: defaults,
            vault: vault,
            now: currentDate
        )

        await connectAndProtect(flow, calendarID: fixture.calendar.id, at: currentDate)

        guard case .unavailable(let message) = flow.coverage(for: fixture.account.id) else {
            return XCTFail("Expected explicit unavailable coverage when the protected snapshot exceeds its cap.")
        }
        XCTAssertTrue(message.contains("next 24 hours"))
        XCTAssertNil(try vault.loadData(as: .eventSnapshot, for: fixture.account.id))
    }

    func testDisconnectPreservesSavedAccountChoicesAndTodaysActivityButDeletesAuthorizationAndEvents() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let vault = try makeVault(at: vaultRoot)
        let connector = LifecycleCalendarConnector(
            connection: fixture.connection,
            events: [fixture.event],
            credentialStore: EncryptedGoogleCredentialStore(vault: vault)
        )
        let flow = makeFlow(
            connector: connector,
            defaults: defaults,
            vault: vault,
            now: currentDate
        )
        await connectAndProtect(flow, calendarID: fixture.calendar.id, at: currentDate)
        let activityIDsBeforeDisconnect = Set(
            flow.activityLog.filter { $0.accountID == fixture.account.id }.map(\.id)
        )

        let didDisconnect = await flow.disconnectGoogleAccount(accountID: fixture.account.id)
        XCTAssertTrue(didDisconnect)

        XCTAssertEqual(flow.coverage(for: fixture.account.id), .reconnectRequired)
        XCTAssertEqual(flow.selectedCalendarIDs(for: fixture.account.id), [fixture.calendar.id])
        XCTAssertTrue(activityIDsBeforeDisconnect.isSubset(of: Set(flow.activityLog.map(\.id))))
        XCTAssertTrue(flow.activityLog.contains {
            $0.kind == .accountDisconnected && $0.accountID == fixture.account.id
        })
        XCTAssertNil(flow.upcomingCommitment)
        XCTAssertNil(try vault.loadData(as: .credential, for: fixture.account.id))
        XCTAssertNil(try vault.loadData(as: .eventSnapshot, for: fixture.account.id))
        XCTAssertNotNil(try vault.loadData(as: .configuration, for: fixture.account.id))
        XCTAssertNotNil(try vault.loadData(as: .activity, for: fixture.account.id))

        let relaunchedVault = try makeVault(at: vaultRoot)
        let relaunch = makeFlow(
            connector: LifecycleCalendarConnector(
                connection: fixture.connection,
                events: [],
                credentialStore: EncryptedGoogleCredentialStore(vault: relaunchedVault),
                restoreMode: .missing
            ),
            defaults: defaults,
            vault: relaunchedVault,
            now: currentDate
        )
        await relaunch.restoreSavedConnection()

        XCTAssertEqual(relaunch.coverage(for: fixture.account.id), .reconnectRequired)
        XCTAssertEqual(relaunch.selectedCalendarIDs(for: fixture.account.id), [fixture.calendar.id])
        XCTAssertTrue(relaunch.activityLog.contains {
            $0.kind == .accountDisconnected && $0.accountID == fixture.account.id
        })
    }

    func testDisconnectStorageFailureDoesNotExposeVaultOperationPayload() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let defaultsFixture = makeDefaults()
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let vault = try makeVault(at: vaultRoot)
        let flow = makeFlow(
            connector: LifecycleCalendarConnector(
                connection: fixture.connection,
                events: [fixture.event]
            ),
            defaults: defaultsFixture.store,
            vault: vault,
            now: currentDate
        )
        await connectAndProtect(flow, calendarID: fixture.calendar.id, at: currentDate)
        let accountsDirectory = vaultRoot.appendingPathComponent("accounts", isDirectory: true)
        let accountDirectory = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: accountsDirectory,
                includingPropertiesForKeys: nil
            ).first
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o500)],
            ofItemAtPath: accountDirectory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: accountDirectory.path
            )
        }

        let didDisconnect = await flow.disconnectGoogleAccount(accountID: fixture.account.id)
        XCTAssertFalse(didDisconnect)
        XCTAssertTrue(flow.accountDisconnectionError?.contains("Protected storage operation failed.") == true)
        XCTAssertFalse(flow.accountDisconnectionError?.contains("removing an account record") == true)
    }

    func testRemoveAccountDeletesAllAccountScopedProtectedDataAndActivity() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let vault = try makeVault(at: vaultRoot)
        let connector = LifecycleCalendarConnector(
            connection: fixture.connection,
            events: [fixture.event],
            credentialStore: EncryptedGoogleCredentialStore(vault: vault)
        )
        let flow = makeFlow(
            connector: connector,
            defaults: defaults,
            vault: vault,
            now: currentDate
        )
        await connectAndProtect(flow, calendarID: fixture.calendar.id, at: currentDate)
        XCTAssertTrue(vault.containsAccount(fixture.account.id))

        let didRemove = await flow.removeGoogleAccount(accountID: fixture.account.id)
        XCTAssertTrue(didRemove)

        XCTAssertFalse(vault.containsAccount(fixture.account.id))
        XCTAssertNil(flow.coverage(for: fixture.account.id))
        XCTAssertTrue(flow.accountCoverages.isEmpty)
        XCTAssertFalse(flow.activityLog.contains { $0.accountID == fixture.account.id })
        XCTAssertEqual(connector.revokedAccountIDs, [fixture.account.id])

        let relaunch = makeFlow(
            connector: LifecycleCalendarConnector(
                connection: fixture.connection,
                events: [],
                restoreMode: .missing
            ),
            defaults: defaults,
            vault: try makeVault(at: vaultRoot),
            now: currentDate
        )
        await relaunch.restoreSavedConnection()
        XCTAssertTrue(relaunch.accountCoverages.isEmpty)
        XCTAssertTrue(relaunch.activityLog.isEmpty)
    }

    func testCredentialOnlyVaultAccountIsRecoveredAndRemovable() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }

        let vault = try makeVault(at: vaultRoot)
        let credentialStore = EncryptedGoogleCredentialStore(vault: vault)
        try await credentialStore.save(
            refreshToken: "refresh-\(fixture.account.id)",
            accountID: fixture.account.id
        )
        XCTAssertNotNil(try vault.loadData(as: .credential, for: fixture.account.id))
        XCTAssertNil(try vault.loadData(as: .configuration, for: fixture.account.id))

        let connector = LifecycleCalendarConnector(
            connection: fixture.connection,
            events: [],
            credentialStore: credentialStore
        )
        let flow = makeFlow(
            connector: connector,
            defaults: defaults,
            vault: vault,
            now: currentDate
        )

        await flow.restoreSavedConnection()

        XCTAssertEqual(connector.connectCallCount, 0)
        XCTAssertEqual(connector.restoreCallCount, 1)
        XCTAssertEqual(flow.connectedAccount, fixture.account)
        XCTAssertEqual(flow.connectionState, .connected)
        XCTAssertEqual(flow.accountCoverages.map(\.account), [fixture.account])
        XCTAssertEqual(flow.coverage(for: fixture.account.id), .noCoverage)
        XCTAssertTrue(flow.selectedCalendarIDs(for: fixture.account.id).isEmpty)
        XCTAssertFalse(flow.isProtectionConfirmed(for: fixture.account.id))
        XCTAssertNotNil(try vault.loadData(as: .credential, for: fixture.account.id))
        XCTAssertNotNil(try vault.loadData(as: .configuration, for: fixture.account.id))

        let didRemove = await flow.removeGoogleAccount(accountID: fixture.account.id)

        XCTAssertTrue(didRemove)
        XCTAssertEqual(connector.revokedAccountIDs, [fixture.account.id])
        XCTAssertFalse(vault.containsAccount(fixture.account.id))
        XCTAssertTrue(flow.accountCoverages.isEmpty)
    }

    func testLegacyPlaintextMigrationKeepsOnlySavedChoicesAndRequiresExplicitReconnect() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let legacySubject = "legacy-google-subject"
        let accountEmail = "person@example.com"
        let calendarID = "work-calendar"
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let legacyConfiguration: [String: Any] = [
            "accounts": [[
                "account": [
                    "id": legacySubject,
                    "email": accountEmail,
                    "displayName": "Legacy Person"
                ],
                "calendars": [[
                    "id": calendarID,
                    "name": "Work",
                    "accountID": legacySubject
                ]],
                "selectedCalendarIDs": [calendarID],
                "isProtectionConfirmed": true,
                "lastFreshEvents": []
            ]]
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: legacyConfiguration),
            forKey: "commitment-protection.configuration"
        )
        let legacyActivity = ProtectionActivity(
            occurredAt: currentDate,
            actor: .system,
            kind: .strongAlertShown,
            title: "Legacy alert",
            detail: "Legacy plaintext activity.",
            commitmentTitle: "Private legacy event",
            commitmentID: "legacy-event",
            accountID: legacySubject,
            accountEmail: accountEmail,
            calendarID: calendarID,
            calendarName: "Work"
        )
        defaults.set(
            try JSONEncoder().encode([legacyActivity]),
            forKey: "commitment-protection.activity-log"
        )
        let legacyCredentialKey = "google.refreshToken.\(legacySubject)"
        defaults.set("plaintext-refresh-token", forKey: legacyCredentialKey)

        let vault = try makeVault(at: vaultRoot)
        let migratedAccount = GoogleAccount(id: accountEmail, email: accountEmail, displayName: "")
        let migratedCalendar = CalendarOption(id: calendarID, name: "Work", accountID: accountEmail)
        let connector = LifecycleCalendarConnector(
            connection: GoogleCalendarConnection(
                account: migratedAccount,
                calendars: [migratedCalendar]
            ),
            events: [],
            restoreMode: .missing
        )
        let flow = makeFlow(
            connector: connector,
            defaults: defaults,
            vault: vault,
            now: currentDate
        )

        await flow.restoreSavedConnection()

        XCTAssertEqual(connector.connectCallCount, 0)
        XCTAssertEqual(connector.restoreCallCount, 1)
        XCTAssertEqual(flow.coverage(for: accountEmail), .reconnectRequired)
        XCTAssertEqual(flow.selectedCalendarIDs(for: accountEmail), [calendarID])
        XCTAssertTrue(flow.isProtectionConfirmed(for: accountEmail))
        XCTAssertFalse(flow.activityLog.contains { $0.id == legacyActivity.id })
        XCTAssertNil(defaults.data(forKey: "commitment-protection.configuration"))
        XCTAssertNil(defaults.data(forKey: "commitment-protection.activity-log"))
        XCTAssertNil(defaults.string(forKey: legacyCredentialKey))
        XCTAssertNil(try vault.loadData(as: .credential, for: accountEmail))
        XCTAssertNil(try vault.loadData(as: .eventSnapshot, for: accountEmail))
        XCTAssertNotNil(try vault.loadData(as: .configuration, for: accountEmail))
    }

    func testMalformedLegacyDefaultsAreScrubbedImmediatelyWithoutBlockingEncryptedRestore() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let defaultsFixture = makeDefaults()
        let defaults = defaultsFixture.store
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let vault = try makeVault(at: vaultRoot)
        await persistProtectedAccounts(
            [fixture],
            defaults: defaults,
            vault: vault,
            now: currentDate
        )
        defaults.set(
            Data("malformed-legacy-configuration".utf8),
            forKey: "commitment-protection.configuration"
        )
        defaults.set(
            Data("malformed-legacy-activity".utf8),
            forKey: "commitment-protection.activity-log"
        )
        let relaunch = makeFlow(
            connector: LifecycleMultiAccountConnector(
                restoreConnections: connectionMap(for: [fixture]),
                eventsByAccountID: eventsMap(for: [fixture])
            ),
            defaults: defaults,
            vault: vault,
            now: currentDate
        )

        XCTAssertNil(defaults.data(forKey: "commitment-protection.configuration"))
        XCTAssertNil(defaults.data(forKey: "commitment-protection.activity-log"))

        await relaunch.restoreSavedConnection()

        XCTAssertEqual(relaunch.connectedAccount, fixture.account)
        XCTAssertEqual(relaunch.coverage(for: fixture.account.id), .fresh)
        XCTAssertEqual(relaunch.selectedCalendarIDs(for: fixture.account.id), [fixture.calendar.id])
        XCTAssertTrue(relaunch.isProtectionConfirmed(for: fixture.account.id))
        XCTAssertEqual(relaunch.upcomingCommitment, fixture.event)
        XCTAssertNotNil(try vault.loadData(as: .configuration, for: fixture.account.id))
        XCTAssertNotNil(try vault.loadData(as: .eventSnapshot, for: fixture.account.id))
    }

    func testCorruptConfigurationIsIsolatedWithoutOverwritingItOrStoppingHealthyProtection() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let healthy = makeFixture(
            now: currentDate,
            accountID: "healthy@example.com",
            calendarID: "healthy-calendar",
            eventID: "healthy-event"
        )
        let corrupt = makeFixture(
            now: currentDate,
            accountID: "corrupt@example.com",
            calendarID: "corrupt-calendar",
            eventID: "corrupt-event",
            eventStartOffset: 60 * 60
        )
        let fixtures = [healthy, corrupt]
        let defaultsFixture = makeDefaults()
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let vault = try makeVault(at: vaultRoot)
        await persistProtectedAccounts(
            fixtures,
            defaults: defaultsFixture.store,
            vault: vault,
            now: currentDate
        )
        let corruptConfiguration = Data("not-json-configuration".utf8)
        try vault.storeData(
            corruptConfiguration,
            as: .configuration,
            for: corrupt.account.id
        )
        let connector = LifecycleMultiAccountConnector(
            restoreConnections: connectionMap(for: fixtures),
            eventsByAccountID: eventsMap(for: fixtures)
        )
        let relaunch = makeFlow(
            connector: connector,
            defaults: defaultsFixture.store,
            vault: vault,
            now: currentDate
        )

        await relaunch.restoreSavedConnection()

        XCTAssertEqual(
            Set(relaunch.accountCoverages.map(\.account.id)),
            Set(fixtures.map(\.account.id))
        )
        XCTAssertEqual(relaunch.coverage(for: healthy.account.id), .fresh)
        guard case .unavailable(let message) = relaunch.coverage(for: corrupt.account.id) else {
            return XCTFail("Expected the corrupt account to remain visible with unavailable coverage.")
        }
        XCTAssertTrue(message.contains("could not be read"))
        XCTAssertTrue(relaunch.requiresEncryptedStorageReset)
        XCTAssertNotNil(relaunch.encryptedStorageError)
        XCTAssertEqual(relaunch.upcomingCommitment, healthy.event)
        XCTAssertTrue(connector.loadedEventAccountIDs.contains(healthy.account.id))
        XCTAssertFalse(connector.loadedEventAccountIDs.contains(corrupt.account.id))
        XCTAssertEqual(
            try vault.loadData(as: .configuration, for: corrupt.account.id),
            corruptConfiguration
        )
        XCTAssertNotNil(try vault.loadData(as: .configuration, for: healthy.account.id))
    }

    func testCorruptEventSnapshotRequiresResetWithoutAbortingHealthyAccountRestore() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let healthy = makeFixture(
            now: currentDate,
            accountID: "healthy@example.com",
            calendarID: "healthy-calendar",
            eventID: "healthy-event"
        )
        let corrupt = makeFixture(
            now: currentDate,
            accountID: "corrupt@example.com",
            calendarID: "corrupt-calendar",
            eventID: "corrupt-event",
            eventStartOffset: 60 * 60
        )
        let fixtures = [healthy, corrupt]
        let defaultsFixture = makeDefaults()
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let vault = try makeVault(at: vaultRoot)
        await persistProtectedAccounts(
            fixtures,
            defaults: defaultsFixture.store,
            vault: vault,
            now: currentDate
        )
        let corruptSnapshot = Data("not-json-event-snapshot".utf8)
        try vault.storeData(
            corruptSnapshot,
            as: .eventSnapshot,
            for: corrupt.account.id
        )
        let connector = LifecycleMultiAccountConnector(
            restoreConnections: connectionMap(for: fixtures),
            eventsByAccountID: eventsMap(for: fixtures)
        )
        let relaunch = makeFlow(
            connector: connector,
            defaults: defaultsFixture.store,
            vault: vault,
            now: currentDate
        )

        await relaunch.restoreSavedConnection()

        XCTAssertEqual(relaunch.coverage(for: healthy.account.id), .fresh)
        guard case .unavailable = relaunch.coverage(for: corrupt.account.id) else {
            return XCTFail("Expected corrupt event data to isolate only its account.")
        }
        XCTAssertTrue(relaunch.requiresEncryptedStorageReset)
        XCTAssertEqual(relaunch.upcomingCommitment, healthy.event)
        XCTAssertTrue(connector.loadedEventAccountIDs.contains(healthy.account.id))
        XCTAssertFalse(connector.loadedEventAccountIDs.contains(corrupt.account.id))
        XCTAssertEqual(
            try vault.loadData(as: .eventSnapshot, for: corrupt.account.id),
            corruptSnapshot
        )
    }

    func testActivityRestoreAndSaveApplyGlobalCountAndByteCapsAcrossAccounts() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let first = makeFixture(
            now: currentDate,
            accountID: "first@example.com",
            calendarID: "first-calendar",
            eventID: "first-event"
        )
        let second = makeFixture(
            now: currentDate,
            accountID: "second@example.com",
            calendarID: "second-calendar",
            eventID: "second-event"
        )
        let fixtures = [first, second]
        let defaultsFixture = makeDefaults()
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let vault = try makeVault(at: vaultRoot)
        await persistProtectedAccounts(
            fixtures,
            defaults: defaultsFixture.store,
            vault: vault,
            now: currentDate
        )
        let activities = (0..<1_200).map { index in
            let fixture = fixtures[index % fixtures.count]
            return ProtectionActivity(
                id: deterministicUUID(index),
                occurredAt: currentDate.addingTimeInterval(-Double(index)),
                actor: .system,
                kind: .coverageRestored,
                title: "Coverage restored \(index)",
                detail: String(repeating: "activity-detail-", count: 120),
                accountID: fixture.account.id,
                accountEmail: fixture.account.email,
                calendarID: fixture.calendar.id,
                calendarName: fixture.calendar.name
            )
        }
        XCTAssertGreaterThan(try JSONEncoder().encode(activities).count, 1_024 * 1_024)
        for fixture in fixtures {
            let accountActivities = activities.filter { $0.accountID == fixture.account.id }
            try vault.storeData(
                JSONEncoder().encode(accountActivities),
                as: .activity,
                for: fixture.account.id
            )
        }
        let relaunch = makeFlow(
            connector: LifecycleMultiAccountConnector(
                restoreConnections: [:],
                eventsByAccountID: [:]
            ),
            defaults: defaultsFixture.store,
            vault: vault,
            now: currentDate
        )

        await relaunch.restoreSavedConnection()

        let restoredActivities = relaunch.activityLog
        XCTAssertFalse(restoredActivities.isEmpty)
        XCTAssertLessThanOrEqual(restoredActivities.count, 1_000)
        XCTAssertLessThanOrEqual(
            try JSONEncoder().encode(restoredActivities).count,
            1_024 * 1_024
        )
        XCTAssertEqual(
            restoredActivities.map(\.id),
            Array(activities.prefix(restoredActivities.count)).map(\.id)
        )
        XCTAssertEqual(
            Set(restoredActivities.compactMap(\.accountID)),
            Set(fixtures.map(\.account.id))
        )

        var persistedActivities: [ProtectionActivity] = []
        var persistedByteCount = 0
        for fixture in fixtures {
            let data = try XCTUnwrap(
                vault.loadData(as: .activity, for: fixture.account.id)
            )
            persistedByteCount += data.count
            persistedActivities.append(
                contentsOf: try JSONDecoder().decode([ProtectionActivity].self, from: data)
            )
        }
        persistedActivities.sort { $0.occurredAt > $1.occurredAt }
        XCTAssertLessThanOrEqual(persistedActivities.count, 1_000)
        XCTAssertLessThanOrEqual(persistedByteCount, 1_024 * 1_024)
        XCTAssertEqual(persistedActivities.map(\.id), restoredActivities.map(\.id))
    }

    func testRelaunchDiscardsMergedActivityWhenASourceAccountWasDeletedAndRewritesOwnerRecord() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let first = makeFixture(
            now: currentDate,
            accountID: "first@example.com",
            calendarID: "first-calendar",
            eventID: "first-event"
        )
        let second = makeFixture(
            now: currentDate,
            accountID: "second@example.com",
            calendarID: "second-calendar",
            eventID: "second-event"
        )
        let defaultsFixture = makeDefaults()
        let vaultRoot = makeVaultRoot()
        defer {
            defaultsFixture.cleanUp()
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let vault = try makeVault(at: vaultRoot)
        await persistProtectedAccounts(
            [first, second],
            defaults: defaultsFixture.store,
            vault: vault,
            now: currentDate
        )
        let retainedActivity = ProtectionActivity(
            occurredAt: currentDate,
            actor: .system,
            kind: .coverageRestored,
            title: "First account coverage restored",
            detail: "Only the first account contributed to this activity.",
            accountID: first.account.id,
            accountEmail: first.account.email,
            calendarID: first.calendar.id,
            calendarName: first.calendar.name,
            sourceAccountIDs: [first.account.id]
        )
        let mergedActivity = ProtectionActivity(
            occurredAt: currentDate.addingTimeInterval(-1),
            actor: .user,
            kind: .dismissed,
            title: "Merged reminder dismissed",
            detail: "Both accounts contributed protected event data.",
            commitmentTitle: "Merged review",
            commitmentID: "merged-event",
            commitmentStartDate: first.event.startDate,
            accountID: first.account.id,
            accountEmail: first.account.email,
            calendarID: first.calendar.id,
            calendarName: first.calendar.name,
            sourceAccountIDs: [first.account.id, second.account.id]
        )
        try vault.storeData(
            JSONEncoder().encode([retainedActivity, mergedActivity]),
            as: .activity,
            for: first.account.id
        )

        try vault.removeAccount(second.account.id)
        XCTAssertFalse(vault.containsAccount(second.account.id))

        let relaunch = makeFlow(
            connector: LifecycleMultiAccountConnector(
                restoreConnections: connectionMap(for: [first]),
                eventsByAccountID: eventsMap(for: [first])
            ),
            defaults: defaultsFixture.store,
            vault: vault,
            now: currentDate
        )
        await relaunch.restoreSavedConnection()

        XCTAssertFalse(relaunch.activityLog.contains { $0.id == mergedActivity.id })
        XCTAssertEqual(relaunch.activityLog.map(\.id), [retainedActivity.id])
        let rewrittenData = try XCTUnwrap(
            vault.loadData(as: .activity, for: first.account.id)
        )
        let rewrittenActivities = try JSONDecoder().decode(
            [ProtectionActivity].self,
            from: rewrittenData
        )
        XCTAssertEqual(rewrittenActivities.map(\.id), [retainedActivity.id])
        XCTAssertFalse(rewrittenActivities.contains { $0.id == mergedActivity.id })
    }

    func testInitialStorageFailureOnlyOffersResetForCorruption() {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let defaultsFixture = makeDefaults()
        defer { defaultsFixture.cleanUp() }
        let connector = LifecycleCalendarConnector(
            connection: fixture.connection,
            events: []
        )
        let unavailableError = EncryptedGoogleVaultError.secureEnclaveUnavailable
        let unavailable = makeFlow(
            connector: connector,
            defaults: defaultsFixture.store,
            vault: nil,
            now: currentDate,
            initialEncryptedStorageError: unavailableError.localizedDescription,
            initialEncryptedStorageRequiresReset: false
        )

        XCTAssertEqual(unavailable.encryptedStorageError, unavailableError.localizedDescription)
        XCTAssertFalse(unavailable.requiresEncryptedStorageReset)

        for corruptionError in [
            EncryptedGoogleVaultError.keyMaterialCorrupted,
            EncryptedGoogleVaultError.indexCorrupted
        ] {
            let corrupt = makeFlow(
                connector: connector,
                defaults: defaultsFixture.store,
                vault: nil,
                now: currentDate,
                initialEncryptedStorageError: corruptionError.localizedDescription,
                initialEncryptedStorageRequiresReset: true
            )
            XCTAssertEqual(corrupt.encryptedStorageError, corruptionError.localizedDescription)
            XCTAssertTrue(corrupt.requiresEncryptedStorageReset)
        }
    }

    func testEncryptedStorageRecoveryFailureDoesNotExposeUnknownNSErrorDetails() {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let defaultsFixture = makeDefaults()
        defer { defaultsFixture.cleanUp() }
        let sensitivePath = "/Users/alice/Library/Application Support/Meeting Incoming/private-token.json"
        let sensitiveMessage = "Unable to read \(sensitivePath)"
        let flow = makeFlow(
            connector: LifecycleCalendarConnector(
                connection: fixture.connection,
                events: []
            ),
            defaults: defaultsFixture.store,
            vault: nil,
            now: currentDate,
            recoverEncryptedGoogleStorage: {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadNoPermissionError,
                    userInfo: [
                        NSFilePathErrorKey: sensitivePath,
                        NSLocalizedDescriptionKey: sensitiveMessage
                    ]
                )
            }
        )

        XCTAssertFalse(flow.resetEncryptedGoogleData())
        XCTAssertEqual(flow.encryptedStorageError, "Protected storage operation failed.")
        XCTAssertFalse(flow.encryptedStorageError?.contains(sensitivePath) == true)
        XCTAssertFalse(flow.encryptedStorageError?.contains(sensitiveMessage) == true)
    }

    func testEncryptedStorageRecoveryFailureDiscardsStorageFailurePayload() {
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeFixture(now: currentDate)
        let defaultsFixture = makeDefaults()
        defer { defaultsFixture.cleanUp() }
        let sensitivePayload = "reading /Users/alice/Library/Application Support/Meeting Incoming/account-index"
        let flow = makeFlow(
            connector: LifecycleCalendarConnector(
                connection: fixture.connection,
                events: []
            ),
            defaults: defaultsFixture.store,
            vault: nil,
            now: currentDate,
            recoverEncryptedGoogleStorage: {
                throw EncryptedGoogleVaultError.storageFailed(sensitivePayload)
            }
        )

        XCTAssertFalse(flow.resetEncryptedGoogleData())
        XCTAssertEqual(flow.encryptedStorageError, "Protected storage operation failed.")
        XCTAssertFalse(flow.encryptedStorageError?.contains(sensitivePayload) == true)
    }

    private func connectAndProtect(
        _ flow: CommitmentProtectionFlow,
        calendarID: String,
        at date: Date
    ) async {
        await flow.connectGoogleAccount()
        flow.setCalendarSelected(true, calendarID: calendarID)
        XCTAssertTrue(flow.confirmProtection())
        await settleScheduledRefreshes()
        await flow.refreshCommitmentProtection(at: date)
        await settleScheduledRefreshes()
    }

    private func makeFlow(
        connector: any GoogleCalendarConnecting,
        defaults: UserDefaults,
        vault: EncryptedGoogleVault?,
        now: Date,
        initialEncryptedStorageError: String? = nil,
        initialEncryptedStorageRequiresReset: Bool = false,
        recoverEncryptedGoogleStorage: (@Sendable () throws -> RecoveredEncryptedGoogleStorage)? = nil
    ) -> CommitmentProtectionFlow {
        CommitmentProtectionFlow(
            calendarConnector: connector,
            launchAtLogin: LifecycleLaunchAtLoginController(),
            stateStore: defaults,
            encryptedGoogleVault: vault,
            initialEncryptedStorageError: initialEncryptedStorageError,
            initialEncryptedStorageRequiresReset: initialEncryptedStorageRequiresReset,
            recoverEncryptedGoogleStorage: recoverEncryptedGoogleStorage,
            now: { now }
        )
    }

    private func makeFixture(
        now: Date,
        accountID: String = "person@example.com",
        calendarID: String = "work",
        eventID: String = "event-1",
        eventStartOffset: TimeInterval = 30 * 60,
        meetingDescription: String? = nil,
        eventType: CalendarEventType? = nil
    ) -> LifecycleFixture {
        let account = GoogleAccount(
            id: accountID,
            email: accountID,
            displayName: ""
        )
        let calendar = CalendarOption(id: calendarID, name: "Work", accountID: account.id)
        let event = CalendarEvent(
            id: eventID,
            title: "Customer review",
            meetingDescription: meetingDescription,
            startDate: now.addingTimeInterval(eventStartOffset),
            endDate: now.addingTimeInterval(eventStartOffset + 30 * 60),
            timeZoneIdentifier: "Europe/Istanbul",
            isAllDay: false,
            isAccepted: true,
            calendarID: calendar.id,
            accountID: account.id,
            eventType: eventType
        )
        return LifecycleFixture(
            account: account,
            calendar: calendar,
            event: event,
            connection: GoogleCalendarConnection(account: account, calendars: [calendar])
        )
    }

    private func persistProtectedAccounts(
        _ fixtures: [LifecycleFixture],
        defaults: UserDefaults,
        vault: EncryptedGoogleVault,
        now: Date
    ) async {
        let flow = makeFlow(
            connector: LifecycleMultiAccountConnector(
                connectQueue: fixtures.map(\.connection),
                restoreConnections: [:],
                eventsByAccountID: eventsMap(for: fixtures)
            ),
            defaults: defaults,
            vault: vault,
            now: now
        )
        for fixture in fixtures {
            await connectAndProtect(flow, calendarID: fixture.calendar.id, at: now)
        }
    }

    private func connectionMap(
        for fixtures: [LifecycleFixture]
    ) -> [String: GoogleCalendarConnection] {
        Dictionary(uniqueKeysWithValues: fixtures.map { ($0.account.id, $0.connection) })
    }

    private func eventsMap(
        for fixtures: [LifecycleFixture]
    ) -> [String: [CalendarEvent]] {
        Dictionary(uniqueKeysWithValues: fixtures.map { ($0.account.id, [$0.event]) })
    }

    private func deterministicUUID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
    }

    private func makeDefaults() -> LifecycleDefaultsFixture {
        let suiteName = "EncryptedPersistenceLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return LifecycleDefaultsFixture(store: defaults, suiteName: suiteName)
    }

    private func makeVaultRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "EncryptedPersistenceLifecycleTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func makeVault(at root: URL) throws -> EncryptedGoogleVault {
        try EncryptedGoogleVault(
            rootDirectory: root,
            keyProtector: LifecycleVaultKeyProtector()
        )
    }

    private func settleScheduledRefreshes() async {
        for _ in 0..<12 {
            await Task.yield()
        }
    }
}

private struct LifecycleFixture {
    let account: GoogleAccount
    let calendar: CalendarOption
    let event: CalendarEvent
    let connection: GoogleCalendarConnection
}

private struct LifecycleDefaultsFixture {
    let store: UserDefaults
    let suiteName: String

    func cleanUp() {
        store.removePersistentDomain(forName: suiteName)
    }
}

private struct LifecycleEventSnapshot: Decodable {
    let events: [CalendarEvent]
}

private enum LifecycleRestoreMode: Sendable {
    case available
    case missing
    case transientFailure
    case invalidCredential
}

private enum LifecycleConnectorError: LocalizedError, Sendable {
    case transient

    var errorDescription: String? {
        "The test calendar service is temporarily unavailable."
    }
}

private final class LifecycleCalendarConnector:
    GoogleCalendarConnecting,
    GoogleAuthorizationRevoking,
    @unchecked Sendable
{
    private let connection: GoogleCalendarConnection
    private let credentialStore: EncryptedGoogleCredentialStore?
    private let restoreMode: LifecycleRestoreMode
    private let honorsRequestedWindow: Bool
    private let lock = NSLock()
    private var storedEvents: [CalendarEvent]
    private var storedConnectCallCount = 0
    private var storedRestoreCallCount = 0
    private var storedRevokedAccountIDs: [String] = []

    init(
        connection: GoogleCalendarConnection,
        events: [CalendarEvent],
        credentialStore: EncryptedGoogleCredentialStore? = nil,
        restoreMode: LifecycleRestoreMode = .available,
        honorsRequestedWindow: Bool = true
    ) {
        self.connection = connection
        storedEvents = events
        self.credentialStore = credentialStore
        self.restoreMode = restoreMode
        self.honorsRequestedWindow = honorsRequestedWindow
    }

    var connectCallCount: Int {
        lock.withLock { storedConnectCallCount }
    }

    var restoreCallCount: Int {
        lock.withLock { storedRestoreCallCount }
    }

    var revokedAccountIDs: [String] {
        lock.withLock { storedRevokedAccountIDs }
    }

    func connect() async throws -> GoogleCalendarConnection {
        lock.withLock { storedConnectCallCount += 1 }
        if let credentialStore {
            try await credentialStore.save(
                refreshToken: "refresh-\(connection.account.id)",
                accountID: connection.account.id
            )
        }
        return connection
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        lock.withLock { storedRestoreCallCount += 1 }
        switch restoreMode {
        case .missing:
            return nil
        case .transientFailure:
            throw LifecycleConnectorError.transient
        case .invalidCredential:
            throw GoogleCalendarConnectorError.tokenExchangeFailed(
                400,
                "invalid_grant: refresh token revoked"
            )
        case .available:
            break
        }
        guard accountID == connection.account.id else { return nil }
        if let credentialStore,
           try await credentialStore.load(accountID: accountID) == nil {
            return nil
        }
        return connection
    }

    func disconnect(accountID: String) throws {
        lock.withLock { storedRevokedAccountIDs.append(accountID) }
    }

    func revokeAuthorization(accountID: String) async throws -> GoogleAuthorizationRevocationResult {
        if let credentialStore {
            try await credentialStore.remove(accountID: accountID)
        }
        lock.withLock { storedRevokedAccountIDs.append(accountID) }
        return .revoked
    }

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        lock.withLock {
            storedEvents.filter { event in
                guard event.accountID == accountID,
                      event.calendarID == calendarID else {
                    return false
                }
                guard honorsRequestedWindow else { return true }
                return (event.endDate ?? .distantPast) > startDate &&
                    (event.startDate ?? .distantFuture) <= endDate
            }
        }
    }
}

private enum LifecycleMultiAccountConnectorError: Error {
    case noQueuedConnection
}

private final class LifecycleMultiAccountConnector: GoogleCalendarConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private let restoreConnections: [String: GoogleCalendarConnection]
    private let eventsByAccountID: [String: [CalendarEvent]]
    private var storedConnectQueue: [GoogleCalendarConnection]
    private var storedLoadedEventAccountIDs: [String] = []

    init(
        connectQueue: [GoogleCalendarConnection] = [],
        restoreConnections: [String: GoogleCalendarConnection],
        eventsByAccountID: [String: [CalendarEvent]]
    ) {
        storedConnectQueue = connectQueue
        self.restoreConnections = restoreConnections
        self.eventsByAccountID = eventsByAccountID
    }

    var loadedEventAccountIDs: [String] {
        lock.withLock { storedLoadedEventAccountIDs }
    }

    func connect() async throws -> GoogleCalendarConnection {
        try lock.withLock {
            guard !storedConnectQueue.isEmpty else {
                throw LifecycleMultiAccountConnectorError.noQueuedConnection
            }
            return storedConnectQueue.removeFirst()
        }
    }

    func restore(accountID: String) async throws -> GoogleCalendarConnection? {
        restoreConnections[accountID]
    }

    func disconnect(accountID: String) throws {}

    func loadEvents(
        accountID: String,
        calendarID: String,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [CalendarEvent] {
        lock.withLock {
            storedLoadedEventAccountIDs.append(accountID)
            return (eventsByAccountID[accountID] ?? []).filter { event in
                event.calendarID == calendarID &&
                    (event.endDate ?? .distantPast) > startDate &&
                    (event.startDate ?? .distantFuture) <= endDate
            }
        }
    }
}

@MainActor
private final class LifecycleLaunchAtLoginController: LaunchAtLoginControlling {
    private(set) var isEnabled = false

    func enable() throws {
        isEnabled = true
    }

    func disable() throws {
        isEnabled = false
    }
}

private struct LifecycleVaultKeyProtector: EncryptedGoogleVaultKeyProtecting {
    private static let keyMaterial = Data("lifecycle-test-key-material".utf8)

    func createKeyMaterial() throws -> Data {
        Self.keyMaterial
    }

    func restoreMasterKey(from keyMaterial: Data) throws -> SymmetricKey {
        guard keyMaterial == Self.keyMaterial else {
            throw EncryptedGoogleVaultError.keyMaterialCorrupted
        }
        return SymmetricKey(data: SHA256.hash(data: keyMaterial))
    }
}
