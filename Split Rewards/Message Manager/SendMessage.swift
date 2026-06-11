//
//  SendMessage.swift
//  Split Rewards
//
//  Created by TeeVee on 3/20/26.
//

import Foundation

struct SendMessageEnvelope {
    let clientMessageId: String
    let recipient: MessagingIdentityBindingPayloadV4
    let ciphertext: String
    let nonce: String
    let senderEphemeralPubkey: String
    let createdAtClientMs: Int64
    let envelopeVersion: Int
    let messageType: String
    let attachmentIds: [String]?
    let sameKeyRetryCount: Int?
}

struct SendMessageResponse: Decodable {
    let ok: Bool
    let message: SentRelayMessage?
    let deduped: Bool?
}

struct SentRelayMessage: Decodable {
    let messageId: String
    let clientMessageId: String
    let recipientWalletPubkey: String?
    let recipientMessagingAccountId: String?
    let recipientMessagingPubkey: String
    let recipientLightningAddress: String?
    let status: String
    let createdAt: Date?
    let createdAtClient: Date?
}

struct MessageSendResult {
    let conversationId: String
    let conversationTitle: String
    let lightningAddress: String
    let storedMessage: StoredMessage
}

private struct OutgoingMessageDraft {
    let clientMessageId: String
    let createdAtClient: Date
    let sameKeyRetryCount: Int?
}

enum SendMessageAPIError: LocalizedError {
    case recipientBindingStale
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .recipientBindingStale:
            return "The recipient messaging identity changed. Retrying with a fresh binding."
        case .serverError(let statusCode, let message):
            return "Server error (HTTP \(statusCode)): \(message)"
        }
    }
}

enum SendMessageAPI {
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
    static func send(
        envelope: SendMessageEnvelope,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> SendMessageResponse {
        try await authManager.ensureSession(walletManager: walletManager)

        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/send") else {
            throw URLError(.badURL)
        }

        struct RequestBody: Encodable {
            let clientMessageId: String
            let recipient: MessagingIdentityBindingPayloadV4
            let ciphertext: String
            let nonce: String
            let senderEphemeralPubkey: String
            let createdAtClientMs: Int64
            let envelopeVersion: Int
            let messageType: String
            let attachmentIds: [String]?
            let sameKeyRetryCount: Int?
        }

        let body = RequestBody(
            clientMessageId: envelope.clientMessageId,
            recipient: envelope.recipient,
            ciphertext: envelope.ciphertext,
            nonce: envelope.nonce,
            senderEphemeralPubkey: envelope.senderEphemeralPubkey,
            createdAtClientMs: envelope.createdAtClientMs,
            envelopeVersion: envelope.envelopeVersion,
            messageType: envelope.messageType,
            attachmentIds: envelope.attachmentIds,
            sameKeyRetryCount: envelope.sameKeyRetryCount
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
        request.httpBody = try JSONEncoder().encode(body)

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
            let serverMessage = extractServerMessage(from: data)
            let normalizedServerMessage = serverMessage.lowercased()
            if http.statusCode == 409 &&
                normalizedServerMessage.contains("recipient messaging") &&
                normalizedServerMessage.contains("stale") &&
                normalizedServerMessage.contains("resolve again") {
                throw SendMessageAPIError.recipientBindingStale
            }

            throw SendMessageAPIError.serverError(
                statusCode: http.statusCode,
                message: serverMessage.isEmpty ? "Unknown server error" : serverMessage
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
            return try decoder.decode(SendMessageResponse.self, from: data)
        } catch {
            throw error
        }
    }

    private static func extractServerMessage(from data: Data) -> String {
        if let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = decoded["error"] as? String,
               !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return error
            }

            if let message = decoded["message"] as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }
        }

        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum MessagingSendCoordinator {
    @MainActor
    static func sendTextMessage(
        lightningAddress: String,
        plaintext: String,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> MessageSendResult {
        try await sendMessage(
            lightningAddress: lightningAddress,
            plaintext: plaintext,
            messageType: "text",
            authManager: authManager,
            walletManager: walletManager
        )
    }

    @MainActor
    static func sendPaymentRequest(
        lightningAddress: String,
        payload: PaymentRequestMessagePayload,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> MessageSendResult {
        let encodedPayload = try MessagePayloadCodec.encodePaymentRequest(payload)
        return try await sendMessage(
            lightningAddress: lightningAddress,
            plaintext: encodedPayload,
            messageType: "payment_request",
            authManager: authManager,
            walletManager: walletManager
        )
    }

    @MainActor
    static func sendPaymentRequestPaid(
        lightningAddress: String,
        payload: PaymentRequestPaidMessagePayload,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> MessageSendResult {
        let encodedPayload = try MessagePayloadCodec.encodePaymentRequestPaid(payload)
        return try await sendMessage(
            lightningAddress: lightningAddress,
            plaintext: encodedPayload,
            messageType: "payment_request_paid",
            authManager: authManager,
            walletManager: walletManager
        )
    }

    @MainActor
    static func sendAttachment(
        lightningAddress: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> MessageSendResult {
        try await sendAttachment(
            lightningAddress: lightningAddress,
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            authManager: authManager,
            walletManager: walletManager,
            draft: nil
        )
    }

    @MainActor
    static func resendStoredMessageIfNeeded(
        _ message: StoredMessage,
        authManager: AuthManager,
        walletManager: WalletManager,
        sameKeyRetryCount: Int? = nil
    ) async throws -> MessageSendResult? {
        guard !message.isIncoming else {
            return nil
        }

        let retryDraft = OutgoingMessageDraft(
            clientMessageId: UUID().uuidString.lowercased(),
            createdAtClient: message.createdAt,
            sameKeyRetryCount: sameKeyRetryCount
        )

        if message.messageType == "attachment" {
            guard let payload = MessagePayloadCodec.decodeAttachment(from: message.body),
                  let fileData = MessageAttachmentManager.shared.cachedAttachmentData(for: payload) else {
                return nil
            }

            return try await sendAttachment(
                lightningAddress: message.recipientLightningAddress,
                fileData: fileData,
                fileName: payload.fileName,
                mimeType: payload.mimeType,
                imageWidth: payload.imageWidth,
                imageHeight: payload.imageHeight,
                authManager: authManager,
                walletManager: walletManager,
                draft: retryDraft
            )
        }

        return try await sendMessage(
            lightningAddress: message.recipientLightningAddress,
            plaintext: message.body,
            messageType: message.messageType,
            authManager: authManager,
            walletManager: walletManager,
            draft: retryDraft
        )
    }

    @MainActor
    private static func sendAttachment(
        lightningAddress: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        imageWidth: Int?,
        imageHeight: Int?,
        authManager: AuthManager,
        walletManager: WalletManager,
        draft: OutgoingMessageDraft?
    ) async throws -> MessageSendResult {
        let senderBinding = try await ensureMessagingBinding(
            authManager: authManager,
            walletManager: walletManager
        )
        let recipient = try await resolveMessagingRecipient(
            lightningAddress: lightningAddress,
            authManager: authManager,
            walletManager: walletManager
        )

        let encryptedAttachment = try MessageCryptoManager.shared.encryptAttachmentData(
            fileData,
            recipientMessagingPubkeyHex: recipient.messagingPubkey
        )

        let attachmentRecord = try await MessageAttachmentUploadAPI.uploadEncryptedAttachment(
            fileData: encryptedAttachment.ciphertext,
            recipient: recipient,
            fileName: "\(UUID().uuidString.lowercased()).bin",
            mimeType: "application/octet-stream",
            authManager: authManager,
            walletManager: walletManager
        )

        try MessageAttachmentManager.shared.cacheOutgoingAttachment(
            attachmentId: attachmentRecord.attachmentId,
            fileName: fileName,
            plaintextData: fileData
        )

        let payload = AttachmentMessagePayload(
            attachmentId: attachmentRecord.attachmentId,
            fileName: fileName,
            mimeType: mimeType,
            sizeBytes: fileData.count,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            attachmentNonce: encryptedAttachment.nonce,
            attachmentSenderEphemeralPubkey: encryptedAttachment.senderEphemeralPubkey
        )

        let encodedPayload = try MessagePayloadCodec.encodeAttachment(payload)

        return try await sendResolvedMessage(
            senderBinding: senderBinding,
            recipient: recipient,
            plaintext: encodedPayload,
            messageType: "attachment",
            attachmentIds: [attachmentRecord.attachmentId],
            authManager: authManager,
            walletManager: walletManager,
            draft: draft
        )
    }

    @MainActor
    static func sendReaction(
        lightningAddress: String,
        payload: MessageReactionPayload,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> MessageSendResult {
        let encodedPayload = try MessagePayloadCodec.encodeReaction(payload)
        return try await sendMessage(
            lightningAddress: lightningAddress,
            plaintext: encodedPayload,
            messageType: "reaction",
            authManager: authManager,
            walletManager: walletManager
        )
    }

    @MainActor
    private static func sendMessage(
        lightningAddress: String,
        plaintext: String,
        messageType: String,
        authManager: AuthManager,
        walletManager: WalletManager,
        draft: OutgoingMessageDraft? = nil
    ) async throws -> MessageSendResult {
        let senderBinding = try await ensureMessagingBinding(
            authManager: authManager,
            walletManager: walletManager
        )
        let recipient = try await resolveMessagingRecipient(
            lightningAddress: lightningAddress,
            authManager: authManager,
            walletManager: walletManager
        )

        return try await sendResolvedMessage(
            senderBinding: senderBinding,
            recipient: recipient,
            plaintext: plaintext,
            messageType: messageType,
            attachmentIds: nil,
            authManager: authManager,
            walletManager: walletManager,
            draft: draft
        )
    }

    @MainActor
    private static func ensureMessagingBinding(
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> SenderMessagingBindingV4 {
        let registration = try await MessageKeyManager.shared.ensureRegistered(
            authManager: authManager,
            walletManager: walletManager
        )

        guard let binding = registration.identityBindingPayloadV4,
              let rawLightningAddress = try await MessageKeyManager.shared
                .fetchLocalLightningAddressForV4Send(walletManager: walletManager) else {
            throw MessageKeyManager.MessageKeyError.invalidResponse
        }

        return SenderMessagingBindingV4(
            binding: binding,
            rawLightningAddress: rawLightningAddress
        )
    }

    @MainActor
    private static func resolveMessagingRecipient(
        lightningAddress: String,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> MessagingRecipient {
        return try await ResolveMessageRecipientAPI.resolveRecipient(
            lightningAddress: lightningAddress,
            authManager: authManager,
            walletManager: walletManager
        )
    }

    @MainActor
    private static func sendResolvedMessage(
        senderBinding: SenderMessagingBindingV4,
        recipient: MessagingRecipient,
        plaintext: String,
        messageType: String,
        attachmentIds: [String]?,
        authManager: AuthManager,
        walletManager: WalletManager,
        draft: OutgoingMessageDraft? = nil
    ) async throws -> MessageSendResult {
        let effectiveDraft = draft ?? OutgoingMessageDraft(
            clientMessageId: UUID().uuidString.lowercased(),
            createdAtClient: Date(),
            sameKeyRetryCount: nil
        )
        let createdAtClient = effectiveDraft.createdAtClient
        let createdAtClientMs = Int64((createdAtClient.timeIntervalSince1970 * 1000).rounded())
        let clientMessageId = effectiveDraft.clientMessageId
        let sameKeyRetryCount = effectiveDraft.sameKeyRetryCount
        var currentRecipient = recipient
        let response: SendMessageResponse

        do {
            response = try await sendEnvelope(
                senderBinding: senderBinding,
                recipient: currentRecipient,
                plaintext: plaintext,
                clientMessageId: clientMessageId,
                createdAtClientMs: createdAtClientMs,
                messageType: messageType,
                attachmentIds: attachmentIds,
                sameKeyRetryCount: sameKeyRetryCount,
                authManager: authManager,
                walletManager: walletManager
            )
        } catch SendMessageAPIError.recipientBindingStale {
            guard attachmentIds?.isEmpty != false else {
                throw SendMessageAPIError.recipientBindingStale
            }

            currentRecipient = try await resolveMessagingRecipient(
                lightningAddress: recipient.lightningAddress,
                authManager: authManager,
                walletManager: walletManager
            )

            response = try await sendEnvelope(
                senderBinding: senderBinding,
                recipient: currentRecipient,
                plaintext: plaintext,
                clientMessageId: clientMessageId,
                createdAtClientMs: createdAtClientMs,
                messageType: messageType,
                attachmentIds: attachmentIds,
                sameKeyRetryCount: sameKeyRetryCount,
                authManager: authManager,
                walletManager: walletManager
            )
        }

        let storedMessage = StoredMessage(
            id: response.message?.messageId ?? clientMessageId,
            conversationId: currentRecipient.walletPubkey,
            clientMessageId: clientMessageId,
            body: plaintext,
            createdAt: createdAtClient,
            isIncoming: false,
            isRead: true,
            senderWalletPubkey: senderBinding.walletPubkey,
            senderMessagingPubkey: senderBinding.binding.messagingPubkey,
            senderLightningAddress: senderBinding.rawLightningAddress,
            recipientWalletPubkey: currentRecipient.walletPubkey,
            recipientMessagingPubkey: currentRecipient.messagingPubkey,
            recipientLightningAddress: currentRecipient.lightningAddress,
            messageType: messageType,
            deliveryState: nil
        )

        _ = try MessageStore.shared.upsert([storedMessage])

        return MessageSendResult(
            conversationId: currentRecipient.walletPubkey,
            conversationTitle: currentRecipient.lightningAddress,
            lightningAddress: currentRecipient.lightningAddress,
            storedMessage: storedMessage
        )
    }

    @MainActor
    private static func sendEnvelope(
        senderBinding: SenderMessagingBindingV4,
        recipient: MessagingRecipient,
        plaintext: String,
        clientMessageId: String,
        createdAtClientMs: Int64,
        messageType: String,
        attachmentIds: [String]?,
        sameKeyRetryCount: Int?,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> SendMessageResponse {
        let encryptedPayload = try MessageCryptoManager.shared.encrypt(
            plaintext: try await buildSealedSenderPayloadString(
                plaintext: plaintext,
                messageType: messageType,
                senderBinding: senderBinding,
                recipient: recipient,
                createdAtClientMs: createdAtClientMs,
                envelopeVersion: 4,
                clientMessageId: clientMessageId,
                walletManager: walletManager
            ),
            recipientMessagingPubkeyHex: recipient.messagingPubkey
        )

        return try await SendMessageAPI.send(
            envelope: SendMessageEnvelope(
                clientMessageId: clientMessageId,
                recipient: try requireRecipientBindingV4(recipient),
                ciphertext: encryptedPayload.ciphertext,
                nonce: encryptedPayload.nonce,
                senderEphemeralPubkey: encryptedPayload.senderEphemeralPubkey,
                createdAtClientMs: createdAtClientMs,
                envelopeVersion: 4,
                messageType: messageType,
                attachmentIds: attachmentIds,
                sameKeyRetryCount: sameKeyRetryCount
            ),
            authManager: authManager,
            walletManager: walletManager
        )
    }

    @MainActor
    private static func buildSealedSenderPayloadString(
        plaintext: String,
        messageType: String,
        senderBinding: SenderMessagingBindingV4,
        recipient: MessagingRecipient,
        createdAtClientMs: Int64,
        envelopeVersion: Int,
        clientMessageId: String,
        walletManager: WalletManager
    ) async throws -> String {
        let recipientBinding = try requireRecipientBindingV4(recipient)
        let messageSignatureVersion = 3
        let canonicalEnvelopeMessage = MessageKeyBindingVerifier.buildMessagingEnvelopeSignatureMessageV4(
            version: messageSignatureVersion,
            clientMessageId: clientMessageId,
            senderBinding: senderBinding.binding,
            recipientBinding: recipientBinding,
            messageType: messageType,
            plaintext: plaintext,
            createdAtClientMs: createdAtClientMs,
            envelopeVersion: envelopeVersion
        )
        let signingCertificate = try await MessageKeyManager.shared.currentMessageSigningCertificateV4(
            senderBinding: senderBinding.binding,
            walletManager: walletManager
        )
        let messageSignature = try MessageKeyManager.shared.signMessageEnvelope(canonicalEnvelopeMessage)

        let sealedPayload = SealedSenderMessagePayloadV4(
            body: plaintext,
            sender: senderBinding.binding,
            senderLightningAddress: senderBinding.rawLightningAddress,
            messagingSigningPubkey: signingCertificate.messagingSigningPubkey,
            messagingSigningPubkeySignature: signingCertificate.messagingSigningPubkeySignature,
            messagingSigningPubkeySignatureVersion: signingCertificate.messagingSigningPubkeySignatureVersion,
            messagingSigningPubkeySignedAt: signingCertificate.messagingSigningPubkeySignedAt,
            messageSignature: messageSignature,
            messageSignatureVersion: messageSignatureVersion
        )
        let sealedPayloadData = try JSONEncoder().encode(sealedPayload)
        guard let sealedPayloadString = String(data: sealedPayloadData, encoding: .utf8) else {
            throw MessageCryptoManager.MessageCryptoError.invalidPlaintext
        }
        return sealedPayloadString
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

private struct SenderMessagingBindingV4 {
    let binding: MessagingIdentityBindingPayloadV4
    let rawLightningAddress: String

    var walletPubkey: String { binding.walletPubkey }
}
