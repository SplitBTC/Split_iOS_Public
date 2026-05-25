//
//  MessageView.swift
//  Split Rewards
//
//  Created by TeeVee on 3/20/26.
//

import SwiftUI

struct MessageView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var messageStore = MessageStore.shared
    @ObservedObject private var messagingNotificationRouter = MessagingNotificationRouter.shared

    private let background = Color.black
    private let composePink = Color.splitBrandPink
    @State private var searchText = ""
    @State private var contactNamesByIdentifier: [String: String] = [:]
    @State private var profilePicUrlsByIdentifier: [String: String] = [:]
    @State private var navigationPath: [ActiveThreadDestination] = []
    @State private var showComposeSheet = false
    @State private var showMessagingInfoSheet = false
    @State private var pendingThreadAfterCompose: ActiveThreadDestination?

    private struct ActiveThreadDestination: Hashable, Identifiable {
        let conversationId: String
        let title: String
        let lightningAddress: String?
        let initialScrollMessageId: String?

        var id: String { conversationId }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var conversations: [MessageConversationPreview] {
        let normalizedSearch = trimmedSearchText.lowercased()
        let allPreviews = messageStore.conversationPreviews()

        guard !normalizedSearch.isEmpty else {
            return allPreviews
        }

        return allPreviews.filter { preview in
            if displayTitle(for: preview).lowercased().contains(normalizedSearch) {
                return true
            }

            return messageStore.messages(for: preview.id).contains { message in
                MessagePayloadCodec
                    .searchableText(for: message)
                    .lowercased()
                    .contains(normalizedSearch)
            }
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    searchBar

                    if conversations.isEmpty {
                        emptyState
                    } else {
                        conversationList
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ActiveThreadDestination.self) { thread in
                MessageThreadView(
                    conversationId: thread.conversationId,
                    title: thread.title,
                    lightningAddress: thread.lightningAddress,
                    initialScrollMessageId: thread.initialScrollMessageId
                )
            }
        }
        .sheet(isPresented: $showComposeSheet, onDismiss: {
            if let pendingThreadAfterCompose {
                navigationPath.append(pendingThreadAfterCompose)
                self.pendingThreadAfterCompose = nil
            }
        }) {
            ComposeMessage(
                onSent: { result in
                    pendingThreadAfterCompose = ActiveThreadDestination(
                        conversationId: result.conversationId,
                        title: displayTitle(
                            forLightningAddress: result.lightningAddress,
                            fallbackTitle: result.conversationTitle
                        ),
                        lightningAddress: result.lightningAddress,
                        initialScrollMessageId: nil
                    )
                }
            )
            .environmentObject(walletManager)
            .environmentObject(authManager)
        }
        .sheet(isPresented: $showMessagingInfoSheet) {
            MessagingPrivacyInfoSheet(pink: composePink)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await refreshContactNames()
            await refreshConversationProfilePics()
            await MessageSyncManager.shared.syncInboxIfPossible(
                authManager: authManager,
                walletManager: walletManager,
                force: false
            )
            await MessageSyncManager.shared.syncOutgoingStatusesIfPossible(
                authManager: authManager,
                walletManager: walletManager,
                force: false
            )
            consumePendingNotificationRouteIfPossible()
        }
        .task(id: conversations.map(\.id).joined(separator: "|")) {
            await refreshConversationProfilePics()
            consumePendingNotificationRouteIfPossible()
        }
        .onChange(of: messagingNotificationRouter.pendingRoute?.id) { _, _ in
            consumePendingNotificationRouteIfPossible()
        }
        .onChange(of: messageStore.messages.count) { _, _ in
            consumePendingNotificationRouteIfPossible()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text("Messages")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)

                Spacer(minLength: 0)

                Button(action: { showComposeSheet = true }) {
                    Image(systemName: "square.and.pencil")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(composePink.opacity(0.98))
                        )
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .center, spacing: 6) {
                Text("Encrypted conversations.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.58))

                Button(action: { showMessagingInfoSheet = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.62))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How Split messaging works")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(background)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.45))

            TextField("Search", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.splitInputSurface)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 86, height: 86)

                Image(systemName: "message.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
            }

            Text("No Messages Yet")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)

            Text("Start a conversation with a friend using their Lightning Address.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.58))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)

            Button(action: { showComposeSheet = true }) {
                Text("New Message")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(composePink)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var conversationList: some View {
        List {
            ForEach(conversations) { conversation in
                NavigationLink(
                    value: ActiveThreadDestination(
                        conversationId: conversation.id,
                        title: displayTitle(for: conversation),
                        lightningAddress: lightningAddress(for: conversation),
                        initialScrollMessageId: mostRecentMatchingMessageId(for: conversation)
                    )
                ) {
                    let title = displayTitle(for: conversation)
                    let subtitle = conversationSubtitle(for: conversation)

                    HStack(spacing: 12) {
                        avatarView(for: conversation)

                        VStack(alignment: .leading, spacing: 4) {
                            highlightedText(
                                title,
                                matching: trimmedSearchText,
                                baseColor: .white,
                                highlightColor: composePink,
                                font: .headline.weight(.semibold)
                            )
                                .lineLimit(1)

                            highlightedText(
                                subtitle,
                                matching: trimmedSearchText,
                                baseColor: conversation.hasFailedOutgoingMessage ? .splitBrandPink : .white.opacity(0.58),
                                highlightColor: composePink,
                                font: .subheadline
                            )
                                .lineLimit(1)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            Text(timeString(for: conversation.latestAt))
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white.opacity(0.45))

                            if conversation.hasFailedOutgoingMessage {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.splitBrandPink)
                            } else if conversation.hasUnreadMessages {
                                Circle()
                                    .fill(Color.splitBrandPink)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.splitInputSurface)
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteConversation(conversation)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .padding(.top, 6)
        .environment(\.colorScheme, .dark)
    }

    private func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func deleteConversation(_ conversation: MessageConversationPreview) {
        do {
            try messageStore.deleteConversation(id: conversation.id)
        } catch {
            print("Failed to delete conversation \(conversation.id): \(error.localizedDescription)")
        }
    }

    private func lightningAddress(for conversation: MessageConversationPreview) -> String? {
        conversation.title.contains("@") ? conversation.title : nil
    }

    private func displayTitle(for conversation: MessageConversationPreview) -> String {
        guard let lightningAddress = lightningAddress(for: conversation) else {
            return conversation.title
        }

        return displayTitle(forLightningAddress: lightningAddress, fallbackTitle: conversation.title)
    }

    private func displayTitle(forLightningAddress lightningAddress: String, fallbackTitle: String) -> String {
        let normalized = lightningAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return contactNamesByIdentifier[normalized] ?? fallbackTitle
    }

    private func conversationSubtitle(for conversation: MessageConversationPreview) -> String {
        guard !conversation.hasFailedOutgoingMessage else {
            return "Couldn't deliver"
        }

        guard !trimmedSearchText.isEmpty else {
            return conversation.latestBody
        }

        for message in messageStore.messages(for: conversation.id).reversed() {
            let candidate = snippetSource(for: message)
            if candidate.localizedCaseInsensitiveContains(trimmedSearchText) {
                return excerpt(around: trimmedSearchText, in: candidate)
            }
        }

        if conversation.latestBody.localizedCaseInsensitiveContains(trimmedSearchText) {
            return excerpt(around: trimmedSearchText, in: conversation.latestBody)
        }

        return conversation.latestBody
    }

    private func mostRecentMatchingMessageId(for conversation: MessageConversationPreview) -> String? {
        guard !trimmedSearchText.isEmpty else {
            return nil
        }

        return messageStore.messages(for: conversation.id).reversed().first { message in
            snippetSource(for: message).localizedCaseInsensitiveContains(trimmedSearchText)
                || MessagePayloadCodec.searchableText(for: message)
                    .localizedCaseInsensitiveContains(trimmedSearchText)
        }?.id
    }

    private func snippetSource(for message: StoredMessage) -> String {
        switch message.messageType {
        case "payment_request", "payment_request_paid", "attachment":
            return normalizedSnippetText(MessagePayloadCodec.previewText(for: message))
        default:
            let body = normalizedSnippetText(message.body)
            return body.isEmpty ? normalizedSnippetText(MessagePayloadCodec.previewText(for: message)) : body
        }
    }

    private func normalizedSnippetText(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func excerpt(around query: String, in text: String, context: Int = 24) -> String {
        let normalizedText = normalizedSnippetText(text)
        guard !normalizedText.isEmpty,
              let matchRange = normalizedText.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
              ) else {
            return normalizedText
        }

        let lowerOffset = normalizedText.distance(from: normalizedText.startIndex, to: matchRange.lowerBound)
        let upperOffset = normalizedText.distance(from: normalizedText.startIndex, to: matchRange.upperBound)
        let startOffset = max(0, lowerOffset - context)
        let endOffset = min(normalizedText.count, upperOffset + context)
        let startIndex = normalizedText.index(normalizedText.startIndex, offsetBy: startOffset)
        let endIndex = normalizedText.index(normalizedText.startIndex, offsetBy: endOffset)

        var snippet = String(normalizedText[startIndex..<endIndex])
        if startOffset > 0 {
            snippet = "..." + snippet
        }
        if endOffset < normalizedText.count {
            snippet += "..."
        }

        return snippet
    }

    private func highlightedText(
        _ text: String,
        matching query: String,
        baseColor: Color,
        highlightColor: Color,
        font: Font
    ) -> Text {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return Text(text)
                .font(font)
                .foregroundColor(baseColor)
        }

        var remaining = text[...]
        var result = Text("")

        while let range = remaining.range(
            of: normalizedQuery,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            let prefix = remaining[..<range.lowerBound]
            if !prefix.isEmpty {
                result = result + Text(String(prefix)).foregroundColor(baseColor)
            }

            result = result + Text(String(remaining[range])).foregroundColor(highlightColor)
            remaining = remaining[range.upperBound...]
        }

        if !remaining.isEmpty {
            result = result + Text(String(remaining)).foregroundColor(baseColor)
        }

        return result.font(font)
    }

    private func avatarView(for conversation: MessageConversationPreview) -> some View {
        let normalizedAddress = lightningAddress(for: conversation)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 54, height: 54)

            if let normalizedAddress,
               let rawUrl = profilePicUrlsByIdentifier[normalizedAddress],
               let url = URL(string: rawUrl),
               !rawUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.88))
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.88))
            }
        }
    }

    private func destination(forConversationId conversationId: String) -> ActiveThreadDestination? {
        guard let conversation = messageStore.conversationPreviews().first(where: { $0.id == conversationId }) else {
            return nil
        }

        return ActiveThreadDestination(
            conversationId: conversation.id,
            title: displayTitle(for: conversation),
            lightningAddress: lightningAddress(for: conversation),
            initialScrollMessageId: nil
        )
    }

    private func consumePendingNotificationRouteIfPossible() {
        guard let pendingRoute = messagingNotificationRouter.pendingRoute,
              let destination = destination(forConversationId: pendingRoute.conversationId) else {
            return
        }

        searchText = ""
        pendingThreadAfterCompose = nil
        showComposeSheet = false
        navigationPath = [destination]
        messagingNotificationRouter.consume(pendingRoute)
    }

    @MainActor
    private func refreshContactNames() async {
        do {
            let contacts = try await walletManager.listContacts()
            contactNamesByIdentifier = Dictionary(
                uniqueKeysWithValues: contacts.map {
                    (
                        $0.paymentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        $0.name
                    )
                }
            )
        } catch {
            contactNamesByIdentifier = [:]
            print("Failed to load contact names for message list: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshConversationProfilePics() async {
        let addresses = Set(
            conversations.compactMap { conversation in
                lightningAddress(for: conversation)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
        )

        guard !addresses.isEmpty else {
            profilePicUrlsByIdentifier = [:]
            return
        }

        var updated = profilePicUrlsByIdentifier

        for address in addresses where updated[address] == nil {
            do {
                let recipient = try await ResolveMessageRecipientAPI.resolveRecipient(
                    lightningAddress: address,
                    authManager: authManager,
                    walletManager: walletManager
                )
                updated[address] = recipient.profilePicUrl
            } catch {
                updated[address] = ""
            }
        }

        profilePicUrlsByIdentifier = updated
    }
}

private struct MessagingPrivacyInfoSheet: View {
    let pink: Color

    private let paragraphs = [
        "Split messages and attachments are end-to-end encrypted. Your device encrypts them before they reach Split, and only the recipient's device is able to decrypt them.",
        "Split's server is just a relay. It helps route and deliver encrypted messages, but it cannot view message text or attachment contents.",
        "Before sending, your app verifies the recipient's wallet-signed messaging key. That signature links their wallet, Lightning Address, and encryption key, helping ensure the message is encrypted for the correct Lightning Address.",
        "Split uses limited delivery metadata while routing pending messages, like sender, recipient, timing, message type, and attachment size. After a message is received, Split deletes the message relay record. Encrypted attachment blobs are stored separately and are deleted after the recipient confirms attachment receipt or they expire."
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.splitAppBlack,
                    Color.splitSurface
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(pink)

                        Text("End-to-End Encrypted Messages")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                    ForEach(paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    NavigationStack {
        MessageView()
    }
    .environmentObject(WalletManager())
    .environmentObject(AuthManager())
}
