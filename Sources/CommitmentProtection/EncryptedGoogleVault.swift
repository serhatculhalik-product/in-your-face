import CryptoKit
import Foundation

public enum EncryptedGoogleVaultRecordKind: String, CaseIterable, Codable, Sendable {
    case credential
    case configuration
    case eventSnapshot = "event-snapshot"
    case activity
}

public enum EncryptedGoogleVaultError: Error, Equatable, LocalizedError, Sendable {
    case secureEnclaveUnavailable
    case invalidApplicationIdentifier
    case invalidAccountIdentifier
    case accountNotFound
    case keyMaterialCorrupted
    case indexCorrupted
    case accountKeyCorrupted
    case recordCorrupted(EncryptedGoogleVaultRecordKind)
    case encodingFailed
    case decodingFailed(EncryptedGoogleVaultRecordKind)
    case storageFailed(String)

    public var errorDescription: String? {
        switch self {
        case .secureEnclaveUnavailable:
            return "Secure Enclave is unavailable on this Mac. Protected Google data cannot be stored."
        case .invalidApplicationIdentifier:
            return "The application identifier cannot be used for protected storage."
        case .invalidAccountIdentifier:
            return "The Google account identifier is invalid."
        case .accountNotFound:
            return "The protected Google account was not found."
        case .keyMaterialCorrupted:
            return "The Secure Enclave key material cannot be restored."
        case .indexCorrupted:
            return "The protected account index is damaged or cannot be authenticated."
        case .accountKeyCorrupted:
            return "The protected account key is damaged or cannot be authenticated."
        case .recordCorrupted:
            return "The protected account record is damaged or cannot be authenticated."
        case .encodingFailed:
            return "The account record could not be encoded for protected storage."
        case .decodingFailed:
            return "The protected account record could not be decoded."
        case .storageFailed(let operation):
            return "Protected storage failed while \(operation)."
        }
    }
}

protocol EncryptedGoogleVaultKeyProtecting: Sendable {
    func createKeyMaterial() throws -> Data
    func restoreMasterKey(from keyMaterial: Data) throws -> SymmetricKey
}

/// Stores Google-derived data without placing credentials or key material in Keychain.
///
/// The external interface deals only in account identifiers, record kinds, and values. The
/// implementation hides Secure Enclave key agreement, envelope encryption, random on-disk
/// account locators, authenticated file formats, permissions, and backup exclusion.
public final class EncryptedGoogleVault: @unchecked Sendable {
    private static let formatVersion = 1
    private static let storageDirectoryName = "EncryptedGoogleVault"
    private static let bootstrapFileName = "device-key-material.v1"
    private static let indexFileName = "account-index.v1.encrypted"
    private static let accountsDirectoryName = "accounts"
    private static let accountKeyFileName = "account-key.v1.encrypted"

    private struct AccountEntry: Codable, Equatable, Sendable {
        let accountID: String
        let directoryID: UUID
    }

    private struct AccountIndex: Codable, Equatable, Sendable {
        let version: Int
        var entries: [AccountEntry]
    }

    private struct PreparedState: Sendable {
        let masterKey: SymmetricKey
        let index: AccountIndex
    }

    private let rootDirectory: URL
    private let accountsDirectory: URL
    private let keyProtector: any EncryptedGoogleVaultKeyProtecting
    private let lock = NSRecursiveLock()
    private var masterKey: SymmetricKey
    private var index: AccountIndex

    private var fileManager: FileManager { .default }

    public static func production(
        applicationIdentifier: String? = nil
    ) throws -> EncryptedGoogleVault {
        let rootDirectory = try productionRootDirectory(applicationIdentifier: applicationIdentifier)
        return try EncryptedGoogleVault(
            rootDirectory: rootDirectory,
            keyProtector: SecureEnclaveGoogleVaultKeyProtector()
        )
    }

    /// Replaces an unreadable production vault only after the user explicitly
    /// confirms local encrypted-data reset. If replacement initialization fails,
    /// the original directory is restored.
    public static func resetProduction(
        applicationIdentifier: String? = nil
    ) throws -> EncryptedGoogleVault {
        let rootDirectory = try productionRootDirectory(applicationIdentifier: applicationIdentifier)
        let fileManager = FileManager.default
        let stagedDirectory = rootDirectory.deletingLastPathComponent().appendingPathComponent(
            ".\(storageDirectoryName)-reset-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        let hadExistingVault = fileManager.fileExists(atPath: rootDirectory.path)
        do {
            if hadExistingVault {
                try fileManager.moveItem(at: rootDirectory, to: stagedDirectory)
            }
            let replacement = try EncryptedGoogleVault(
                rootDirectory: rootDirectory,
                keyProtector: SecureEnclaveGoogleVaultKeyProtector()
            )
            if hadExistingVault {
                try fileManager.removeItem(at: stagedDirectory)
            }
            return replacement
        } catch {
            try? fileManager.removeItem(at: rootDirectory)
            if hadExistingVault {
                try? fileManager.moveItem(at: stagedDirectory, to: rootDirectory)
            }
            throw (error as? EncryptedGoogleVaultError) ?? .storageFailed("resetting protected storage")
        }
    }

    private static func productionRootDirectory(
        applicationIdentifier: String?
    ) throws -> URL {
        let identifier = applicationIdentifier ?? Bundle.main.bundleIdentifier ?? "MeetingIncoming"
        guard Self.isSafePathComponent(identifier) else {
            throw EncryptedGoogleVaultError.invalidApplicationIdentifier
        }

        let applicationSupportDirectory: URL
        do {
            applicationSupportDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw EncryptedGoogleVaultError.storageFailed("locating Application Support")
        }
        return applicationSupportDirectory
            .appendingPathComponent(identifier, isDirectory: true)
            .appendingPathComponent(Self.storageDirectoryName, isDirectory: true)
    }

    init(
        rootDirectory: URL,
        keyProtector: any EncryptedGoogleVaultKeyProtecting
    ) throws {
        let accountsDirectory = rootDirectory.appendingPathComponent(Self.accountsDirectoryName, isDirectory: true)
        let preparedState = try Self.prepareStorage(
            rootDirectory: rootDirectory,
            accountsDirectory: accountsDirectory,
            keyProtector: keyProtector,
            fileManager: .default
        )
        self.rootDirectory = rootDirectory
        self.accountsDirectory = accountsDirectory
        self.keyProtector = keyProtector
        masterKey = preparedState.masterKey
        index = preparedState.index
    }

    private static func prepareStorage(
        rootDirectory: URL,
        accountsDirectory: URL,
        keyProtector: any EncryptedGoogleVaultKeyProtecting,
        fileManager: FileManager
    ) throws -> PreparedState {
        try secureDirectory(rootDirectory, fileManager: fileManager)
        try secureDirectory(accountsDirectory, fileManager: fileManager)

        let bootstrapURL = rootDirectory.appendingPathComponent(Self.bootstrapFileName, isDirectory: false)
        let keyMaterial: Data
        if fileManager.fileExists(atPath: bootstrapURL.path) {
            do {
                keyMaterial = try Data(contentsOf: bootstrapURL)
            } catch {
                throw EncryptedGoogleVaultError.keyMaterialCorrupted
            }
            try Self.secureFile(bootstrapURL, fileManager: fileManager)
        } else {
            let existingAccountItems: [String]
            do {
                existingAccountItems = try fileManager.contentsOfDirectory(atPath: accountsDirectory.path)
            } catch {
                throw EncryptedGoogleVaultError.storageFailed("inspecting protected account storage")
            }
            let hasExistingProtectedData = fileManager.fileExists(
                atPath: rootDirectory.appendingPathComponent(Self.indexFileName).path
            ) || !existingAccountItems.isEmpty
            guard !hasExistingProtectedData else {
                throw EncryptedGoogleVaultError.keyMaterialCorrupted
            }
            keyMaterial = try keyProtector.createKeyMaterial()
            try Self.atomicWrite(keyMaterial, to: bootstrapURL, fileManager: fileManager)
        }

        let masterKey: SymmetricKey
        do {
            masterKey = try keyProtector.restoreMasterKey(from: keyMaterial)
        } catch let error as EncryptedGoogleVaultError {
            throw error
        } catch {
            throw EncryptedGoogleVaultError.keyMaterialCorrupted
        }

        let indexURL = rootDirectory.appendingPathComponent(Self.indexFileName, isDirectory: false)
        let index: AccountIndex
        if fileManager.fileExists(atPath: indexURL.path) {
            let encryptedIndex: Data
            do {
                encryptedIndex = try Data(contentsOf: indexURL)
            } catch {
                throw EncryptedGoogleVaultError.indexCorrupted
            }
            let decodedIndex = try Self.openIndex(encryptedIndex, using: masterKey)
            guard Self.isValid(decodedIndex) else {
                throw EncryptedGoogleVaultError.indexCorrupted
            }
            index = decodedIndex
            try Self.secureFile(indexURL, fileManager: fileManager)
        } else {
            let existingAccountItems: [String]
            do {
                existingAccountItems = try fileManager.contentsOfDirectory(atPath: accountsDirectory.path)
            } catch {
                throw EncryptedGoogleVaultError.storageFailed("inspecting protected account storage")
            }
            guard existingAccountItems.isEmpty else {
                throw EncryptedGoogleVaultError.indexCorrupted
            }
            index = AccountIndex(version: Self.formatVersion, entries: [])
            let encryptedIndex = try Self.sealIndex(index, using: masterKey)
            try Self.atomicWrite(encryptedIndex, to: indexURL, fileManager: fileManager)
        }

        try Self.reconcileInterruptedAccountRemovals(
            rootDirectory: rootDirectory,
            accountsDirectory: accountsDirectory,
            index: index,
            fileManager: fileManager
        )
        try Self.validateAccountDirectories(
            accountsDirectory: accountsDirectory,
            index: index,
            fileManager: fileManager
        )

        for entry in index.entries {
            let directory = accountsDirectory.appendingPathComponent(
                Self.directoryName(for: entry.directoryID),
                isDirectory: true
            )
            guard fileManager.fileExists(atPath: directory.path) else {
                throw EncryptedGoogleVaultError.indexCorrupted
            }
            try Self.secureDirectory(directory, fileManager: fileManager)
            let accountKeyURL = directory.appendingPathComponent(Self.accountKeyFileName)
            if fileManager.fileExists(atPath: accountKeyURL.path) {
                try Self.secureFile(accountKeyURL, fileManager: fileManager)
            }
            for kind in EncryptedGoogleVaultRecordKind.allCases {
                let recordURL = directory.appendingPathComponent(Self.fileName(for: kind))
                if fileManager.fileExists(atPath: recordURL.path) {
                    try Self.secureFile(recordURL, fileManager: fileManager)
                }
            }
        }
        return PreparedState(masterKey: masterKey, index: index)
    }

    private static func reconcileInterruptedAccountRemovals(
        rootDirectory: URL,
        accountsDirectory: URL,
        index: AccountIndex,
        fileManager: FileManager
    ) throws {
        let rootItems: [URL]
        do {
            rootItems = try fileManager.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            throw EncryptedGoogleVaultError.storageFailed("inspecting interrupted account removals")
        }

        let prefix = ".removing-"
        var stagedDirectoriesByID: [UUID: [URL]] = [:]
        for item in rootItems where item.lastPathComponent.hasPrefix(prefix) {
            guard let directoryID = UUID(
                uuidString: String(item.lastPathComponent.dropFirst(prefix.count))
            ) else {
                throw EncryptedGoogleVaultError.indexCorrupted
            }
            let values: URLResourceValues
            do {
                values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            } catch {
                throw EncryptedGoogleVaultError.storageFailed("inspecting an interrupted account removal")
            }
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw EncryptedGoogleVaultError.indexCorrupted
            }
            stagedDirectoriesByID[directoryID, default: []].append(item)
        }

        let indexedDirectoryIDs = Set(index.entries.map(\.directoryID))
        for stagedDirectories in stagedDirectoriesByID.values {
            guard stagedDirectories.count == 1 else {
                throw EncryptedGoogleVaultError.indexCorrupted
            }
        }

        for entry in index.entries {
            let accountDirectory = accountsDirectory.appendingPathComponent(
                directoryName(for: entry.directoryID),
                isDirectory: true
            )
            let stagedDirectories = stagedDirectoriesByID[entry.directoryID] ?? []
            let accountDirectoryExists = fileManager.fileExists(atPath: accountDirectory.path)
            guard accountDirectoryExists || !stagedDirectories.isEmpty else {
                throw EncryptedGoogleVaultError.indexCorrupted
            }
            guard !(accountDirectoryExists && !stagedDirectories.isEmpty) else {
                throw EncryptedGoogleVaultError.indexCorrupted
            }
        }

        for (directoryID, stagedDirectories) in stagedDirectoriesByID {
            let stagedDirectory = stagedDirectories[0]
            do {
                if indexedDirectoryIDs.contains(directoryID) {
                    let accountDirectory = accountsDirectory.appendingPathComponent(
                        directoryName(for: directoryID),
                        isDirectory: true
                    )
                    try fileManager.moveItem(at: stagedDirectory, to: accountDirectory)
                } else {
                    try fileManager.removeItem(at: stagedDirectory)
                }
            } catch {
                let operation = indexedDirectoryIDs.contains(directoryID)
                    ? "recovering an interrupted account removal"
                    : "finishing an interrupted account removal"
                throw EncryptedGoogleVaultError.storageFailed(operation)
            }
        }
    }

    private static func validateAccountDirectories(
        accountsDirectory: URL,
        index: AccountIndex,
        fileManager: FileManager
    ) throws {
        let accountItems: [URL]
        do {
            accountItems = try fileManager.contentsOfDirectory(
                at: accountsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            throw EncryptedGoogleVaultError.storageFailed("inspecting protected account directories")
        }

        let indexedDirectoryIDs = Set(index.entries.map(\.directoryID))
        var foundDirectoryIDs: Set<UUID> = []
        for item in accountItems {
            guard let directoryID = UUID(uuidString: item.lastPathComponent),
                  item.lastPathComponent == directoryName(for: directoryID) else {
                throw EncryptedGoogleVaultError.indexCorrupted
            }
            let values: URLResourceValues
            do {
                values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            } catch {
                throw EncryptedGoogleVaultError.storageFailed("inspecting a protected account directory")
            }
            guard values.isDirectory == true,
                  values.isSymbolicLink != true,
                  indexedDirectoryIDs.contains(directoryID),
                  foundDirectoryIDs.insert(directoryID).inserted else {
                throw EncryptedGoogleVaultError.indexCorrupted
            }
        }
        guard foundDirectoryIDs == indexedDirectoryIDs else {
            throw EncryptedGoogleVaultError.indexCorrupted
        }
    }

    public func accountIDs() -> [String] {
        lock.withLock {
            index.entries.map(\.accountID).sorted()
        }
    }

    public func containsAccount(_ accountID: String) -> Bool {
        lock.withLock {
            index.entries.contains { $0.accountID == accountID }
        }
    }

    public func storeData(
        _ data: Data,
        as kind: EncryptedGoogleVaultRecordKind,
        for accountID: String
    ) throws {
        try lock.withLock {
            let entry = try ensureAccount(accountID)
            let accountKey = try loadAccountKey(for: entry)
            let sealedRecord = try Self.seal(
                data,
                using: accountKey,
                authenticatedBy: Self.recordAuthenticatedData(kind: kind, directoryID: entry.directoryID),
                corruptionError: .recordCorrupted(kind)
            )
            try Self.atomicWrite(
                sealedRecord,
                to: accountDirectory(for: entry).appendingPathComponent(Self.fileName(for: kind)),
                fileManager: fileManager
            )
        }
    }

    public func loadData(
        as kind: EncryptedGoogleVaultRecordKind,
        for accountID: String
    ) throws -> Data? {
        try lock.withLock {
            let entry = try accountEntry(for: accountID)
            let recordURL = accountDirectory(for: entry).appendingPathComponent(Self.fileName(for: kind))
            guard fileManager.fileExists(atPath: recordURL.path) else { return nil }

            let encryptedRecord: Data
            do {
                encryptedRecord = try Data(contentsOf: recordURL)
            } catch {
                throw EncryptedGoogleVaultError.storageFailed("reading an account record")
            }
            let accountKey = try loadAccountKey(for: entry)
            return try Self.open(
                encryptedRecord,
                using: accountKey,
                authenticatedBy: Self.recordAuthenticatedData(kind: kind, directoryID: entry.directoryID),
                corruptionError: .recordCorrupted(kind)
            )
        }
    }

    public func store<Value: Encodable & Sendable>(
        _ value: Value,
        as kind: EncryptedGoogleVaultRecordKind,
        for accountID: String
    ) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw EncryptedGoogleVaultError.encodingFailed
        }
        try storeData(data, as: kind, for: accountID)
    }

    public func load<Value: Decodable & Sendable>(
        _ type: Value.Type,
        as kind: EncryptedGoogleVaultRecordKind,
        for accountID: String
    ) throws -> Value? {
        guard let data = try loadData(as: kind, for: accountID) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw EncryptedGoogleVaultError.decodingFailed(kind)
        }
    }

    public func removeRecord(
        _ kind: EncryptedGoogleVaultRecordKind,
        for accountID: String
    ) throws {
        try lock.withLock {
            let entry = try accountEntry(for: accountID)
            let recordURL = accountDirectory(for: entry).appendingPathComponent(Self.fileName(for: kind))
            guard fileManager.fileExists(atPath: recordURL.path) else { return }
            do {
                try fileManager.removeItem(at: recordURL)
            } catch {
                throw EncryptedGoogleVaultError.storageFailed("removing an account record")
            }
        }
    }

    public func removeAccount(_ accountID: String) throws {
        try lock.withLock {
            let entry = try accountEntry(for: accountID)
            let accountDirectory = accountDirectory(for: entry)
            let stagedDeletion = rootDirectory.appendingPathComponent(
                ".removing-\(entry.directoryID.uuidString.lowercased())",
                isDirectory: true
            )
            do {
                if fileManager.fileExists(atPath: stagedDeletion.path) {
                    try fileManager.removeItem(at: stagedDeletion)
                }
                try fileManager.moveItem(at: accountDirectory, to: stagedDeletion)
            } catch {
                throw EncryptedGoogleVaultError.storageFailed("staging account removal")
            }

            let previousIndex = index
            var updatedIndex = index
            updatedIndex.entries.removeAll { $0.accountID == accountID }
            do {
                try persist(updatedIndex)
                index = updatedIndex
                try fileManager.removeItem(at: stagedDeletion)
            } catch {
                if index == previousIndex {
                    try? fileManager.moveItem(at: stagedDeletion, to: accountDirectory)
                } else {
                    index = previousIndex
                    try? persist(previousIndex)
                    try? fileManager.moveItem(at: stagedDeletion, to: accountDirectory)
                }
                throw EncryptedGoogleVaultError.storageFailed("removing an account")
            }
        }
    }

    public func reset() throws {
        try lock.withLock {
            let stagedReset = rootDirectory.deletingLastPathComponent().appendingPathComponent(
                ".\(rootDirectory.lastPathComponent)-reset-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
            var didStageExistingVault = false
            do {
                if fileManager.fileExists(atPath: stagedReset.path) {
                    try fileManager.removeItem(at: stagedReset)
                }
                try fileManager.moveItem(at: rootDirectory, to: stagedReset)
                didStageExistingVault = true
                try Self.secureDirectory(rootDirectory, fileManager: fileManager)
                try Self.secureDirectory(accountsDirectory, fileManager: fileManager)

                let keyMaterial = try keyProtector.createKeyMaterial()
                let replacementMasterKey = try keyProtector.restoreMasterKey(from: keyMaterial)
                try Self.atomicWrite(
                    keyMaterial,
                    to: rootDirectory.appendingPathComponent(Self.bootstrapFileName),
                    fileManager: fileManager
                )
                let replacementIndex = AccountIndex(version: Self.formatVersion, entries: [])
                let encryptedIndex = try Self.sealIndex(replacementIndex, using: replacementMasterKey)
                try Self.atomicWrite(
                    encryptedIndex,
                    to: rootDirectory.appendingPathComponent(Self.indexFileName),
                    fileManager: fileManager
                )
                try fileManager.removeItem(at: stagedReset)
                masterKey = replacementMasterKey
                index = replacementIndex
            } catch {
                if didStageExistingVault {
                    try? fileManager.removeItem(at: rootDirectory)
                    try? fileManager.moveItem(at: stagedReset, to: rootDirectory)
                }
                throw (error as? EncryptedGoogleVaultError) ?? .storageFailed("resetting protected storage")
            }
        }
    }

    private func ensureAccount(_ accountID: String) throws -> AccountEntry {
        let trimmedAccountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccountID.isEmpty, trimmedAccountID == accountID else {
            throw EncryptedGoogleVaultError.invalidAccountIdentifier
        }
        if let existingEntry = index.entries.first(where: { $0.accountID == accountID }) {
            return existingEntry
        }

        let entry = AccountEntry(accountID: accountID, directoryID: UUID())
        let directory = accountDirectory(for: entry)
        do {
            try Self.secureDirectory(directory, fileManager: fileManager)
            let accountKey = SymmetricKey(size: .bits256)
            let wrappedAccountKey = try Self.seal(
                Self.data(for: accountKey),
                using: masterKey,
                authenticatedBy: Self.accountKeyAuthenticatedData(directoryID: entry.directoryID),
                corruptionError: .accountKeyCorrupted
            )
            try Self.atomicWrite(
                wrappedAccountKey,
                to: directory.appendingPathComponent(Self.accountKeyFileName),
                fileManager: fileManager
            )

            var updatedIndex = index
            updatedIndex.entries.append(entry)
            try persist(updatedIndex)
            index = updatedIndex
            return entry
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    private func accountEntry(for accountID: String) throws -> AccountEntry {
        guard let entry = index.entries.first(where: { $0.accountID == accountID }) else {
            throw EncryptedGoogleVaultError.accountNotFound
        }
        return entry
    }

    private func loadAccountKey(for entry: AccountEntry) throws -> SymmetricKey {
        let keyURL = accountDirectory(for: entry).appendingPathComponent(Self.accountKeyFileName)
        let wrappedKey: Data
        do {
            wrappedKey = try Data(contentsOf: keyURL)
        } catch {
            throw EncryptedGoogleVaultError.accountKeyCorrupted
        }
        let keyData = try Self.open(
            wrappedKey,
            using: masterKey,
            authenticatedBy: Self.accountKeyAuthenticatedData(directoryID: entry.directoryID),
            corruptionError: .accountKeyCorrupted
        )
        guard keyData.count == 32 else {
            throw EncryptedGoogleVaultError.accountKeyCorrupted
        }
        return SymmetricKey(data: keyData)
    }

    private func persist(_ updatedIndex: AccountIndex) throws {
        let encryptedIndex = try Self.sealIndex(updatedIndex, using: masterKey)
        try Self.atomicWrite(
            encryptedIndex,
            to: rootDirectory.appendingPathComponent(Self.indexFileName),
            fileManager: fileManager
        )
    }

    private func accountDirectory(for entry: AccountEntry) -> URL {
        accountsDirectory.appendingPathComponent(
            Self.directoryName(for: entry.directoryID),
            isDirectory: true
        )
    }

    private static func sealIndex(_ index: AccountIndex, using key: SymmetricKey) throws -> Data {
        let encodedIndex: Data
        do {
            encodedIndex = try JSONEncoder().encode(index)
        } catch {
            throw EncryptedGoogleVaultError.encodingFailed
        }
        return try seal(
            encodedIndex,
            using: key,
            authenticatedBy: indexAuthenticatedData,
            corruptionError: .indexCorrupted
        )
    }

    private static func openIndex(_ encryptedIndex: Data, using key: SymmetricKey) throws -> AccountIndex {
        let encodedIndex = try open(
            encryptedIndex,
            using: key,
            authenticatedBy: indexAuthenticatedData,
            corruptionError: .indexCorrupted
        )
        do {
            return try JSONDecoder().decode(AccountIndex.self, from: encodedIndex)
        } catch {
            throw EncryptedGoogleVaultError.indexCorrupted
        }
    }

    private static func seal(
        _ plaintext: Data,
        using key: SymmetricKey,
        authenticatedBy authenticatedData: Data,
        corruptionError: EncryptedGoogleVaultError
    ) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(plaintext, using: key, authenticating: authenticatedData)
            guard let combined = sealedBox.combined else { throw corruptionError }
            return combined
        } catch let error as EncryptedGoogleVaultError {
            throw error
        } catch {
            throw corruptionError
        }
    }

    private static func open(
        _ ciphertext: Data,
        using key: SymmetricKey,
        authenticatedBy authenticatedData: Data,
        corruptionError: EncryptedGoogleVaultError
    ) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(sealedBox, using: key, authenticating: authenticatedData)
        } catch {
            throw corruptionError
        }
    }

    private static func atomicWrite(_ data: Data, to destination: URL, fileManager: FileManager) throws {
        let parentDirectory = destination.deletingLastPathComponent()
        try secureDirectory(parentDirectory, fileManager: fileManager)
        let temporaryURL = parentDirectory.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString.lowercased()).tmp",
            isDirectory: false
        )
        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: nil,
            attributes: [.posixPermissions: NSNumber(value: 0o600)]
        ) else {
            throw EncryptedGoogleVaultError.storageFailed("creating a protected temporary file")
        }

        do {
            let handle = try FileHandle(forWritingTo: temporaryURL)
            do {
                try handle.write(contentsOf: data)
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            try secureFile(temporaryURL, fileManager: fileManager)

            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destination)
            }
            try secureFile(destination, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw (error as? EncryptedGoogleVaultError) ?? .storageFailed("writing protected data")
        }
    }

    private static func secureDirectory(_ url: URL, fileManager: FileManager) throws {
        do {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: url.path
            )
            try excludeFromBackup(url)
        } catch let error as EncryptedGoogleVaultError {
            throw error
        } catch {
            throw EncryptedGoogleVaultError.storageFailed("securing a protected directory")
        }
    }

    private static func secureFile(_ url: URL, fileManager: FileManager) throws {
        do {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: url.path
            )
            try excludeFromBackup(url)
        } catch let error as EncryptedGoogleVaultError {
            throw error
        } catch {
            throw EncryptedGoogleVaultError.storageFailed("securing a protected file")
        }
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        do {
            var mutableURL = url
            try mutableURL.setResourceValues(resourceValues)
        } catch {
            throw EncryptedGoogleVaultError.storageFailed("excluding protected data from backup")
        }
    }

    private static func isValid(_ index: AccountIndex) -> Bool {
        guard index.version == formatVersion else { return false }
        let accountIDs = index.entries.map(\.accountID)
        let directoryIDs = index.entries.map(\.directoryID)
        return accountIDs.allSatisfy { !$0.isEmpty } &&
            Set(accountIDs).count == accountIDs.count &&
            Set(directoryIDs).count == directoryIDs.count
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty &&
            trimmed == value &&
            value != "." &&
            value != ".." &&
            !value.contains("/") &&
            !value.contains(":")
    }

    private static func directoryName(for directoryID: UUID) -> String {
        directoryID.uuidString.lowercased()
    }

    private static func fileName(for kind: EncryptedGoogleVaultRecordKind) -> String {
        "\(kind.rawValue).v1.encrypted"
    }

    private static var indexAuthenticatedData: Data {
        Data("meeting-incoming.google-vault.index.v1".utf8)
    }

    private static func accountKeyAuthenticatedData(directoryID: UUID) -> Data {
        Data("meeting-incoming.google-vault.account-key.v1|\(directoryName(for: directoryID))".utf8)
    }

    private static func recordAuthenticatedData(
        kind: EncryptedGoogleVaultRecordKind,
        directoryID: UUID
    ) -> Data {
        Data(
            "meeting-incoming.google-vault.record.v1|\(directoryName(for: directoryID))|\(kind.rawValue)".utf8
        )
    }

    private static func data(for key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
}

private struct SecureEnclaveGoogleVaultKeyProtector: EncryptedGoogleVaultKeyProtecting {
    private struct KeyMaterial: Codable, Sendable {
        let version: Int
        let secureEnclaveDataRepresentation: Data
        let peerPublicKeyRepresentation: Data
        let salt: Data
    }

    func createKeyMaterial() throws -> Data {
        guard SecureEnclave.isAvailable else {
            throw EncryptedGoogleVaultError.secureEnclaveUnavailable
        }
        do {
            let secureEnclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey()
            let oneTimePeerKey = P256.KeyAgreement.PrivateKey()
            let material = KeyMaterial(
                version: 1,
                secureEnclaveDataRepresentation: secureEnclaveKey.dataRepresentation,
                peerPublicKeyRepresentation: oneTimePeerKey.publicKey.x963Representation,
                salt: randomData(byteCount: 32)
            )
            return try PropertyListEncoder().encode(material)
        } catch let error as EncryptedGoogleVaultError {
            throw error
        } catch {
            throw EncryptedGoogleVaultError.keyMaterialCorrupted
        }
    }

    func restoreMasterKey(from keyMaterial: Data) throws -> SymmetricKey {
        guard SecureEnclave.isAvailable else {
            throw EncryptedGoogleVaultError.secureEnclaveUnavailable
        }
        do {
            let material = try PropertyListDecoder().decode(KeyMaterial.self, from: keyMaterial)
            guard material.version == 1, material.salt.count == 32 else {
                throw EncryptedGoogleVaultError.keyMaterialCorrupted
            }
            let secureEnclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                dataRepresentation: material.secureEnclaveDataRepresentation
            )
            let peerPublicKey = try P256.KeyAgreement.PublicKey(
                x963Representation: material.peerPublicKeyRepresentation
            )
            let sharedSecret = try secureEnclaveKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
            return sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: material.salt,
                sharedInfo: Data("meeting-incoming.google-vault.master-key.v1".utf8),
                outputByteCount: 32
            )
        } catch let error as EncryptedGoogleVaultError {
            throw error
        } catch {
            throw EncryptedGoogleVaultError.keyMaterialCorrupted
        }
    }

    private func randomData(byteCount: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}
