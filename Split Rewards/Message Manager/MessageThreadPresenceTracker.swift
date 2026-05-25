//
//  MessageThreadPresenceTracker.swift
//  Split Rewards
//
//  Created by TeeVee on 4/12/26.
//

import Foundation

final class MessageThreadPresenceTracker {
    static let shared = MessageThreadPresenceTracker()

    private let lock = NSLock()
    private var activeConversationId: String?

    private init() {}

    func enterConversation(_ conversationId: String?) {
        let normalizedConversationId = normalize(conversationId)

        lock.lock()
        activeConversationId = normalizedConversationId
        lock.unlock()
    }

    func leaveConversation(_ conversationId: String?) {
        let normalizedConversationId = normalize(conversationId)

        lock.lock()
        defer { lock.unlock() }

        guard activeConversationId == normalizedConversationId else {
            return
        }

        activeConversationId = nil
    }

    func shouldSuppressNotification(for conversationId: String?) -> Bool {
        guard let normalizedConversationId = normalize(conversationId) else {
            return false
        }

        lock.lock()
        defer { lock.unlock() }

        return activeConversationId == normalizedConversationId
    }

    private func normalize(_ conversationId: String?) -> String? {
        guard let conversationId else {
            return nil
        }

        let trimmedConversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedConversationId.isEmpty else {
            return nil
        }

        return trimmedConversationId.lowercased()
    }
}
