//
//  SecureMessagingStorage.swift
//  Split Rewards
//
//  Created by TeeVee on 3/24/26.
//

import Foundation
import CryptoKit

struct SecureMessagingStorage {
    static let shared = SecureMessagingStorage()

    private let storageKeyKeychainKey = "split.messaging.storageKey"
    private let payloadHeader = Data("SPMSG1".utf8)

    enum SecureStorageError: LocalizedError {
        case invalidStoredKey
        case missingStoredKey
        case invalidEncryptedPayload
        case failedToEncrypt
        case failedToDecrypt

        var errorDescription: String? {
            switch self {
            case .invalidStoredKey:
                return "Stored secure messaging key is invalid."
            case .missingStoredKey:
                return "Stored secure messaging key is missing."
            case .invalidEncryptedPayload:
                return "Encrypted messaging payload is invalid."
            case .failedToEncrypt:
                return "Could not encrypt local messaging data."
            case .failedToDecrypt:
                return "Could not decrypt local messaging data."
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
