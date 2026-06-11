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

private struct ResolveMessageRecipientV4Response: Decodable {
    let ok: Bool
    let recipient: MessagingRecipientV4Payload
    let directory: MessagingDirectoryV4Payload?
}

private struct MessagingRecipientV4Payload: Decodable {
    let walletPubkey: String
    let lightningAddressHash: String
    let lightningAddressHashScheme: String
    let messagingPubkey: String
    let messagingIdentitySignature: String
    let messagingIdentitySignatureVersion: Int
    let messagingIdentitySignedAt: Int
}

private struct MessagingDirectoryV4Payload: Decodable {
    let mode: String?
    let proof: String?
    let issuedAt: Date?
}

struct MessagingRecipient: Codable, Hashable {
    let walletPubkey: String
    let lightningAddress: String
    let lightningAddressHash: String?
    let lightningAddressHashScheme: String?
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

    var identityBindingPayloadV4: MessagingIdentityBindingPayloadV4? {
        guard let lightningAddressHash = lightningAddressHash?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              !lightningAddressHash.isEmpty,
              let lightningAddressHashScheme = lightningAddressHashScheme?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !lightningAddressHashScheme.isEmpty else {
            return nil
        }

        return MessagingIdentityBindingPayloadV4(
            walletPubkey: walletPubkey,
            lightningAddressHash: lightningAddressHash,
            lightningAddressHashScheme: lightningAddressHashScheme,
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

        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/directory/lookup") else {
            throw URLError(.badURL)
        }

        let normalizedLightningAddress = try MessagingPrivacyV4.normalizeLightningAddress(lightningAddress)
        let lightningAddressHash = try MessagingPrivacyV4.lightningAddressClientHash(
            for: normalizedLightningAddress
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try await MessagingAuthenticatedWalletHeader.apply(
            to: &request,
            walletManager: walletManager
        )
        struct RequestBody: Encodable {
            let lightningAddressHash: String
            let lightningAddressHashScheme: String
        }
        request.httpBody = try JSONEncoder().encode(RequestBody(
            lightningAddressHash: lightningAddressHash,
            lightningAddressHashScheme: MessagingPrivacyV4.lightningAddressClientHashScheme
        ))

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
            let decoded = try decoder.decode(ResolveMessageRecipientV4Response.self, from: data)
            let recipient = MessagingRecipient(
                walletPubkey: decoded.recipient.walletPubkey,
                lightningAddress: normalizedLightningAddress,
                lightningAddressHash: decoded.recipient.lightningAddressHash,
                lightningAddressHashScheme: decoded.recipient.lightningAddressHashScheme,
                messagingPubkey: decoded.recipient.messagingPubkey,
                messagingIdentitySignature: decoded.recipient.messagingIdentitySignature,
                messagingIdentitySignatureVersion: decoded.recipient.messagingIdentitySignatureVersion,
                messagingIdentitySignedAt: Date(
                    timeIntervalSince1970: TimeInterval(decoded.recipient.messagingIdentitySignedAt)
                ),
                profilePicUrl: nil
            )

            guard recipient.lightningAddressHash == lightningAddressHash,
                  recipient.lightningAddressHashScheme == MessagingPrivacyV4.lightningAddressClientHashScheme else {
                throw MessageKeyBindingVerifier.VerificationError.invalidLightningAddressHash
            }

            try MessageKeyBindingVerifier.verifyRecipientBindingV4(recipient)
            try MessageRecipientTrustStore.enforceOrPin(
                lightningAddress: normalizedLightningAddress,
                walletPubkey: recipient.walletPubkey
            )
            return recipient
        } catch {
            throw error
        }
    }
}
