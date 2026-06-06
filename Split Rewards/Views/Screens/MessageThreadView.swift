//
//  MessageThreadView.swift
//  Split Rewards
//
//  Created by TeeVee on 3/21/26.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MessageThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject private var lndWalletManager: LNDWalletManager
    @EnvironmentObject private var nwcWalletManager: NWCWalletManager
    @EnvironmentObject private var activeSpendWalletStore: ActiveSpendWalletStore
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var messageStore = MessageStore.shared
    @ObservedObject private var attachmentManager = MessageAttachmentManager.shared

    let conversationId: String
    let title: String
    let lightningAddress: String?
    let initialScrollMessageId: String?

    @FocusState private var composerFocused: Bool
    @GestureState private var timestampRevealDragOffset: CGFloat = 0

    @State private var draftMessage = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var contactExists = false
    @State private var contactName: String?
    @State private var savedContact: WalletManager.WalletContact?
    @State private var showPaymentOptions = false
    @State private var showAttachmentOptions = false
    @State private var showRequestSheet = false
    @State private var showingAttachmentImagePicker = false
    @State private var showingAttachmentVideoPicker = false
    @State private var showingAttachmentFileImporter = false
    @State private var sendDestination: SendDestination?
    @State private var keyboardHeight: CGFloat = 0
    @State private var profilePicUrl: String?
    @State private var activeBlock: MessagingBlockedUser?
    @State private var pickedAttachmentImage: UIImage?
    @State private var pickedAttachmentVideoURL: URL?
    @State private var openingAttachmentId: String?
    @State private var previewAttachment: CachedMessageAttachment?
    @State private var didPerformInitialMessageScroll = false
    @State private var currentWalletPubkey: String?
    @State private var retryingFailedMessageIds: Set<String> = []

    private let background = Color.black
    private let incomingBlue = Color.splitBrandBlue
    private let outgoingPink = Color.splitBrandPink
    private let composerSurface = Color.white.opacity(0.08)
    private let bottomBarSurface = Color.splitCardSurface
    private let bottomMessageInset: CGFloat = 18
    private let timestampRevealWidth: CGFloat = 74

    private struct SendDestination: Hashable, Identifiable {
        let paymentRequest: String
        var id: String { paymentRequest }
    }

    private struct ReactionStateKey: Hashable {
        let targetMessageId: String
        let senderWalletPubkey: String
    }

    private struct ReactionBadgeSummary: Identifiable, Hashable {
        let kind: MessageReactionKind
        let count: Int

        var id: String { kind.rawValue }
    }

    private let bottomScrollAnchorId = "message-thread-bottom-anchor"

    init(
        conversationId: String,
        title: String,
        lightningAddress: String?,
        initialScrollMessageId: String? = nil
    ) {
        self.conversationId = conversationId
        self.title = title
        self.lightningAddress = lightningAddress
        self.initialScrollMessageId = initialScrollMessageId
    }

    private var conversationMessages: [StoredMessage] {
        messageStore.messages(for: conversationId)
    }

    private var visibleConversationMessages: [StoredMessage] {
        conversationMessages.filter { message in
            message.messageType != "payment_request_paid" && message.messageType != "reaction"
        }
    }

    private struct IndexedVisibleMessage: Identifiable {
        let index: Int
        let message: StoredMessage

        var id: String { message.id }
    }

    private var indexedVisibleConversationMessages: [IndexedVisibleMessage] {
        visibleConversationMessages.enumerated().map { index, message in
            IndexedVisibleMessage(index: index, message: message)
        }
    }

    private var latestReactionByTargetAndSender: [ReactionStateKey: MessageReactionKind] {
        conversationMessages
            .filter { $0.messageType == "reaction" }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }
            .reduce(into: [:]) { partialResult, reactionMessage in
                guard let payload = MessagePayloadCodec.decodeReaction(from: reactionMessage.body),
                      let reactionKind = MessageReactionKind(rawValue: payload.reactionKey) else {
                    return
                }

                let key = ReactionStateKey(
                    targetMessageId: payload.targetMessageId,
                    senderWalletPubkey: reactionMessage.senderWalletPubkey
                )

                if reactionKind == .remove {
                    partialResult.removeValue(forKey: key)
                } else {
                    partialResult[key] = reactionKind
                }
            }
    }

    private var reactionsByMessageId: [String: [ReactionBadgeSummary]] {
        var grouped: [String: [MessageReactionKind: Int]] = [:]

        for (key, reactionKind) in latestReactionByTargetAndSender {
            grouped[key.targetMessageId, default: [:]][reactionKind, default: 0] += 1
        }

        return grouped.mapValues { counts in
            MessageReactionKind.selectableCases.compactMap { kind in
                guard let count = counts[kind], count > 0 else { return nil }
                return ReactionBadgeSummary(kind: kind, count: count)
            }
        }
    }

    private var currentUserReactionByMessageId: [String: MessageReactionKind] {
        guard let currentWalletPubkey else { return [:] }

        var result: [String: MessageReactionKind] = [:]
        for (key, reactionKind) in latestReactionByTargetAndSender where key.senderWalletPubkey == currentWalletPubkey {
            result[key.targetMessageId] = reactionKind
        }
        return result
    }

    private var paidRequestMessageIds: Set<String> {
        Set(
            conversationMessages.compactMap { message in
                guard message.messageType == "payment_request_paid" else { return nil }
                return MessagePayloadCodec.decodePaymentRequestPaid(from: message.body)?.requestMessageId
            }
        )
    }

    private var activeBottomMessageInset: CGFloat {
        keyboardHeight > 0 ? bottomMessageInset + 12 : bottomMessageInset
    }

    private var timestampRevealAmount: CGFloat {
        min(max(timestampRevealDragOffset, 0), timestampRevealWidth)
    }

    private var timestampRevealProgress: CGFloat {
        guard timestampRevealWidth > 0 else { return 0 }
        return timestampRevealAmount / timestampRevealWidth
    }

    private var canSend: Bool {
        let hasDraftText = !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return lightningAddress != nil && activeBlock == nil && hasDraftText
    }

    private var displayTitle: String {
        if let contactName, !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return contactName
        }
        return title
    }

    var body: some View {
        configuredBody(content: threadContent)
    }

    private var threadContent: some View {
        ZStack {
            background
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                conversationScrollView(using: proxy)
            }
        }
    }

    private func configuredBody<Content: View>(content: Content) -> some View {
        content
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerBar
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Bitcoin", isPresented: $showPaymentOptions, titleVisibility: .visible) {
            if let lightningAddress {
                Button("Send") {
                    sendDestination = SendDestination(paymentRequest: lightningAddress)
                }

                if activeBlock == nil {
                    Button("Request") {
                        showRequestSheet = true
                    }
                }
            }

            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Send Attachment", isPresented: $showAttachmentOptions, titleVisibility: .visible) {
            Button("Choose Photo") {
                showingAttachmentImagePicker = true
            }

            Button("Choose Video") {
                showingAttachmentVideoPicker = true
            }

            Button("Choose File") {
                showingAttachmentFileImporter = true
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose a photo, video, or file to send as an encrypted attachment.")
        }
        .fullScreenCover(isPresented: $showRequestSheet) {
            if let lightningAddress {
                NavigationStack {
                    RequestPaymentMessageView(
                        lightningAddress: lightningAddress,
                        onSent: {}
                    )
                    .environmentObject(walletManager)
                    .environmentObject(lndWalletManager)
                    .environmentObject(nwcWalletManager)
                    .environmentObject(activeSpendWalletStore)
                    .environmentObject(authManager)
                }
            }
        }
        .sheet(isPresented: $showingAttachmentImagePicker) {
            ImagePicker(image: $pickedAttachmentImage)
        }
        .sheet(isPresented: $showingAttachmentVideoPicker) {
            VideoPicker(videoURL: $pickedAttachmentVideoURL)
        }
        .sheet(item: $previewAttachment) { attachment in
            MessageAttachmentPreview(item: attachment)
                .onDisappear {
                    attachmentManager.cleanupTemporaryPreview(attachment)
                }
        }
        .fileImporter(
            isPresented: $showingAttachmentFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleAttachmentFileSelection(result)
        }
        .fullScreenCover(item: $sendDestination) { destination in
            NavigationStack {
                SendToView(prefilledRecipientInput: destination.paymentRequest)
                    .environmentObject(walletManager)
            }
        }
        .task(id: conversationId) {
            MessageThreadPresenceTracker.shared.enterConversation(conversationId)
            await refreshThread(force: true)
            markConversationAsRead()
            await refreshCurrentWalletPubkey()
            await refreshContactState()
            await refreshBlockState()
            await refreshProfilePic()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await refreshThread(force: true)
            }
        }
        .onAppear {
            MessageThreadPresenceTracker.shared.enterConversation(conversationId)
            Task {
                await refreshCurrentWalletPubkey()
                await refreshContactState()
                await refreshBlockState()
                await refreshProfilePic()
            }
        }
        .onDisappear {
            MessageThreadPresenceTracker.shared.leaveConversation(conversationId)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            keyboardHeight = keyboardHeight(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await refreshThread(force: true)
                await refreshBlockState()
                await refreshProfilePic()
            }
        }
        .onChange(of: pickedAttachmentImage) { _, newImage in
            guard let newImage else { return }
            Task {
                await handleSelectedAttachmentImage(newImage)
                pickedAttachmentImage = nil
            }
        }
        .onChange(of: pickedAttachmentVideoURL) { _, newURL in
            guard let newURL else { return }
            Task {
                await handleSelectedAttachmentVideo(newURL)
                pickedAttachmentVideoURL = nil
            }
        }
        .onChange(of: activeBlock) { _, newBlock in
            if newBlock != nil {
                composerFocused = false
            }
        }
    }

    private func conversationScrollView(using proxy: ScrollViewProxy) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(indexedVisibleConversationMessages) { entry in
                    if shouldShowDaySeparator(
                        for: entry.message,
                        previousMessage: previousVisibleMessage(before: entry.index)
                    ) {
                        messageDaySeparator(for: entry.message.createdAt)
                            .id("day-separator-\(entry.message.id)")
                    }

                    bubbleRow(for: entry.message)
                        .id(entry.message.id)
                }

                Color.clear
                    .frame(height: activeBottomMessageInset)
                    .id(bottomScrollAnchorId)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(timestampRevealGesture)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scrollToInitialPositionIfNeeded(using: proxy)
            }

            if initialScrollMessageId == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    composerFocused = true
                }
            }
        }
        .onChange(of: visibleConversationMessages.count) { _, _ in
            if !scrollToInitialPositionIfNeeded(using: proxy) {
                scrollToBottom(using: proxy, animated: true)
            }
            markConversationAsRead()
        }
        .onChange(of: keyboardHeight) { _, _ in
            scrollToBottom(using: proxy, animated: true)
        }
        .onChange(of: composerFocused) { _, isFocused in
            guard isFocused else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scrollToBottom(using: proxy, animated: true)
            }
        }
    }

    private func previousVisibleMessage(before index: Int) -> StoredMessage? {
        guard index > 0 else { return nil }
        return indexedVisibleConversationMessages[index - 1].message
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

            if let lightningAddress {
                NavigationLink(
                    destination: MessageParticipantDetailView(
                        title: displayTitle,
                        lightningAddress: lightningAddress,
                        walletPubkey: conversationId,
                        savedContact: savedContact,
                        profilePicUrl: profilePicUrl
                    )
                ) {
                    headerIdentity
                }
                .buttonStyle(.plain)
            } else {
                headerIdentity
            }

            Spacer()

            if lightningAddress != nil {
                HStack(spacing: 10) {
                    Button(action: { showPaymentOptions = true }) {
                        Image(systemName: "bolt.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(Color.splitInputSurfaceSecondary)
                            )
                    }
                    .buttonStyle(.plain)

                    if let lightningAddress, !contactExists {
                        NavigationLink(
                            destination: CreateContactView(
                                paymentIdentifier: lightningAddress,
                                onSaved: {
                                    contactExists = true
                                    contactName = nil
                                    Task {
                                        await refreshContactState()
                                    }
                                }
                            )
                        ) {
                            Image(systemName: "plus")
                                .font(.headline.weight(.bold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle()
                                        .fill(Color.splitInputSurfaceSecondary)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: 52, alignment: .trailing)
            } else {
                Color.clear
                    .frame(width: 52, height: 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(background)
    }

    private var headerIdentity: some View {
        HStack(spacing: 10) {
            if hasProfileImage {
                profileImageView
            }

            VStack(spacing: 2) {
                Text(displayTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("Encrypted conversation")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.52))
            }
        }
    }

    private var profileImageView: some View {
        ZStack {
            if let profilePicUrl,
               let url = URL(string: profilePicUrl),
               !profilePicUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color.clear
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(Circle())
            }
        }
        .frame(width: 38, height: 38)
    }

    private var hasProfileImage: Bool {
        guard let profilePicUrl else { return false }
        return !profilePicUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if activeBlock != nil {
                Text("You blocked this user.")
                    .font(.subheadline)
                    .foregroundColor(.splitBrandPink)
                    .multilineTextAlignment(.leading)
            }

            if let sendError {
                Text(sendError)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
            }

            HStack(alignment: .bottom, spacing: 12) {
                Button(action: {
                    guard lightningAddress != nil, activeBlock == nil, !isSending else { return }
                    showAttachmentOptions = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(
                            lightningAddress != nil && activeBlock == nil
                                ? .white.opacity(0.86)
                                : .white.opacity(0.18)
                        )
                }
                .buttonStyle(.plain)
                .disabled(lightningAddress == nil || activeBlock != nil || isSending)

                TextField("iMessage", text: $draftMessage, axis: .vertical)
                    .focused($composerFocused)
                    .lineLimit(1...5)
                    .textInputAutocapitalization(.sentences)
                    .foregroundColor(.white)
                    .disabled(lightningAddress == nil || activeBlock != nil)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(composerSurface)
                    )

                Button(action: {
                    guard !isSending, canSend else { return }
                    Task {
                        await sendMessage()
                    }
                }) {
                    if isSending {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 42, height: 42)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundColor(canSend ? outgoingPink : .white.opacity(0.18))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isSending)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(
            Rectangle()
                .fill(bottomBarSurface)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                }
        )
    }

    private var timestampRevealGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($timestampRevealDragOffset) { value, state, transaction in
                transaction.animation = .interactiveSpring(response: 0.24, dampingFraction: 0.88)

                let horizontalTranslation = value.translation.width
                let verticalTranslation = value.translation.height

                guard horizontalTranslation < 0,
                      abs(horizontalTranslation) > abs(verticalTranslation) else {
                    state = 0
                    return
                }

                state = min(-horizontalTranslation, timestampRevealWidth)
            }
    }

    @ViewBuilder
    private func messageDaySeparator(for date: Date) -> some View {
        Text(daySeparatorText(for: date))
            .font(.caption.weight(.semibold))
            .foregroundColor(.white.opacity(0.48))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.055))
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .accessibilityLabel(daySeparatorAccessibilityText(for: date))
    }

    private func timestampRevealRow<Content: View>(
        for message: StoredMessage,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let progress = timestampRevealProgress

        return ZStack(alignment: .trailing) {
            content()
                .frame(maxWidth: .infinity)
                .offset(x: -timestampRevealAmount)

            Text(messageTimeText(for: message.createdAt))
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.48))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: timestampRevealWidth, alignment: .trailing)
                .padding(.trailing, 2)
                .opacity(progress)
                .offset(x: (1 - progress) * 10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHint("Sent \(messageTimestampAccessibilityText(for: message.createdAt))")
    }

    private func shouldShowDaySeparator(
        for message: StoredMessage,
        previousMessage: StoredMessage?
    ) -> Bool {
        guard let previousMessage else { return true }
        return !Calendar.current.isDate(message.createdAt, inSameDayAs: previousMessage.createdAt)
    }

    private func daySeparatorText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE M/d/yy"
        return formatter.string(from: date)
    }

    private func daySeparatorAccessibilityText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func messageTimeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func messageTimestampAccessibilityText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func bubbleRow(for message: StoredMessage) -> some View {
        if message.messageType == "payment_request",
           let payload = MessagePayloadCodec.decodePaymentRequest(from: message.body) {
            deliveryDecoratedRow(for: message) {
                reactionDecoratedRow(for: message) {
                    paymentRequestRow(for: message, payload: payload)
                }
            }
        } else if message.messageType == "attachment",
                  let payload = MessagePayloadCodec.decodeAttachment(from: message.body) {
            deliveryDecoratedRow(for: message) {
                reactionDecoratedRow(for: message) {
                    attachmentRow(for: message, payload: payload)
                }
            }
        } else {
            deliveryDecoratedRow(for: message) {
                reactionDecoratedRow(for: message) {
                    HStack {
                        if message.isIncoming {
                            messageText(for: message.body)
                                .font(.body)
                                .foregroundColor(.white)
                                .tint(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(incomingBlue)
                                )
                            Spacer(minLength: 48)
                        } else {
                            Spacer(minLength: 48)
                            messageText(for: message.body)
                                .font(.body)
                                .foregroundColor(.white)
                                .tint(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(outgoingPink)
                                )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func deliveryDecoratedRow<Content: View>(
        for message: StoredMessage,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(
            alignment: message.isIncoming ? .leading : .trailing,
            spacing: 6
        ) {
            timestampRevealRow(for: message) {
                content()
            }

            if !message.isIncoming, message.deliveryState == .failedSameKey {
                Button(action: {
                    Task {
                        await resendFailedMessage(message)
                    }
                }) {
                    HStack(spacing: 6) {
                        if retryingFailedMessageIds.contains(message.id) {
                            ProgressView()
                                .tint(.splitBrandPink)
                        } else {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption.weight(.semibold))
                        }

                        Text(retryingFailedMessageIds.contains(message.id) ? "Retrying..." : "Couldn't deliver. Tap to resend.")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(.splitBrandPink)
                }
                .buttonStyle(.plain)
                .disabled(retryingFailedMessageIds.contains(message.id) || activeBlock != nil)
                .offset(x: -timestampRevealAmount)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isIncoming ? .leading : .trailing)
    }

    @ViewBuilder
    private func reactionDecoratedRow<Content: View>(
        for message: StoredMessage,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let reactions = reactionsByMessageId[message.id] ?? []
        let baseContent = content()
            .padding(.bottom, reactions.isEmpty ? 0 : 12)
            .overlay(
                alignment: message.isIncoming ? .bottomLeading : .bottomTrailing
            ) {
                if !reactions.isEmpty {
                    reactionBadge(reactions)
                        .offset(x: message.isIncoming ? -6 : 6, y: 6)
                        .zIndex(1)
                        .allowsHitTesting(false)
                }
            }

        if lightningAddress != nil && activeBlock == nil {
            baseContent.contextMenu {
                reactionContextMenu(for: message)
            }
        } else {
            baseContent
        }
    }

    @ViewBuilder
    private func attachmentRow(for message: StoredMessage, payload: AttachmentMessagePayload) -> some View {
        HStack {
            if message.isIncoming {
                Button(action: {
                    Task {
                        await openAttachment(for: message, payload: payload)
                    }
                }) {
                    attachmentCard(for: message, payload: payload)
                }
                .buttonStyle(.plain)
                .disabled(isAttachmentBusy(payload))
                Spacer(minLength: 36)
            } else {
                Spacer(minLength: 36)
                Button(action: {
                    Task {
                        await openAttachment(for: message, payload: payload)
                    }
                }) {
                    attachmentCard(for: message, payload: payload)
                }
                .buttonStyle(.plain)
                .disabled(isAttachmentBusy(payload))
            }
        }
    }

    private func attachmentCard(for message: StoredMessage, payload: AttachmentMessagePayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let previewImage = attachmentPreviewImage(for: payload) {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 248, height: 170)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }

            HStack(spacing: 8) {
                Image(systemName: attachmentSymbolName(for: payload))
                    .font(.subheadline.weight(.bold))

                Text(attachmentTitle(for: payload))
                    .font(.subheadline.weight(.bold))

                Spacer()
            }
            .foregroundColor(.white)

            Text(payload.fileName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(2)

            Text(ByteCountFormatter.string(fromByteCount: Int64(payload.sizeBytes), countStyle: .file))
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.75))

            if isAttachmentBusy(payload) {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Preparing attachment...")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.78))
                }
            } else {
                Text(attachmentHelperText(for: message, payload: payload))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.78))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(message.isIncoming ? incomingBlue : outgoingPink)
        )
    }

    private func messageText(for body: String) -> Text {
        Text(linkifiedAttributedString(from: body))
    }

    private func linkifiedAttributedString(from body: String) -> AttributedString {
        let mutable = NSMutableAttributedString(string: body)

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let nsRange = NSRange(location: 0, length: (body as NSString).length)
            let matches = detector.matches(in: body, options: [], range: nsRange)

            for match in matches {
                guard let url = match.url else { continue }
                mutable.addAttribute(.link, value: url, range: match.range)
                mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
            }
        }

        return (try? AttributedString(mutable, including: \.foundation)) ?? AttributedString(body)
    }

    @ViewBuilder
    private func paymentRequestRow(for message: StoredMessage, payload: PaymentRequestMessagePayload) -> some View {
        let isPaid = paidRequestMessageIds.contains(message.id)
        let card = paymentRequestCard(for: message, payload: payload)

        HStack {
            if message.isIncoming {
                Button(action: {
                    guard !isPaid else { return }
                    sendDestination = SendDestination(paymentRequest: payload.invoice)
                }) {
                    card
                }
                .buttonStyle(.plain)
                .disabled(isPaid)
                Spacer(minLength: 36)
            } else {
                Spacer(minLength: 36)
                card
            }
        }
    }

    private func paymentRequestCard(for message: StoredMessage, payload: PaymentRequestMessagePayload) -> some View {
        let isPaid = paidRequestMessageIds.contains(message.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.subheadline.weight(.bold))

                Text("Payment Request")
                    .font(.subheadline.weight(.bold))

                Spacer()

                if isPaid {
                    Text("Paid")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.16))
                        )
                }
            }
            .foregroundColor(.white)

            Text("\(MessagePayloadCodec.formattedSats(payload.amountSats)) sats")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            if let requesterAddress = payload.requesterLightningAddress, !requesterAddress.isEmpty {
                Text(requesterAddress)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
            }

            if isPaid {
                Text("Invoice paid")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.78))
            } else if message.isIncoming {
                Text("Tap to pay in the existing send flow")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.78))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(message.isIncoming ? incomingBlue : outgoingPink)
        )
    }

    @ViewBuilder
    private func reactionBadge(_ reactions: [ReactionBadgeSummary]) -> some View {
        HStack(spacing: 6) {
            ForEach(reactions) { reaction in
                HStack(spacing: 4) {
                    reactionBadgeIcon(for: reaction.kind)

                    if reaction.count > 1 {
                        Text("\(reaction.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white.opacity(0.82))
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.82))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 2)
    }

    @ViewBuilder
    private func reactionBadgeIcon(for reactionKind: MessageReactionKind) -> some View {
        switch reactionKind {
        case .laugh, .emphasize, .question:
            Text(reactionKind.badgeText)
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
        case .remove:
            EmptyView()
        default:
            if let systemImageName = reactionKind.systemImageName {
                Image(systemName: systemImageName)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
            }
        }
    }

    @ViewBuilder
    private func reactionContextMenu(for message: StoredMessage) -> some View {
        ForEach(MessageReactionKind.selectableCases) { reactionKind in
            Button {
                Task {
                    await sendReaction(reactionKind, for: message)
                }
            } label: {
                reactionMenuLabel(for: reactionKind)
            }
        }

        if currentUserReactionByMessageId[message.id] != nil {
            Button(role: .destructive) {
                Task {
                    await sendReaction(.remove, for: message)
                }
            } label: {
                reactionMenuLabel(for: .remove)
            }
        }
    }

    @ViewBuilder
    private func reactionMenuLabel(for reactionKind: MessageReactionKind) -> some View {
        Group {
            switch reactionKind {
            case .laugh, .emphasize, .question:
                Text(reactionKind.badgeText)
                    .font(.body.weight(.bold))
            case .remove:
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
            default:
                if let systemImageName = reactionKind.systemImageName {
                    Image(systemName: systemImageName)
                        .font(.body.weight(.bold))
                }
            }
        }
    }

    @MainActor
    private func sendReaction(_ reactionKind: MessageReactionKind, for message: StoredMessage) async {
        guard activeBlock == nil else {
            sendError = "Messaging is blocked for this user."
            return
        }

        guard let lightningAddress else {
            sendError = "This message cannot be reacted to right now."
            return
        }

        sendError = nil

        do {
            _ = try await MessagingSendCoordinator.sendReaction(
                lightningAddress: lightningAddress,
                payload: MessageReactionPayload(
                    targetMessageId: message.id,
                    reactionKey: reactionKind.rawValue
                ),
                authManager: authManager,
                walletManager: walletManager
            )
        } catch {
            sendError = error.localizedDescription
        }
    }

    @MainActor
    private func sendMessage() async {
        guard activeBlock == nil else {
            sendError = "Messaging is blocked for this user."
            return
        }

        guard let lightningAddress else { return }

        let submittedDraft = draftMessage
        let trimmed = submittedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSending = true
        sendError = nil

        do {
            _ = try await MessagingSendCoordinator.sendTextMessage(
                lightningAddress: lightningAddress,
                plaintext: trimmed,
                authManager: authManager,
                walletManager: walletManager
            )
            if draftMessage == submittedDraft {
                draftMessage = ""
            }
        } catch {
            sendError = error.localizedDescription
        }

        isSending = false
    }

    @MainActor
    private func resendFailedMessage(_ message: StoredMessage) async {
        guard !message.isIncoming else { return }
        guard !retryingFailedMessageIds.contains(message.id) else { return }

        retryingFailedMessageIds.insert(message.id)
        sendError = nil

        defer {
            retryingFailedMessageIds.remove(message.id)
        }

        do {
            guard let resentResult = try await MessagingSendCoordinator.resendStoredMessageIfNeeded(
                message,
                authManager: authManager,
                walletManager: walletManager
            ) else {
                sendError = message.messageType == "attachment"
                    ? "Couldn't resend this attachment right now."
                    : "Couldn't resend this message right now."
                return
            }

            try MessageStore.shared.replaceOutgoingMessage(
                matchingStoredMessageId: message.id,
                with: resentResult.storedMessage
            )
        } catch {
            sendError = error.localizedDescription
        }
    }

    @MainActor
    private func handleSelectedAttachmentImage(_ image: UIImage) async {
        let fileName = "photo-\(Int(Date().timeIntervalSince1970)).jpg"
        let imageData = image.jpegData(compressionQuality: 0.82)

        guard let imageData, !imageData.isEmpty else {
            sendError = "Could not prepare the selected image."
            return
        }

        let imageWidth = image.cgImage?.width ?? Int(image.size.width)
        let imageHeight = image.cgImage?.height ?? Int(image.size.height)

        await sendAttachment(
            fileData: imageData,
            fileName: fileName,
            mimeType: "image/jpeg",
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )
    }

    @MainActor
    private func handleSelectedAttachmentVideo(_ url: URL) async {
        do {
            let preparedVideo = try await MessageVideoProcessor.prepareVideoAttachment(
                from: url,
                maximumBytes: attachmentManager.maximumAttachmentBytes
            )

            await sendAttachment(
                fileData: preparedVideo.fileData,
                fileName: preparedVideo.fileName,
                mimeType: preparedVideo.mimeType,
                imageWidth: nil,
                imageHeight: nil
            )
        } catch {
            sendError = error.localizedDescription
        }
    }

    private func handleAttachmentFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            Task {
                let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccessSecurityScope {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let fileName = url.lastPathComponent.isEmpty ? "attachment" : url.lastPathComponent
                    let mimeType = mimeTypeForFile(at: url)

                    if mimeType.lowercased().hasPrefix("video/") {
                        let preparedVideo = try await MessageVideoProcessor.prepareVideoAttachment(
                            from: url,
                            maximumBytes: attachmentManager.maximumAttachmentBytes
                        )

                        await sendAttachment(
                            fileData: preparedVideo.fileData,
                            fileName: preparedVideo.fileName,
                            mimeType: preparedVideo.mimeType,
                            imageWidth: nil,
                            imageHeight: nil
                        )
                    } else {
                        let data = try Data(contentsOf: url)

                        await sendAttachment(
                            fileData: data,
                            fileName: fileName,
                            mimeType: mimeType,
                            imageWidth: nil,
                            imageHeight: nil
                        )
                    }
                } catch {
                    await MainActor.run {
                        sendError = error.localizedDescription
                    }
                }
            }
        case .failure(let error):
            print("Attachment file import cancelled or failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func sendAttachment(
        fileData: Data,
        fileName: String,
        mimeType: String,
        imageWidth: Int?,
        imageHeight: Int?
    ) async {
        guard activeBlock == nil else {
            sendError = "Messaging is blocked for this user."
            return
        }

        guard let lightningAddress else { return }

        guard fileData.count <= attachmentManager.maximumAttachmentBytes else {
            sendError = MessageAttachmentManager.AttachmentManagerError
                .fileTooLarge(maxBytes: attachmentManager.maximumAttachmentBytes)
                .localizedDescription
            return
        }

        isSending = true
        sendError = nil

        do {
            _ = try await MessagingSendCoordinator.sendAttachment(
                lightningAddress: lightningAddress,
                fileData: fileData,
                fileName: fileName,
                mimeType: mimeType,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                authManager: authManager,
                walletManager: walletManager
            )
        } catch {
            sendError = error.localizedDescription
        }

        isSending = false
    }

    private func isAttachmentBusy(_ payload: AttachmentMessagePayload) -> Bool {
        openingAttachmentId == payload.attachmentId
    }

    private func attachmentHelperText(
        for _: StoredMessage,
        payload: AttachmentMessagePayload
    ) -> String {
        if payload.mimeType.lowercased().hasPrefix("video/") {
            if attachmentManager.hasCachedAttachment(payload) {
                return "Tap to play video"
            }
            return "Tap to download video"
        }

        if attachmentManager.hasCachedAttachment(payload) {
            return "Tap to open"
        }
        return "Tap to download"
    }

    private func attachmentPreviewImage(for payload: AttachmentMessagePayload) -> UIImage? {
        guard payload.mimeType.lowercased().hasPrefix("image/"),
              let imageData = attachmentManager.cachedAttachmentData(for: payload) else {
            return nil
        }

        return UIImage(data: imageData)
    }

    @MainActor
    private func openAttachment(
        for message: StoredMessage,
        payload: AttachmentMessagePayload
    ) async {
        guard openingAttachmentId != payload.attachmentId else { return }

        openingAttachmentId = payload.attachmentId
        sendError = nil

        defer {
            openingAttachmentId = nil
        }

        do {
            let cached = try await attachmentManager.prepareAttachmentForPreview(
                payload: payload,
                recipientMessagingPubkeyHex: message.recipientMessagingPubkey,
                shouldMarkReceived: message.isIncoming,
                authManager: authManager,
                walletManager: walletManager
            )
            previewAttachment = cached
        } catch {
            sendError = error.localizedDescription
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        guard !visibleConversationMessages.isEmpty else { return }

        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomScrollAnchorId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomScrollAnchorId, anchor: .bottom)
        }
    }

    @discardableResult
    private func scrollToInitialPositionIfNeeded(using proxy: ScrollViewProxy) -> Bool {
        guard !didPerformInitialMessageScroll else { return false }

        if let initialScrollMessageId,
           visibleConversationMessages.contains(where: { $0.id == initialScrollMessageId }) {
            didPerformInitialMessageScroll = true
            proxy.scrollTo(initialScrollMessageId, anchor: .center)
            return true
        }

        didPerformInitialMessageScroll = true
        scrollToBottom(using: proxy, animated: false)
        return true
    }

    private func keyboardHeight(from notification: Notification) -> CGFloat {
        guard
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return 0
        }

        return max(0, frame.height)
    }

    private func markConversationAsRead() {
        do {
            try messageStore.markConversationAsRead(id: conversationId)
        } catch {
            print("Failed to mark conversation \(conversationId) as read: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshThread(force: Bool) async {
        await MessageSyncManager.shared.syncInboxIfPossible(
            authManager: authManager,
            walletManager: walletManager,
            force: force,
            minimumInterval: 0
        )
        await MessageSyncManager.shared.syncOutgoingStatusesIfPossible(
            authManager: authManager,
            walletManager: walletManager,
            force: force,
            minimumInterval: 0
        )
        markConversationAsRead()
    }

    @MainActor
    private func refreshCurrentWalletPubkey() async {
        do {
            currentWalletPubkey = try await MessageKeyManager.shared.currentWalletPubkey(
                walletManager: walletManager
            )
        } catch {
            currentWalletPubkey = nil
        }
    }

    @MainActor
    private func refreshContactState() async {
        guard let lightningAddress else {
            contactExists = true
            contactName = nil
            savedContact = nil
            return
        }

        do {
            let contact = try await walletManager.contact(forPaymentIdentifier: lightningAddress)
            contactExists = contact != nil
            contactName = contact?.name
            savedContact = contact
        } catch {
            contactExists = false
            contactName = nil
            savedContact = nil
            print("Failed to check contact state for \(lightningAddress): \(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshBlockState() async {
        guard let lightningAddress else {
            activeBlock = nil
            return
        }

        let normalizedLightningAddress = lightningAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        do {
            let blocks = try await MessagingBlockAPI.fetchBlocks(
                authManager: authManager,
                walletManager: walletManager
            )
            activeBlock = blocks.first(where: { block in
                block.blockedWalletPubkey == conversationId ||
                    block.normalizedLightningAddress == normalizedLightningAddress
            })
        } catch {
            activeBlock = nil
        }
    }

    @MainActor
    private func refreshProfilePic() async {
        if let activeBlock {
            profilePicUrl = activeBlock.blockedProfilePicUrl
            return
        }

        guard let lightningAddress,
              !lightningAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            profilePicUrl = nil
            return
        }

        do {
            let recipient = try await ResolveMessageRecipientAPI.resolveRecipient(
                lightningAddress: lightningAddress,
                authManager: authManager,
                walletManager: walletManager
            )
            profilePicUrl = recipient.profilePicUrl
        } catch {
            profilePicUrl = nil
        }
    }

    private func mimeTypeForFile(at url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = values.contentType,
           let mimeType = contentType.preferredMIMEType {
            return mimeType
        }

        return "application/octet-stream"
    }

    private func attachmentTitle(for payload: AttachmentMessagePayload) -> String {
        let lowercasedMimeType = payload.mimeType.lowercased()
        if lowercasedMimeType.hasPrefix("image/") {
            return "Photo"
        }
        if lowercasedMimeType.hasPrefix("video/") {
            return "Video"
        }
        return "Attachment"
    }

    private func attachmentSymbolName(for payload: AttachmentMessagePayload) -> String {
        let lowercasedMimeType = payload.mimeType.lowercased()
        if lowercasedMimeType.hasPrefix("image/") {
            return "photo.fill"
        }
        if lowercasedMimeType.hasPrefix("video/") {
            return "video.fill"
        }
        return "paperclip"
    }
}
