//
//  GetMessages.swift
//  Split Rewards
//
//  Created by TeeVee on 3/20/26.
//

import Foundation

struct MessagesInboxResponse: Decodable {
    let ok: Bool
    let messages: [InboxMessage]
}

struct InboxMessage: Identifiable, Decodable {
    let id: String
    let clientMessageId: String
    let senderMessagingAccountId: String?
    let senderWalletPubkey: String?
    let senderMessagingPubkey: String
    let senderLightningAddress: String?
    let senderMessagingIdentitySignature: String?
    let senderMessagingIdentitySignatureVersion: Int?
    let senderMessagingIdentitySignedAt: Date?
    let senderEnvelopeSignature: String?
    let senderEnvelopeSignatureVersion: Int?
    let recipientMessagingAccountId: String?
    let recipientWalletPubkey: String?
    let recipientMessagingPubkey: String
    let recipientLightningAddress: String?
    let messageType: String
    let envelopeVersion: Int
    let ciphertext: String?
    let nonce: String?
    let senderEphemeralPubkey: String?
    let status: String
    let createdAt: Date?
    let createdAtClient: Date?
    let expiresAt: Date?
    let deliveredAt: Date?
    let rekeyRequiredAt: Date?
    let expiredAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "messageId"
        case clientMessageId
        case senderMessagingAccountId
        case senderWalletPubkey
        case senderMessagingPubkey
        case senderLightningAddress
        case senderMessagingIdentitySignature
        case senderMessagingIdentitySignatureVersion
        case senderMessagingIdentitySignedAt
        case senderEnvelopeSignature
        case senderEnvelopeSignatureVersion
        case recipientMessagingAccountId
        case recipientWalletPubkey
        case recipientMessagingPubkey
        case recipientLightningAddress
        case messageType
        case envelopeVersion
        case ciphertext
        case nonce
        case senderEphemeralPubkey
        case status
        case createdAt
        case createdAtClient
        case expiresAt
        case deliveredAt
        case rekeyRequiredAt
        case expiredAt
    }

    var senderIdentityBindingPayload: MessagingIdentityBindingPayload? {
        guard let lightningAddress = senderLightningAddress?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              !lightningAddress.isEmpty,
              let senderMessagingIdentitySignature,
              let senderMessagingIdentitySignatureVersion,
              let senderMessagingIdentitySignedAt,
              let senderWalletPubkey
        else {
            return nil
        }

        return MessagingIdentityBindingPayload(
            walletPubkey: senderWalletPubkey,
            lightningAddress: lightningAddress,
            messagingPubkey: senderMessagingPubkey,
            messagingIdentitySignature: senderMessagingIdentitySignature,
            messagingIdentitySignatureVersion: senderMessagingIdentitySignatureVersion,
            messagingIdentitySignedAt: Int(senderMessagingIdentitySignedAt.timeIntervalSince1970)
        )
    }

    var createdAtClientMilliseconds: Int64? {
        guard let createdAtClient else { return nil }
        return Int64((createdAtClient.timeIntervalSince1970 * 1000).rounded())
    }
}

enum MessagesInboxAPI {
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
    static func fetchMessages(
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> [InboxMessage] {

        try await authManager.ensureSession(walletManager: walletManager)

        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/inbox") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true

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
                domain: "MessagesInboxAPI",
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
            return try decoder.decode(MessagesInboxResponse.self, from: data).messages
        } catch {
            throw error
        }
    }
}
