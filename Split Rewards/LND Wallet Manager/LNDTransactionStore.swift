//
//  LNDTransactionStore.swift
//  Split Rewards
//
//  Created by TeeVee on 4/21/26.
//

import CryptoKit
import Foundation
import Security

actor LNDTransactionStore {
    static let shared = LNDTransactionStore()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var rowsByNodeId: [String: [LNDStoredTransactionRow]]?

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func rows(forNodeId nodeId: String) -> [WalletManager.TransactionRow] {
        loadRows()[nodeId, default: []]
            .map(\.transactionRow)
            .sorted { $0.transactionDate > $1.transactionDate }
    }

    func merge(_ rows: [WalletManager.TransactionRow], forNodeId nodeId: String) {
        var allRows = loadRows()
        var existingRows = Dictionary(
            uniqueKeysWithValues: allRows[nodeId, default: []].map { ($0.id, $0) }
        )

        for row in rows {
            existingRows[row.id] = LNDStoredTransactionRow(row)
        }

        allRows[nodeId] = existingRows.values.sorted { $0.transactionDate > $1.transactionDate }
        rowsByNodeId = allRows
        persistRows(allRows)
    }

    func clear(nodeId: String) {
        var allRows = loadRows()
        allRows.removeValue(forKey: nodeId)
        rowsByNodeId = allRows
        persistRows(allRows)
    }

    private func loadRows() -> [String: [LNDStoredTransactionRow]] {
        if let rowsByNodeId {
            return rowsByNodeId
        }

        do {
            let fileURL = try storageFileURL()
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                rowsByNodeId = [:]
                return [:]
            }

            let data = try Data(contentsOf: fileURL)
            let isEncrypted = SecureLNDTransactionRowStorage.shared.isEncryptedPayload(data)
            let plaintextData = isEncrypted
                ? try SecureLNDTransactionRowStorage.shared.decrypt(data)
                : data
            let rows = try decoder.decode([String: [LNDStoredTransactionRow]].self, from: plaintextData)
            rowsByNodeId = rows

            if isEncrypted {
                try protectRowsFile(at: fileURL)
            } else {
                persistRows(rows)
            }

            return rows
        } catch {
            print("⚠️ LNDTransactionStore load failed: \(error)")
            rowsByNodeId = [:]
            return [:]
        }
    }

    private func persistRows(_ rows: [String: [LNDStoredTransactionRow]]) {
        do {
            let fileURL = try storageFileURL()
            let data = try encoder.encode(rows)
            let encryptedData = try SecureLNDTransactionRowStorage.shared.encrypt(data)
            try encryptedData.write(to: fileURL, options: [.atomic])
            try protectRowsFile(at: fileURL)
        } catch {
            print("⚠️ LNDTransactionStore persist failed: \(error)")
        }
    }

    private func storageFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directory = appSupport.appendingPathComponent("lnd-transactions", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("rows.json", isDirectory: false)
    }

    private func protectRowsFile(at fileURL: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
    }
}

private struct SecureLNDTransactionRowStorage {
    static let shared = SecureLNDTransactionRowStorage()

    private let storageKeyKeychainKey = "split.lnd.transactions.rows.storageKey.v1"
    private let payloadHeader = Data("SLNDR1".utf8)

    enum SecureStorageError: LocalizedError {
        case invalidStoredKey
        case missingStoredKey
        case invalidEncryptedPayload
        case failedToEncrypt
        case failedToDecrypt

        var errorDescription: String? {
            switch self {
            case .invalidStoredKey:
                return "Stored LND transaction row key is invalid."
            case .missingStoredKey:
                return "Stored LND transaction row key is missing."
            case .invalidEncryptedPayload:
                return "Encrypted LND transaction row payload is invalid."
            case .failedToEncrypt:
                return "Could not encrypt local LND transaction rows."
            case .failedToDecrypt:
                return "Could not decrypt local LND transaction rows."
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

    private func storageKey(createIfMissing: Bool) throws -> SymmetricKey {
        if let stored = LNDTransactionRowKeychain.read(forKey: storageKeyKeychainKey) {
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
        LNDTransactionRowKeychain.save(keyData.base64EncodedString(), forKey: storageKeyKeychainKey)
        return newKey
    }
}

private enum LNDTransactionRowKeychain {
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

private struct LNDStoredTransactionRow: Codable {
    let id: String
    let transactionDate: Date
    let direction: String
    let btcAmount: String
    let feeBtcAmount: String
    let network: String
    let status: String
    let dateString: String
    let note: String
    let amountSats: Int64
    let feeSats: Int64
    let method: String
    let destinationPubkey: String?
    let invoice: String?
    let lnAddress: String?
    let lnurlDomain: String?
    let lnurlComment: String?
    let senderComment: String?
    let paymentHash: String?
    let preimage: String?
    let expiryDateString: String?
    let txReferenceLabel: String?
    let txReference: String?
    let hasConversion: Bool

    init(_ row: WalletManager.TransactionRow) {
        id = row.id
        transactionDate = row.transactionDate
        direction = row.direction
        btcAmount = row.btcAmount
        feeBtcAmount = row.feeBtcAmount
        network = row.network
        status = row.status
        dateString = row.dateString
        note = row.note
        amountSats = row.amountSats
        feeSats = row.feeSats
        method = row.method
        destinationPubkey = row.destinationPubkey
        invoice = row.invoice
        lnAddress = row.lnAddress
        lnurlDomain = row.lnurlDomain
        lnurlComment = row.lnurlComment
        senderComment = row.senderComment
        paymentHash = row.paymentHash
        preimage = row.preimage
        expiryDateString = row.expiryDateString
        txReferenceLabel = row.txReferenceLabel
        txReference = row.txReference
        hasConversion = row.hasConversion
    }

    var transactionRow: WalletManager.TransactionRow {
        WalletManager.TransactionRow(
            id: id,
            transactionDate: transactionDate,
            direction: direction,
            btcAmount: btcAmount,
            feeBtcAmount: feeBtcAmount,
            network: network,
            status: status,
            dateString: dateString,
            note: note,
            userLog: nil,
            amountSats: amountSats,
            feeSats: feeSats,
            method: method,
            destinationPubkey: destinationPubkey,
            invoice: invoice,
            lnAddress: lnAddress,
            lnurlDomain: lnurlDomain,
            lnurlComment: lnurlComment,
            senderComment: senderComment,
            paymentHash: paymentHash,
            preimage: preimage,
            expiryDateString: expiryDateString,
            txReferenceLabel: txReferenceLabel,
            txReference: txReference,
            hasConversion: hasConversion
        )
    }
}
