import CryptoKit
import Foundation
import XCTest
@testable import CommitmentProtection

final class EncryptedGoogleVaultTests: XCTestCase {
    private struct FixtureRecord: Codable, Equatable, Sendable {
        let token: String
        let title: String
    }

    func testCiphertextAndPathsContainNoPlaintextGoogleIdentifiersOrPayload() throws {
        let root = temporaryVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let accountID = "google-account-sentinel@example.com"
        let token = "refresh-token-plaintext-sentinel"
        let title = "Board meeting plaintext sentinel"
        let vault = try makeVault(at: root)

        try vault.store(
            FixtureRecord(token: token, title: title),
            as: .credential,
            for: accountID
        )

        let storedURLs = try allStoredURLs(under: root)
        XCTAssertFalse(storedURLs.isEmpty)
        for url in storedURLs {
            XCTAssertFalse(url.path.contains(accountID))
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            let contents = try Data(contentsOf: url)
            for sentinel in [accountID, token, title] {
                XCTAssertNil(
                    contents.range(of: Data(sentinel.utf8)),
                    "\(url.lastPathComponent) exposed plaintext \(sentinel)"
                )
            }
        }

        let accountDirectories = try storedAccountDirectories(under: root)
        XCTAssertEqual(accountDirectories.count, 1)
        XCTAssertNotNil(UUID(uuidString: accountDirectories[0].lastPathComponent))
    }

    func testTypedRecordSurvivesVaultRelaunch() throws {
        let root = temporaryVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let protector = TestVaultKeyProtector()
        let expected = FixtureRecord(token: "refresh-token", title: "Planning")

        let firstLaunch = try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)
        try firstLaunch.store(expected, as: .credential, for: "account-1")

        let secondLaunch = try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)
        let restored = try secondLaunch.load(
            FixtureRecord.self,
            as: .credential,
            for: "account-1"
        )

        XCTAssertEqual(restored, expected)
        let accountIDs = secondLaunch.accountIDs()
        XCTAssertEqual(accountIDs, ["account-1"])
        let containsAccount = secondLaunch.containsAccount("account-1")
        XCTAssertTrue(containsAccount)
    }

    func testTamperedRecordFailsAuthentication() throws {
        let root = temporaryVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try makeVault(at: root)
        try vault.storeData(Data("secret".utf8), as: .credential, for: "account-1")
        let directory = try XCTUnwrap(storedAccountDirectories(under: root).first)
        let recordURL = directory.appendingPathComponent("credential.v1.encrypted")
        try tamperFile(at: recordURL)

        do {
            _ = try vault.loadData(as: .credential, for: "account-1")
            XCTFail("Tampered ciphertext should not authenticate")
        } catch let error as EncryptedGoogleVaultError {
            XCTAssertEqual(error, .recordCorrupted(.credential))
        }
    }

    func testCorruptionInOneAccountDoesNotAffectAnotherAccount() throws {
        let root = temporaryVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try makeVault(at: root)
        try vault.storeData(Data("first-secret".utf8), as: .credential, for: "account-1")
        let firstDirectory = try XCTUnwrap(storedAccountDirectories(under: root).first)
        try vault.storeData(Data("second-secret".utf8), as: .credential, for: "account-2")
        try tamperFile(at: firstDirectory.appendingPathComponent("account-key.v1.encrypted"))

        do {
            _ = try vault.loadData(as: .credential, for: "account-1")
            XCTFail("The corrupted account should fail")
        } catch let error as EncryptedGoogleVaultError {
            XCTAssertEqual(error, .accountKeyCorrupted)
        }

        let healthyData = try vault.loadData(as: .credential, for: "account-2")
        XCTAssertEqual(healthyData, Data("second-secret".utf8))
        let accountIDs = vault.accountIDs()
        XCTAssertEqual(accountIDs, ["account-1", "account-2"])
    }

    func testRecordAccountAndVaultDeletionAreIsolatedAndPersistent() throws {
        let root = temporaryVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let protector = TestVaultKeyProtector()
        let vault = try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)
        try vault.storeData(Data("credential".utf8), as: .credential, for: "account-1")
        try vault.storeData(Data("activity".utf8), as: .activity, for: "account-1")
        try vault.storeData(Data("other".utf8), as: .credential, for: "account-2")

        try vault.removeRecord(.activity, for: "account-1")
        let removedRecord = try vault.loadData(as: .activity, for: "account-1")
        XCTAssertNil(removedRecord)
        let retainedCredential = try vault.loadData(as: .credential, for: "account-1")
        XCTAssertEqual(retainedCredential, Data("credential".utf8))

        try vault.removeAccount("account-1")
        let accountIDsAfterRemoval = vault.accountIDs()
        XCTAssertEqual(accountIDsAfterRemoval, ["account-2"])
        XCTAssertEqual(try storedAccountDirectories(under: root).count, 1)

        let relaunched = try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)
        let relaunchedAccountIDs = relaunched.accountIDs()
        XCTAssertEqual(relaunchedAccountIDs, ["account-2"])
        try relaunched.reset()
        let resetAccountIDs = relaunched.accountIDs()
        XCTAssertTrue(resetAccountIDs.isEmpty)
        XCTAssertTrue(try storedAccountDirectories(under: root).isEmpty)
    }

    func testRelaunchRestoresStagedAccountRemovalWhenIndexStillReferencesAccount() throws {
        let root = temporaryVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let protector = TestVaultKeyProtector()
        let firstLaunch = try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)
        try firstLaunch.storeData(Data("credential".utf8), as: .credential, for: "account-1")
        let accountDirectory = try XCTUnwrap(storedAccountDirectories(under: root).first)
        let stagedDirectory = root.appendingPathComponent(
            ".removing-\(accountDirectory.lastPathComponent)",
            isDirectory: true
        )
        try FileManager.default.moveItem(at: accountDirectory, to: stagedDirectory)

        let relaunched = try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)

        XCTAssertEqual(relaunched.accountIDs(), ["account-1"])
        XCTAssertEqual(
            try relaunched.loadData(as: .credential, for: "account-1"),
            Data("credential".utf8)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: accountDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedDirectory.path))
    }

    func testRelaunchDeletesStagedAccountRemovalWhenIndexNoLongerReferencesAccount() throws {
        let root = temporaryVaultRoot()
        let preservedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "EncryptedGoogleVaultTests-preserved-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: preservedDirectory)
        }
        let protector = TestVaultKeyProtector()
        let firstLaunch = try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)
        try firstLaunch.storeData(Data("credential".utf8), as: .credential, for: "account-1")
        let accountDirectory = try XCTUnwrap(storedAccountDirectories(under: root).first)
        let stagedDirectory = root.appendingPathComponent(
            ".removing-\(accountDirectory.lastPathComponent)",
            isDirectory: true
        )
        try FileManager.default.copyItem(at: accountDirectory, to: preservedDirectory)
        try firstLaunch.removeAccount("account-1")
        try FileManager.default.moveItem(at: preservedDirectory, to: stagedDirectory)

        let relaunched = try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)

        XCTAssertTrue(relaunched.accountIDs().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedDirectory.path))
        XCTAssertTrue(try storedAccountDirectories(under: root).isEmpty)
    }

    func testRelaunchRejectsIndexedAccountWithBothLiveAndStagedDirectories() throws {
        let root = temporaryVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let protector = TestVaultKeyProtector()
        let firstLaunch = try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)
        try firstLaunch.storeData(Data("credential".utf8), as: .credential, for: "account-1")
        let accountDirectory = try XCTUnwrap(storedAccountDirectories(under: root).first)
        let stagedDirectory = root.appendingPathComponent(
            ".removing-\(accountDirectory.lastPathComponent)",
            isDirectory: true
        )
        try FileManager.default.copyItem(at: accountDirectory, to: stagedDirectory)

        XCTAssertThrowsError(
            try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)
        ) { error in
            XCTAssertEqual(error as? EncryptedGoogleVaultError, .indexCorrupted)
        }
    }

    func testRelaunchRejectsIndexedAccountWhoseDirectoryIsMissing() throws {
        let root = temporaryVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let protector = TestVaultKeyProtector()
        let firstLaunch = try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)
        try firstLaunch.storeData(Data("credential".utf8), as: .credential, for: "account-1")
        let accountDirectory = try XCTUnwrap(storedAccountDirectories(under: root).first)
        try FileManager.default.removeItem(at: accountDirectory)

        XCTAssertThrowsError(
            try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)
        ) { error in
            XCTAssertEqual(error as? EncryptedGoogleVaultError, .indexCorrupted)
        }
    }

    func testRelaunchRejectsUnindexedAccountDirectory() throws {
        let root = temporaryVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let protector = TestVaultKeyProtector()
        _ = try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)
        let orphanDirectory = root
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: orphanDirectory, withIntermediateDirectories: false)

        XCTAssertThrowsError(
            try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)
        ) { error in
            XCTAssertEqual(error as? EncryptedGoogleVaultError, .indexCorrupted)
        }
    }

    func testRelaunchRejectsInvalidlyNamedAccountDirectory() throws {
        try assertRelaunchRejectsUnexpectedAccountItem { accountsDirectory in
            try FileManager.default.createDirectory(
                at: accountsDirectory.appendingPathComponent("not-an-account-uuid", isDirectory: true),
                withIntermediateDirectories: false
            )
        }
    }

    func testRelaunchRejectsFileInAccountDirectory() throws {
        try assertRelaunchRejectsUnexpectedAccountItem { accountsDirectory in
            let fileURL = accountsDirectory.appendingPathComponent(UUID().uuidString.lowercased())
            guard FileManager.default.createFile(atPath: fileURL.path, contents: Data()) else {
                throw TestVaultFixtureError.couldNotCreateAccountItem
            }
        }
    }

    func testRelaunchRejectsSymlinkInAccountDirectory() throws {
        try assertRelaunchRejectsUnexpectedAccountItem { accountsDirectory in
            let targetDirectory = accountsDirectory.deletingLastPathComponent().appendingPathComponent(
                "symlink-target",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: targetDirectory,
                withIntermediateDirectories: false
            )
            try FileManager.default.createSymbolicLink(
                at: accountsDirectory.appendingPathComponent(UUID().uuidString.lowercased()),
                withDestinationURL: targetDirectory
            )
        }
    }

    func testDirectoriesFilesAndBackupExclusionAreHardened() throws {
        let root = temporaryVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try makeVault(at: root)
        try vault.storeData(Data("secret".utf8), as: .eventSnapshot, for: "account-1")

        let storedURLs = try allStoredURLs(under: root)
        for url in [root] + storedURLs {
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isExcludedFromBackupKey
            ])
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
            if values.isDirectory == true {
                XCTAssertEqual(permissions & 0o777, 0o700, "Unexpected directory mode at \(url.path)")
            } else if values.isRegularFile == true {
                XCTAssertEqual(permissions & 0o777, 0o600, "Unexpected file mode at \(url.path)")
            }
            XCTAssertEqual(values.isExcludedFromBackup, true, "Backup exclusion missing at \(url.path)")
        }
    }

    func testUnavailableAndCorruptKeyProtectorsFailClosedWithoutFallback() throws {
        let unavailableRoot = temporaryVaultRoot()
        defer { try? FileManager.default.removeItem(at: unavailableRoot) }
        XCTAssertThrowsError(
            try EncryptedGoogleVault(
                rootDirectory: unavailableRoot,
                keyProtector: TestVaultKeyProtector(isAvailable: false)
            )
        ) { error in
            XCTAssertEqual(error as? EncryptedGoogleVaultError, .secureEnclaveUnavailable)
        }

        let corruptRoot = temporaryVaultRoot()
        defer { try? FileManager.default.removeItem(at: corruptRoot) }
        _ = try EncryptedGoogleVault(
            rootDirectory: corruptRoot,
            keyProtector: TestVaultKeyProtector()
        )
        let bootstrapURL = corruptRoot.appendingPathComponent("device-key-material.v1")
        try Data("not-valid-key-material".utf8).write(to: bootstrapURL, options: .atomic)

        XCTAssertThrowsError(
            try EncryptedGoogleVault(
                rootDirectory: corruptRoot,
                keyProtector: TestVaultKeyProtector()
            )
        ) { error in
            XCTAssertEqual(error as? EncryptedGoogleVaultError, .keyMaterialCorrupted)
        }
    }

    private func makeVault(at root: URL) throws -> EncryptedGoogleVault {
        try EncryptedGoogleVault(rootDirectory: root, keyProtector: TestVaultKeyProtector())
    }

    private func assertRelaunchRejectsUnexpectedAccountItem(
        createItem: (URL) throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let root = temporaryVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let protector = TestVaultKeyProtector()
        _ = try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector)
        try createItem(root.appendingPathComponent("accounts", isDirectory: true))

        XCTAssertThrowsError(
            try EncryptedGoogleVault(rootDirectory: root, keyProtector: protector),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? EncryptedGoogleVaultError,
                .indexCorrupted,
                file: file,
                line: line
            )
        }
    }

    private func temporaryVaultRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "EncryptedGoogleVaultTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func storedAccountDirectories(under root: URL) throws -> [URL] {
        let accountsDirectory = root.appendingPathComponent("accounts", isDirectory: true)
        return try FileManager.default.contentsOfDirectory(
            at: accountsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func allStoredURLs(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
    }

    private func tamperFile(at url: URL) throws {
        var data = try Data(contentsOf: url)
        let index = data.index(data.startIndex, offsetBy: data.count / 2)
        data[index] ^= 0x01
        try data.write(to: url, options: .atomic)
    }
}

private enum TestVaultFixtureError: Error {
    case couldNotCreateAccountItem
}

private struct TestVaultKeyProtector: EncryptedGoogleVaultKeyProtecting {
    private static let marker = Data("test-vault-key-v1|".utf8)
    private let isAvailable: Bool
    private let key: Data

    init(isAvailable: Bool = true, seed: String = "stable-test-vault-key") {
        self.isAvailable = isAvailable
        key = Data(SHA256.hash(data: Data(seed.utf8)))
    }

    func createKeyMaterial() throws -> Data {
        guard isAvailable else {
            throw EncryptedGoogleVaultError.secureEnclaveUnavailable
        }
        return Self.marker + key
    }

    func restoreMasterKey(from keyMaterial: Data) throws -> SymmetricKey {
        guard isAvailable else {
            throw EncryptedGoogleVaultError.secureEnclaveUnavailable
        }
        guard keyMaterial.count == Self.marker.count + key.count,
              keyMaterial.prefix(Self.marker.count) == Self.marker,
              keyMaterial.suffix(key.count) == key else {
            throw EncryptedGoogleVaultError.keyMaterialCorrupted
        }
        return SymmetricKey(data: key)
    }
}
