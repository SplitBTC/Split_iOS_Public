//
//  MessageSyncManager.swift
//  Split Rewards
//
//  Created by TeeVee on 3/20/26.
//

import Foundation

@MainActor
final class MessageSyncManager {
    static let shared = MessageSyncManager()

    private var inFlightSyncTask: Task<SyncResult, Error>?
    private var inFlightOutgoingStatusSyncTask: Task<Int, Error>?
    private var lastSuccessfulSyncAt: Date?
    private var lastSuccessfulOutgoingStatusSyncAt: Date?
    private let defaultMinimumInterval: TimeInterval = 5
    private let defaultOutgoingStatusMinimumInterval: TimeInterval = 30

    private init() {}

    private enum InboxRecoveryFailureReason: String {
        case invalidStoredKey
        case ciphertextDecryptFailed
        case sealedPayloadDecodeFailed
        case sealedEnvelopeVerificationFailed

        var shouldRotateMessagingIdentity: Bool {
            switch self {
            case .invalidStoredKey, .ciphertextDecryptFailed:
                return true
            case .sealedPayloadDecodeFailed, .sealedEnvelopeVerificationFailed:
                return false
            }
        }
    }

    private struct InboxRecoveryCandidate {
        let message: InboxMessage
        let reason: InboxRecoveryFailureReason
    }

    struct SyncResult {
        let fetchedCount: Int
        let persistedCount: Int
        let acknowledgedCount: Int
        let failedCount: Int
        let retriedCount: Int
    }

    private static let emptyResult = SyncResult(
        fetchedCount: 0,
        persistedCount: 0,
        acknowledgedCount: 0,
        failedCount: 0,
        retriedCount: 0
    )

    func syncInboxIfNeeded(
        authManager: AuthManager,
        walletManager: WalletManager,
        force: Bool = false,
        minimumInterval: TimeInterval? = nil
    ) async throws -> SyncResult {
        if let inFlightSyncTask {
            return try await inFlightSyncTask.value
        }

        let threshold = minimumInterval ?? defaultMinimumInterval
        if !force,
           let lastSuccessfulSyncAt,
           Date().timeIntervalSince(lastSuccessfulSyncAt) < threshold {
            return Self.emptyResult
        }

        let task = Task { @MainActor [weak self] in
            let result = try await self?.syncInbox(
                authManager: authManager,
                walletManager: walletManager
            ) ?? Self.emptyResult
            self?.lastSuccessfulSyncAt = Date()
            return result
        }

        inFlightSyncTask = task
        defer { inFlightSyncTask = nil }

        return try await task.value
    }

    func syncInboxIfPossible(
        authManager: AuthManager,
        walletManager: WalletManager,
        force: Bool = false,
        minimumInterval: TimeInterval? = nil
    ) async {
        do {
            _ = try await syncInboxIfNeeded(
                authManager: authManager,
                walletManager: walletManager,
                force: force,
                minimumInterval: minimumInterval
            )
        } catch {
            guard !MessageKeyManager.shared.shouldSilentlyDeferActivation(for: error) else {
                return
            }
            print("Failed to sync inbox: \(error.localizedDescription)")
        }
    }

    func syncOutgoingStatusesIfNeeded(
        authManager: AuthManager,
        walletManager: WalletManager,
        force: Bool = false,
        minimumInterval: TimeInterval? = nil
    ) async throws -> Int {
        if let inFlightOutgoingStatusSyncTask {
            return try await inFlightOutgoingStatusSyncTask.value
        }

        let threshold = minimumInterval ?? defaultOutgoingStatusMinimumInterval
        if !force,
           let lastSuccessfulOutgoingStatusSyncAt,
           Date().timeIntervalSince(lastSuccessfulOutgoingStatusSyncAt) < threshold {
            return 0
        }

        let task = Task { @MainActor [weak self] in
            let result = try await self?.syncOutgoingStatuses(
                authManager: authManager,
                walletManager: walletManager
            ) ?? 0
            self?.lastSuccessfulOutgoingStatusSyncAt = Date()
            return result
        }

        inFlightOutgoingStatusSyncTask = task
        defer { inFlightOutgoingStatusSyncTask = nil }

        return try await task.value
    }

    func syncOutgoingStatusesIfPossible(
        authManager: AuthManager,
        walletManager: WalletManager,
        force: Bool = false,
        minimumInterval: TimeInterval? = nil
    ) async {
        do {
            _ = try await syncOutgoingStatusesIfNeeded(
                authManager: authManager,
                walletManager: walletManager,
                force: force,
                minimumInterval: minimumInterval
            )
        } catch {
            guard !MessageKeyManager.shared.shouldSilentlyDeferActivation(for: error) else {
                return
            }
            print("Failed to sync outgoing message statuses: \(error.localizedDescription)")
        }
    }

    func syncInbox(
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> SyncResult {
        let inboxMessages = try await MessagesInboxAPI.fetchMessages(
            authManager: authManager,
            walletManager: walletManager
        )

        var decryptedMessages: [StoredMessage] = []
        var failedCount = 0
        var recoveryCandidates: [InboxRecoveryCandidate] = []

        for inboxMessage in inboxMessages {
            do {
                let storedMessage: StoredMessage
                if inboxMessage.envelopeVersion >= 3 {
                    let sealedPayload = try decryptSealedPayload(for: inboxMessage)
                    try MessageKeyBindingVerifier.verifySealedIncomingEnvelope(
                        inboxMessage,
                        sealedPayload: sealedPayload
                    )
                    storedMessage = StoredMessage(
                        id: inboxMessage.id,
                        conversationId: sealedPayload.sender.walletPubkey,
                        clientMessageId: inboxMessage.clientMessageId,
                        body: sealedPayload.body,
                        createdAt: inboxMessage.createdAtClient ?? inboxMessage.createdAt ?? Date(),
                        isIncoming: true,
                        isRead: false,
                        senderWalletPubkey: sealedPayload.sender.walletPubkey,
                        senderMessagingPubkey: sealedPayload.sender.messagingPubkey,
                        senderLightningAddress: sealedPayload.sender.lightningAddress,
                        recipientWalletPubkey: inboxMessage.recipientWalletPubkey,
                        recipientMessagingPubkey: inboxMessage.recipientMessagingPubkey,
                        recipientLightningAddress: inboxMessage.recipientLightningAddress,
                        messageType: inboxMessage.messageType
                    )
                } else {
                    try MessageKeyBindingVerifier.verifyIncomingEnvelope(inboxMessage)
                    let plaintext = try MessageCryptoManager.shared.decrypt(inboxMessage)
                    storedMessage = StoredMessage(
                        id: inboxMessage.id,
                        conversationId: inboxMessage.senderWalletPubkey,
                        clientMessageId: inboxMessage.clientMessageId,
                        body: plaintext,
                        createdAt: inboxMessage.createdAtClient ?? inboxMessage.createdAt ?? Date(),
                        isIncoming: true,
                        isRead: false,
                        senderWalletPubkey: inboxMessage.senderWalletPubkey,
                        senderMessagingPubkey: inboxMessage.senderMessagingPubkey,
                        senderLightningAddress: inboxMessage.senderLightningAddress,
                        recipientWalletPubkey: inboxMessage.recipientWalletPubkey,
                        recipientMessagingPubkey: inboxMessage.recipientMessagingPubkey,
                        recipientLightningAddress: inboxMessage.recipientLightningAddress,
                        messageType: inboxMessage.messageType
                    )
                }
                decryptedMessages.append(storedMessage)
            } catch {
                failedCount += 1
                if let reason = serverRecoveryFailureReason(for: error) {
                    recoveryCandidates.append(InboxRecoveryCandidate(
                        message: inboxMessage,
                        reason: reason
                    ))
                }
            }
        }

        let persistedIds = try MessageStore.shared.upsert(decryptedMessages)
        if !recoveryCandidates.isEmpty {
            let currentMessagingPubkey: String?
            do {
                _ = try await MessageKeyManager.shared.ensureRegistered(
                    authManager: authManager,
                    walletManager: walletManager
                )
                await MessagingDeviceTokenManager.shared.syncDeviceTokenIfPossible(
                    authManager: authManager,
                    walletManager: walletManager,
                    force: true
                )
                currentMessagingPubkey = try? MessageKeyManager.shared.currentMessagingPublicKeyHex()
            } catch {
                print("Failed to realign messaging identity before requesting rekey: \(error.localizedDescription)")
                currentMessagingPubkey = nil
            }

            let rekeyRequiredMessageIds = recoveryCandidates.compactMap { candidate in
                shouldRequestRekey(
                    for: candidate.message,
                    currentMessagingPubkey: currentMessagingPubkey
                )
                    ? candidate.message.id
                    : nil
            }
            let decryptFailedCandidates = recoveryCandidates.filter { candidate in
                shouldMarkDecryptFailed(
                    for: candidate.message,
                    currentMessagingPubkey: currentMessagingPubkey
                )
            }
            let decryptFailedMessageIds = decryptFailedCandidates.map { $0.message.id }
            let decryptFailedReasons = Dictionary(
                uniqueKeysWithValues: decryptFailedCandidates.map { candidate in
                    (candidate.message.id, candidate.reason.rawValue)
                }
            )

            if !rekeyRequiredMessageIds.isEmpty {
                _ = try await RekeyMessagesAPI.markMessagesRekeyRequired(
                    messageIds: rekeyRequiredMessageIds,
                    authManager: authManager,
                    walletManager: walletManager
                )
            }

            if !decryptFailedMessageIds.isEmpty {
                _ = try await DecryptFailedMessagesAPI.markMessagesDecryptFailed(
                    messageIds: decryptFailedMessageIds,
                    failureReasons: decryptFailedReasons,
                    authManager: authManager,
                    walletManager: walletManager
                )
                if decryptFailedCandidates.contains(where: { $0.reason.shouldRotateMessagingIdentity }) {
                    do {
                        _ = try await MessageKeyManager.shared.rotateMessagingIdentityAfterSameKeyFailure(
                            authManager: authManager,
                            walletManager: walletManager,
                            reason: "same-key \(decryptFailedReasons.values.sorted().joined(separator: ","))"
                        )
                        await MessagingDeviceTokenManager.shared.syncDeviceTokenIfPossible(
                            authManager: authManager,
                            walletManager: walletManager,
                            force: true
                        )
                    } catch {
                        print("Failed to rotate messaging identity after same-key failure: \(error.localizedDescription)")
                    }
                }
            }
        }
        let ackResponse = try await AckMessagesAPI.acknowledgeMessages(
            messageIds: persistedIds,
            authManager: authManager,
            walletManager: walletManager
        )

        return SyncResult(
            fetchedCount: inboxMessages.count,
            persistedCount: persistedIds.count,
            acknowledgedCount: ackResponse.acknowledgedCount,
            failedCount: failedCount,
            retriedCount: 0
        )
    }

    func syncOutgoingStatuses(
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> Int {
        guard MessageStore.shared.messages.contains(where: { !$0.isIncoming }) else {
            return 0
        }

        let statuses = try await OutgoingMessageStatusesAPI.fetchOutgoingStatuses(
            limit: 200,
            authManager: authManager,
            walletManager: walletManager
        )

        var processedCount = 0
        for status in statuses {
            guard let localMessage = MessageStore.shared.outgoingMessage(
                serverMessageId: status.id,
                clientMessageId: status.clientMessageId
            ) else {
                continue
            }

            switch status.status {
            case "rekey_required":
                do {
                    guard let resentResult = try await MessagingSendCoordinator.resendStoredMessageIfNeeded(
                        localMessage,
                        authManager: authManager,
                        walletManager: walletManager
                    ) else {
                        continue
                    }

                    try MessageStore.shared.replaceOutgoingMessage(
                        matchingStoredMessageId: localMessage.id,
                        with: resentResult.storedMessage
                    )
                    processedCount += 1
                } catch {
                    print("Failed to resend rekey-required message \(status.id): \(error.localizedDescription)")
                }
            case "same_key_retry_required":
                do {
                    guard let resentResult = try await MessagingSendCoordinator.resendStoredMessageIfNeeded(
                        localMessage,
                        authManager: authManager,
                        walletManager: walletManager,
                        sameKeyRetryCount: 1
                    ) else {
                        continue
                    }

                    try MessageStore.shared.replaceOutgoingMessage(
                        matchingStoredMessageId: localMessage.id,
                        with: resentResult.storedMessage
                    )
                    processedCount += 1
                } catch {
                    print("Failed to resend same-key retry-required message \(status.id): \(error.localizedDescription)")
                }
            case "failed_same_key", "undelivered":
                do {
                    let didUpdate = try MessageStore.shared.updateOutgoingMessageDeliveryState(
                        serverMessageId: status.id,
                        clientMessageId: status.clientMessageId,
                        deliveryState: .failedSameKey
                    )
                    if didUpdate {
                        processedCount += 1
                    }
                } catch {
                    print("Failed to mark message \(status.id) as failed: \(error.localizedDescription)")
                }
            default:
                continue
            }
        }

        return processedCount
    }

    private func decryptSealedPayload(
        for message: InboxMessage
    ) throws -> SealedSenderMessagePayload {
        let sealedPayloadString = try MessageCryptoManager.shared.decrypt(message)
        guard let sealedPayloadData = sealedPayloadString.data(using: .utf8) else {
            throw MessageCryptoManager.MessageCryptoError.invalidPlaintext
        }

        return try JSONDecoder().decode(SealedSenderMessagePayload.self, from: sealedPayloadData)
    }

    private func serverRecoveryFailureReason(for error: Error) -> InboxRecoveryFailureReason? {
        if let messageKeyError = error as? MessageKeyManager.MessageKeyError,
           case .invalidStoredKey = messageKeyError {
            return .invalidStoredKey
        }

        if error is MessageKeyBindingVerifier.VerificationError {
            return .sealedEnvelopeVerificationFailed
        }

        if error is DecodingError {
            return .sealedPayloadDecodeFailed
        }

        if error is MessageCryptoManager.MessageCryptoError {
            return .ciphertextDecryptFailed
        }

        return nil
    }

    private func shouldRequestRekey(
        for message: InboxMessage,
        currentMessagingPubkey: String?
    ) -> Bool {
        let normalizedCurrentMessagingPubkey = currentMessagingPubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalizedCurrentMessagingPubkey,
              !normalizedCurrentMessagingPubkey.isEmpty else {
            return false
        }

        let normalizedMessageRecipientMessagingPubkey = message.recipientMessagingPubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedMessageRecipientMessagingPubkey != normalizedCurrentMessagingPubkey
    }

    private func shouldMarkDecryptFailed(
        for message: InboxMessage,
        currentMessagingPubkey: String?
    ) -> Bool {
        let normalizedCurrentMessagingPubkey = currentMessagingPubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalizedCurrentMessagingPubkey,
              !normalizedCurrentMessagingPubkey.isEmpty else {
            return false
        }

        let normalizedMessageRecipientMessagingPubkey = message.recipientMessagingPubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedMessageRecipientMessagingPubkey == normalizedCurrentMessagingPubkey
    }

}
