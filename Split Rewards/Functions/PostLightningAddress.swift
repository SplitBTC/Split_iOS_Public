//
//  PostLightningAddress.swift
//  Split Rewards
//
//  Created by TeeVee on 3/12/26.
//

import Foundation

struct PostLightningAddressRequest: Encodable {
    let lightningAddress: String
}

struct PostLightningAddressResponse: Decodable {
    let ok: Bool?
    let didUpdate: Bool?
    let lightningAddress: String?
    let error: String?
}

enum PostLightningAddressError: LocalizedError {
    case invalidURL
    case invalidLightningAddress
    case invalidResponse
    case encodingFailed
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid lightning address endpoint URL."
        case .invalidLightningAddress:
            return "Lightning address is invalid."
        case .invalidResponse:
            return "Invalid server response."
        case .encodingFailed:
            return "Failed to encode lightning address request."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}

enum LightningAddressAPI {
    @MainActor
    static func postLightningAddress(
        _ lightningAddress: String,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> PostLightningAddressResponse {

        let trimmed = lightningAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PostLightningAddressError.invalidLightningAddress
        }

        guard let url = URL(string: "\(AppConfig.baseURL)/lightning-address") else {
            throw PostLightningAddressError.invalidURL
        }

        try await authManager.ensureSession(walletManager: walletManager)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            request.httpBody = try JSONEncoder().encode(
                PostLightningAddressRequest(lightningAddress: trimmed.lowercased())
            )
        } catch {
            throw PostLightningAddressError.encodingFailed
        }

        // FIRST ATTEMPT
        var (data, response) = try await URLSession.shared.data(for: request)

        // If cookie/session is invalid, re-auth and retry once
        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {

            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)

            // RETRY ONCE
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PostLightningAddressError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let serverMessage: String

            if let decoded = try? JSONDecoder().decode(PostLightningAddressResponse.self, from: data),
               let error = decoded.error,
               !error.isEmpty {
                serverMessage = error
            } else {
                serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            }

            throw PostLightningAddressError.serverError(
                statusCode: httpResponse.statusCode,
                message: serverMessage
            )
        }

        if data.isEmpty {
            return PostLightningAddressResponse(
                ok: true,
                didUpdate: nil,
                lightningAddress: trimmed.lowercased(),
                error: nil
            )
        }

        do {
            return try JSONDecoder().decode(PostLightningAddressResponse.self, from: data)
        } catch {
            throw PostLightningAddressError.invalidResponse
        }
    }
}
