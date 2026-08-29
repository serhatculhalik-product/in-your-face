import Foundation
import XCTest
@testable import MeetingIncomingHelperSupport

final class AppDataResetRunnerTests: XCTestCase {
    func testPublicResetWaitsForParentThenRemovesOnlyAppStateWithoutTCC() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MeetingIncomingAppDataResetTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let app = root.appendingPathComponent("Meeting Incoming.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let bundleIdentifier = "com.example.meeting-incoming"
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleIdentifier],
            format: .xml,
            options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        let appState = [
            home.appendingPathComponent("Library/Preferences/\(bundleIdentifier).plist"),
            home.appendingPathComponent("Library/Application Support/\(bundleIdentifier)/state"),
            home.appendingPathComponent("Library/Caches/\(bundleIdentifier)/state"),
            home.appendingPathComponent("Library/HTTPStorages/\(bundleIdentifier)/state"),
            home.appendingPathComponent("Library/Saved Application State/\(bundleIdentifier).savedState/state")
        ]
        for file in appState {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("state".utf8).write(to: file)
        }
        let retained = home.appendingPathComponent(
            "Library/Application Support/\(bundleIdentifier).runtime-control/keep"
        )
        try FileManager.default.createDirectory(
            at: retained.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(to: retained)
        let receiptURL = home.appendingPathComponent(
            "Library/Application Support/\(bundleIdentifier).reset-control/app-data-helper-result.v1.json"
        )

        let events = AppResetEventRecorder()
        let operation = MeetingIncomingHelperOperation(
            parentProcessIdentifier: 51_001,
            bundleIdentifier: bundleIdentifier,
            applicationBundlePath: app.path,
            homeDirectoryPath: home.path
        )
        let runner = AppDataResetRunner(
            environment: MeetingIncomingHelperEnvironment(
                containingApplicationBundleURL: app,
                homeDirectoryURL: home
            ),
            fileManager: .default,
            parentWaiter: AppResetParentWaiter(events: events) {
                XCTAssertEqual(
                    try decodeReceipt(at: receiptURL),
                    MeetingIncomingResetReceipt(state: .pending)
                )
            },
            commandRunner: AppResetCommandRunner(events: events) { executableURL, _ in
                if executableURL.path == "/usr/bin/open" {
                    XCTAssertEqual(
                        try decodeReceipt(at: receiptURL),
                        MeetingIncomingResetReceipt(state: .succeeded)
                    )
                }
                return 0
            }
        )

        let result = try runner.run(operation: operation)

        XCTAssertEqual(events.values.first, "wait:51001")
        XCTAssertEqual(
            events.values.dropFirst(),
            [
                "command:/usr/bin/defaults:delete|\(bundleIdentifier)",
                "command:/usr/bin/open:-F|\(app.path)"
            ]
        )
        XCTAssertFalse(events.values.contains { $0.contains("tccutil") })
        XCTAssertTrue(appState.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
        XCTAssertEqual(result.relaunchedApplicationPath, app.path)
        XCTAssertEqual(
            try decodeReceipt(at: receiptURL),
            MeetingIncomingResetReceipt(state: .succeeded)
        )
        let receiptText = try String(contentsOf: receiptURL, encoding: .utf8)
        XCTAssertFalse(receiptText.contains(bundleIdentifier))
        XCTAssertFalse(receiptText.contains(home.path))
        XCTAssertFalse(receiptText.contains("failureCategory"))
    }

    func testRemovalFailureRecordsSafeTargetDiagnosticAndStillReopens() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MeetingIncomingAppDataResetDiagnosticTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let app = root.appendingPathComponent("Meeting Incoming.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let bundleIdentifier = "com.example.meeting-incoming"
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleIdentifier],
            format: .xml,
            options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        let applicationSupport = home.appendingPathComponent(
            "Library/Application Support/\(bundleIdentifier)",
            isDirectory: true
        )
        let applicationSupportState = applicationSupport.appendingPathComponent("state")
        let cacheState = home.appendingPathComponent(
            "Library/Caches/\(bundleIdentifier)/state"
        )
        for file in [applicationSupportState, cacheState] {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("state".utf8).write(to: file)
        }
        let receiptURL = home.appendingPathComponent(
            "Library/Application Support/\(bundleIdentifier).reset-control/app-data-helper-result.v1.json"
        )
        let events = AppResetEventRecorder()
        let fileManager = FailingRemovalFileManager(
            failingURL: applicationSupport,
            error: NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteNoPermissionError,
                userInfo: [NSLocalizedDescriptionKey: "secret-path-must-not-leak"]
            )
        )
        let runner = AppDataResetRunner(
            environment: MeetingIncomingHelperEnvironment(
                containingApplicationBundleURL: app,
                homeDirectoryURL: home
            ),
            fileManager: fileManager,
            parentWaiter: AppResetParentWaiter(events: events),
            commandRunner: AppResetCommandRunner(events: events)
        )
        let operation = MeetingIncomingHelperOperation(
            parentProcessIdentifier: 51_005,
            bundleIdentifier: bundleIdentifier,
            applicationBundlePath: app.path,
            homeDirectoryPath: home.path
        )

        XCTAssertThrowsError(try runner.run(operation: operation)) { error in
            XCTAssertEqual(
                error as? MeetingIncomingHelperError,
                .resetOperationFailed(.localCleanup)
            )
        }

        XCTAssertEqual(
            events.values,
            ["wait:51005", "command:/usr/bin/open:-F|\(app.path)"]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: applicationSupportState.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheState.path))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL))
                as? [String: Any]
        )
        let diagnostic = try XCTUnwrap(object["diagnostic"] as? [String: Any])
        XCTAssertEqual(diagnostic["category"] as? String, "targetRemoval")
        XCTAssertEqual(diagnostic["target"] as? String, "applicationSupport")
        XCTAssertEqual(diagnostic["errorDomain"] as? String, "NSCocoaErrorDomain")
        XCTAssertEqual(diagnostic["errorCode"] as? Int, NSFileWriteNoPermissionError)
        let receiptText = try String(contentsOf: receiptURL, encoding: .utf8)
        XCTAssertFalse(receiptText.contains(home.path))
        XCTAssertFalse(receiptText.contains(bundleIdentifier))
        XCTAssertFalse(receiptText.contains("secret-path-must-not-leak"))
    }

    func testInspectionFailureIsNotMistakenForAnAbsentTarget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MeetingIncomingAppDataResetInspectionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let app = root.appendingPathComponent("Meeting Incoming.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let bundleIdentifier = "com.example.meeting-incoming"
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleIdentifier],
            format: .xml,
            options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        let applicationSupport = home.appendingPathComponent(
            "Library/Application Support/\(bundleIdentifier)",
            isDirectory: true
        )
        let applicationSupportState = applicationSupport.appendingPathComponent("state")
        let cacheState = home.appendingPathComponent(
            "Library/Caches/\(bundleIdentifier)/state"
        )
        for file in [applicationSupportState, cacheState] {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("state".utf8).write(to: file)
        }
        let receiptURL = home.appendingPathComponent(
            "Library/Application Support/\(bundleIdentifier).reset-control/app-data-helper-result.v1.json"
        )
        let events = AppResetEventRecorder()
        let fileManager = FailingInspectionFileManager(
            failingURL: applicationSupport,
            error: NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadNoPermissionError,
                userInfo: [NSLocalizedDescriptionKey: "private-inspection-detail"]
            )
        )
        let runner = AppDataResetRunner(
            environment: MeetingIncomingHelperEnvironment(
                containingApplicationBundleURL: app,
                homeDirectoryURL: home
            ),
            fileManager: fileManager,
            parentWaiter: AppResetParentWaiter(events: events),
            commandRunner: AppResetCommandRunner(events: events)
        )
        let operation = MeetingIncomingHelperOperation(
            parentProcessIdentifier: 51_006,
            bundleIdentifier: bundleIdentifier,
            applicationBundlePath: app.path,
            homeDirectoryPath: home.path
        )

        XCTAssertThrowsError(try runner.run(operation: operation)) { error in
            XCTAssertEqual(
                error as? MeetingIncomingHelperError,
                .resetOperationFailed(.localCleanup)
            )
        }

        XCTAssertEqual(
            events.values,
            ["wait:51006", "command:/usr/bin/open:-F|\(app.path)"]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: applicationSupportState.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheState.path))
        let receipt = try decodeReceipt(at: receiptURL)
        XCTAssertEqual(receipt.state, .failed)
        XCTAssertEqual(receipt.failureCategory, .localCleanup)
        XCTAssertEqual(
            receipt.diagnostic,
            MeetingIncomingResetDiagnostic(
                category: .targetInspection,
                target: .applicationSupport,
                errorDomain: .cocoa,
                errorCode: NSFileReadNoPermissionError
            )
        )
        let receiptText = try String(contentsOf: receiptURL, encoding: .utf8)
        XCTAssertFalse(receiptText.contains(home.path))
        XCTAssertFalse(receiptText.contains(bundleIdentifier))
        XCTAssertFalse(receiptText.contains("private-inspection-detail"))
    }

    func testReopenFailureLeavesTerminalIdentityFreeReceiptForManualRecovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MeetingIncomingAppDataResetFailureTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let app = root.appendingPathComponent("Meeting Incoming.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let bundleIdentifier = "com.example.meeting-incoming"
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleIdentifier],
            format: .xml,
            options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        let receiptURL = home.appendingPathComponent(
            "Library/Application Support/\(bundleIdentifier).reset-control/app-data-helper-result.v1.json"
        )
        let operation = MeetingIncomingHelperOperation(
            parentProcessIdentifier: 51_002,
            bundleIdentifier: bundleIdentifier,
            applicationBundlePath: app.path,
            homeDirectoryPath: home.path
        )
        let events = AppResetEventRecorder()
        let runner = AppDataResetRunner(
            environment: MeetingIncomingHelperEnvironment(
                containingApplicationBundleURL: app,
                homeDirectoryURL: home
            ),
            fileManager: .default,
            parentWaiter: AppResetParentWaiter(events: events),
            commandRunner: AppResetCommandRunner(events: events) { executableURL, _ in
                guard executableURL.path == "/usr/bin/open" else { return 0 }
                XCTAssertEqual(
                    try decodeReceipt(at: receiptURL),
                    MeetingIncomingResetReceipt(state: .succeeded)
                )
                return 69
            }
        )

        XCTAssertThrowsError(try runner.run(operation: operation)) { error in
            XCTAssertEqual(
                error as? MeetingIncomingHelperError,
                .resetOperationFailed(.reopen)
            )
        }
        let receipt = try decodeReceipt(at: receiptURL)
        XCTAssertEqual(receipt.state, .failed)
        XCTAssertEqual(receipt.failureCategory, .reopen)
        XCTAssertEqual(receipt.diagnostic?.category, .reopenCommand)
        XCTAssertNil(receipt.diagnostic?.target)
        XCTAssertEqual(receipt.diagnostic?.errorDomain?.rawValue, "ProcessExitStatus")
        XCTAssertEqual(receipt.diagnostic?.errorCode, 69)
        let receiptText = try String(contentsOf: receiptURL, encoding: .utf8)
        XCTAssertFalse(receiptText.contains(bundleIdentifier))
        XCTAssertFalse(receiptText.contains(app.path))
    }

    func testParentWaitFailureLeavesReceiptWithoutCleaningOrOpeningAnotherProcess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MeetingIncomingAppDataResetParentWaitTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let app = root.appendingPathComponent("Meeting Incoming.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let bundleIdentifier = "com.example.meeting-incoming"
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleIdentifier],
            format: .xml,
            options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        let appState = home.appendingPathComponent(
            "Library/Application Support/\(bundleIdentifier)/state"
        )
        try FileManager.default.createDirectory(
            at: appState.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("state".utf8).write(to: appState)
        let receiptURL = home.appendingPathComponent(
            "Library/Application Support/\(bundleIdentifier).reset-control/app-data-helper-result.v1.json"
        )
        let operation = MeetingIncomingHelperOperation(
            parentProcessIdentifier: 51_003,
            bundleIdentifier: bundleIdentifier,
            applicationBundlePath: app.path,
            homeDirectoryPath: home.path
        )
        let events = AppResetEventRecorder()
        let runner = AppDataResetRunner(
            environment: MeetingIncomingHelperEnvironment(
                containingApplicationBundleURL: app,
                homeDirectoryURL: home
            ),
            fileManager: .default,
            parentWaiter: AppResetParentWaiter(events: events) {
                throw MeetingIncomingHelperError.parentWaitFailed(51_003)
            },
            commandRunner: AppResetCommandRunner(events: events)
        )

        XCTAssertThrowsError(try runner.run(operation: operation)) { error in
            XCTAssertEqual(
                error as? MeetingIncomingHelperError,
                .resetOperationFailed(.parentWait)
            )
        }
        XCTAssertEqual(events.values, ["wait:51003"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: appState.path))
        XCTAssertEqual(
            try decodeReceipt(at: receiptURL),
            MeetingIncomingResetReceipt(state: .failed, failureCategory: .parentWait)
        )
    }

    func testReceiptControlDirectorySymlinkOutsideHomeIsRejectedBeforeWaiting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MeetingIncomingAppDataResetReceiptSafetyTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let app = root.appendingPathComponent("Meeting Incoming.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let applicationSupport = home.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let bundleIdentifier = "com.example.meeting-incoming"
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleIdentifier],
            format: .xml,
            options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        let controlDirectory = applicationSupport.appendingPathComponent(
            "\(bundleIdentifier).reset-control",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: controlDirectory,
            withDestinationURL: outside
        )
        let receiptURL = controlDirectory.appendingPathComponent(
            "app-data-helper-result.v1.json"
        )
        let operation = MeetingIncomingHelperOperation(
            parentProcessIdentifier: 51_004,
            bundleIdentifier: bundleIdentifier,
            applicationBundlePath: app.path,
            homeDirectoryPath: home.path
        )
        let events = AppResetEventRecorder()
        let runner = AppDataResetRunner(
            environment: MeetingIncomingHelperEnvironment(
                containingApplicationBundleURL: app,
                homeDirectoryURL: home
            ),
            fileManager: .default,
            parentWaiter: AppResetParentWaiter(events: events),
            commandRunner: AppResetCommandRunner(events: events)
        )

        XCTAssertThrowsError(try runner.run(operation: operation)) { error in
            XCTAssertEqual(
                error as? MeetingIncomingHelperError,
                .unsafeResetTarget(receiptURL.path)
            )
        }
        XCTAssertEqual(events.values, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }
}

private func decodeReceipt(at url: URL) throws -> MeetingIncomingResetReceipt {
    try JSONDecoder().decode(
        MeetingIncomingResetReceipt.self,
        from: Data(contentsOf: url)
    )
}

private final class AppResetEventRecorder {
    var values: [String] = []
}

private struct AppResetParentWaiter: ParentProcessWaiting {
    let events: AppResetEventRecorder
    var onWait: () throws -> Void = {}

    func wait(for processIdentifier: Int32) throws {
        events.values.append("wait:\(processIdentifier)")
        try onWait()
    }
}

private struct AppResetCommandRunner: HelperCommandRunning {
    let events: AppResetEventRecorder
    var status: (URL, [String]) throws -> Int32 = { _, _ in 0 }

    func run(executableURL: URL, arguments: [String]) throws -> Int32 {
        events.values.append(
            "command:\(executableURL.path):\(arguments.joined(separator: "|"))"
        )
        return try status(executableURL, arguments)
    }
}

private final class FailingRemovalFileManager: FileManager, @unchecked Sendable {
    private let failingURL: URL
    private let failure: any Error

    init(failingURL: URL, error: any Error) {
        self.failingURL = failingURL.standardizedFileURL
        self.failure = error
        super.init()
    }

    override func removeItem(at URL: URL) throws {
        if URL.standardizedFileURL == failingURL {
            throw failure
        }
        try super.removeItem(at: URL)
    }
}

private final class FailingInspectionFileManager: FileManager, @unchecked Sendable {
    private let failingPath: String
    private let failure: any Error

    init(failingURL: URL, error: any Error) {
        self.failingPath = failingURL.standardizedFileURL.path
        self.failure = error
        super.init()
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        if URL(fileURLWithPath: path).standardizedFileURL.path == failingPath {
            throw failure
        }
        return try super.attributesOfItem(atPath: path)
    }
}
