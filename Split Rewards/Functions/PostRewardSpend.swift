//
//  PostRewardSpend.swift
//  Split Rewards
//
//  Created by TeeVee on 12/6/25.
//

import Foundation

// MARK: - Response Model

struct RewardSpendResponse: Decodable {
    let ok: Bool
    let rewardSpendApplied: Bool
}

// MARK: - API Call (AUTHENTICATED)

/// Call this after you receive/refresh a Breez transaction and want the backend
/// to apply reward spend logic (no Transaction is created server-side).
///
/// This endpoint is USER-IDENTITY dependent and therefore ensures a valid
/// server session via AuthManager before making the request.
@MainActor
func postRewardSpend(
    walletManager: WalletManager,
    authManager: AuthManager,

    direction: String,              // "sent" | "received"
    usdAmountCents: Int,            // e.g. $8.50 -> 850
    btcAmountSats: Int,             // NEW: sats (int)
    destinationPubkey: String?,     // merchant pubkey (if available/needed)
    network: String,                // "lightning" | "onchain" | "swap"
    status: String,                 // "Pending" | "Completed" | "Failed"
    paymentHash: String? = nil,

    onSuccess: ((RewardSpendResponse) -> Void)? = nil,
    onError: ((String) -> Void)? = nil
) {
    Task {
        do {
            // 🔐 Ensure we have a valid wallet-authenticated session
            try await authManager.ensureSession(walletManager: walletManager)
        } catch {
            onError?("Authentication failed: \(error.localizedDescription)")
            return
        }

        guard let url = URL(string: "\(AppConfig.baseURL)/LogRewardSpend") else {
            onError?("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true

        struct RequestBody: Encodable {
            let direction: String
            let usdAmountCents: Int
            let btcAmountSats: Int       // NEW
            let destinationPubkey: String?
            let network: String
            let status: String
            let paymentHash: String?
        }

        let body = RequestBody(
            direction: direction,
            usdAmountCents: usdAmountCents,
            btcAmountSats: btcAmountSats,       // NEW
            destinationPubkey: destinationPubkey,
            network: network,
            status: status,
            paymentHash: paymentHash
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            onError?("Failed to encode reward spend request.")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    onError?("Network error while posting reward spend: \(error.localizedDescription)")
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    onError?("No data received from server.")
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {

                let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                print("Reward spend server error \(httpResponse.statusCode): \(bodyString)")

                DispatchQueue.main.async {
                    onError?("Server error \(httpResponse.statusCode) while posting reward spend.")
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(RewardSpendResponse.self, from: data)
                DispatchQueue.main.async {
                    onSuccess?(decoded)
                }
            } catch {
                let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                print("Reward spend decode error: \(error)")
                print("Raw response body: \(bodyString)")

                DispatchQueue.main.async {
                    onError?("Failed to decode reward spend response.")
                }
            }
        }
        .resume()
    }
}











