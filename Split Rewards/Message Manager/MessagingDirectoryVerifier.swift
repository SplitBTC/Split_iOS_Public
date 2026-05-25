//
//  MessagingDirectoryVerifier.swift
//  Split Rewards
//
//  Created by TeeVee on 4/1/26.
//

import Foundation
import CryptoKit

struct MessagingDirectoryCheckpoint: Codable, Hashable {
    let rootHash: String
    let treeSize: Int
    let issuedAt: Date
}

struct MessagingDirectoryProofNode: Codable, Hashable {
    let position: String
    let hash: String
}

struct MessagingDirectoryProofPayload: Codable, Hashable {
    let leafIndex: Int
    let leafHash: String
    let proof: [MessagingDirectoryProofNode]
    let checkpoint: MessagingDirectoryCheckpoint
}

enum MessageDirectoryCheckpointStore {
    enum CheckpointError: LocalizedError {
        case staleCheckpoint
        case conflictingCheckpoint

        var errorDescription: String? {
            switch self {
            case .staleCheckpoint:
                return "The messaging directory checkpoint is stale."
            case .conflictingCheckpoint:
                return "The messaging directory checkpoint conflicts with a previously stored checkpoint."
            }
        }
    }

    private static let legacyDefaultsKey = "split.messaging.directoryCheckpoint"
    private static let defaultsKeyPrefix = "split.messaging.directoryCheckpoint."

    static func storeIfNewer(
        _ checkpoint: MessagingDirectoryCheckpoint,
        scope: String = AppConfig.baseURL
    ) throws {
        let defaults = UserDefaults.standard
        removeLegacyCheckpointIfPresent(from: defaults)
        let defaultsKey = scopedDefaultsKey(for: scope)

        if let existingData = defaults.data(forKey: defaultsKey),
           let existing = try? JSONDecoder().decode(MessagingDirectoryCheckpoint.self, from: existingData) {
            if checkpoint.treeSize < existing.treeSize {
                throw CheckpointError.staleCheckpoint
            }

            if checkpoint.treeSize == existing.treeSize,
               checkpoint.rootHash.lowercased() != existing.rootHash.lowercased() {
                throw CheckpointError.conflictingCheckpoint
            }

            if checkpoint.treeSize == existing.treeSize {
                return
            }
        }

        let data = try JSONEncoder().encode(checkpoint)
        defaults.set(data, forKey: defaultsKey)
    }

    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: legacyDefaultsKey)

        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(defaultsKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func scopedDefaultsKey(for scope: String) -> String {
        let normalizedScope = scope
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedScope.isEmpty else {
            return "\(defaultsKeyPrefix)default"
        }

        return defaultsKeyPrefix + normalizedScope
    }

    private static func removeLegacyCheckpointIfPresent(from defaults: UserDefaults) {
        // Legacy builds stored one checkpoint globally, which causes false conflicts
        // after switching between different backend origins. Once we scope by origin,
        // the old value can no longer be attributed safely, so we discard it.
        if defaults.object(forKey: legacyDefaultsKey) != nil {
            defaults.removeObject(forKey: legacyDefaultsKey)
        }
    }
}

enum MessagingDirectoryVerifier {
    enum VerificationError: LocalizedError {
        case invalidLeafHash
        case invalidProofHash
        case invalidProofPosition
        case invalidRootHash

        var errorDescription: String? {
            switch self {
            case .invalidLeafHash:
                return "The messaging directory leaf hash is invalid."
            case .invalidProofHash:
                return "The messaging directory proof is invalid."
            case .invalidProofPosition:
                return "The messaging directory proof position is invalid."
            case .invalidRootHash:
                return "The messaging directory root hash does not match the binding proof."
            }
        }
    }

    static func verifyDirectoryProof(
        binding: MessagingIdentityBindingPayload,
        directory: MessagingDirectoryProofPayload
    ) throws {
        let computedLeafHash = try sha256Hex(MessageKeyBindingVerifier.buildDirectoryLeafMessage(binding))
        guard computedLeafHash == normalizedHex(directory.leafHash) else {
            throw VerificationError.invalidLeafHash
        }

        var cursorHash = computedLeafHash
        for node in directory.proof {
            let siblingHash = normalizedHex(node.hash)
            switch node.position.lowercased() {
            case "left":
                cursorHash = try sha256HexPair(leftHex: siblingHash, rightHex: cursorHash)
            case "right":
                cursorHash = try sha256HexPair(leftHex: cursorHash, rightHex: siblingHash)
            default:
                throw VerificationError.invalidProofPosition
            }
        }

        guard cursorHash == normalizedHex(directory.checkpoint.rootHash) else {
            throw VerificationError.invalidRootHash
        }
    }

    private static func sha256Hex(_ value: String) throws -> String {
        guard let data = value.data(using: .utf8) else {
            throw VerificationError.invalidLeafHash
        }

        return Data(SHA256.hash(data: data)).hexString
    }

    private static func sha256HexPair(leftHex: String, rightHex: String) throws -> String {
        let left = try strictHexData(leftHex)
        let right = try strictHexData(rightHex)
        return Data(SHA256.hash(data: left + right)).hexString
    }

    private static func strictHexData(_ hex: String) throws -> Data {
        let normalized = normalizedHex(hex)
        guard normalized.count == 64 else {
            throw VerificationError.invalidProofHash
        }

        var data = Data(capacity: normalized.count / 2)
        var index = normalized.startIndex

        while index < normalized.endIndex {
            let next = normalized.index(index, offsetBy: 2)
            let byteString = normalized[index..<next]
            guard let byte = UInt8(byteString, radix: 16) else {
                throw VerificationError.invalidProofHash
            }
            data.append(byte)
            index = next
        }

        return data
    }

    private static func normalizedHex(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
