//
//  MessagingNotificationRouter.swift
//  Split Rewards
//
//  Created by TeeVee on 3/28/26.
//

import Foundation

@MainActor
final class MessagingNotificationRouter: ObservableObject {
    static let shared = MessagingNotificationRouter()

    struct RouteRequest: Identifiable, Equatable {
        let id = UUID()
        let conversationId: String
    }

    @Published private(set) var pendingRoute: RouteRequest?

    private init() {}

    func queueConversationRoute(_ conversationId: String?) {
        let normalizedConversationId = conversationId?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let normalizedConversationId,
              !normalizedConversationId.isEmpty else {
            return
        }

        pendingRoute = RouteRequest(conversationId: normalizedConversationId)
    }

    func consume(_ request: RouteRequest) {
        guard pendingRoute?.id == request.id else { return }
        pendingRoute = nil
    }
}
