//  GetBreezApiKey.swift
//  Split Rewards
//
//  Created by TeeVee on 3/8/26.
//

import Foundation

struct GetBreezApiKeyResponse: Decodable {
    let apiKey: String
}

enum GetBreezApiKeyError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int, message: String)
    case missingApiKey

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Breez API key URL."
        case .invalidResponse:
            return "Invalid server response."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .missingApiKey:
            return "Missing API key in server response."
        }
    }
}

func getBreezApiKey() async throws -> String {
    guard let url = URL(string: "\(AppConfig.baseURL)/breez-api-key") else {
        throw GetBreezApiKeyError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw GetBreezApiKeyError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
        let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
        throw GetBreezApiKeyError.serverError(
            statusCode: httpResponse.statusCode,
            message: message
        )
    }

    let decoded = try JSONDecoder().decode(GetBreezApiKeyResponse.self, from: data)

    guard !decoded.apiKey.isEmpty else {
        throw GetBreezApiKeyError.missingApiKey
    }

    return decoded.apiKey
}

