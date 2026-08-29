import CommitmentProtection
import Foundation
import XCTest
@testable import InYourFace

final class RuntimeBootstrapTests: XCTestCase {
    @MainActor
    func testCommittedResetRecoveryFactoryDoesNotOpenVaultOrMutateDefaults() async throws {
        let suiteName = "RuntimeBootstrapTests.recovery.\(UUID().uuidString)"
        let stateStore = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        stateStore.set(
            Data("legacy-configuration".utf8),
            forKey: "commitment-protection.configuration"
        )
        stateStore.set(
            "legacy-refresh-token",
            forKey: "google.refreshToken.account-id"
        )
        let before = stateStore.persistentDomain(forName: suiteName) ?? [:]
        var vaultOpenCount = 0

        let composition = RuntimeProtectionFactory.make(
            profile: .production(vaultApplicationIdentifier: "com.example.recovery"),
            stateStore: stateStore,
            oauthConfiguration: GoogleCalendarOAuthConfiguration(clientID: "unused"),
            startupMode: .committedResetRecovery,
            productionVaultFactory: { _ in
                vaultOpenCount += 1
                throw RecoveryFactoryProbeError.unexpectedVaultOpen
            }
        )
        await composition.flow.restoreSavedConnection()
        composition.flow.startMonitoring()
        let after = stateStore.persistentDomain(forName: suiteName) ?? [:]

        XCTAssertEqual(vaultOpenCount, 0)
        XCTAssertTrue(composition.flow.isAppManagedDataResetInProgress)
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: after))
    }

    func testThreeOfFivePostRevocationJournalUsesCommittedResetRecovery() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let journal = ResetJournal(
            fileURL: fixture.control.appendingPathComponent(
                "app-managed-data-reset.v1.json"
            )
        )
        let snapshot = try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [
                .revokeGoogleAuthorization(position: 0),
                .revokeGoogleAuthorization(position: 1),
                .unregisterLaunchAtLogin,
                .eraseLocalData,
                .relaunch
            ]
        )
        for entry in snapshot.entries.prefix(3) {
            try await journal.markRunning(entry.id)
            try await journal.markCompleted(entry.id)
        }

        let helperRecovery = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )
        let journalRecovery = RuntimeBootstrap.resetJournalRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertTrue(journalRecovery.appDataRequiresResume)
        XCTAssertFalse(journalRecovery.requiresProtectedStorage)
        XCTAssertEqual(
            RuntimeBootstrap.resetProtectionStartupMode(
                helperRecovery: helperRecovery,
                journalRecovery: journalRecovery
            ),
            .committedResetRecovery
        )
    }

    func testPendingRevocationJournalUsesActiveResetRecovery() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let journal = ResetJournal(
            fileURL: fixture.control.appendingPathComponent(
                "app-managed-data-reset.v1.json"
            )
        )
        try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [
                .revokeGoogleAuthorization(position: 0),
                .revokeGoogleAuthorization(position: 1),
                .unregisterLaunchAtLogin,
                .eraseLocalData,
                .relaunch
            ]
        )

        let helperRecovery = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )
        let journalRecovery = RuntimeBootstrap.resetJournalRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertTrue(journalRecovery.appDataRequiresResume)
        XCTAssertTrue(journalRecovery.requiresProtectedStorage)
        XCTAssertEqual(
            RuntimeBootstrap.resetProtectionStartupMode(
                helperRecovery: helperRecovery,
                journalRecovery: journalRecovery
            ),
            .activeResetRecovery
        )
    }

#if !INTERNAL_BUILD
    func testPublicBuildQuarantinesActiveInternalResetJournalForManualRepair() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let journal = ResetJournal(
            fileURL: fixture.control.appendingPathComponent(
                "internal-full-first-run.v1.json"
            )
        )
        try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [
                .revokeGoogleAuthorization(position: 0),
                .unregisterLaunchAtLogin,
                .eraseLocalData,
                .relaunch
            ]
        )

        let helperRecovery = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )
        let journalRecovery = RuntimeBootstrap.resetJournalRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertFalse(journalRecovery.internalRequiresResume)
        XCTAssertFalse(journalRecovery.requiresProtectedStorage)
        XCTAssertTrue(journalRecovery.requiresManualRepair)
        XCTAssertTrue(journalRecovery.report?.contains("matching internal build") == true)
        XCTAssertEqual(
            RuntimeBootstrap.resetProtectionStartupMode(
                helperRecovery: helperRecovery,
                journalRecovery: journalRecovery
            ),
            .committedResetRecovery
        )
    }

    func testPublicBuildQuarantinesUnreadableInternalResetJournalForManualRepair() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let journalURL = fixture.control.appendingPathComponent(
            "internal-full-first-run.v1.json"
        )
        try Data("not a reset journal".utf8).write(to: journalURL, options: .atomic)

        let helperRecovery = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )
        let journalRecovery = RuntimeBootstrap.resetJournalRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertFalse(journalRecovery.internalRequiresResume)
        XCTAssertFalse(journalRecovery.requiresProtectedStorage)
        XCTAssertTrue(journalRecovery.requiresManualRepair)
        XCTAssertTrue(journalRecovery.report?.contains("matching internal build") == true)
        XCTAssertEqual(
            RuntimeBootstrap.resetProtectionStartupMode(
                helperRecovery: helperRecovery,
                journalRecovery: journalRecovery
            ),
            .committedResetRecovery
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func testPublicBuildQuarantinesUnsafeInternalResetJournalForManualRepair() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let externalJournal = fixture.root.appendingPathComponent(
            "external-internal-reset.json"
        )
        try Data("external journal".utf8).write(to: externalJournal, options: .atomic)
        let journalURL = fixture.control.appendingPathComponent(
            "internal-full-first-run.v1.json"
        )
        try FileManager.default.createSymbolicLink(
            at: journalURL,
            withDestinationURL: externalJournal
        )

        let helperRecovery = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )
        let journalRecovery = RuntimeBootstrap.resetJournalRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertFalse(journalRecovery.internalRequiresResume)
        XCTAssertFalse(journalRecovery.requiresProtectedStorage)
        XCTAssertTrue(journalRecovery.requiresManualRepair)
        XCTAssertTrue(journalRecovery.report?.contains("matching internal build") == true)
        XCTAssertEqual(
            RuntimeBootstrap.resetProtectionStartupMode(
                helperRecovery: helperRecovery,
                journalRecovery: journalRecovery
            ),
            .committedResetRecovery
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: journalURL.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalJournal.path))
    }
#endif

#if INTERNAL_BUILD
    func testInternalBuildAutoResumesActiveInternalResetJournal() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let journal = ResetJournal(
            fileURL: fixture.control.appendingPathComponent(
                "internal-full-first-run.v1.json"
            )
        )
        try await journal.begin(
            kind: .eraseAppManagedData,
            steps: [
                .revokeGoogleAuthorization(position: 0),
                .unregisterLaunchAtLogin,
                .eraseLocalData,
                .relaunch
            ]
        )

        let helperRecovery = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )
        let journalRecovery = RuntimeBootstrap.resetJournalRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertFalse(journalRecovery.appDataRequiresResume)
        XCTAssertTrue(journalRecovery.internalRequiresResume)
        XCTAssertTrue(journalRecovery.requiresProtectedStorage)
        XCTAssertFalse(journalRecovery.requiresManualRepair)
        XCTAssertNil(journalRecovery.report)
        XCTAssertEqual(
            RuntimeBootstrap.resetProtectionStartupMode(
                helperRecovery: helperRecovery,
                journalRecovery: journalRecovery
            ),
            .activeResetRecovery
        )
    }
#endif

    func testSucceededResetHelperReceiptIsConsumedWithoutRecoveryReport() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = fixture.control.appendingPathComponent(
            "app-data-helper-result.v1.json"
        )
        try writeReceipt(state: "succeeded", category: nil, to: receipt)

        let report = RuntimeBootstrap.resetHelperRecoveryReport(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertNil(report)
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.path))
    }

#if INTERNAL_BUILD
    func testInternalBuildOffersRetryForKnownFailedInternalHelperReceipt() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = fixture.control.appendingPathComponent(
            "internal-helper-result.v1.json"
        )
        try writeReceipt(state: "failed", category: "tccReset", to: receipt)

        let summary = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertTrue(summary.report?.contains("macOS permission reset") == true)
        XCTAssertTrue(summary.report?.contains("Full First Run + macOS Permissions") == true)
        XCTAssertFalse(summary.appDataResetRetryAvailable)
        XCTAssertTrue(summary.internalResetRetryAvailable)
        XCTAssertFalse(summary.requiresManualRepair)
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.path))
    }
#else
    func testPublicBuildRequiresManualRecoveryForKnownFailedInternalHelperReceipt() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = fixture.control.appendingPathComponent(
            "internal-helper-result.v1.json"
        )
        try writeReceipt(state: "failed", category: "tccReset", to: receipt)

        let summary = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )
        let report = try XCTUnwrap(summary.report)

        XCTAssertFalse(summary.appDataResetRetryAvailable)
        XCTAssertFalse(summary.internalResetRetryAvailable)
        XCTAssertTrue(summary.requiresManualRepair)
        XCTAssertTrue(report.contains("matching internal build"))
        XCTAssertTrue(report.contains("Reveal Recovery Files"))
        XCTAssertFalse(report.contains("Run Full First Run + macOS Permissions again"))
        XCTAssertFalse(report.contains(fixture.root.path))
        XCTAssertFalse(report.contains(fixture.namespace))
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.path))
    }
#endif

    func testPendingResetHelperReceiptRequiresWaitWithoutOfferingRetry() throws {
        for receiptName in [
            "app-data-helper-result.v1.json",
            "internal-helper-result.v1.json"
        ] {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let receipt = fixture.control.appendingPathComponent(receiptName)
            try writeReceipt(state: "pending", category: nil, to: receipt)

            let summary = RuntimeBootstrap.resetHelperRecoverySummary(
                applicationSupportDirectory: fixture.applicationSupport,
                namespace: fixture.namespace,
                fileManager: .default
            )
            let report = try XCTUnwrap(summary.report)

            XCTAssertFalse(summary.appDataResetRetryAvailable)
            XCTAssertFalse(summary.internalResetRetryAvailable)
            XCTAssertTrue(summary.requiresManualRepair)
            XCTAssertTrue(report.contains("may still be running"))
            XCTAssertTrue(report.contains("Quit Meeting Incoming"))
            XCTAssertTrue(report.contains("wait"))
            XCTAssertTrue(report.contains("Reveal Recovery Files"))
            XCTAssertFalse(report.contains(fixture.root.path))
            XCTAssertFalse(report.contains(fixture.namespace))
            XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.path))
        }
    }

    func testPendingResetHelperReceiptSuppressesRetryForAnotherFailedReceipt() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let pendingReceipt = fixture.control.appendingPathComponent(
            "app-data-helper-result.v1.json"
        )
        let failedReceipt = fixture.control.appendingPathComponent(
            "internal-helper-result.v1.json"
        )
        try writeReceipt(state: "pending", category: nil, to: pendingReceipt)
        try writeReceipt(state: "failed", category: "tccReset", to: failedReceipt)

        let summary = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertFalse(summary.appDataResetRetryAvailable)
        XCTAssertFalse(summary.internalResetRetryAvailable)
        XCTAssertTrue(summary.requiresManualRepair)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingReceipt.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: failedReceipt.path))
    }

    func testUnsupportedResetHelperReceiptRequiresManualRepairWithoutOfferingRetry() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = fixture.control.appendingPathComponent(
            "app-data-helper-result.v1.json"
        )
        try writeReceipt(
            version: 2,
            state: "pending",
            category: nil,
            to: receipt
        )

        let summary = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertFalse(summary.appDataResetRetryAvailable)
        XCTAssertFalse(summary.internalResetRetryAvailable)
        XCTAssertTrue(summary.requiresManualRepair)
        XCTAssertTrue(summary.report?.contains("unsupported recovery receipt") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.path))
    }

    func testUnknownResetHelperReceiptStateRequiresManualRepairWithoutOfferingRetry() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = fixture.control.appendingPathComponent(
            "internal-helper-result.v1.json"
        )
        try writeReceipt(state: "still-running-v2", category: nil, to: receipt)

        let summary = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertFalse(summary.appDataResetRetryAvailable)
        XCTAssertFalse(summary.internalResetRetryAvailable)
        XCTAssertTrue(summary.requiresManualRepair)
        XCTAssertTrue(summary.report?.contains("unreadable recovery state") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.path))
    }

    func testMalformedResetHelperReceiptRequiresManualRepairWithoutOfferingRetry() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = fixture.control.appendingPathComponent(
            "app-data-helper-result.v1.json"
        )
        let malformedData = Data("{ not-a-reset-receipt".utf8)
        try malformedData.write(to: receipt, options: .atomic)

        let summary = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertFalse(summary.appDataResetRetryAvailable)
        XCTAssertFalse(summary.internalResetRetryAvailable)
        XCTAssertTrue(summary.requiresManualRepair)
        XCTAssertTrue(summary.report?.contains("could not be read") == true)
        XCTAssertEqual(try Data(contentsOf: receipt), malformedData)
    }

    func testUnreadableResetHelperReceiptRequiresManualRepairWithoutOfferingRetry() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = fixture.control.appendingPathComponent(
            "internal-helper-result.v1.json",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: receipt,
            withIntermediateDirectories: false
        )

        let summary = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertFalse(summary.appDataResetRetryAvailable)
        XCTAssertFalse(summary.internalResetRetryAvailable)
        XCTAssertTrue(summary.requiresManualRepair)
        XCTAssertTrue(summary.report?.contains("could not be read") == true)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: receipt.path,
            isDirectory: &isDirectory
        ))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testUnknownReceiptSuppressesRetryForAnotherKnownCleanupFailure() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let unknownReceipt = fixture.control.appendingPathComponent(
            "app-data-helper-result.v1.json"
        )
        let failedReceipt = fixture.control.appendingPathComponent(
            "internal-helper-result.v1.json"
        )
        try writeReceipt(
            state: "future-helper-state",
            category: nil,
            to: unknownReceipt
        )
        try writeReceipt(
            state: "failed",
            category: "tccReset",
            to: failedReceipt
        )

        let summary = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertFalse(summary.appDataResetRetryAvailable)
        XCTAssertFalse(summary.internalResetRetryAvailable)
        XCTAssertTrue(summary.requiresManualRepair)
        XCTAssertTrue(summary.report?.contains("unreadable recovery state") == true)
#if INTERNAL_BUILD
        XCTAssertTrue(summary.report?.contains("macOS permission reset") == true)
#else
        XCTAssertTrue(summary.report?.contains("matching internal build") == true)
        XCTAssertTrue(summary.report?.contains("Reveal Recovery Files") == true)
#endif
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknownReceipt.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: failedReceipt.path))
    }

    func testFailedAppDataReceiptReportsSafeTargetCategoryAndErrorCode() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = fixture.control.appendingPathComponent(
            "app-data-helper-result.v1.json"
        )
        try writeReceipt(
            state: "failed",
            category: "localCleanup",
            diagnostic: [
                "category": "targetRemoval",
                "target": "applicationSupport",
                "errorDomain": "NSCocoaErrorDomain",
                "errorCode": NSFileWriteNoPermissionError
            ],
            to: receipt
        )

        let summary = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )
        let report = try XCTUnwrap(summary.report)

        XCTAssertTrue(summary.appDataResetRetryAvailable)
        XCTAssertTrue(report.contains("Application Support"))
        XCTAssertTrue(report.contains("could not be removed"))
        XCTAssertTrue(report.contains("NSCocoaErrorDomain 513"))
        XCTAssertFalse(report.contains(fixture.root.path))
        XCTAssertFalse(report.contains(fixture.namespace))
    }

    func testReopenOnlyFailureDoesNotOfferAnotherDestructiveReset() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = fixture.control.appendingPathComponent(
            "app-data-helper-result.v1.json"
        )
        try writeReceipt(
            state: "failed",
            category: "reopen",
            diagnostic: [
                "category": "reopenCommand",
                "errorDomain": "ProcessExitStatus",
                "errorCode": 69
            ],
            to: receipt
        )

        let summary = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertFalse(summary.appDataResetRetryAvailable)
        XCTAssertFalse(summary.internalResetRetryAvailable)
        XCTAssertTrue(summary.report?.contains("cleanup finished") == true)
        XCTAssertTrue(summary.report?.contains("could not reopen automatically") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.path))
    }

    func testSymlinkedResetControlDirectoryIsNeitherReadNorRemoved() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let externalDirectory = fixture.root.appendingPathComponent(
            "External Receipts",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: externalDirectory,
            withIntermediateDirectories: true
        )
        let externalReceipt = externalDirectory.appendingPathComponent(
            "app-data-helper-result.v1.json"
        )
        try writeReceipt(state: "succeeded", category: nil, to: externalReceipt)
        try FileManager.default.removeItem(at: fixture.control)
        try FileManager.default.createSymbolicLink(
            at: fixture.control,
            withDestinationURL: externalDirectory
        )

        let summary = RuntimeBootstrap.resetHelperRecoverySummary(
            applicationSupportDirectory: fixture.applicationSupport,
            namespace: fixture.namespace,
            fileManager: .default
        )

        XCTAssertTrue(summary.requiresManualRepair)
        XCTAssertFalse(summary.appDataResetRetryAvailable)
        XCTAssertFalse(summary.internalResetRetryAvailable)
        XCTAssertTrue(summary.report?.contains("recovery path is unsafe") == true)
        XCTAssertTrue(summary.report?.contains("Repair or remove") == true)
        XCTAssertFalse(summary.report?.contains("Run Erase App-Managed Data") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalReceipt.path))
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.control.path
        )
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
    }

    private func makeFixture() throws -> (
        root: URL,
        applicationSupport: URL,
        control: URL,
        namespace: String
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "runtime-bootstrap-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        let applicationSupport = root.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        let namespace = "com.example.receipt-tests"
        let control = applicationSupport.appendingPathComponent(
            "\(namespace).reset-control",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: control,
            withIntermediateDirectories: true
        )
        return (root, applicationSupport, control, namespace)
    }

    private func writeReceipt(
        version: Int = 1,
        state: String,
        category: String?,
        diagnostic: [String: Any]? = nil,
        to url: URL
    ) throws {
        var object: [String: Any] = ["version": version, "state": state]
        if let category {
            object["failureCategory"] = category
        }
        if let diagnostic {
            object["diagnostic"] = diagnostic
        }
        try JSONSerialization.data(withJSONObject: object).write(to: url, options: .atomic)
    }
}

private enum RecoveryFactoryProbeError: Error {
    case unexpectedVaultOpen
}
