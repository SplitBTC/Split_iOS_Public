//
//  SupportView.swift
//  Split Rewards
//
//  Created by TeeVee on 3/24/26.
//

import SwiftUI

struct SupportView: View {
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var messageStore = MessageStore.shared

    private let background = Color.black
    private let heroSurface = Color.splitInputSurface
    private let accentBlue = Color.splitBrandBlue
    private let accentPink = Color.splitBrandPink
    private let supportLightningAddress = "support@example.com"
    private let supportDisplayName = "Support"

    @State private var showComposeSheet = false
    @State private var pendingThreadAfterCompose: ActiveThreadDestination?
    @State private var activeThread: ActiveThreadDestination?

    private struct ActiveThreadDestination: Hashable, Identifiable {
        let conversationId: String
        let title: String
        let lightningAddress: String

        var id: String { conversationId }
    }

    private var existingSupportThread: ActiveThreadDestination? {
        guard let existingConversation = messageStore.conversationPreview(forLightningAddress: supportLightningAddress) else {
            return nil
        }

        return ActiveThreadDestination(
            conversationId: existingConversation.id,
            title: existingConversation.title,
            lightningAddress: supportLightningAddress
        )
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    contactButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $activeThread) { thread in
            MessageThreadView(
                conversationId: thread.conversationId,
                title: thread.title,
                lightningAddress: thread.lightningAddress
            )
        }
        .sheet(isPresented: $showComposeSheet, onDismiss: {
            if let pendingThreadAfterCompose {
                activeThread = pendingThreadAfterCompose
                self.pendingThreadAfterCompose = nil
            }
        }) {
            ComposeMessage(
                prefilledLightningAddress: supportLightningAddress,
                onSent: { result in
                    pendingThreadAfterCompose = ActiveThreadDestination(
                        conversationId: result.conversationId,
                        title: supportDisplayName,
                        lightningAddress: result.lightningAddress
                    )
                }
            )
            .environmentObject(walletManager)
            .environmentObject(authManager)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentBlue,
                                accentPink
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Support")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)

                    Text("Thank you for using Split. Please do not hesitate to reach out at any time with any suggestions, comments, questions, concerns, bugs, feedback, or product ideas.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
            }
            .frame(minHeight: 194)

            HStack(spacing: 10) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.88))

                Text(supportLightningAddress)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(heroSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private var contactButton: some View {
        Button(action: openSupportConversation) {
            HStack {
                Spacer()

                Image(systemName: "message.fill")
                    .font(.headline.weight(.semibold))

                Text(existingSupportThread == nil ? "Message Support" : "Open Support Chat")
                    .font(.headline.weight(.semibold))

                Spacer()
            }
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(accentPink)
            )
        }
        .buttonStyle(.plain)
    }

    private func openSupportConversation() {
        if let existingSupportThread {
            activeThread = existingSupportThread
        } else {
            showComposeSheet = true
        }
    }
}

#Preview {
    NavigationStack {
        SupportView()
            .environmentObject(WalletManager())
            .environmentObject(AuthManager())
    }
}
