//
//  PaymentUsdSnapshotStore.swift
//  Split Rewards
//
//  Created by TeeVee on 3/31/26.
//

import CryptoKit
import Foundation

struct PaymentUsdSnapshot: Codable, Equatable {
    enum PaymentType: String, Codable {
        case sent
        case received
    }

    let walletPubkey: String
    let paymentId: String
    let paymentType: PaymentType
    let usdValueAtTransaction: Double?
    let btcUsdRateAtTransaction: Double?
    let isReportable: Bool
    let userLog: String?
    let destinationPubkey: String?
    let paymentHash: String?

    enum CodingKeys: String, CodingKey {
        case walletPubkey
        case paymentId
        case paymentType
        case usdValueAtTransaction
        case btcUsdRateAtTransaction
        case isReportable
        case userLog
        case destinationPubkey
        case paymentHash
    }

    init(
        walletPubkey: String,
        paymentId: String,
        paymentType: PaymentType,
        usdValueAtTransaction: Double? = nil,
        btcUsdRateAtTransaction: Double? = nil,
        isReportable: Bool = false,
        userLog: String? = nil,
        destinationPubkey: String? = nil,
        paymentHash: String? = nil
    ) {
        self.walletPubkey = walletPubkey
        self.paymentId = paymentId
        self.paymentType = paymentType
        self.usdValueAtTransaction = usdValueAtTransaction
        self.btcUsdRateAtTransaction = btcUsdRateAtTransaction
        self.isReportable = isReportable
        self.userLog = Self.normalizedUserLog(userLog)
        self.destinationPubkey = Self.normalizedUserLog(destinationPubkey)
        self.paymentHash = Self.normalizedUserLog(paymentHash)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        walletPubkey = try container.decode(String.self, forKey: .walletPubkey)
        paymentId = try container.decode(String.self, forKey: .paymentId)
        paymentType = try container.decode(PaymentType.self, forKey: .paymentType)
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

    func merging(snapshot: PaymentUsdSnapshot) -> PaymentUsdSnapshot {
        PaymentUsdSnapshot(
            walletPubkey: snapshot.walletPubkey,
            paymentId: snapshot.paymentId,
            paymentType: snapshot.paymentType,
            usdValueAtTransaction: snapshot.usdValueAtTransaction ?? usdValueAtTransaction,
            btcUsdRateAtTransaction: snapshot.btcUsdRateAtTransaction ?? btcUsdRateAtTransaction,
            isReportable: isReportable || snapshot.isReportable,
            userLog: snapshot.userLog ?? userLog,
            destinationPubkey: snapshot.destinationPubkey ?? destinationPubkey,
            paymentHash: snapshot.paymentHash ?? paymentHash
        )
    }

    func withReportable(_ isReportable: Bool) -> PaymentUsdSnapshot {
        PaymentUsdSnapshot(
            walletPubkey: walletPubkey,
            paymentId: paymentId,
            paymentType: paymentType,
            usdValueAtTransaction: usdValueAtTransaction,
            btcUsdRateAtTransaction: btcUsdRateAtTransaction,
            isReportable: isReportable,
            userLog: userLog,
            destinationPubkey: destinationPubkey,
            paymentHash: paymentHash
        )
    }

    func withUserLog(_ userLog: String?) -> PaymentUsdSnapshot {
        PaymentUsdSnapshot(
            walletPubkey: walletPubkey,
            paymentId: paymentId,
            paymentType: paymentType,
            usdValueAtTransaction: usdValueAtTransaction,
            btcUsdRateAtTransaction: btcUsdRateAtTransaction,
            isReportable: isReportable,
            userLog: userLog,
            destinationPubkey: destinationPubkey,
            paymentHash: paymentHash
        )
    }

    func withDestinationMetadata(destinationPubkey: String?, paymentHash: String?) -> PaymentUsdSnapshot {
        PaymentUsdSnapshot(
            walletPubkey: walletPubkey,
            paymentId: paymentId,
            paymentType: paymentType,
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

private struct SecurePaymentSnapshotStorage {
    static let shared = SecurePaymentSnapshotStorage()

    private let storageKeyKeychainKey = "split.transactions.storageKey"
    private let payloadHeader = Data("SPTXN1".utf8)

    enum SecureStorageError: LocalizedError {
        case invalidStoredKey
        case missingStoredKey
        case invalidEncryptedPayload
        case failedToEncrypt
        case failedToDecrypt

        var errorDescription: String? {
            switch self {
            case .invalidStoredKey:
                return "Stored transaction snapshot key is invalid."
            case .missingStoredKey:
                return "Stored transaction snapshot key is missing."
            case .invalidEncryptedPayload:
                return "Encrypted transaction snapshot payload is invalid."
            case .failedToEncrypt:
                return "Could not encrypt local transaction snapshot data."
            case .failedToDecrypt:
                return "Could not decrypt local transaction snapshot data."
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
        KeychainHelper.delete(forKey: storageKeyKeychainKey)
    }

    private func storageKey(createIfMissing: Bool) throws -> SymmetricKey {
        if let stored = KeychainHelper.read(forKey: storageKeyKeychainKey) {
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
        KeychainHelper.save(keyData.base64EncodedString(), forKey: storageKeyKeychainKey)
        return newKey
    }
}

actor PaymentUsdSnapshotStore {
    static let shared = PaymentUsdSnapshotStore()

    private var snapshotsByCompositeKey: [String: PaymentUsdSnapshot]?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func snapshot(walletPubkey: String, paymentId: String) -> PaymentUsdSnapshot? {
        let key = compositeKey(walletPubkey: walletPubkey, paymentId: paymentId)
        return loadSnapshots()[key]
    }

    func containsSnapshot(walletPubkey: String, paymentId: String) -> Bool {
        snapshot(walletPubkey: walletPubkey, paymentId: paymentId)?.hasUsdSnapshot == true
    }

    func snapshots(walletPubkey: String, paymentIds: [String]) -> [String: PaymentUsdSnapshot] {
        let allSnapshots = loadSnapshots()
        return paymentIds.reduce(into: [String: PaymentUsdSnapshot]()) { partialResult, paymentId in
            if let snapshot = allSnapshots[compositeKey(walletPubkey: walletPubkey, paymentId: paymentId)] {
                partialResult[paymentId] = snapshot
            }
        }
    }

    func reportableStates(walletPubkey: String, paymentIds: [String]) -> [String: Bool] {
        let allSnapshots = loadSnapshots()
        return paymentIds.reduce(into: [String: Bool]()) { partialResult, paymentId in
            if let snapshot = allSnapshots[compositeKey(walletPubkey: walletPubkey, paymentId: paymentId)] {
                partialResult[paymentId] = snapshot.isReportable
            }
        }
    }

    func userLogs(walletPubkey: String, paymentIds: [String]) -> [String: String] {
        let allSnapshots = loadSnapshots()
        return paymentIds.reduce(into: [String: String]()) { partialResult, paymentId in
            guard let snapshot = allSnapshots[compositeKey(walletPubkey: walletPubkey, paymentId: paymentId)],
                  let userLog = snapshot.userLog else {
                return
            }

            partialResult[paymentId] = userLog
        }
    }

    func upsert(_ snapshot: PaymentUsdSnapshot) {
        var snapshots = loadSnapshots()
        let key = compositeKey(walletPubkey: snapshot.walletPubkey, paymentId: snapshot.paymentId)
        if let existing = snapshots[key] {
            snapshots[key] = existing.merging(snapshot: snapshot)
        } else {
            snapshots[key] = snapshot
        }
        snapshotsByCompositeKey = snapshots
        persistSnapshots(snapshots)
    }

    func setReportable(
        walletPubkey: String,
        paymentId: String,
        paymentType: PaymentUsdSnapshot.PaymentType,
        isReportable: Bool
    ) {
        var snapshots = loadSnapshots()
        let key = compositeKey(walletPubkey: walletPubkey, paymentId: paymentId)

        if let existing = snapshots[key] {
            snapshots[key] = existing.withReportable(isReportable)
        } else {
            snapshots[key] = PaymentUsdSnapshot(
                walletPubkey: walletPubkey,
                paymentId: paymentId,
                paymentType: paymentType,
                isReportable: isReportable
            )
        }

        snapshotsByCompositeKey = snapshots
        persistSnapshots(snapshots)
    }

    func setUserLog(
        walletPubkey: String,
        paymentId: String,
        paymentType: PaymentUsdSnapshot.PaymentType,
        userLog: String?
    ) {
        var snapshots = loadSnapshots()
        let key = compositeKey(walletPubkey: walletPubkey, paymentId: paymentId)
        let normalizedUserLog = PaymentUsdSnapshot.normalizedUserLog(userLog)

        if let existing = snapshots[key] {
            snapshots[key] = existing.withUserLog(normalizedUserLog)
        } else if normalizedUserLog != nil {
            snapshots[key] = PaymentUsdSnapshot(
                walletPubkey: walletPubkey,
                paymentId: paymentId,
                paymentType: paymentType,
                userLog: normalizedUserLog
            )
        } else {
            return
        }

        snapshotsByCompositeKey = snapshots
        persistSnapshots(snapshots)
    }

    func setDestinationMetadata(
        walletPubkey: String,
        paymentId: String,
        paymentType: PaymentUsdSnapshot.PaymentType,
        destinationPubkey: String?,
        paymentHash: String?
    ) {
        let normalizedDestinationPubkey = PaymentUsdSnapshot.normalizedUserLog(destinationPubkey)
        let normalizedPaymentHash = PaymentUsdSnapshot.normalizedUserLog(paymentHash)
        guard normalizedDestinationPubkey != nil || normalizedPaymentHash != nil else { return }

        var snapshots = loadSnapshots()
        let key = compositeKey(walletPubkey: walletPubkey, paymentId: paymentId)

        if let existing = snapshots[key] {
            snapshots[key] = existing.withDestinationMetadata(
                destinationPubkey: normalizedDestinationPubkey,
                paymentHash: normalizedPaymentHash
            )
        } else {
            snapshots[key] = PaymentUsdSnapshot(
                walletPubkey: walletPubkey,
                paymentId: paymentId,
                paymentType: paymentType,
                destinationPubkey: normalizedDestinationPubkey,
                paymentHash: normalizedPaymentHash
            )
        }

        snapshotsByCompositeKey = snapshots
        persistSnapshots(snapshots)
    }

    func clearAll() {
        snapshotsByCompositeKey = [:]
        do {
            let fileURL = try storageFileURL()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            SecurePaymentSnapshotStorage.shared.clearStoredKey()
        } catch {
            print("⚠️ PaymentUsdSnapshotStore clear failed: \(error)")
        }
    }

    func clear(walletPubkey: String) {
        let prefix = "\(walletPubkey)|"
        var snapshots = loadSnapshots()
        snapshots = snapshots.filter { !$0.key.hasPrefix(prefix) }
        snapshotsByCompositeKey = snapshots
        persistSnapshots(snapshots)
    }

    private func compositeKey(walletPubkey: String, paymentId: String) -> String {
        "\(walletPubkey)|\(paymentId)"
    }

    private func loadSnapshots() -> [String: PaymentUsdSnapshot] {
        if let snapshotsByCompositeKey {
            return snapshotsByCompositeKey
        }

        do {
            let fileURL = try storageFileURL()
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                snapshotsByCompositeKey = [:]
                return [:]
            }

            let data = try Data(contentsOf: fileURL)
            let isEncrypted = SecurePaymentSnapshotStorage.shared.isEncryptedPayload(data)
            let plaintextData = isEncrypted
                ? try SecurePaymentSnapshotStorage.shared.decrypt(data)
                : data
            let snapshots = try decoder.decode([String: PaymentUsdSnapshot].self, from: plaintextData)
            snapshotsByCompositeKey = snapshots

            if isEncrypted {
                try protectSnapshotFile(at: fileURL)
            } else {
                persistSnapshots(snapshots)
            }

            return snapshots
        } catch {
            print("⚠️ PaymentUsdSnapshotStore load failed: \(error)")
            snapshotsByCompositeKey = [:]
            return [:]
        }
    }

    private func persistSnapshots(_ snapshots: [String: PaymentUsdSnapshot]) {
        do {
            let fileURL = try storageFileURL()
            let data = try encoder.encode(snapshots)
            let encryptedData = try SecurePaymentSnapshotStorage.shared.encrypt(data)
            try encryptedData.write(to: fileURL, options: [.atomic])
            try protectSnapshotFile(at: fileURL)
        } catch {
            print("⚠️ PaymentUsdSnapshotStore persist failed: \(error)")
        }
    }

    private func storageFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directory = appSupport.appendingPathComponent("payment-usd-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("snapshots.json", isDirectory: false)
    }

    private func protectSnapshotFile(at fileURL: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
    }
}
