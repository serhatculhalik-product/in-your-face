import Foundation
import XCTest
@testable import InYourFace

@MainActor
final class RuntimeProfileTests: XCTestCase {
    func testMissingJournalResolvesProductionAndCreatesPrivateMarker() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let router = try fixture.makeRouter()

        let resolution = try router.resolveForBootstrap()

        XCTAssertEqual(
            resolution.route,
            .ready(.production(vaultApplicationIdentifier: fixture.productionVaultIdentifier))
        )
        XCTAssertTrue(resolution.cleanupIntents.isEmpty)
        XCTAssertNil(resolution.recovery)

        let journalURL = try XCTUnwrap(try journalURL(in: fixture.root))
        let rootPermissions = try posixPermissions(at: fixture.root)
        let journalPermissions = try posixPermissions(at: journalURL)
        XCTAssertEqual(rootPermissions & 0o777, 0o700)
        XCTAssertEqual(journalPermissions & 0o777, 0o600)
    }

    func testFreshTestUsesIsolatedNamedDefaultsAndSurvivesRouterRelaunch() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let firstRouter = try fixture.makeRouter()

        let firstResolution = try firstRouter.beginFreshTest()
        let profile = try testProfile(from: firstResolution)
        fixture.track(profile)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: profile.defaultsSuiteName))
        defaults.set("test-only", forKey: "sentinel")

        XCTAssertTrue(profile.defaultsSuiteName.contains(profile.id.uuidString.lowercased()))
        XCTAssertTrue(profile.vaultApplicationIdentifier.contains(profile.id.uuidString.lowercased()))
        XCTAssertNotEqual(profile.vaultApplicationIdentifier, fixture.productionVaultIdentifier)
        XCTAssertEqual(profile.createdAt, fixture.clock.date)
        XCTAssertEqual(profile.expiresAt, .distantFuture)

        let journalURL = try XCTUnwrap(try journalURL(in: fixture.root))
        let journal = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any]
        )
        let encodedProfile = try XCTUnwrap(journal["activeTestProfile"] as? [String: Any])
        XCTAssertNotNil(
            encodedProfile["expiresAt"],
            "The legacy expiresAt key must remain in the v1 wire format"
        )

        let relaunchedRouter = try fixture.makeRouter()
        let relaunchedResolution = try relaunchedRouter.resolveForBootstrap()

        XCTAssertEqual(relaunchedResolution.profile, .test(profile))
        XCTAssertEqual(defaults.string(forKey: "sentinel"), "test-only")
        XCTAssertTrue(relaunchedResolution.cleanupIntents.isEmpty)
    }

    func testPastLegacyExpirationDoesNotExitTestMode() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let router = try fixture.makeRouter()
        let original = try testProfile(from: router.beginFreshTest())
        fixture.track(original)
        let legacyExpiration = original.createdAt.addingTimeInterval(60)
        try replaceActiveTestExpiration(with: legacyExpiration, in: fixture.root)
        fixture.clock.advance(by: 61)

        let relaunchedRouter = try fixture.makeRouter()
        let resolution = try relaunchedRouter.resolveForBootstrap()
        let restored = try testProfile(from: resolution)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.expiresAt, legacyExpiration)
        XCTAssertTrue(resolution.cleanupIntents.isEmpty)
    }

    func testRestartUsesNewGenerationAndPersistsExternalCleanupOutcome() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let router = try fixture.makeRouter()
        let firstProfile = try testProfile(from: router.beginFreshTest())
        fixture.track(firstProfile)
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: firstProfile.defaultsSuiteName))
        firstDefaults.set("preserved-until-adapter-cleans", forKey: "sentinel")

        fixture.clock.advance(by: 1)
        let restartResolution = try router.beginFreshTest()
        let replacement = try testProfile(from: restartResolution)
        fixture.track(replacement)
        let cleanup = try XCTUnwrap(restartResolution.cleanupIntents.first)

        XCTAssertNotEqual(replacement.id, firstProfile.id)
        XCTAssertEqual(cleanup.profile, firstProfile)
        XCTAssertEqual(cleanup.reason, .replacedByFreshTest)
        XCTAssertEqual(cleanup.attemptCount, 0)
        XCTAssertEqual(firstDefaults.string(forKey: "sentinel"), "preserved-until-adapter-cleans")

        let failedResolution = try router.recordCleanupResult(.failed, for: cleanup.id)
        XCTAssertEqual(failedResolution.cleanupIntents.first?.attemptCount, 1)

        let relaunchedRouter = try fixture.makeRouter()
        let afterCrashRecovery = try relaunchedRouter.resolveForBootstrap()
        XCTAssertEqual(afterCrashRecovery.profile, .test(replacement))
        XCTAssertEqual(afterCrashRecovery.cleanupIntents.first?.id, cleanup.id)
        XCTAssertEqual(afterCrashRecovery.cleanupIntents.first?.attemptCount, 1)

        let succeededResolution = try relaunchedRouter.recordCleanupResult(.succeeded, for: cleanup.id)
        XCTAssertEqual(succeededResolution.profile, .test(replacement))
        XCTAssertTrue(succeededResolution.cleanupIntents.isEmpty)
        XCTAssertEqual(firstDefaults.string(forKey: "sentinel"), "preserved-until-adapter-cleans")
    }

    func testExitNeverExposesProductionBeforeTestCleanupSucceeds() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let router = try fixture.makeRouter()
        let testProfile = try testProfile(from: router.beginFreshTest())
        fixture.track(testProfile)
        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: testProfile.defaultsSuiteName))
        testDefaults.set(true, forKey: "still-present")

        let exitResolution = try router.requestExitTest()
        let cleanup = try XCTUnwrap(exitResolution.cleanupIntents.first)

        XCTAssertEqual(exitResolution.route, .cleanupRequired)
        XCTAssertNil(exitResolution.profile)
        XCTAssertEqual(cleanup.profile, testProfile)
        XCTAssertEqual(cleanup.reason, .exitRequested)

        let relaunchedRouter = try fixture.makeRouter()
        XCTAssertEqual(try relaunchedRouter.resolveForBootstrap().route, .cleanupRequired)
        XCTAssertEqual(
            try relaunchedRouter.beginFreshTest().route,
            .cleanupRequired,
            "A pending exit must not be bypassed by starting another test profile"
        )

        let failedResolution = try relaunchedRouter.recordCleanupResult(.failed, for: cleanup.id)
        XCTAssertEqual(failedResolution.route, .cleanupRequired)
        XCTAssertEqual(failedResolution.cleanupIntents.first?.attemptCount, 1)

        let completedResolution = try relaunchedRouter.recordCleanupResult(.succeeded, for: cleanup.id)
        XCTAssertEqual(
            completedResolution.route,
            .ready(.production(vaultApplicationIdentifier: fixture.productionVaultIdentifier))
        )
        XCTAssertTrue(testDefaults.bool(forKey: "still-present"))
    }

    func testPreviouslyCommittedExpiredCleanupStillRecoversThroughV1Journal() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let router = try fixture.makeRouter()
        let testProfile = try testProfile(from: router.beginFreshTest())
        fixture.track(testProfile)

        XCTAssertEqual(try router.requestExitTest().route, .cleanupRequired)
        let markerURL = try XCTUnwrap(try journalURL(in: fixture.root))
        let markerData = try Data(contentsOf: markerURL)
        let marker = try XCTUnwrap(String(data: markerData, encoding: .utf8))
        let legacyExpiredMarker = marker.replacingOccurrences(
            of: "\"reason\":\"exitRequested\"",
            with: "\"reason\":\"expired\""
        )
        XCTAssertNotEqual(legacyExpiredMarker, marker)
        try Data(legacyExpiredMarker.utf8).write(to: markerURL, options: .atomic)

        let relaunchedRouter = try fixture.makeRouter()
        let expiredResolution = try relaunchedRouter.resolveForBootstrap()
        let cleanup = try XCTUnwrap(expiredResolution.cleanupIntents.first)

        XCTAssertEqual(expiredResolution.route, .cleanupRequired)
        XCTAssertEqual(cleanup.profile, testProfile)
        XCTAssertEqual(cleanup.reason, .expired)

        let completedResolution = try relaunchedRouter.recordCleanupResult(.succeeded, for: cleanup.id)
        XCTAssertEqual(
            completedResolution.profile,
            .production(vaultApplicationIdentifier: fixture.productionVaultIdentifier)
        )
    }

    func testCorruptJournalFallsBackToProductionWithoutDeletingTestSuite() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let router = try fixture.makeRouter()
        let testProfile = try testProfile(from: router.beginFreshTest())
        fixture.track(testProfile)
        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: testProfile.defaultsSuiteName))
        testDefaults.set("untouched", forKey: "sentinel")
        let markerURL = try XCTUnwrap(try journalURL(in: fixture.root))
        try Data("not-json".utf8).write(to: markerURL, options: .atomic)

        let recoveredRouter = try fixture.makeRouter()
        let recovery = try recoveredRouter.resolveForBootstrap()

        XCTAssertEqual(
            recovery.profile,
            .production(vaultApplicationIdentifier: fixture.productionVaultIdentifier)
        )
        XCTAssertEqual(recovery.recovery, .corruptJournalReplaced)
        XCTAssertTrue(recovery.cleanupIntents.isEmpty)
        XCTAssertEqual(testDefaults.string(forKey: "sentinel"), "untouched")

        let nextBootstrap = try recoveredRouter.resolveForBootstrap()
        XCTAssertNil(nextBootstrap.recovery)
        XCTAssertEqual(
            nextBootstrap.profile,
            .production(vaultApplicationIdentifier: fixture.productionVaultIdentifier)
        )
    }

    func testManagedProfileValidationRejectsJournalThatTargetsProductionVault() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let router = try fixture.makeRouter()
        let testProfile = try testProfile(from: router.beginFreshTest())
        fixture.track(testProfile)
        let markerURL = try XCTUnwrap(try journalURL(in: fixture.root))
        let markerData = try Data(contentsOf: markerURL)
        let marker = try XCTUnwrap(String(data: markerData, encoding: .utf8))
        let forgedMarker = marker.replacingOccurrences(
            of: testProfile.vaultApplicationIdentifier,
            with: fixture.productionVaultIdentifier
        )
        XCTAssertNotEqual(forgedMarker, marker)
        try Data(forgedMarker.utf8).write(to: markerURL, options: .atomic)

        let recoveredRouter = try fixture.makeRouter()
        let resolution = try recoveredRouter.resolveForBootstrap()

        XCTAssertEqual(
            resolution.profile,
            .production(vaultApplicationIdentifier: fixture.productionVaultIdentifier)
        )
        XCTAssertEqual(resolution.recovery, .corruptJournalReplaced)
        XCTAssertTrue(resolution.cleanupIntents.isEmpty)
    }

    func testStaleCleanupResultIsRejectedWithoutChangingCurrentProfile() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let router = try fixture.makeRouter()

        XCTAssertThrowsError(try router.recordCleanupResult(.succeeded, for: UUID())) { error in
            guard case RuntimeProfileRouterError.cleanupIntentNotPending = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(
            try router.resolveForBootstrap().profile,
            .production(vaultApplicationIdentifier: fixture.productionVaultIdentifier)
        )
    }

    private func testProfile(from resolution: RuntimeProfileResolution) throws -> RuntimeTestProfile {
        guard case .test(let profile) = resolution.profile else {
            throw TestFailure.expectedTestProfile
        }
        return profile
    }

    private func makeFixture() -> RouterFixture {
        RouterFixture()
    }

    private func journalURL(in root: URL) throws -> URL? {
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        return try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "json" }
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap((attributes[.posixPermissions] as? NSNumber)?.intValue)
    }

    private func replaceActiveTestExpiration(with expiration: Date, in root: URL) throws {
        let markerURL = try XCTUnwrap(try journalURL(in: root))
        let markerData = try Data(contentsOf: markerURL)
        var marker = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: markerData) as? [String: Any]
        )
        var activeProfile = try XCTUnwrap(marker["activeTestProfile"] as? [String: Any])
        activeProfile["expiresAt"] = expiration.timeIntervalSince1970 * 1_000
        marker["activeTestProfile"] = activeProfile
        let updatedData = try JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys])
        try updatedData.write(to: markerURL, options: .atomic)
    }
}

@MainActor
private final class RouterFixture {
    let root: URL
    let namespace: String
    let productionVaultIdentifier: String
    let clock = TestClock(date: Date(timeIntervalSince1970: 2_000_000_000))

    private var suites: Set<String> = []

    init() {
        let identifier = UUID().uuidString.lowercased()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RuntimeProfileTests-\(identifier)",
            isDirectory: true
        )
        namespace = "RuntimeProfileTests.\(identifier)"
        productionVaultIdentifier = "\(namespace).production"
    }

    func makeRouter() throws -> RuntimeProfileRouter {
        try RuntimeProfileRouter(
            storageRoot: root,
            namespace: namespace,
            productionVaultApplicationIdentifier: productionVaultIdentifier,
            now: { [clock] in clock.date }
        )
    }

    func track(_ profile: RuntimeTestProfile) {
        suites.insert(profile.defaultsSuiteName)
    }

    func cleanUp() {
        for suiteName in suites {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class TestClock {
    private(set) var date: Date

    init(date: Date) {
        self.date = date
    }

    func advance(by interval: TimeInterval) {
        date = date.addingTimeInterval(interval)
    }
}

private enum TestFailure: Error {
    case expectedTestProfile
}
