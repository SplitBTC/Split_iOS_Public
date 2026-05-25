//
//  MessagingPushSyncCoordinator.swift
//  Split Rewards
//
//  Created by TeeVee on 3/21/26.
//

import Foundation

@MainActor
final class MessagingPushSyncCoordinator {
    static let shared = MessagingPushSyncCoordinator()

    private weak var authManager: AuthManager?
    private weak var walletManager: WalletManager?
    private var hasPendingIncomingMessagePush = false
    private var hasPendingOutgoingStatusPush = false

    private init() {}

    func configure(
        authManager: AuthManager,
        walletManager: WalletManager
    ) {
        self.authManager = authManager
        self.walletManager = walletManager

        Task { @MainActor in
            _ = await processPendingPushIfPossible()
        }
    }

    func handleIncomingMessagePush() async -> Bool {
        hasPendingIncomingMessagePush = true
        return await processPendingPushIfPossible()
    }

    func handleOutgoingStatusPush() async -> Bool {
        hasPendingOutgoingStatusPush = true
        return await processPendingPushIfPossible()
    }

    func processPendingPushIfPossible() async -> Bool {
        guard hasPendingIncomingMessagePush || hasPendingOutgoingStatusPush else {
            return false
        }

        guard let authManager, let walletManager else {
            return false
        }

        guard case .ready = walletManager.state else {
            return false
        }

        let hadIncomingMessagePush = hasPendingIncomingMessagePush
        let hadOutgoingStatusPush = hasPendingOutgoingStatusPush

        do {
            var didProcess = false

            if hadIncomingMessagePush {
                hasPendingIncomingMessagePush = false
                let result = try await MessageSyncManager.shared.syncInboxIfNeeded(
                    authManager: authManager,
                    walletManager: walletManager,
                    force: true,
                    minimumInterval: 0
                )

                didProcess = didProcess ||
                    result.fetchedCount > 0 ||
                    result.persistedCount > 0 ||
                    result.acknowledgedCount > 0
            }

            if hadOutgoingStatusPush {
                hasPendingOutgoingStatusPush = false
                let retriedCount = try await MessageSyncManager.shared.syncOutgoingStatusesIfNeeded(
                    authManager: authManager,
                    walletManager: walletManager,
                    force: true,
                    minimumInterval: 0
                )
                didProcess = didProcess || retriedCount > 0
            }

            return didProcess
        } catch {
            if hadIncomingMessagePush {
                hasPendingIncomingMessagePush = true
            }
            if hadOutgoingStatusPush {
                hasPendingOutgoingStatusPush = true
            }
            print("Failed to process pending messaging push: \(error.localizedDescription)")
            return false
        }
    }
}
