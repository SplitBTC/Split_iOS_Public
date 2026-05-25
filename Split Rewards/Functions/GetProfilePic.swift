//
//  GetProfilePic.swift
//  Split Rewards
//
//  Created by TeeVee on 3/18/26.
//

import Foundation

struct GetProfilePicResponse: Decodable {
    let profilePicUrl: String?
}

enum ProfilePicAPI {
    @MainActor
    static func fetchProfilePic(
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> GetProfilePicResponse {

        try await authManager.ensureSession(walletManager: walletManager)

        guard let url = URL(string: "\(AppConfig.baseURL)/Profile_Pic") else {
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
                domain: "ProfilePicAPI",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        raw.isEmpty
                        ? "Server error (HTTP \(http.statusCode))"
                        : "Server error (HTTP \(http.statusCode)): \(raw)"
                ]
            )
        }

        return try JSONDecoder().decode(GetProfilePicResponse.self, from: data)
    }
}
