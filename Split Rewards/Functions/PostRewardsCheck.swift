//
//  PostRewardsCheck.swift
//  Split Rewards
//
//  Created by TeeVee on 5/20/26.
//

import Foundation
import CryptoKit

struct RewardMerchantPubkeyHashList: Decodable, Equatable {
    let ok: Bool
    let algorithm: String
    let normalization: String
    let hashVersion: String
    let hashPrefix: String
    let cacheTtlSeconds: Int
    let count: Int
    let hashes: [String]
}

struct LocalRewardsCheckResult: Equatable {
    let rewardEligible: Bool
    let merchantPubkeyHash: String?
}

private enum RewardMerchantHashing {
    static let supportedAlgorithm = "sha256"
    static let supportedNormalization = "trim-lowercase"
    static let supportedHashVersion = "split-merchant-pubkey-sha256-v1"
    static let supportedHashPrefix = "split:merchant-pubkey:v1:"

    static func normalizedPubkey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func hashPubkey(_ value: String) -> String? {
        let normalized = normalizedPubkey(value)
        guard !normalized.isEmpty else { return nil }

        let payload = "\(supportedHashPrefix)\(normalized)"
        return Data(SHA256.hash(data: Data(payload.utf8))).splitRewardsHexString
    }
}

private actor RewardMerchantPubkeyHashCache {
    static let shared = RewardMerchantPubkeyHashCache()

    private var cachedList: RewardMerchantPubkeyHashList?
    private var cachedAt: Date?

    func list() async throws -> RewardMerchantPubkeyHashList {
        if let cachedList, let cachedAt {
            let ttl = max(60, cachedList.cacheTtlSeconds)
            if Date().timeIntervalSince(cachedAt) < TimeInterval(ttl) {
                return cachedList
            }
        }

        guard let url = URL(string: "\(AppConfig.baseURL)/v1/reward-merchant-pubkey-hashes") else {
            throw RewardsCheckError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .useProtocolCachePolicy
        request.httpShouldHandleCookies = false

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RewardsCheckError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw RewardsCheckError.server(message)
        }

        let decoded = try JSONDecoder().decode(RewardMerchantPubkeyHashList.self, from: data)
        guard decoded.ok,
              decoded.algorithm == RewardMerchantHashing.supportedAlgorithm,
              decoded.normalization == RewardMerchantHashing.supportedNormalization,
              decoded.hashVersion == RewardMerchantHashing.supportedHashVersion,
              decoded.hashPrefix == RewardMerchantHashing.supportedHashPrefix else {
            throw RewardsCheckError.invalidResponse
        }

        cachedList = decoded
        cachedAt = Date()
        return decoded
    }
}

func localRewardsCheck(destinationPubkey: String) async throws -> LocalRewardsCheckResult {
    guard let merchantPubkeyHash = RewardMerchantHashing.hashPubkey(destinationPubkey) else {
        throw RewardsCheckError.invalidRequest
    }

    let list = try await RewardMerchantPubkeyHashCache.shared.list()
    let eligibleHashes = Set(list.hashes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    let isEligible = eligibleHashes.contains(merchantPubkeyHash)

    return LocalRewardsCheckResult(
        rewardEligible: isEligible,
        merchantPubkeyHash: isEligible ? merchantPubkeyHash : nil
    )
}

extension String {
    var splitRewardsMerchantPubkeyHashForTesting: String? {
        RewardMerchantHashing.hashPubkey(self)
    }
}

enum RewardsCheckError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "This payment can’t be checked for rewards right now."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .server(let message):
            return message
        }
    }
}

private extension Data {
    var splitRewardsHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
