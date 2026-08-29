import Foundation
import XCTest
@testable import MeetingIncomingHelperSupport

final class InternalResetRunnerTests: XCTestCase {
    func testPublicBundleIdentityIsRejectedBeforeWaitingOrRunningCommands() throws {
        let fixture = try HelperFixture(bundleIdentifier: "com.serhatculhalik.in-your-face")
        defer { fixture.remove() }
        let parentWaiter = RecordingParentProcessWaiter()
        let commandRunner = RecordingHelperCommandRunner()
        let runner = InternalResetRunner(
            environment: fixture.environment,
            fileManager: .default,
            parentWaiter: parentWaiter,
            commandRunner: commandRunner
        )

        XCTAssertThrowsError(try runner.run(operation: fixture.operation)) { error in
            XCTAssertEqual(
                error as? MeetingIncomingHelperError,
                .bundleIdentifierMustBeInternal("com.serhatculhalik.in-your-face")
            )
        }
        XCTAssertEqual(parentWaiter.waitedProcessIdentifiers, [])
        XCTAssertEqual(commandRunner.invocations, [])
    }

    func testDifferentInternalSuffixIsRejectedByExactAllowlist() throws {
        let fixture = try HelperFixture(bundleIdentifier: "com.example.other.internal")
        defer { fixture.remove() }
        let parentWaiter = RecordingParentProcessWaiter()
        let commandRunner = RecordingHelperCommandRunner()
        let runner = InternalResetRunner(
            environment: fixture.environment,
            fileManager: .default,
            parentWaiter: parentWaiter,
            commandRunner: commandRunner
        )

        XCTAssertThrowsError(try runner.run(operation: fixture.operation)) { error in
            XCTAssertEqual(
                error as? MeetingIncomingHelperError,
                .bundleIdentifierMustBeInternal("com.example.other.internal")
            )
        }
        XCTAssertEqual(parentWaiter.waitedProcessIdentifiers, [])
        XCTAssertEqual(commandRunner.invocations, [])
    }

    func testInternalSuffixWithoutInternalBuildMarkerIsRejected() throws {
        let fixture = try HelperFixture(
            bundleIdentifier: "com.serhatculhalik.in-your-face.internal",
            isInternalBuild: false
        )
        defer { fixture.remove() }
        let parentWaiter = RecordingParentProcessWaiter()
        let commandRunner = RecordingHelperCommandRunner()
        let runner = InternalResetRunner(
            environment: fixture.environment,
            fileManager: .default,
            parentWaiter: parentWaiter,
            commandRunner: commandRunner
        )

        XCTAssertThrowsError(try runner.run(operation: fixture.operation)) { error in
            XCTAssertEqual(
                error as? MeetingIncomingHelperError,
                .internalBuildMarkerMissing
            )
        }
        XCTAssertEqual(parentWaiter.waitedProcessIdentifiers, [])
        XCTAssertEqual(commandRunner.invocations, [])
    }

    func testInternalResetRemovesOnlyAllowedStateAndUsesScopedTCCCommands() throws {
        let bundleIdentifier = "com.serhatculhalik.in-your-face.internal"
        let fixture = try HelperFixture(bundleIdentifier: bundleIdentifier)
        defer { fixture.remove() }
        let allowedPaths = try fixture.createResetState()
        let retainedPath = try fixture.createRetainedPublicState()
        try fixture.seedSupersededPublicReceipt()
        let parentWaiter = RecordingParentProcessWaiter {
            XCTAssertEqual(
                try fixture.internalReceipt(),
                MeetingIncomingResetReceipt(state: .pending)
            )
        }
        let commandRunner = RecordingHelperCommandRunner { invocation in
            if invocation.executablePath == "/usr/bin/open" {
                XCTAssertEqual(
                    try fixture.internalReceipt(),
                    MeetingIncomingResetReceipt(state: .succeeded)
                )
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: fixture.publicReceiptURL.path)
                )
            }
            return 0
        }
        let runner = InternalResetRunner(
            environment: fixture.environment,
            fileManager: .default,
            parentWaiter: parentWaiter,
            commandRunner: commandRunner
        )

        let result = try runner.run(operation: fixture.operation)

        XCTAssertEqual(parentWaiter.waitedProcessIdentifiers, [41_002])
        XCTAssertTrue(allowedPaths.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedPath.path))
        XCTAssertEqual(Set(result.removedPaths), Set(allowedPaths.map(\.path)))
        XCTAssertEqual(result.relaunchedApplicationPath, fixture.applicationBundleURL.path)
        XCTAssertEqual(try fixture.internalReceipt(), .init(state: .succeeded))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.publicReceiptURL.path))
        XCTAssertEqual(
            commandRunner.invocations,
            [
                .init(
                    executablePath: "/usr/bin/tccutil",
                    arguments: ["reset", "Accessibility", bundleIdentifier]
                ),
                .init(
                    executablePath: "/usr/bin/tccutil",
                    arguments: ["reset", "ListenEvent", bundleIdentifier]
                ),
                .init(
                    executablePath: "/usr/bin/defaults",
                    arguments: ["delete", bundleIdentifier]
                ),
                .init(
                    executablePath: "/usr/bin/open",
                    arguments: ["-F", fixture.applicationBundleURL.path]
                )
            ]
        )
    }

    func testOneTCCFailureStillAttemptsSecondServiceCleanupAndReopen() throws {
        let bundleIdentifier = "com.serhatculhalik.in-your-face.internal"
        let fixture = try HelperFixture(bundleIdentifier: bundleIdentifier)
        defer { fixture.remove() }
        let resetPaths = try fixture.createResetState()
        let parentWaiter = RecordingParentProcessWaiter()
        let commandRunner = RecordingHelperCommandRunner { invocation in
            if invocation.executablePath == "/usr/bin/open" {
                XCTAssertEqual(
                    try fixture.internalReceipt(),
                    MeetingIncomingResetReceipt(
                        state: .failed,
                        failureCategory: .tccReset
                    )
                )
            }
            return invocation.arguments.contains("Accessibility") ? 69 : 0
        }
        let runner = InternalResetRunner(
            environment: fixture.environment,
            fileManager: .default,
            parentWaiter: parentWaiter,
            commandRunner: commandRunner
        )

        XCTAssertThrowsError(try runner.run(operation: fixture.operation)) { error in
            XCTAssertEqual(
                error as? MeetingIncomingHelperError,
                .resetOperationFailed(.tccReset)
            )
        }
        XCTAssertTrue(resetPaths.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertEqual(
            try fixture.internalReceipt(),
            .init(state: .failed, failureCategory: .tccReset)
        )
        let receiptText = try String(
            contentsOf: fixture.internalReceiptURL,
            encoding: .utf8
        )
        XCTAssertFalse(receiptText.contains(bundleIdentifier))
        XCTAssertFalse(receiptText.contains(fixture.homeDirectoryURL.path))
        XCTAssertEqual(
            commandRunner.invocations,
            [
                .init(
                    executablePath: "/usr/bin/tccutil",
                    arguments: ["reset", "Accessibility", bundleIdentifier]
                ),
                .init(
                    executablePath: "/usr/bin/tccutil",
                    arguments: ["reset", "ListenEvent", bundleIdentifier]
                ),
                .init(
                    executablePath: "/usr/bin/defaults",
                    arguments: ["delete", bundleIdentifier]
                ),
                .init(
                    executablePath: "/usr/bin/open",
                    arguments: ["-F", fixture.applicationBundleURL.path]
                )
            ]
        )
    }

    func testResetRejectsAnAllowedPathThatResolvesOutsideTheHomeDirectory() throws {
        let bundleIdentifier = "com.serhatculhalik.in-your-face.internal"
        let fixture = try HelperFixture(bundleIdentifier: bundleIdentifier)
        defer { fixture.remove() }
        let outsideDirectoryURL = fixture.rootURL
            .appendingPathComponent("outside-home", isDirectory: true)
        let protectedFileURL = outsideDirectoryURL.appendingPathComponent("keep.bin")
        try FileManager.default.createDirectory(
            at: outsideDirectoryURL,
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(to: protectedFileURL)
        let applicationSupportURL = fixture.homeDirectoryURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        let linkedTargetURL = applicationSupportURL
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedTargetURL,
            withDestinationURL: outsideDirectoryURL
        )
        let parentWaiter = RecordingParentProcessWaiter()
        let commandRunner = RecordingHelperCommandRunner()
        let runner = InternalResetRunner(
            environment: fixture.environment,
            fileManager: .default,
            parentWaiter: parentWaiter,
            commandRunner: commandRunner
        )

        XCTAssertThrowsError(try runner.run(operation: fixture.operation)) { error in
            XCTAssertEqual(
                error as? MeetingIncomingHelperError,
                .resetOperationFailed(.localCleanup)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedFileURL.path))
        XCTAssertEqual(parentWaiter.waitedProcessIdentifiers, [41_002])
        XCTAssertEqual(
            commandRunner.invocations,
            [
                .init(
                    executablePath: "/usr/bin/tccutil",
                    arguments: ["reset", "Accessibility", bundleIdentifier]
                ),
                .init(
                    executablePath: "/usr/bin/tccutil",
                    arguments: ["reset", "ListenEvent", bundleIdentifier]
                ),
                .init(
                    executablePath: "/usr/bin/open",
                    arguments: ["-F", fixture.applicationBundleURL.path]
                )
            ]
        )
        XCTAssertEqual(
            try fixture.internalReceipt(),
            .init(state: .failed, failureCategory: .localCleanup)
        )
    }

    func testParentWaitFailureLeavesReceiptWithoutTCCCleanupOrReopen() throws {
        let bundleIdentifier = "com.serhatculhalik.in-your-face.internal"
        let fixture = try HelperFixture(bundleIdentifier: bundleIdentifier)
        defer { fixture.remove() }
        let resetPaths = try fixture.createResetState()
        let parentWaiter = RecordingParentProcessWaiter {
            throw MeetingIncomingHelperError.parentWaitFailed(41_002)
        }
        let commandRunner = RecordingHelperCommandRunner()
        let runner = InternalResetRunner(
            environment: fixture.environment,
            fileManager: .default,
            parentWaiter: parentWaiter,
            commandRunner: commandRunner
        )

        XCTAssertThrowsError(try runner.run(operation: fixture.operation)) { error in
            XCTAssertEqual(
                error as? MeetingIncomingHelperError,
                .resetOperationFailed(.parentWait)
            )
        }
        XCTAssertEqual(parentWaiter.waitedProcessIdentifiers, [41_002])
        XCTAssertEqual(commandRunner.invocations, [])
        XCTAssertTrue(resetPaths.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        })
        XCTAssertEqual(
            try fixture.internalReceipt(),
            .init(state: .failed, failureCategory: .parentWait)
        )
    }

    func testInspectionFailureIsNotMistakenForAnAbsentInternalTarget() throws {
        let bundleIdentifier = "com.serhatculhalik.in-your-face.internal"
        let fixture = try HelperFixture(bundleIdentifier: bundleIdentifier)
        defer { fixture.remove() }
        let resetPaths = try fixture.createResetState()
        let applicationSupport = resetPaths[1]
        let fileManager = FailingInternalInspectionFileManager(
            failingURL: applicationSupport,
            error: NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadNoPermissionError,
                userInfo: [NSLocalizedDescriptionKey: "private-internal-detail"]
            )
        )
        let parentWaiter = RecordingParentProcessWaiter()
        let commandRunner = RecordingHelperCommandRunner()
        let runner = InternalResetRunner(
            environment: fixture.environment,
            fileManager: fileManager,
            parentWaiter: parentWaiter,
            commandRunner: commandRunner
        )

        XCTAssertThrowsError(try runner.run(operation: fixture.operation)) { error in
            XCTAssertEqual(
                error as? MeetingIncomingHelperError,
                .resetOperationFailed(.localCleanup)
            )
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: applicationSupport.path))
        XCTAssertTrue(
            resetPaths.enumerated().allSatisfy { index, path in
                index == 1 || !FileManager.default.fileExists(atPath: path.path)
            }
        )
        XCTAssertEqual(
            try fixture.internalReceipt().diagnostic,
            MeetingIncomingResetDiagnostic(
                category: .targetInspection,
                target: .applicationSupport,
                errorDomain: .cocoa,
                errorCode: NSFileReadNoPermissionError
            )
        )
        XCTAssertEqual(commandRunner.invocations.last?.executablePath, "/usr/bin/open")
        let receiptText = try String(
            contentsOf: fixture.internalReceiptURL,
            encoding: .utf8
        )
        XCTAssertFalse(receiptText.contains(fixture.homeDirectoryURL.path))
        XCTAssertFalse(receiptText.contains(bundleIdentifier))
        XCTAssertFalse(receiptText.contains("private-internal-detail"))
    }
}

private final class RecordingParentProcessWaiter: ParentProcessWaiting {
    private(set) var waitedProcessIdentifiers: [Int32] = []
    private let onWait: () throws -> Void

    init(onWait: @escaping () throws -> Void = {}) {
        self.onWait = onWait
    }

    func wait(for processIdentifier: Int32) throws {
        waitedProcessIdentifiers.append(processIdentifier)
        try onWait()
    }
}

private final class RecordingHelperCommandRunner: HelperCommandRunning {
    struct Invocation: Equatable {
        let executablePath: String
        let arguments: [String]
    }

    private(set) var invocations: [Invocation] = []
    private let statusForInvocation: (Invocation) throws -> Int32

    init(statusForInvocation: @escaping (Invocation) throws -> Int32 = { _ in 0 }) {
        self.statusForInvocation = statusForInvocation
    }

    func run(executableURL: URL, arguments: [String]) throws -> Int32 {
        let invocation = Invocation(executablePath: executableURL.path, arguments: arguments)
        invocations.append(invocation)
        return try statusForInvocation(invocation)
    }
}

private final class FailingInternalInspectionFileManager: FileManager, @unchecked Sendable {
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

private struct HelperFixture {
    let rootURL: URL
    let homeDirectoryURL: URL
    let applicationBundleURL: URL
    let environment: MeetingIncomingHelperEnvironment
    let operation: MeetingIncomingHelperOperation

    var controlDirectoryURL: URL {
        homeDirectoryURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("\(operation.bundleIdentifier).reset-control", isDirectory: true)
    }

    var internalReceiptURL: URL {
        controlDirectoryURL.appendingPathComponent("internal-helper-result.v1.json")
    }

    var publicReceiptURL: URL {
        controlDirectoryURL.appendingPathComponent("app-data-helper-result.v1.json")
    }

    init(bundleIdentifier: String, isInternalBuild: Bool = true) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingIncomingHelperTests-\(UUID().uuidString)", isDirectory: true)
        homeDirectoryURL = rootURL.appendingPathComponent("home", isDirectory: true)
        applicationBundleURL = rootURL.appendingPathComponent("Meeting Incoming Internal.app", isDirectory: true)
        let contentsURL = applicationBundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contentsURL,
            withIntermediateDirectories: true
        )
        var plist: [String: Any] = ["CFBundleIdentifier": bundleIdentifier]
        if isInternalBuild {
            plist["MeetingIncomingInternalBuild"] = true
        }
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        try FileManager.default.createDirectory(
            at: homeDirectoryURL,
            withIntermediateDirectories: true
        )
        environment = MeetingIncomingHelperEnvironment(
            containingApplicationBundleURL: applicationBundleURL,
            homeDirectoryURL: homeDirectoryURL
        )
        operation = MeetingIncomingHelperOperation(
            parentProcessIdentifier: 41_002,
            bundleIdentifier: bundleIdentifier,
            applicationBundlePath: applicationBundleURL.path,
            homeDirectoryPath: homeDirectoryURL.path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func internalReceipt() throws -> MeetingIncomingResetReceipt {
        try JSONDecoder().decode(
            MeetingIncomingResetReceipt.self,
            from: Data(contentsOf: internalReceiptURL)
        )
    }

    func seedSupersededPublicReceipt() throws {
        try FileManager.default.createDirectory(
            at: controlDirectoryURL,
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(
            MeetingIncomingResetReceipt(
                state: .failed,
                failureCategory: .localCleanup
            )
        ).write(to: publicReceiptURL)
    }

    func createResetState() throws -> [URL] {
        let bundleIdentifier = operation.bundleIdentifier
        let paths = [
            homeDirectoryURL
                .appendingPathComponent("Library/Preferences", isDirectory: true)
                .appendingPathComponent("\(bundleIdentifier).plist"),
            homeDirectoryURL
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(bundleIdentifier, isDirectory: true),
            homeDirectoryURL
                .appendingPathComponent("Library/Caches", isDirectory: true)
                .appendingPathComponent(bundleIdentifier, isDirectory: true),
            homeDirectoryURL
                .appendingPathComponent("Library/HTTPStorages", isDirectory: true)
                .appendingPathComponent(bundleIdentifier, isDirectory: true),
            homeDirectoryURL
                .appendingPathComponent("Library/Saved Application State", isDirectory: true)
                .appendingPathComponent("\(bundleIdentifier).savedState", isDirectory: true)
        ]
        for path in paths {
            if path.pathExtension == "plist" {
                try FileManager.default.createDirectory(
                    at: path.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("preference".utf8).write(to: path)
            } else {
                try FileManager.default.createDirectory(
                    at: path,
                    withIntermediateDirectories: true
                )
                try Data("state".utf8).write(
                    to: path.appendingPathComponent("state.bin")
                )
            }
        }
        return paths
    }

    func createRetainedPublicState() throws -> URL {
        let retainedPath = homeDirectoryURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("com.serhatculhalik.in-your-face", isDirectory: true)
            .appendingPathComponent("keep.bin")
        try FileManager.default.createDirectory(
            at: retainedPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(to: retainedPath)
        return retainedPath
    }
}
