//
//  MessageStore.swift
//  Split Rewards
//
//  Created by TeeVee on 3/20/26.
//

import Foundation
import Combine

struct StoredMessage: Identifiable, Codable, Equatable {
    enum DeliveryState: String, Codable {
        case failedSameKey = "failed_same_key"
    }

    let id: String
    let conversationId: String
    let clientMessageId: String
    let body: String
    let createdAt: Date
    let isIncoming: Bool
    let isRead: Bool
    let senderWalletPubkey: String
    let senderMessagingPubkey: String
    let senderLightningAddress: String?
    let recipientWalletPubkey: String
    let recipientMessagingPubkey: String
    let recipientLightningAddress: String
    let messageType: String
    let deliveryState: DeliveryState?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId
        case clientMessageId
        case body
        case createdAt
        case isIncoming
        case isRead
        case senderWalletPubkey
        case senderMessagingPubkey
        case senderLightningAddress
        case recipientWalletPubkey
        case recipientMessagingPubkey
        case recipientLightningAddress
        case messageType
        case deliveryState
    }

    init(
        id: String,
        conversationId: String,
        clientMessageId: String,
        body: String,
        createdAt: Date,
        isIncoming: Bool,
        isRead: Bool,
        senderWalletPubkey: String,
        senderMessagingPubkey: String,
        senderLightningAddress: String? = nil,
        recipientWalletPubkey: String,
        recipientMessagingPubkey: String,
        recipientLightningAddress: String,
        messageType: String,
        deliveryState: DeliveryState? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.clientMessageId = clientMessageId
        self.body = body
        self.createdAt = createdAt
        self.isIncoming = isIncoming
        self.isRead = isRead
        self.senderWalletPubkey = senderWalletPubkey
        self.senderMessagingPubkey = senderMessagingPubkey
        self.senderLightningAddress = senderLightningAddress
        self.recipientWalletPubkey = recipientWalletPubkey
        self.recipientMessagingPubkey = recipientMessagingPubkey
        self.recipientLightningAddress = recipientLightningAddress
        self.messageType = messageType
        self.deliveryState = deliveryState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        clientMessageId = try container.decode(String.self, forKey: .clientMessageId)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isIncoming = try container.decode(Bool.self, forKey: .isIncoming)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? !isIncoming
        senderWalletPubkey = try container.decode(String.self, forKey: .senderWalletPubkey)
        senderMessagingPubkey = try container.decode(String.self, forKey: .senderMessagingPubkey)
        senderLightningAddress = try container.decodeIfPresent(String.self, forKey: .senderLightningAddress)
        recipientWalletPubkey = try container.decode(String.self, forKey: .recipientWalletPubkey)
        recipientMessagingPubkey = try container.decode(String.self, forKey: .recipientMessagingPubkey)
        recipientLightningAddress = try container.decode(String.self, forKey: .recipientLightningAddress)
        messageType = try container.decode(String.self, forKey: .messageType)
        deliveryState = try container.decodeIfPresent(DeliveryState.self, forKey: .deliveryState)
    }
}

struct MessageConversationPreview: Identifiable, Equatable {
    let id: String
    let title: String
    let latestBody: String
    let latestAt: Date
    let hasIncomingMessages: Bool
    let hasUnreadMessages: Bool
    let hasFailedOutgoingMessage: Bool
}

@MainActor
final class MessageStore: ObservableObject {
    static let shared = MessageStore()

    @Published private(set) var messages: [StoredMessage] = []

    private let storeURL: URL
    private var needsRecoveryReload = false

    private struct LoadedMessages {
        let messages: [StoredMessage]
        let needsMigration: Bool
        let needsRecoveryReload: Bool
    }

    enum MessageStoreError: LocalizedError {
        case storeUnavailable
        case failedToCreateDirectory
        case failedToPersist

        var errorDescription: String? {
            switch self {
            case .storeUnavailable:
                return "Local messages are temporarily unavailable."
            case .failedToCreateDirectory:
                return "Could not create the local message storage directory."
            case .failedToPersist:
                return "Could not save messages locally."
            }
        }
    }

    private init() {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let messagingDirectory = baseDirectory
            .appendingPathComponent("Messaging", isDirectory: true)
            .appendingPathComponent(AppConfig.messagingPushEnvironment, isDirectory: true)
        self.storeURL = messagingDirectory.appendingPathComponent("messages.json")
        Self.migrateLegacyProdStoreIfNeeded(to: storeURL, baseDirectory: baseDirectory)
        let loadedMessages = Self.loadMessages(from: storeURL)
        self.messages = loadedMessages.messages
        self.needsRecoveryReload = loadedMessages.needsRecoveryReload

        if loadedMessages.needsMigration {
            try? persist(loadedMessages.messages)
        } else if !loadedMessages.needsRecoveryReload,
                  FileManager.default.fileExists(atPath: storeURL.path) {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: storeURL.path
            )
        }

        syncApplicationBadge(for: messages)
    }

    var unreadMessageCount: Int {
        reloadFromDiskIfNeeded()
        return messages.filter { $0.isIncoming && !$0.isRead }.count
    }

    var unreadConversationCount: Int {
        reloadFromDiskIfNeeded()
        return Set(messages.filter { $0.isIncoming && !$0.isRead }.map(\.conversationId)).count
    }

    func upsert(_ incomingMessages: [StoredMessage]) throws -> [String] {
        guard !incomingMessages.isEmpty else { return [] }
        try ensureStoreAvailableForMutation()

        var mergedById = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        let persistedIds = incomingMessages.map(\.id)

        for message in incomingMessages {
            mergedById[message.id] = message
        }

        let mergedMessages = mergedById.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }

        try persist(mergedMessages)
        messages = mergedMessages
        syncApplicationBadge(for: mergedMessages)
        return persistedIds
    }

    func containsMessage(id: String) -> Bool {
        reloadFromDiskIfNeeded()
        return messages.contains(where: { $0.id == id })
    }

    func messages(for conversationId: String) -> [StoredMessage] {
        reloadFromDiskIfNeeded()
        return messages
            .filter { $0.conversationId == conversationId }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func conversationPreviews(matching searchText: String = "") -> [MessageConversationPreview] {
        reloadFromDiskIfNeeded()
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let grouped = Dictionary(grouping: messages, by: \.conversationId)

        return grouped.compactMap { conversationId, conversationMessages in
            guard let latestMessage = conversationMessages.max(by: { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }) else {
                return nil
            }

            let title = conversationTitle(for: conversationMessages)
            let latestPreviewBody = MessagePayloadCodec.previewText(for: latestMessage)

            if !normalizedSearch.isEmpty {
                let titleMatches = title.lowercased().contains(normalizedSearch)
                let messageMatches = conversationMessages.contains { message in
                    MessagePayloadCodec
                        .searchableText(for: message)
                        .lowercased()
                        .contains(normalizedSearch)
                }

                guard titleMatches || messageMatches else {
                    return nil
                }
            }

            return MessageConversationPreview(
                id: conversationId,
                title: title,
                latestBody: latestPreviewBody,
                latestAt: latestMessage.createdAt,
                hasIncomingMessages: conversationMessages.contains(where: \.isIncoming),
                hasUnreadMessages: conversationMessages.contains(where: { $0.isIncoming && !$0.isRead }),
                hasFailedOutgoingMessage: !latestMessage.isIncoming && latestMessage.deliveryState == .failedSameKey
            )
        }
        .sorted { lhs, rhs in
            if lhs.latestAt == rhs.latestAt {
                return lhs.id < rhs.id
            }
            return lhs.latestAt > rhs.latestAt
        }
    }

    func conversationPreview(forLightningAddress lightningAddress: String) -> MessageConversationPreview? {
        let normalizedTarget = lightningAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return conversationPreviews().first { preview in
            messages(for: preview.id).contains { message in
                counterpartyLightningAddress(for: message) == normalizedTarget
            }
        }
    }

    func outgoingPaymentRequestMessage(forInvoice invoice: String) -> StoredMessage? {
        reloadFromDiskIfNeeded()
        let normalizedInvoice = invoice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedInvoice.isEmpty else { return nil }

        return messages
            .filter { !$0.isIncoming && $0.messageType == "payment_request" }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id > rhs.id
                }
                return lhs.createdAt > rhs.createdAt
            }
            .first { message in
                MessagePayloadCodec.decodePaymentRequest(from: message.body)?.invoice == normalizedInvoice
            }
    }

    func outgoingMessage(
        serverMessageId: String,
        clientMessageId: String
    ) -> StoredMessage? {
        reloadFromDiskIfNeeded()

        return messages
            .filter { !$0.isIncoming }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id > rhs.id
                }
                return lhs.createdAt > rhs.createdAt
            }
            .first { message in
                message.id == serverMessageId || message.clientMessageId == clientMessageId
            }
    }

    func replaceOutgoingMessage(
        matchingStoredMessageId storedMessageId: String,
        with replacement: StoredMessage
    ) throws {
        try ensureStoreAvailableForMutation()

        var updatedMessages = messages.filter { message in
            message.id != storedMessageId && message.id != replacement.id
        }
        updatedMessages.append(replacement)
        updatedMessages.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }

        try persist(updatedMessages)
        messages = updatedMessages
        syncApplicationBadge(for: updatedMessages)
    }

    @discardableResult
    func updateOutgoingMessageDeliveryState(
        serverMessageId: String,
        clientMessageId: String,
        deliveryState: StoredMessage.DeliveryState?
    ) throws -> Bool {
        try ensureStoreAvailableForMutation()

        var didChange = false
        let updatedMessages = messages.map { message in
            guard !message.isIncoming,
                  message.id == serverMessageId || message.clientMessageId == clientMessageId else {
                return message
            }

            guard message.deliveryState != deliveryState else {
                return message
            }

            didChange = true
            return StoredMessage(
                id: message.id,
                conversationId: message.conversationId,
                clientMessageId: message.clientMessageId,
                body: message.body,
                createdAt: message.createdAt,
                isIncoming: message.isIncoming,
                isRead: message.isRead,
                senderWalletPubkey: message.senderWalletPubkey,
                senderMessagingPubkey: message.senderMessagingPubkey,
                senderLightningAddress: message.senderLightningAddress,
                recipientWalletPubkey: message.recipientWalletPubkey,
                recipientMessagingPubkey: message.recipientMessagingPubkey,
                recipientLightningAddress: message.recipientLightningAddress,
                messageType: message.messageType,
                deliveryState: deliveryState
            )
        }

        guard didChange else {
            return false
        }

        try persist(updatedMessages)
        messages = updatedMessages
        syncApplicationBadge(for: updatedMessages)
        return true
    }

    func hasPaymentRequestPaidMarker(forRequestMessageId requestMessageId: String) -> Bool {
        reloadFromDiskIfNeeded()
        return messages.contains { message in
            guard message.messageType == "payment_request_paid",
                  let payload = MessagePayloadCodec.decodePaymentRequestPaid(from: message.body) else {
                return false
            }

            return payload.requestMessageId == requestMessageId
        }
    }

    func deleteConversation(id conversationId: String) throws {
        try ensureStoreAvailableForMutation()
        let filteredMessages = messages.filter { $0.conversationId != conversationId }

        guard filteredMessages.count != messages.count else {
            return
        }

        try persist(filteredMessages)
        messages = filteredMessages
        syncApplicationBadge(for: filteredMessages)
    }

    func markConversationAsRead(id conversationId: String) throws {
        try ensureStoreAvailableForMutation()
        let updatedMessages = messages.map { message in
            guard message.conversationId == conversationId,
                  message.isIncoming,
                  !message.isRead else {
                return message
            }

            return StoredMessage(
                id: message.id,
                conversationId: message.conversationId,
                clientMessageId: message.clientMessageId,
                body: message.body,
                createdAt: message.createdAt,
                isIncoming: message.isIncoming,
                isRead: true,
                senderWalletPubkey: message.senderWalletPubkey,
                senderMessagingPubkey: message.senderMessagingPubkey,
                senderLightningAddress: message.senderLightningAddress,
                recipientWalletPubkey: message.recipientWalletPubkey,
                recipientMessagingPubkey: message.recipientMessagingPubkey,
                recipientLightningAddress: message.recipientLightningAddress,
                messageType: message.messageType,
                deliveryState: message.deliveryState
            )
        }

        guard updatedMessages != messages else {
            return
        }

        try persist(updatedMessages)
        messages = updatedMessages
        syncApplicationBadge(for: updatedMessages)
    }

    func clearAll() {
        needsRecoveryReload = false
        messages = []
        syncApplicationBadge(for: [])

        do {
            if FileManager.default.fileExists(atPath: storeURL.path) {
                try FileManager.default.removeItem(at: storeURL)
            }
        } catch {
            print("Failed to clear stored messages: \(error.localizedDescription)")
        }
    }

    private func persist(_ messages: [StoredMessage]) throws {
        let directory = storeURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw MessageStoreError.failedToCreateDirectory
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        do {
            let data = try encoder.encode(messages)
            let encryptedData = try SecureMessagingStorage.shared.encrypt(data)
            try encryptedData.write(to: storeURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: storeURL.path
            )
        } catch {
            throw MessageStoreError.failedToPersist
        }
    }

    private static func loadMessages(from url: URL) -> LoadedMessages {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LoadedMessages(messages: [], needsMigration: false, needsRecoveryReload: false)
        }

        guard let data = try? Data(contentsOf: url) else {
            print("⚠️ [MessageStore] Message file exists but could not be read. Deferring reload instead of clearing messages.")
            return LoadedMessages(messages: [], needsMigration: false, needsRecoveryReload: true)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if SecureMessagingStorage.shared.isEncryptedPayload(data) {
            guard let decryptedData = try? SecureMessagingStorage.shared.decrypt(data),
                  let decodedMessages = try? decoder.decode([StoredMessage].self, from: decryptedData) else {
                print("⚠️ [MessageStore] Existing encrypted message store could not be decrypted or decoded. Deferring reload instead of clearing messages.")
                return LoadedMessages(messages: [], needsMigration: false, needsRecoveryReload: true)
            }

            return LoadedMessages(messages: decodedMessages, needsMigration: false, needsRecoveryReload: false)
        }

        if let decodedMessages = try? decoder.decode([StoredMessage].self, from: data) {
            return LoadedMessages(messages: decodedMessages, needsMigration: true, needsRecoveryReload: false)
        }

        print("⚠️ [MessageStore] Existing plaintext message store could not be decoded. Deferring reload instead of clearing messages.")
        return LoadedMessages(messages: [], needsMigration: false, needsRecoveryReload: true)
    }

    private static func migrateLegacyProdStoreIfNeeded(to storeURL: URL, baseDirectory: URL) {
        guard AppConfig.messagingPushEnvironment == "prod",
              !FileManager.default.fileExists(atPath: storeURL.path)
        else {
            return
        }

        let legacyURL = baseDirectory
            .appendingPathComponent("Messaging", isDirectory: true)
            .appendingPathComponent("messages.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try FileManager.default.copyItem(at: legacyURL, to: storeURL)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: storeURL.path
            )
            print("MessageStore: copied legacy shared message store into prod-scoped store.")
        } catch {
            print("MessageStore: legacy prod message migration skipped. \(error.localizedDescription)")
        }
    }

    private func ensureStoreAvailableForMutation() throws {
        reloadFromDiskIfNeeded()

        if needsRecoveryReload {
            throw MessageStoreError.storeUnavailable
        }
    }

    private func reloadFromDiskIfNeeded() {
        guard needsRecoveryReload else { return }

        let loadedMessages = Self.loadMessages(from: storeURL)
        guard !loadedMessages.needsRecoveryReload else { return }

        needsRecoveryReload = false
        messages = loadedMessages.messages
        syncApplicationBadge(for: loadedMessages.messages)

        if loadedMessages.needsMigration {
            try? persist(loadedMessages.messages)
        } else if FileManager.default.fileExists(atPath: storeURL.path) {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: storeURL.path
            )
        }
    }

    private func conversationTitle(for messages: [StoredMessage]) -> String {
        if let outgoing = messages.last(where: { !$0.isIncoming && !$0.recipientLightningAddress.isEmpty }) {
            return outgoing.recipientLightningAddress
        }

        if let incoming = messages.last(where: { $0.isIncoming && !(($0.senderLightningAddress ?? "").isEmpty) }) {
            return incoming.senderLightningAddress ?? "Conversation"
        }

        if let incoming = messages.last(where: { $0.isIncoming }) {
            let pubkey = incoming.senderWalletPubkey
            if pubkey.count > 16 {
                return "\(pubkey.prefix(8))...\(pubkey.suffix(8))"
            }
            return pubkey
        }

        return "Conversation"
    }

    private func counterpartyLightningAddress(for message: StoredMessage) -> String? {
        let rawAddress = message.isIncoming
            ? (message.senderLightningAddress ?? "")
            : message.recipientLightningAddress

        let normalized = rawAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalized.isEmpty ? nil : normalized
    }

    private func syncApplicationBadge(for messages: [StoredMessage]) {
        MessagingNotificationBadgeManager.shared.syncUnreadMessageCount(
            messages.filter { $0.isIncoming && !$0.isRead }.count
        )
    }
}
