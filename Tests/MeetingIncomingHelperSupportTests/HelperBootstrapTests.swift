import Foundation
import XCTest
@testable import MeetingIncomingHelperSupport

final class HelperBootstrapTests: XCTestCase {
    func testBootstrapLoadsOperationAndDerivesItsContainingApplication() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingIncomingBootstrapTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let helperURL = rootURL
            .appendingPathComponent("Meeting Incoming Internal.app/Contents/Helpers", isDirectory: true)
            .appendingPathComponent("MeetingIncomingInternalResetHelper")
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(
            at: helperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        let operation = MeetingIncomingHelperOperation(
            parentProcessIdentifier: 41_004,
            bundleIdentifier: "com.serhatculhalik.in-your-face.internal",
            applicationBundlePath: rootURL.appendingPathComponent("Meeting Incoming Internal.app").path,
            homeDirectoryPath: homeURL.path
        )
        let operationURL = rootURL.appendingPathComponent(
            "meeting-incoming-relaunch-\(UUID().uuidString.lowercased()).json"
        )
        try JSONEncoder().encode(operation).write(to: operationURL)

        let bootstrap = try MeetingIncomingHelperBootstrap.load(
            arguments: ["helper", "--operation", operationURL.path],
            helperExecutableURL: helperURL,
            homeDirectoryURL: homeURL,
            temporaryDirectoryURL: rootURL
        )

        XCTAssertEqual(bootstrap.operation, operation)
        XCTAssertEqual(bootstrap.operationFileURL, operationURL)
        XCTAssertEqual(
            bootstrap.environment.containingApplicationBundleURL.path,
            rootURL.appendingPathComponent("Meeting Incoming Internal.app").path
        )
        XCTAssertEqual(bootstrap.environment.homeDirectoryURL.path, homeURL.path)
    }

    func testBootstrapRejectsOperationFileOutsideConfiguredTemporaryDirectory() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingIncomingBootstrapTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let allowedTemporaryURL = rootURL.appendingPathComponent("allowed", isDirectory: true)
        let outsideURL = rootURL.appendingPathComponent("outside", isDirectory: true)
        let helperURL = rootURL
            .appendingPathComponent("Meeting Incoming.app/Contents/Helpers", isDirectory: true)
            .appendingPathComponent("MeetingIncomingRelaunchHelper")
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(
            at: helperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: allowedTemporaryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        let operationURL = outsideURL.appendingPathComponent(
            "meeting-incoming-relaunch-\(UUID().uuidString.lowercased()).json"
        )
        let operation = MeetingIncomingHelperOperation(
            parentProcessIdentifier: 41_005,
            bundleIdentifier: "com.serhatculhalik.in-your-face",
            applicationBundlePath: rootURL.appendingPathComponent("Meeting Incoming.app").path,
            homeDirectoryPath: homeURL.path
        )
        try JSONEncoder().encode(operation).write(to: operationURL)

        XCTAssertThrowsError(
            try MeetingIncomingHelperBootstrap.load(
                arguments: ["helper", "--operation", operationURL.path],
                helperExecutableURL: helperURL,
                homeDirectoryURL: homeURL,
                temporaryDirectoryURL: allowedTemporaryURL
            )
        ) { error in
            XCTAssertEqual(
                error as? MeetingIncomingHelperError,
                .unsafeOperationFile(operationURL.path)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: operationURL.path))
    }
}
