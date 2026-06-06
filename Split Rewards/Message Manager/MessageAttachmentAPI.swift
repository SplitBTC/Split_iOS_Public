//
//  MessageAttachmentAPI.swift
//  Split Rewards
//
//  Created by TeeVee on 3/23/26.
//

import Foundation

struct MessagingAttachmentRecord: Decodable {
    let attachmentId: String
    let recipientLightningAddress: String?
    let sizeBytes: Int
    let uploadContentType: String
    let status: String
    let expiresAt: Date?
    let linkedMessageId: String?
    let receivedAt: Date?
    let deletedAt: Date?
}

private struct MessageAttachmentUploadResponse: Decodable {
    let ok: Bool
    let attachment: MessagingAttachmentRecord
}

private struct MessageAttachmentReceiptResponse: Decodable {
    let ok: Bool
    let updatedCount: Int
}

enum MessageAttachmentUploadError: LocalizedError {
    case invalidURL
    case emptyFileData
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid attachment upload endpoint URL."
        case .emptyFileData:
            return "Attachment data is empty."
        case .invalidResponse:
            return "Invalid attachment upload response."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}

enum MessageAttachmentDownloadError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid attachment download endpoint URL."
        case .invalidResponse:
            return "Invalid attachment download response."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}

enum MessageAttachmentReceiptError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid attachment receipt endpoint URL."
        case .invalidResponse:
            return "Invalid attachment receipt response."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}

enum MessageAttachmentUploadAPI {
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
    static func uploadEncryptedAttachment(
        fileData: Data,
        recipient: MessagingRecipient,
        fileName: String = "attachment.bin",
        mimeType: String = "application/octet-stream",
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> MessagingAttachmentRecord {
        guard !fileData.isEmpty else {
            throw MessageAttachmentUploadError.emptyFileData
        }

        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/attachments/upload") else {
            throw MessageAttachmentUploadError.invalidURL
        }

        try await authManager.ensureSession(walletManager: walletManager)

        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = makeMultipartBody(
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            recipient: try requireRecipientBindingV4(recipient),
            boundary: boundary
        )

        var (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)

            request.httpBody = makeMultipartBody(
                fileData: fileData,
                fileName: fileName,
                mimeType: mimeType,
                recipient: try requireRecipientBindingV4(recipient),
                boundary: boundary
            )

            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MessageAttachmentUploadError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw MessageAttachmentUploadError.serverError(
                statusCode: httpResponse.statusCode,
                message: serverMessage
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
            return try decoder.decode(MessageAttachmentUploadResponse.self, from: data).attachment
        } catch {
            throw MessageAttachmentUploadError.invalidResponse
        }
    }

    private static func makeMultipartBody(
        fileData: Data,
        fileName: String,
        mimeType: String,
        recipient: MessagingIdentityBindingPayloadV4,
        boundary: String
    ) -> Data {
        var body = Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"walletPubkey\"\r\n\r\n")
        body.append(recipient.walletPubkey)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"lightningAddressHash\"\r\n\r\n")
        body.append(recipient.lightningAddressHash)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"lightningAddressHashScheme\"\r\n\r\n")
        body.append(recipient.lightningAddressHashScheme)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"messagingPubkey\"\r\n\r\n")
        body.append(recipient.messagingPubkey)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"messagingIdentitySignature\"\r\n\r\n")
        body.append(recipient.messagingIdentitySignature)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"messagingIdentitySignatureVersion\"\r\n\r\n")
        body.append(String(recipient.messagingIdentitySignatureVersion))
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"messagingIdentitySignedAt\"\r\n\r\n")
        body.append(String(recipient.messagingIdentitySignedAt))
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"attachment\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        return body
    }

    private static func requireRecipientBindingV4(
        _ recipient: MessagingRecipient
    ) throws -> MessagingIdentityBindingPayloadV4 {
        guard let binding = recipient.identityBindingPayloadV4 else {
            throw MessageKeyManager.MessageKeyError.invalidResponse
        }

        return binding
    }
}

enum MessageAttachmentDownloadAPI {
    @MainActor
    static func downloadEncryptedAttachment(
        attachmentId: String,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> Data {
        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/attachments/\(attachmentId)/download") else {
            throw MessageAttachmentDownloadError.invalidURL
        }

        try await authManager.ensureSession(walletManager: walletManager)

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

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MessageAttachmentDownloadError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw MessageAttachmentDownloadError.serverError(
                statusCode: httpResponse.statusCode,
                message: serverMessage
            )
        }

        return data
    }
}

enum MessageAttachmentReceiptAPI {
    @MainActor
    static func markReceived(
        attachmentIds: [String],
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws {
        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/attachments/mark-received") else {
            throw MessageAttachmentReceiptError.invalidURL
        }

        try await authManager.ensureSession(walletManager: walletManager)

        struct RequestBody: Encodable {
            let attachmentIds: [String]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(RequestBody(attachmentIds: attachmentIds))

        var (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MessageAttachmentReceiptError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw MessageAttachmentReceiptError.serverError(
                statusCode: httpResponse.statusCode,
                message: serverMessage
            )
        }

        _ = try JSONDecoder().decode(MessageAttachmentReceiptResponse.self, from: data)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
