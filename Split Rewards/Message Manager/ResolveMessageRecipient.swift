//
//  ResolveMessageRecipient.swift
//  Split Rewards
//
//  Created by TeeVee on 3/20/26.
//

import Foundation

struct ResolveMessageRecipientResponse: Decodable {
    let ok: Bool
    let recipient: MessagingRecipient
    let directory: MessagingDirectoryProofPayload
}

struct MessagingRecipient: Codable, Hashable {
    let walletPubkey: String
    let lightningAddress: String
    let messagingPubkey: String
    let messagingIdentitySignature: String
    let messagingIdentitySignatureVersion: Int
    let messagingIdentitySignedAt: Date
    let profilePicUrl: String?

    var identityBindingPayload: MessagingIdentityBindingPayload {
        MessagingIdentityBindingPayload(
            walletPubkey: walletPubkey,
            lightningAddress: lightningAddress
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            messagingPubkey: messagingPubkey,
            messagingIdentitySignature: messagingIdentitySignature,
            messagingIdentitySignatureVersion: messagingIdentitySignatureVersion,
            messagingIdentitySignedAt: Int(messagingIdentitySignedAt.timeIntervalSince1970)
        )
    }
}

enum ResolveMessageRecipientAPI {
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
    static func resolveRecipient(
        lightningAddress: String,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> MessagingRecipient {
        try await authManager.ensureSession(walletManager: walletManager)

        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v3/directory/lookup") else {
            throw URLError(.badURL)
        }

        let normalizedLightningAddress = lightningAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["lightningAddress": normalizedLightningAddress])

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
                domain: "ResolveMessageRecipientAPI",
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
        do {
            let decoded = try decoder.decode(ResolveMessageRecipientResponse.self, from: data)
            let recipient = decoded.recipient
            try MessageKeyBindingVerifier.verifyRecipientBinding(recipient)
            try MessagingDirectoryVerifier.verifyDirectoryProof(
                binding: recipient.identityBindingPayload,
                directory: decoded.directory
            )
            try MessageDirectoryCheckpointStore.storeIfNewer(decoded.directory.checkpoint)
            return recipient
        } catch {
            throw error
        }
    }
}
