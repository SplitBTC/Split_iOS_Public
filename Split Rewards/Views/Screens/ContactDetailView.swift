//
//  ContactDetailView.swift
//  Split Rewards
//
//  Created by TeeVee on 3/22/26.
//

import SwiftUI

struct ContactDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var messageStore = MessageStore.shared

    @State private var contact: WalletManager.WalletContact
    @State private var isMessagingAvailable = false
    @State private var resolvedRecipient: MessagingRecipient?
    @State private var activeBlock: MessagingBlockedUser?
    @State private var profilePicUrl = ""
    @State private var showPaymentFlow = false
    @State private var showComposeSheet = false
    @State private var isUpdatingBlockState = false
    @State private var blockActionError: String?
    @State private var showBlockConfirmation = false
    @State private var showUnblockConfirmation = false
    @State private var pendingThreadAfterCompose: ActiveThreadDestination?
    @State private var activeThread: ActiveThreadDestination?

    private let background = Color.black
    private let actionSurface = Color.splitInputSurface

    private struct ActiveThreadDestination: Hashable, Identifiable {
        let conversationId: String
        let title: String
        let lightningAddress: String

        var id: String { conversationId }
    }

    init(contact: WalletManager.WalletContact) {
        _contact = State(initialValue: contact)
    }

    private var existingConversationDestination: ActiveThreadDestination? {
        guard let existingConversation = messageStore.conversationPreview(forLightningAddress: contact.paymentIdentifier) else {
            return nil
        }

        return ActiveThreadDestination(
            conversationId: existingConversation.id,
            title: existingConversation.title,
            lightningAddress: contact.paymentIdentifier
        )
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Spacer()

                VStack(spacing: 12) {
                    if hasProfilePic, let url = URL(string: profilePicUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                EmptyView()
                            }
                        }
                        .frame(width: 104, height: 104)
                        .clipShape(Circle())
                    }

                    Text(contact.name)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(contact.paymentIdentifier)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                HStack(spacing: 20) {
                    messageActionButton
                    paymentActionButton
                    blockActionButton
                }
                .padding(.top, 28)
                .padding(.horizontal, 20)

                if let blockActionError {
                    Text(blockActionError)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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
                prefilledLightningAddress: contact.paymentIdentifier,
                onSent: { result in
                    pendingThreadAfterCompose = ActiveThreadDestination(
                        conversationId: result.conversationId,
                        title: contact.name,
                        lightningAddress: result.lightningAddress
                    )
                }
            )
            .environmentObject(walletManager)
            .environmentObject(authManager)
        }
        .confirmationDialog("Block User", isPresented: $showBlockConfirmation, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task {
                    await blockCurrentUser()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won’t be able to message you, and you won’t be able to message them until you unblock them.")
        }
        .confirmationDialog("Unblock User", isPresented: $showUnblockConfirmation, titleVisibility: .visible) {
            Button("Unblock") {
                Task {
                    await unblockCurrentUser()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will let you message each other again.")
        }
        .task(id: contact.paymentIdentifier) {
            await refreshScreenState()
        }
        .fullScreenCover(isPresented: $showPaymentFlow) {
            NavigationStack {
                SendToView(prefilledRecipientInput: contact.paymentIdentifier)
            }
            .environmentObject(walletManager)
        }
    }

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))

                    Text("Back")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            Spacer()

            NavigationLink(
                destination: EditContactView(
                    contact: contact,
                    onUpdated: { updated in
                        contact = updated
                    },
                    onDeleted: {
                        dismiss()
                    }
                )
            ) {
                Text("Edit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var hasProfilePic: Bool {
        !profilePicUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func iconActionLabel(
        systemName: String,
        foregroundColor: Color = .white
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(foregroundColor)
            .frame(width: 64, height: 64)
            .background(
                Circle()
                    .fill(actionSurface)
            )
    }

    @ViewBuilder
    private var messageActionButton: some View {
        if activeBlock != nil {
            Button(action: {}) {
                iconActionLabel(systemName: "message.fill")
                    .opacity(0.35)
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityLabel("Messaging is blocked for this user")
        } else if let existingConversationDestination {
            Button {
                activeThread = existingConversationDestination
            } label: {
                iconActionLabel(systemName: "message.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Message contact")
        } else if isMessagingAvailable {
            Button {
                showComposeSheet = true
            } label: {
                iconActionLabel(systemName: "message.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Message contact")
        } else {
            Button(action: {}) {
                iconActionLabel(systemName: "message.fill")
                    .opacity(0.35)
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityLabel("Messaging unavailable for this contact")
        }
    }

    private var paymentActionButton: some View {
        Button {
            showPaymentFlow = true
        } label: {
            iconActionLabel(systemName: "bolt.fill")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Payment options")
    }

    private var blockActionButton: some View {
        Button {
            blockActionError = nil
            if activeBlock == nil {
                showBlockConfirmation = true
            } else {
                showUnblockConfirmation = true
            }
        } label: {
            iconActionLabel(
                systemName: "nosign",
                foregroundColor: activeBlock == nil ? .white : .splitBrandPink
            )
                .overlay {
                    if isUpdatingBlockState {
                        ProgressView()
                            .tint(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingBlockState)
        .accessibilityLabel(activeBlock == nil ? "Block user" : "Unblock user")
    }

    @MainActor
    private func refreshScreenState() async {
        blockActionError = nil
        await refreshBlockState()

        guard activeBlock == nil else {
            isMessagingAvailable = false
            resolvedRecipient = nil
            profilePicUrl = activeBlock?.blockedProfilePicUrl?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return
        }

        await refreshMessagingAvailability()
    }

    @MainActor
    private func refreshMessagingAvailability() async {
        do {
            let recipient = try await ResolveMessageRecipientAPI.resolveRecipient(
                lightningAddress: contact.paymentIdentifier,
                authManager: authManager,
                walletManager: walletManager
            )
            resolvedRecipient = recipient
            isMessagingAvailable = true
            profilePicUrl = recipient.profilePicUrl?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            resolvedRecipient = nil
            isMessagingAvailable = false
            profilePicUrl = ""
        }
    }

    @MainActor
    private func refreshBlockState() async {
        let normalizedPaymentIdentifier = contact.paymentIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        do {
            let blocks = try await MessagingBlockAPI.fetchBlocks(
                authManager: authManager,
                walletManager: walletManager
            )
            activeBlock = blocks.first(where: { block in
                if let resolvedRecipient,
                   block.blockedWalletPubkey == resolvedRecipient.walletPubkey {
                    return true
                }

                return block.normalizedLightningAddress == normalizedPaymentIdentifier
            })
        } catch {
            activeBlock = nil
        }
    }

    @MainActor
    private func blockCurrentUser() async {
        isUpdatingBlockState = true
        blockActionError = nil

        do {
            let block = try await MessagingBlockAPI.blockUser(
                walletPubkey: resolvedRecipient?.walletPubkey,
                lightningAddress: contact.paymentIdentifier,
                authManager: authManager,
                walletManager: walletManager
            )
            activeBlock = block
            isMessagingAvailable = false
            resolvedRecipient = nil
            profilePicUrl = block.blockedProfilePicUrl?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? profilePicUrl
        } catch {
            blockActionError = error.localizedDescription
        }

        isUpdatingBlockState = false
    }

    @MainActor
    private func unblockCurrentUser() async {
        guard let blockedWalletPubkey = activeBlock?.blockedWalletPubkey else {
            return
        }

        isUpdatingBlockState = true
        blockActionError = nil

        do {
            _ = try await MessagingBlockAPI.unblockUser(
                blockedWalletPubkey: blockedWalletPubkey,
                authManager: authManager,
                walletManager: walletManager
            )
            activeBlock = nil
            await refreshMessagingAvailability()
        } catch {
            blockActionError = error.localizedDescription
        }

        isUpdatingBlockState = false
    }
}

#Preview {
    NavigationStack {
        ContactDetailView(
            contact: WalletManager.WalletContact(
                id: "1",
                name: "Alice",
                paymentIdentifier: "alice@example.com",
                createdAt: .now,
                updatedAt: .now
            )
        )
    }
    .environmentObject(WalletManager())
    .environmentObject(AuthManager())
}
