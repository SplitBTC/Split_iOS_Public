//
//  SparkSubwalletModels.swift
//  Split Rewards
//
//  Created by TeeVee on 5/12/26.
//

import Foundation

enum SparkSubwalletError: LocalizedError, Equatable {
    case invalidSeedPhrase
    case missingSeed
    case noStoredWallet
    case walletNotConnected
    case missingPaymentMetadata

    var errorDescription: String? {
        switch self {
        case .invalidSeedPhrase:
            return "Invalid seed phrase."
        case .missingSeed:
            return "Spark sub-wallet seed is missing from this device."
        case .noStoredWallet:
            return "No Spark sub-wallet is stored on this device."
        case .walletNotConnected:
            return "Spark sub-wallet is not connected."
        case .missingPaymentMetadata:
            return "Spark sub-wallet payment details are unavailable."
        }
    }
}

struct SparkSubwalletCredentials: Codable, Equatable, Identifiable {
    let id: String
    let label: String?
    let seedKeychainKey: String
    let storageDirectoryName: String
    let sparkAddress: String?
    let connectedAt: Date
    let lastVerifiedAt: Date?

    var displayName: String {
        label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "Spark Wallet"
    }

    var identityPubkey: String {
        id
    }

    func withLabel(_ label: String?) -> SparkSubwalletCredentials {
        SparkSubwalletCredentials(
            id: id,
            label: label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            seedKeychainKey: seedKeychainKey,
            storageDirectoryName: storageDirectoryName,
            sparkAddress: sparkAddress,
            connectedAt: connectedAt,
            lastVerifiedAt: lastVerifiedAt
        )
    }

    func verified(sparkAddress: String?) -> SparkSubwalletCredentials {
        SparkSubwalletCredentials(
            id: id,
            label: label,
            seedKeychainKey: seedKeychainKey,
            storageDirectoryName: storageDirectoryName,
            sparkAddress: sparkAddress?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? self.sparkAddress,
            connectedAt: connectedAt,
            lastVerifiedAt: Date()
        )
    }
}
