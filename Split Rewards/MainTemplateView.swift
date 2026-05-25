//
//  MainTemplateView.swift
//  Split Rewards
//
//  Created by TeeVee on 1/20/25.
//

import SwiftUI

struct MainTemplateView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var messagingNotificationRouter = MessagingNotificationRouter.shared

    @State private var selectedTab: NavBarView.Tab = .wallet

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderView()
                NavBarView(selectedTab: $selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationBarBackButtonHidden(true)
        }
        .preferredColorScheme(.dark)
        .task {
            await syncMessagesIfPossible(force: true)
            await syncOutgoingStatusesIfPossible(force: true)
            activateMessagesTabIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await syncMessagesIfPossible(force: true)
                    await syncOutgoingStatusesIfPossible(force: true)
                }
            }
        }
        .onChange(of: messagingNotificationRouter.pendingRoute?.id) { _, _ in
            activateMessagesTabIfNeeded()
        }
    }

    @MainActor
    private func syncMessagesIfPossible(force: Bool) async {
        guard case .ready = walletManager.state else { return }
        await MessageSyncManager.shared.syncInboxIfPossible(
            authManager: authManager,
            walletManager: walletManager,
            force: force
        )
        _ = await MessagingPushSyncCoordinator.shared.processPendingPushIfPossible()
    }

    @MainActor
    private func syncOutgoingStatusesIfPossible(force: Bool) async {
        guard case .ready = walletManager.state else { return }
        await MessageSyncManager.shared.syncOutgoingStatusesIfPossible(
            authManager: authManager,
            walletManager: walletManager,
            force: force
        )
        _ = await MessagingPushSyncCoordinator.shared.processPendingPushIfPossible()
    }

    @MainActor
    private func activateMessagesTabIfNeeded() {
        if messagingNotificationRouter.pendingRoute != nil {
            selectedTab = .messages
        }
    }
}

struct MainTemplateView_Previews: PreviewProvider {
    static var previews: some View {
        MainTemplateView()
    }
}
