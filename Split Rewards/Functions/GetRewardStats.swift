//  GetRewardStats.swift
//  Split Rewards
//
//  Created by TeeVee on 2/5/26.
//
import SwiftUI
import Foundation

// MARK: - DTOs

struct RewardStatsResponse: Decodable {
    let monthKey: String
    let monthlyPot: MonthlyPot
    let platform: PlatformTotals
    let user: UserTotals
    let stats: RewardStats

    struct MonthlyPot: Decodable {
        let sats: Int
    }

    struct PlatformTotals: Decodable {
        /// Reward spend used for calculations: (merchantSpendCents + purchaseSpendCents) (cents)
        let rewardSpendCents: Int
        /// Merchant transactions only
        let transactions: Int
    }

    struct UserTotals: Decodable {
        /// Reward spend used for calculations: (merchantSpendCents + purchaseSpendCents) (cents)
        let rewardSpendCents: Int
        /// Merchant transactions only
        let transactions: Int
    }

    struct RewardStats: Decodable {
        let shareBps: Int
        let projectedEarningsSats: Int
        /// NEW: Lifetime earnings in sats (paid only)
        let lifetimeEarningsSats: Int
    }
}

// MARK: - Networking

enum RewardsStatsAPI {
    @MainActor
    static func fetchRewardsStats(
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> RewardStatsResponse {

        try await authManager.ensureSession(walletManager: walletManager)

        guard let url = URL(string: "\(AppConfig.baseURL)/v1/RewardStats") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true

        // FIRST ATTEMPT
        var (data, response) = try await URLSession.shared.data(for: request)

        // Retry once on auth failures after refreshing session
        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {

            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)

            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "RewardsStatsAPI",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        raw.isEmpty
                        ? "Server error (HTTP \(http.statusCode))"
                        : "Server error (HTTP \(http.statusCode)): \(raw)"
                ]
            )
        }

        return try JSONDecoder().decode(RewardStatsResponse.self, from: data)
    }
}


