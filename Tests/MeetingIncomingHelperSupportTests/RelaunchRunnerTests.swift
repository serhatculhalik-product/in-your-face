import Foundation
import XCTest
@testable import MeetingIncomingHelperSupport

final class RelaunchRunnerTests: XCTestCase {
    func testRelaunchWaitsForParentAndOpensVerifiedAppWithoutResetCommands() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingIncomingRelaunchTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let homeDirectoryURL = rootURL.appendingPathComponent("home", isDirectory: true)
        let appURL = rootURL.appendingPathComponent("Meeting Incoming.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeDirectoryURL, withIntermediateDirectories: true)
        let bundleIdentifier = "com.serhatculhalik.in-your-face"
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleIdentifier],
            format: .xml,
            options: 0
        )
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        let retainedStateURL = homeDirectoryURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("keep.bin")
        try FileManager.default.createDirectory(
            at: retainedStateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(to: retainedStateURL)
        let operation = MeetingIncomingHelperOperation(
            parentProcessIdentifier: 41_003,
            bundleIdentifier: bundleIdentifier,
            applicationBundlePath: appURL.path,
            homeDirectoryPath: homeDirectoryURL.path
        )
        let parentWaiter = RelaunchRecordingParentWaiter()
        let commandRunner = RelaunchRecordingCommandRunner()
        let runner = RelaunchRunner(
            environment: MeetingIncomingHelperEnvironment(
                containingApplicationBundleURL: appURL,
                homeDirectoryURL: homeDirectoryURL
            ),
            parentWaiter: parentWaiter,
            commandRunner: commandRunner
        )

        let result = try runner.run(operation: operation)

        XCTAssertEqual(parentWaiter.waitedProcessIdentifiers, [41_003])
        XCTAssertEqual(
            commandRunner.invocations,
            [
                .init(
                    executablePath: "/usr/bin/open",
                    arguments: ["-F", appURL.path]
                )
            ]
        )
        XCTAssertEqual(result.relaunchedApplicationPath, appURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedStateURL.path))
    }
}

private final class RelaunchRecordingParentWaiter: ParentProcessWaiting {
    private(set) var waitedProcessIdentifiers: [Int32] = []

    func wait(for processIdentifier: Int32) throws {
        waitedProcessIdentifiers.append(processIdentifier)
    }
}

private final class RelaunchRecordingCommandRunner: HelperCommandRunning {
    struct Invocation: Equatable {
        let executablePath: String
        let arguments: [String]
    }

    private(set) var invocations: [Invocation] = []

    func run(executableURL: URL, arguments: [String]) throws -> Int32 {
        invocations.append(.init(executablePath: executableURL.path, arguments: arguments))
        return 0
    }
}
