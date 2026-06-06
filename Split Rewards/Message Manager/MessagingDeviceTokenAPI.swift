//
//  MessagingDeviceTokenAPI.swift
//  Split Rewards
//
//  Created by TeeVee on 3/21/26.
//

import Foundation

struct MessagingDeviceRegistrationRecord: Decodable {
    let registrationId: String?
    let messagingAccountId: String?
    let walletPubkey: String?
    let messagingPubkey: String?
    let deviceToken: String?
    let platform: String?
    let environment: String?
    let appVersion: String?
    let bundleId: String?
    let registrationSignedAt: Date?
    let lastSeenAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
}

struct MessagingDeviceTokenResponse: Decodable {
    let ok: Bool
    let didUpdate: Bool?
    let registration: MessagingDeviceRegistrationRecord?
    let error: String?
}

enum MessagingDeviceTokenAPI {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    @MainActor
    static func registerDeviceToken(
        _ deviceToken: String?,
        messagingPubkey: String?,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> MessagingDeviceTokenResponse {
        guard let deviceToken = deviceToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !deviceToken.isEmpty,
              let messagingPubkey = messagingPubkey?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              !messagingPubkey.isEmpty else {
            return MessagingDeviceTokenResponse(
                ok: true,
                didUpdate: false,
                registration: nil,
                error: nil
            )
        }

        try await authManager.ensureSession(walletManager: walletManager)

        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/device-registrations") else {
            throw URLError(.badURL)
        }

        let walletPubkey = try await MessageKeyManager.shared.currentWalletPubkey(
            walletManager: walletManager
        )
        let signedAt = Int(Date().timeIntervalSince1970)
        let signatureVersion = 2
        let canonicalMessage = MessageKeyBindingVerifier.buildMessagingDeviceRegistrationMessageV4(
            version: signatureVersion,
            walletPubkey: walletPubkey,
            messagingPubkey: messagingPubkey,
            platform: "apns",
            environment: AppConfig.messagingPushEnvironment,
            deviceToken: deviceToken,
            signedAt: signedAt
        )
        let signed = try await walletManager.signAuthMessage(canonicalMessage)
        guard signed.pubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == walletPubkey.lowercased() else {
            throw NSError(
                domain: "MessagingDeviceTokenAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Signed wallet pubkey did not match the active wallet."]
            )
        }

        struct RequestBody: Encodable {
            let walletPubkey: String
            let messagingPubkey: String
            let platform: String
            let environment: String
            let deviceToken: String
            let registrationSignature: String
            let registrationSignatureVersion: Int
            let registrationSignedAt: Int
            let appVersion: String?
            let bundleId: String?
        }

        let bundle = Bundle.main
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let bundleId = bundle.bundleIdentifier

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                walletPubkey: signed.pubkey,
                messagingPubkey: messagingPubkey,
                platform: "apns",
                environment: AppConfig.messagingPushEnvironment,
                deviceToken: deviceToken,
                registrationSignature: signed.signature,
                registrationSignatureVersion: signatureVersion,
                registrationSignedAt: signedAt,
                appVersion: appVersion,
                bundleId: bundleId
            )
        )

        var (data, response) = try await URLSession.shared.data(for: request)

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
                domain: "MessagingDeviceTokenAPI",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        raw.isEmpty
                        ? "Server error (HTTP \(http.statusCode))"
                        : "Server error (HTTP \(http.statusCode)): \(raw)"
                ]
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            if let date = standardFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return try decoder.decode(MessagingDeviceTokenResponse.self, from: data)
    }
}
