//
//  AckMessages.swift
//  Split Rewards
//
//  Created by TeeVee on 3/20/26.
//

import Foundation

struct AckMessagesResponse: Decodable {
    let ok: Bool
    let acknowledgedCount: Int
}

struct RekeyMessagesResponse: Decodable {
    let ok: Bool
    let updatedCount: Int
    let resetAttachmentCount: Int
}

struct DecryptFailedMessagesResponse: Decodable {
    let ok: Bool
    let retryRequiredCount: Int
    let failedCount: Int
    let resetAttachmentCount: Int
}

struct OutgoingMessageStatusesResponse: Decodable {
    let ok: Bool
    let messages: [OutgoingMessageStatus]
}

struct OutgoingMessageStatus: Identifiable, Decodable {
    let id: String
    let clientMessageId: String
    let recipientLightningAddress: String?
    let recipientWalletPubkey: String?
    let status: String
    let sameKeyRetryCount: Int
    let createdAt: Date?
    let deliveredAt: Date?
    let rekeyRequiredAt: Date?
    let sameKeyDecryptFailedAt: Date?
    let failedAt: Date?
    let expiredAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "messageId"
        case clientMessageId
        case recipientLightningAddress
        case recipientWalletPubkey
        case status
        case sameKeyRetryCount
        case createdAt
        case deliveredAt
        case rekeyRequiredAt
        case sameKeyDecryptFailedAt
        case failedAt
        case expiredAt
    }
}

enum AckMessagesAPI {
    @MainActor
    static func acknowledgeMessages(
        messageIds: [String],
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> AckMessagesResponse {

        guard !messageIds.isEmpty else {
            return AckMessagesResponse(ok: true, acknowledgedCount: 0)
        }

        try await authManager.ensureSession(walletManager: walletManager)

        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/ack") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["messageIds": messageIds])

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
                domain: "AckMessagesAPI",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        raw.isEmpty
                        ? "Server error (HTTP \(http.statusCode))"
                        : "Server error (HTTP \(http.statusCode)): \(raw)"
                ]
            )
        }

        return try JSONDecoder().decode(AckMessagesResponse.self, from: data)
    }
}

enum RekeyMessagesAPI {
    @MainActor
    static func markMessagesRekeyRequired(
        messageIds: [String],
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> RekeyMessagesResponse {

        guard !messageIds.isEmpty else {
            return RekeyMessagesResponse(ok: true, updatedCount: 0, resetAttachmentCount: 0)
        }

        try await authManager.ensureSession(walletManager: walletManager)

        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/rekey-required") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["messageIds": messageIds])

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
                domain: "RekeyMessagesAPI",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        raw.isEmpty
                        ? "Server error (HTTP \(http.statusCode))"
                        : "Server error (HTTP \(http.statusCode)): \(raw)"
                ]
            )
        }

        return try JSONDecoder().decode(RekeyMessagesResponse.self, from: data)
    }
}

enum DecryptFailedMessagesAPI {
    @MainActor
    static func markMessagesDecryptFailed(
        messageIds: [String],
        failureReasons: [String: String] = [:],
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> DecryptFailedMessagesResponse {

        guard !messageIds.isEmpty else {
            return DecryptFailedMessagesResponse(
                ok: true,
                retryRequiredCount: 0,
                failedCount: 0,
                resetAttachmentCount: 0
            )
        }

        try await authManager.ensureSession(walletManager: walletManager)

        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/decrypt-failed") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        struct RequestBody: Encodable {
            let messageIds: [String]
            let failureReasons: [String: String]
        }

        request.httpBody = try JSONEncoder().encode(RequestBody(
            messageIds: messageIds,
            failureReasons: failureReasons
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
                domain: "DecryptFailedMessagesAPI",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        raw.isEmpty
                        ? "Server error (HTTP \(http.statusCode))"
                        : "Server error (HTTP \(http.statusCode)): \(raw)"
                ]
            )
        }

        return try JSONDecoder().decode(DecryptFailedMessagesResponse.self, from: data)
    }
}

enum OutgoingMessageStatusesAPI {
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
    static func fetchOutgoingStatuses(
        limit: Int = 100,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> [OutgoingMessageStatus] {
        try await authManager.ensureSession(walletManager: walletManager)

        let clampedLimit = min(max(limit, 1), 200)
        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/outgoing-statuses?limit=\(clampedLimit)") else {
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
                domain: "OutgoingMessageStatusesAPI",
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

        return try decoder.decode(OutgoingMessageStatusesResponse.self, from: data).messages
    }
}
