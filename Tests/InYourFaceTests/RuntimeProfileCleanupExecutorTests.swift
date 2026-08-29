import Foundation
import XCTest
@testable import InYourFace

final class RuntimeProfileCleanupExecutorTests: XCTestCase {
    func testRemovesOnlyTheManagedTestProfileState() throws {
        let fixture = try CleanupFixture()
        defer { fixture.cleanUp() }
        let intent = try fixture.makeIntent()
        let testDefaults = try fixture.defaults(named: intent.profile.defaultsSuiteName)
        let productionDefaults = try fixture.defaults(named: fixture.productionDefaultsSuiteName)
        testDefaults.set("test", forKey: "sentinel")
        productionDefaults.set("production", forKey: "sentinel")
        try fixture.createDirectory(for: intent.profile.vaultApplicationIdentifier)
        try fixture.createDirectory(for: fixture.productionVaultApplicationIdentifier)
        let sibling = "unrelated-sibling"
        try fixture.createDirectory(for: sibling)

        try fixture.makeExecutor().execute(intent)

        XCTAssertNil(testDefaults.persistentDomain(forName: intent.profile.defaultsSuiteName))
        XCTAssertEqual(
            productionDefaults.string(forKey: "sentinel"),
            "production"
        )
        XCTAssertFalse(fixture.directoryExists(for: intent.profile.vaultApplicationIdentifier))
        XCTAssertTrue(fixture.directoryExists(for: fixture.productionVaultApplicationIdentifier))
        XCTAssertTrue(fixture.directoryExists(for: sibling))
    }

    func testCleanupIsIdempotent() throws {
        let fixture = try CleanupFixture()
        defer { fixture.cleanUp() }
        let intent = try fixture.makeIntent()
        let defaults = try fixture.defaults(named: intent.profile.defaultsSuiteName)
        defaults.set(true, forKey: "sentinel")
        try fixture.createDirectory(for: intent.profile.vaultApplicationIdentifier)
        let executor = try fixture.makeExecutor()

        try executor.execute(intent)
        try executor.execute(intent)

        XCTAssertNil(defaults.persistentDomain(forName: intent.profile.defaultsSuiteName))
        XCTAssertFalse(fixture.directoryExists(for: intent.profile.vaultApplicationIdentifier))
    }

    func testRemovalFailureDoesNotExposeTheUnderlyingPathOrMessage() throws {
        let fixture = try CleanupFixture()
        defer { fixture.cleanUp() }
        let intent = try fixture.makeIntent()
        let defaults = try fixture.defaults(named: intent.profile.defaultsSuiteName)
        defaults.set("keep", forKey: "sentinel")
        try fixture.createDirectory(for: intent.profile.vaultApplicationIdentifier)
        let sensitivePath = "/Users/private-person/Library/Application Support/private-data"
        let sensitiveMessage = "provider-secret=do-not-display"
        let injectedError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteNoPermissionError,
            userInfo: [
                NSFilePathErrorKey: sensitivePath,
                NSLocalizedDescriptionKey: sensitiveMessage
            ]
        )
        let fileManager = RemovalFailingFileManager(error: injectedError)

        XCTAssertThrowsError(
            try fixture.makeExecutor(fileManager: fileManager).execute(intent)
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "The test-profile Application Support directory could not be removed."
            )
            XCTAssertFalse(error.localizedDescription.contains(sensitivePath))
            XCTAssertFalse(error.localizedDescription.contains(sensitiveMessage))
        }
        XCTAssertEqual(defaults.string(forKey: "sentinel"), "keep")
        XCTAssertTrue(fixture.directoryExists(for: intent.profile.vaultApplicationIdentifier))
    }

    func testInspectionFailureFailsClosedWithoutExposingTheUnderlyingDetails() throws {
        let fixture = try CleanupFixture()
        defer { fixture.cleanUp() }
        let intent = try fixture.makeIntent()
        let defaults = try fixture.defaults(named: intent.profile.defaultsSuiteName)
        defaults.set("keep", forKey: "sentinel")
        try fixture.createDirectory(for: intent.profile.vaultApplicationIdentifier)
        let sensitivePath = "/Users/private-person/Library/Application Support/private-data"
        let sensitiveMessage = "inspection-secret=do-not-display"
        let injectedError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [
                NSFilePathErrorKey: sensitivePath,
                NSLocalizedDescriptionKey: sensitiveMessage
            ]
        )
        let fileManager = InspectionFailingFileManager(error: injectedError)

        XCTAssertThrowsError(
            try fixture.makeExecutor(fileManager: fileManager).execute(intent)
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "The test-profile Application Support directory could not be inspected."
            )
            XCTAssertFalse(error.localizedDescription.contains(sensitivePath))
            XCTAssertFalse(error.localizedDescription.contains(sensitiveMessage))
        }
        XCTAssertEqual(defaults.string(forKey: "sentinel"), "keep")
        XCTAssertTrue(fixture.directoryExists(for: intent.profile.vaultApplicationIdentifier))
    }

    func testRejectsAnArbitraryNamedDefaultsDomainBeforeMutation() throws {
        let fixture = try CleanupFixture()
        defer { fixture.cleanUp() }
        let arbitrarySuite = "\(fixture.namespace).arbitrary.defaults"
        let intent = try fixture.makeIntent(defaultsSuiteName: arbitrarySuite)
        let defaults = try fixture.defaults(named: arbitrarySuite)
        defaults.set("keep", forKey: "sentinel")
        try fixture.createDirectory(for: intent.profile.vaultApplicationIdentifier)

        XCTAssertThrowsError(try fixture.makeExecutor().execute(intent)) { error in
            XCTAssertEqual(
                error as? RuntimeProfileCleanupExecutorError,
                .unmanagedDefaultsSuite
            )
        }
        XCTAssertEqual(defaults.string(forKey: "sentinel"), "keep")
        XCTAssertTrue(fixture.directoryExists(for: intent.profile.vaultApplicationIdentifier))
    }

    func testRejectsProductionDefaultsAndVaultTargets() throws {
        let fixture = try CleanupFixture()
        defer { fixture.cleanUp() }
        let productionDefaultsIntent = try fixture.makeIntent(
            defaultsSuiteName: fixture.productionDefaultsSuiteName
        )
        let productionVaultIntent = try fixture.makeIntent(
            vaultApplicationIdentifier: fixture.productionVaultApplicationIdentifier
        )

        XCTAssertThrowsError(try fixture.makeExecutor().execute(productionDefaultsIntent)) { error in
            XCTAssertEqual(
                error as? RuntimeProfileCleanupExecutorError,
                .protectedDefaultsDomain
            )
        }
        XCTAssertThrowsError(try fixture.makeExecutor().execute(productionVaultIntent)) { error in
            XCTAssertEqual(
                error as? RuntimeProfileCleanupExecutorError,
                .protectedVaultApplicationIdentifier
            )
        }
    }

    func testRefusesASymlinkThatEscapesApplicationSupport() throws {
        let fixture = try CleanupFixture()
        defer { fixture.cleanUp() }
        let intent = try fixture.makeIntent()
        let defaults = try fixture.defaults(named: intent.profile.defaultsSuiteName)
        defaults.set("keep", forKey: "sentinel")
        let outsideDirectory = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outsideDirectory,
            withIntermediateDirectories: true
        )
        let sentinel = outsideDirectory.appendingPathComponent("sentinel")
        XCTAssertTrue(FileManager.default.createFile(atPath: sentinel.path, contents: Data("keep".utf8)))
        try FileManager.default.createSymbolicLink(
            at: fixture.directory(for: intent.profile.vaultApplicationIdentifier),
            withDestinationURL: outsideDirectory
        )

        XCTAssertThrowsError(try fixture.makeExecutor().execute(intent)) { error in
            XCTAssertEqual(
                error as? RuntimeProfileCleanupExecutorError,
                .unsafeApplicationSupportTarget
            )
        }
        XCTAssertEqual(defaults.string(forKey: "sentinel"), "keep")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }

    func testRejectsUnsafeExecutorConfiguration() throws {
        let fixture = try CleanupFixture()
        defer { fixture.cleanUp() }

        XCTAssertThrowsError(
            try RuntimeProfileCleanupExecutor(
                applicationSupportDirectory: URL(fileURLWithPath: "/"),
                namespace: fixture.namespace,
                productionVaultApplicationIdentifier: fixture.productionVaultApplicationIdentifier
            )
        ) { error in
            XCTAssertEqual(
                error as? RuntimeProfileCleanupExecutorError,
                .invalidApplicationSupportDirectory
            )
        }
        XCTAssertThrowsError(
            try RuntimeProfileCleanupExecutor(
                applicationSupportDirectory: fixture.applicationSupportDirectory,
                namespace: "../escape",
                productionVaultApplicationIdentifier: fixture.productionVaultApplicationIdentifier
            )
        ) { error in
            XCTAssertEqual(error as? RuntimeProfileCleanupExecutorError, .invalidNamespace)
        }
    }
}

private final class CleanupFixture {
    let root: URL
    let applicationSupportDirectory: URL
    let namespace: String
    let productionDefaultsSuiteName: String
    let productionVaultApplicationIdentifier: String

    private let profileID = UUID()
    private var defaultsSuiteNames = Set<String>()

    init() throws {
        let suffix = UUID().uuidString.lowercased()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RuntimeProfileCleanupExecutorTests-\(suffix)",
            isDirectory: true
        )
        applicationSupportDirectory = root
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        namespace = "RuntimeProfileCleanupExecutorTests.\(suffix)"
        productionDefaultsSuiteName = "\(namespace).production.defaults"
        productionVaultApplicationIdentifier = "\(namespace).production.vault"
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
    }

    func makeExecutor(
        fileManager: FileManager = .default
    ) throws -> RuntimeProfileCleanupExecutor {
        try RuntimeProfileCleanupExecutor(
            applicationSupportDirectory: applicationSupportDirectory,
            namespace: namespace,
            productionVaultApplicationIdentifier: productionVaultApplicationIdentifier,
            productionDefaultsSuiteName: productionDefaultsSuiteName,
            fileManager: fileManager
        )
    }

    func makeIntent(
        defaultsSuiteName: String? = nil,
        vaultApplicationIdentifier: String? = nil
    ) throws -> RuntimeProfileCleanupIntent {
        let id = profileID.uuidString.lowercased()
        let profile = RuntimeTestProfile(
            id: profileID,
            defaultsSuiteName: defaultsSuiteName ??
                "\(namespace).runtime-profile.test.\(id).defaults",
            vaultApplicationIdentifier: vaultApplicationIdentifier ??
                "\(namespace).runtime-profile.test.\(id).vault",
            createdAt: Date(timeIntervalSince1970: 2_000_000_000),
            expiresAt: .distantFuture
        )
        let payload = CleanupIntentPayload(
            id: UUID(),
            profile: profile,
            reason: .exitRequested,
            attemptCount: 0
        )
        return try JSONDecoder().decode(
            RuntimeProfileCleanupIntent.self,
            from: JSONEncoder().encode(payload)
        )
    }

    func defaults(named suiteName: String) throws -> UserDefaults {
        defaultsSuiteNames.insert(suiteName)
        return try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    func directory(for identifier: String) -> URL {
        applicationSupportDirectory.appendingPathComponent(identifier, isDirectory: true)
    }

    func createDirectory(for identifier: String) throws {
        try FileManager.default.createDirectory(
            at: directory(for: identifier),
            withIntermediateDirectories: true
        )
    }

    func directoryExists(for identifier: String) -> Bool {
        FileManager.default.fileExists(atPath: directory(for: identifier).path)
    }

    func cleanUp() {
        for suiteName in defaultsSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        try? FileManager.default.removeItem(at: root)
    }
}

private final class RemovalFailingFileManager: FileManager, @unchecked Sendable {
    private let error: NSError

    init(error: NSError) {
        self.error = error
        super.init()
    }

    override func removeItem(at URL: URL) throws {
        throw error
    }
}

private final class InspectionFailingFileManager: FileManager, @unchecked Sendable {
    private let error: NSError

    init(error: NSError) {
        self.error = error
        super.init()
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        throw error
    }
}

private struct CleanupIntentPayload: Codable {
    let id: UUID
    let profile: RuntimeTestProfile
    let reason: RuntimeProfileCleanupReason
    let attemptCount: Int
}
