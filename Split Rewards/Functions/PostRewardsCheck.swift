//
//  PostRewardsCheck.swift
//  Split Rewards
//
//  Created by TeeVee on 5/20/26.
//

import Foundation

struct RewardsCheckResponse: Decodable, Equatable {
    let ok: Bool
    let rewardEligible: Bool
    let merchantMatched: Bool
    let error: String?
}

@MainActor
func postRewardsCheck(
    walletManager: WalletManager,
    authManager: AuthManager,
    destinationPubkey: String
) async throws -> RewardsCheckResponse {
    try await authManager.ensureSession(walletManager: walletManager)

    let trimmedDestinationPubkey = destinationPubkey.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedDestinationPubkey.isEmpty,
          let url = URL(string: "\(AppConfig.baseURL)/RewardsCheck") else {
        throw RewardsCheckError.invalidRequest
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpShouldHandleCookies = true

    struct RequestBody: Encodable {
        let destinationPubkey: String
    }

    request.httpBody = try JSONEncoder().encode(
        RequestBody(destinationPubkey: trimmedDestinationPubkey)
    )

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw RewardsCheckError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
        let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
        throw RewardsCheckError.server(message)
    }

    let decoded = try JSONDecoder().decode(RewardsCheckResponse.self, from: data)
    if decoded.ok == false {
        throw RewardsCheckError.server(decoded.error ?? "Rewards check failed")
    }

    return decoded
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
