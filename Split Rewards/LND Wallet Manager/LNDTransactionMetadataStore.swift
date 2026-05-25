//
//  LNDTransactionMetadataStore.swift
//  Split Rewards
//
//  Created by TeeVee on 4/21/26.
//

import CryptoKit
import Foundation
import Security

struct LNDTransactionMetadata: Codable, Equatable {
    enum TransactionType: String, Codable {
        case sent
        case received
    }

    let nodeId: String
    let transactionId: String
    let transactionType: TransactionType
    let usdValueAtTransaction: Double?
    let btcUsdRateAtTransaction: Double?
    let isReportable: Bool
    let userLog: String?
    let destinationPubkey: String?
    let paymentHash: String?

    enum CodingKeys: String, CodingKey {
        case nodeId
        case transactionId
        case transactionType
        case usdValueAtTransaction
        case btcUsdRateAtTransaction
        case isReportable
        case userLog
        case destinationPubkey
        case paymentHash
    }

    init(
        nodeId: String,
        transactionId: String,
        transactionType: TransactionType,
        usdValueAtTransaction: Double? = nil,
        btcUsdRateAtTransaction: Double? = nil,
        isReportable: Bool = false,
        userLog: String? = nil,
        destinationPubkey: String? = nil,
        paymentHash: String? = nil
    ) {
        self.nodeId = nodeId
        self.transactionId = transactionId
        self.transactionType = transactionType
        self.usdValueAtTransaction = usdValueAtTransaction
        self.btcUsdRateAtTransaction = btcUsdRateAtTransaction
        self.isReportable = isReportable
        self.userLog = Self.normalizedUserLog(userLog)
        self.destinationPubkey = Self.normalizedUserLog(destinationPubkey)
        self.paymentHash = Self.normalizedUserLog(paymentHash)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeId = try container.decode(String.self, forKey: .nodeId)
        transactionId = try container.decode(String.self, forKey: .transactionId)
        transactionType = try container.decode(TransactionType.self, forKey: .transactionType)
        usdValueAtTransaction = try container.decodeIfPresent(Double.self, forKey: .usdValueAtTransaction)
        btcUsdRateAtTransaction = try container.decodeIfPresent(Double.self, forKey: .btcUsdRateAtTransaction)
        isReportable = try container.decodeIfPresent(Bool.self, forKey: .isReportable) ?? false
        userLog = Self.normalizedUserLog(try container.decodeIfPresent(String.self, forKey: .userLog))
        destinationPubkey = Self.normalizedUserLog(try container.decodeIfPresent(String.self, forKey: .destinationPubkey))
        paymentHash = Self.normalizedUserLog(try container.decodeIfPresent(String.self, forKey: .paymentHash))
    }

    var hasUsdSnapshot: Bool {
        usdValueAtTransaction != nil && btcUsdRateAtTransaction != nil
    }

    func merging(metadata: LNDTransactionMetadata) -> LNDTransactionMetadata {
        LNDTransactionMetadata(
            nodeId: metadata.nodeId,
            transactionId: metadata.transactionId,
            transactionType: metadata.transactionType,
            usdValueAtTransaction: metadata.usdValueAtTransaction ?? usdValueAtTransaction,
            btcUsdRateAtTransaction: metadata.btcUsdRateAtTransaction ?? btcUsdRateAtTransaction,
            isReportable: isReportable || metadata.isReportable,
            userLog: metadata.userLog ?? userLog,
            destinationPubkey: metadata.destinationPubkey ?? destinationPubkey,
            paymentHash: metadata.paymentHash ?? paymentHash
        )
    }

    func withReportable(_ isReportable: Bool) -> LNDTransactionMetadata {
        LNDTransactionMetadata(
            nodeId: nodeId,
            transactionId: transactionId,
            transactionType: transactionType,
            usdValueAtTransaction: usdValueAtTransaction,
            btcUsdRateAtTransaction: btcUsdRateAtTransaction,
            isReportable: isReportable,
            userLog: userLog,
            destinationPubkey: destinationPubkey,
            paymentHash: paymentHash
        )
    }

    func withUserLog(_ userLog: String?) -> LNDTransactionMetadata {
        LNDTransactionMetadata(
            nodeId: nodeId,
            transactionId: transactionId,
            transactionType: transactionType,
            usdValueAtTransaction: usdValueAtTransaction,
            btcUsdRateAtTransaction: btcUsdRateAtTransaction,
            isReportable: isReportable,
            userLog: userLog,
            destinationPubkey: destinationPubkey,
            paymentHash: paymentHash
        )
    }

    func withDestinationMetadata(destinationPubkey: String?, paymentHash: String?) -> LNDTransactionMetadata {
        LNDTransactionMetadata(
            nodeId: nodeId,
            transactionId: transactionId,
            transactionType: transactionType,
            usdValueAtTransaction: usdValueAtTransaction,
            btcUsdRateAtTransaction: btcUsdRateAtTransaction,
            isReportable: isReportable,
            userLog: userLog,
            destinationPubkey: Self.normalizedUserLog(destinationPubkey) ?? self.destinationPubkey,
            paymentHash: Self.normalizedUserLog(paymentHash) ?? self.paymentHash
        )
    }

    static func normalizedUserLog(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct SecureLNDTransactionMetadataStorage {
    static let shared = SecureLNDTransactionMetadataStorage()

    private let storageKeyKeychainKey = "split.lnd.transactions.storageKey.v1"
    private let payloadHeader = Data("SLNDM1".utf8)

    enum SecureStorageError: LocalizedError {
        case invalidStoredKey
        case missingStoredKey
        case invalidEncryptedPayload
        case failedToEncrypt
        case failedToDecrypt

        var errorDescription: String? {
            switch self {
            case .invalidStoredKey:
                return "Stored LND transaction metadata key is invalid."
            case .missingStoredKey:
                return "Stored LND transaction metadata key is missing."
            case .invalidEncryptedPayload:
                return "Encrypted LND transaction metadata payload is invalid."
            case .failedToEncrypt:
                return "Could not encrypt local LND transaction metadata."
            case .failedToDecrypt:
                return "Could not decrypt local LND transaction metadata."
            }
        }
    }

    func isEncryptedPayload(_ data: Data) -> Bool {
        data.starts(with: payloadHeader)
    }

    func encrypt(_ plaintext: Data) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(plaintext, using: try storageKey(createIfMissing: true))

            guard let combined = sealedBox.combined else {
                throw SecureStorageError.failedToEncrypt
            }

            return payloadHeader + combined
        } catch let error as SecureStorageError {
            throw error
        } catch {
            throw SecureStorageError.failedToEncrypt
        }
    }

    func decrypt(_ encryptedPayload: Data) throws -> Data {
        guard isEncryptedPayload(encryptedPayload) else {
            throw SecureStorageError.invalidEncryptedPayload
        }

        do {
            let combined = encryptedPayload.dropFirst(payloadHeader.count)
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(sealedBox, using: try storageKey(createIfMissing: false))
        } catch let error as SecureStorageError {
            throw error
        } catch {
            throw SecureStorageError.failedToDecrypt
        }
    }

    func clearStoredKey() {
        LNDTransactionMetadataKeychain.delete(forKey: storageKeyKeychainKey)
    }

    private func storageKey(createIfMissing: Bool) throws -> SymmetricKey {
        if let stored = LNDTransactionMetadataKeychain.read(forKey: storageKeyKeychainKey) {
            guard let keyData = Data(base64Encoded: stored), !keyData.isEmpty else {
                throw SecureStorageError.invalidStoredKey
            }

            return SymmetricKey(data: keyData)
        }

        guard createIfMissing else {
            throw SecureStorageError.missingStoredKey
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        LNDTransactionMetadataKeychain.save(keyData.base64EncodedString(), forKey: storageKeyKeychainKey)
        return newKey
    }
}

actor LNDTransactionMetadataStore {
    static let shared = LNDTransactionMetadataStore()

    private var metadataByCompositeKey: [String: LNDTransactionMetadata]?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func metadata(nodeId: String, transactionId: String) -> LNDTransactionMetadata? {
        let key = compositeKey(nodeId: nodeId, transactionId: transactionId)
        return loadMetadata()[key]
    }

    func containsUsdSnapshot(nodeId: String, transactionId: String) -> Bool {
        metadata(nodeId: nodeId, transactionId: transactionId)?.hasUsdSnapshot == true
    }

    func metadata(nodeId: String, transactionIds: [String]) -> [String: LNDTransactionMetadata] {
        let allMetadata = loadMetadata()
        return transactionIds.reduce(into: [String: LNDTransactionMetadata]()) { partialResult, transactionId in
            if let metadata = allMetadata[compositeKey(nodeId: nodeId, transactionId: transactionId)] {
                partialResult[transactionId] = metadata
            }
        }
    }

    func reportableStates(nodeId: String, transactionIds: [String]) -> [String: Bool] {
        let allMetadata = loadMetadata()
        return transactionIds.reduce(into: [String: Bool]()) { partialResult, transactionId in
            if let metadata = allMetadata[compositeKey(nodeId: nodeId, transactionId: transactionId)] {
                partialResult[transactionId] = metadata.isReportable
            }
        }
    }

    func userLogs(nodeId: String, transactionIds: [String]) -> [String: String] {
        let allMetadata = loadMetadata()
        return transactionIds.reduce(into: [String: String]()) { partialResult, transactionId in
            guard let metadata = allMetadata[compositeKey(nodeId: nodeId, transactionId: transactionId)],
                  let userLog = metadata.userLog else {
                return
            }

            partialResult[transactionId] = userLog
        }
    }

    func upsert(_ metadata: LNDTransactionMetadata) {
        var allMetadata = loadMetadata()
        let key = compositeKey(nodeId: metadata.nodeId, transactionId: metadata.transactionId)
        if let existing = allMetadata[key] {
            allMetadata[key] = existing.merging(metadata: metadata)
        } else {
            allMetadata[key] = metadata
        }
        metadataByCompositeKey = allMetadata
        persistMetadata(allMetadata)
    }

    func setReportable(
        nodeId: String,
        transactionId: String,
        transactionType: LNDTransactionMetadata.TransactionType,
        isReportable: Bool
    ) {
        var allMetadata = loadMetadata()
        let key = compositeKey(nodeId: nodeId, transactionId: transactionId)

        if let existing = allMetadata[key] {
            allMetadata[key] = existing.withReportable(isReportable)
        } else {
            allMetadata[key] = LNDTransactionMetadata(
                nodeId: nodeId,
                transactionId: transactionId,
                transactionType: transactionType,
                isReportable: isReportable
            )
        }

        metadataByCompositeKey = allMetadata
        persistMetadata(allMetadata)
    }

    func setUserLog(
        nodeId: String,
        transactionId: String,
        transactionType: LNDTransactionMetadata.TransactionType,
        userLog: String?
    ) {
        var allMetadata = loadMetadata()
        let key = compositeKey(nodeId: nodeId, transactionId: transactionId)
        let normalizedUserLog = LNDTransactionMetadata.normalizedUserLog(userLog)

        if let existing = allMetadata[key] {
            allMetadata[key] = existing.withUserLog(normalizedUserLog)
        } else if normalizedUserLog != nil {
            allMetadata[key] = LNDTransactionMetadata(
                nodeId: nodeId,
                transactionId: transactionId,
                transactionType: transactionType,
                userLog: normalizedUserLog
            )
        } else {
            return
        }

        metadataByCompositeKey = allMetadata
        persistMetadata(allMetadata)
    }

    func setDestinationMetadata(
        nodeId: String,
        transactionId: String,
        transactionType: LNDTransactionMetadata.TransactionType,
        destinationPubkey: String?,
        paymentHash: String?
    ) {
        let normalizedDestinationPubkey = LNDTransactionMetadata.normalizedUserLog(destinationPubkey)
        let normalizedPaymentHash = LNDTransactionMetadata.normalizedUserLog(paymentHash)
        guard normalizedDestinationPubkey != nil || normalizedPaymentHash != nil else { return }

        var allMetadata = loadMetadata()
        let key = compositeKey(nodeId: nodeId, transactionId: transactionId)

        if let existing = allMetadata[key] {
            allMetadata[key] = existing.withDestinationMetadata(
                destinationPubkey: normalizedDestinationPubkey,
                paymentHash: normalizedPaymentHash
            )
        } else {
            allMetadata[key] = LNDTransactionMetadata(
                nodeId: nodeId,
                transactionId: transactionId,
                transactionType: transactionType,
                destinationPubkey: normalizedDestinationPubkey,
                paymentHash: normalizedPaymentHash
            )
        }

        metadataByCompositeKey = allMetadata
        persistMetadata(allMetadata)
    }

    func ensureUsdSnapshots(
        for rows: [WalletManager.TransactionRow],
        nodeId: String,
        currentBtcUsdRate: Double?
    ) async {
        let completedRows = rows
            .filter { $0.status == "Completed" && ($0.direction == "sent" || $0.direction == "received") }
            .filter { $0.amountSats > 0 }
            .sorted { $0.transactionDate < $1.transactionDate }

        for row in completedRows {
            if Task.isCancelled { return }
            await persistUsdSnapshotIfNeeded(
                for: row,
                nodeId: nodeId,
                currentBtcUsdRate: currentBtcUsdRate
            )
        }
    }

    func clear(nodeId: String) {
        var allMetadata = loadMetadata()
        allMetadata = allMetadata.filter { _, metadata in
            metadata.nodeId != nodeId
        }
        metadataByCompositeKey = allMetadata
        persistMetadata(allMetadata)
    }

    func clearAll() {
        metadataByCompositeKey = [:]
        do {
            let fileURL = try storageFileURL()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            SecureLNDTransactionMetadataStorage.shared.clearStoredKey()
        } catch {
            print("⚠️ LNDTransactionMetadataStore clear failed: \(error)")
        }
    }

    private func persistUsdSnapshotIfNeeded(
        for row: WalletManager.TransactionRow,
        nodeId: String,
        currentBtcUsdRate: Double?
    ) async {
        guard !containsUsdSnapshot(nodeId: nodeId, transactionId: row.id) else { return }

        let rate: Double
        do {
            rate = try await usdRateForSnapshot(
                at: row.transactionDate,
                currentBtcUsdRate: currentBtcUsdRate
            )
        } catch {
            print("⚠️ LNDTransactionMetadataStore failed to fetch BTC/USD snapshot for \(row.id): \(error.localizedDescription)")
            return
        }

        guard rate > 0 else { return }

        let usdValue = (Double(row.amountSats) / 100_000_000.0) * rate
        let transactionType: LNDTransactionMetadata.TransactionType = row.direction == "sent" ? .sent : .received

        upsert(
            LNDTransactionMetadata(
                nodeId: nodeId,
                transactionId: row.id,
                transactionType: transactionType,
                usdValueAtTransaction: usdValue,
                btcUsdRateAtTransaction: rate
            )
        )
    }

    private func usdRateForSnapshot(
        at transactionDate: Date,
        currentBtcUsdRate: Double?
    ) async throws -> Double {
        let now = Date()
        if abs(now.timeIntervalSince(transactionDate)) <= 300,
           let currentBtcUsdRate,
           currentBtcUsdRate > 0 {
            return currentBtcUsdRate
        }

        return try await fetchBitcoinPriceUSD(at: transactionDate)
    }

    private func compositeKey(nodeId: String, transactionId: String) -> String {
        "\(nodeId)|\(transactionId)"
    }

    private func loadMetadata() -> [String: LNDTransactionMetadata] {
        if let metadataByCompositeKey {
            return metadataByCompositeKey
        }

        do {
            let fileURL = try storageFileURL()
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                metadataByCompositeKey = [:]
                return [:]
            }

            let data = try Data(contentsOf: fileURL)
            let isEncrypted = SecureLNDTransactionMetadataStorage.shared.isEncryptedPayload(data)
            let plaintextData = isEncrypted
                ? try SecureLNDTransactionMetadataStorage.shared.decrypt(data)
                : data
            let metadata = try decoder.decode([String: LNDTransactionMetadata].self, from: plaintextData)
            metadataByCompositeKey = metadata

            if isEncrypted {
                try protectMetadataFile(at: fileURL)
            } else {
                persistMetadata(metadata)
            }

            return metadata
        } catch {
            print("⚠️ LNDTransactionMetadataStore load failed: \(error)")
            metadataByCompositeKey = [:]
            return [:]
        }
    }

    private func persistMetadata(_ metadata: [String: LNDTransactionMetadata]) {
        do {
            let fileURL = try storageFileURL()
            let data = try encoder.encode(metadata)
            let encryptedData = try SecureLNDTransactionMetadataStorage.shared.encrypt(data)
            try encryptedData.write(to: fileURL, options: [.atomic])
            try protectMetadataFile(at: fileURL)
        } catch {
            print("⚠️ LNDTransactionMetadataStore persist failed: \(error)")
        }
    }

    private func storageFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directory = appSupport.appendingPathComponent("lnd-transaction-metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("metadata.json", isDirectory: false)
    }

    private func protectMetadataFile(at fileURL: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
    }
}

private enum LNDTransactionMetadataKeychain {
    private static let service = "com.split.rewards.lnd"

    static func save(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }

        delete(forKey: key)

        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(forKey key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func delete(forKey key: String) {
        SecItemDelete(baseQuery(forKey: key) as CFDictionary)
    }

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
