import CommitmentProtection
import Foundation
import XCTest
@testable import InYourFace

final class ResetRecoveryProtectionFactoryTests: XCTestCase {
    func testResetRecoveryReusesProductionCompositionInsteadOfOpeningATestVault() {
        let testProfile = RuntimeProfile.test(
            RuntimeTestProfile(
                id: UUID(),
                defaultsSuiteName: "com.example.test.defaults",
                vaultApplicationIdentifier: "com.example.test.vault",
                createdAt: Date(timeIntervalSince1970: 2_000_000_000),
                expiresAt: .distantFuture
            )
        )

        XCTAssertTrue(
            RuntimeProtectionCompositionPolicy.usesIsolatedTestComposition(
                profile: testProfile,
                hasResetRecovery: false
            )
        )
        XCTAssertFalse(
            RuntimeProtectionCompositionPolicy.usesIsolatedTestComposition(
                profile: testProfile,
                hasResetRecovery: true
            )
        )
        XCTAssertFalse(
            RuntimeProtectionCompositionPolicy.usesIsolatedTestComposition(
                profile: .production(vaultApplicationIdentifier: "com.example.production"),
                hasResetRecovery: false
            )
        )
    }

    @MainActor
    func testVaultFactoryFailureDoesNotExposeUnderlyingPathOrMessage() throws {
        let suiteName = "ResetRecoveryProtectionFactoryTests.failure.\(UUID().uuidString)"
        let stateStore = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { stateStore.removePersistentDomain(forName: suiteName) }
        let sensitivePath = "/Users/private-person/Library/Application Support/private-data"
        let sensitiveMessage = "vault-provider-secret=do-not-display"
        let injectedError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [
                NSFilePathErrorKey: sensitivePath,
                NSLocalizedDescriptionKey: sensitiveMessage
            ]
        )

        let composition = RuntimeProtectionFactory.make(
            profile: .production(vaultApplicationIdentifier: "com.example.failure"),
            stateStore: stateStore,
            oauthConfiguration: GoogleCalendarOAuthConfiguration(clientID: "unused"),
            productionVaultFactory: { _ in throw injectedError }
        )

        XCTAssertEqual(
            composition.flow.encryptedStorageError,
            "Protected storage could not be opened."
        )
        XCTAssertFalse(composition.flow.encryptedStorageError?.contains(sensitivePath) == true)
        XCTAssertFalse(composition.flow.encryptedStorageError?.contains(sensitiveMessage) == true)
    }

    @MainActor
    func testActiveResetRecoveryOpensVaultWithoutMutatingLegacyDefaultsOrVolatileStoreIdentity() throws {
        let suiteName = "ResetRecoveryProtectionFactoryTests.active.\(UUID().uuidString)"
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
            profile: .production(vaultApplicationIdentifier: "com.example.active-recovery"),
            stateStore: stateStore,
            oauthConfiguration: GoogleCalendarOAuthConfiguration(clientID: "unused"),
            startupMode: .activeResetRecovery,
            productionVaultFactory: { _ in
                vaultOpenCount += 1
                throw ActiveResetRecoveryProbeError.expectedVaultOpen
            }
        )
        let after = stateStore.persistentDomain(forName: suiteName) ?? [:]

        XCTAssertEqual(vaultOpenCount, 1)
        XCTAssertTrue(composition.flow.isAppManagedDataResetInProgress)
        XCTAssertNil(
            stateStore.string(forKey: "commitment-protection.volatile-test-store-id")
        )
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: after))
    }
}

private enum ActiveResetRecoveryProbeError: Error {
    case expectedVaultOpen
}
