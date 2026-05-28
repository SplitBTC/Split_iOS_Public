//
//  ComposeMessage.swift
//  Split Rewards
//
//  Created by TeeVee on 3/20/26.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ComposeMessage: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var authManager: AuthManager

    @ObservedObject private var messageStore = MessageStore.shared
    @FocusState private var focusedField: Field?

    @State private var recipientQuery: String
    @State private var selectedRecipient: MessageRecipientRecord?
    @State private var allRecipientRecords: [MessageRecipientRecord] = []
    @State private var recipientSuggestions: [MessageRecipientRecord] = []
    @State private var messageText = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var showAttachmentOptions = false
    @State private var showingAttachmentImagePicker = false
    @State private var showingAttachmentVideoPicker = false
    @State private var showingAttachmentFileImporter = false
    @State private var pickedAttachmentImage: UIImage?
    @State private var pickedAttachmentVideoURL: URL?

    private let background = Color.black
    private let fieldSurface = Color.splitInputSurface
    private let composerSurface = Color.white.opacity(0.08)
    private let bottomBarSurface = Color.splitCardSurface
    private let separator = Color.white.opacity(0.08)
    private var lightningDomainSuffix: String { "@\(AppConfig.lightningAddressDomain)" }

    let onSent: ((MessageSendResult) -> Void)?

    init(
        prefilledLightningAddress: String? = nil,
        onSent: ((MessageSendResult) -> Void)? = nil
    ) {
        let trimmedPrefilled = prefilledLightningAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrefilled = trimmedPrefilled.flatMap(Self.normalizeRecipientInput)

        _recipientQuery = State(initialValue: normalizedPrefilled == nil ? (trimmedPrefilled ?? "") : "")
        _selectedRecipient = State(
            initialValue: normalizedPrefilled.map {
                MessageRecipientRecord(
                    lightningAddress: $0,
                    displayName: $0,
                    profilePicURL: nil,
                    lastInteractedAt: nil,
                    source: .conversation
                )
            }
        )
        _messageText = State(initialValue: "")
        self.onSent = onSent
    }

    private enum Field {
        case recipient
        case message
    }

    private var resolvedRecipientAddress: String? {
        if let selectedRecipient {
            return selectedRecipient.lightningAddress
        }

        return Self.normalizeRecipientInput(recipientQuery)
    }

    private var canSend: Bool {
        resolvedRecipientAddress != nil &&
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var trimmedRecipientQuery: String {
        Self.normalizedSearchText(recipientQuery)
    }

    private var showsRecipientSuggestions: Bool {
        selectedRecipient == nil
            && !trimmedRecipientQuery.isEmpty
            && (!recipientSuggestions.isEmpty || typedRecipientCandidate != nil)
    }

    private var typedRecipientCandidate: String? {
        guard selectedRecipient == nil,
              shouldOfferTypedRecipientCandidate,
              let normalized = Self.normalizeRecipientInput(recipientQuery) else {
            return nil
        }

        let alreadyKnown = allRecipientRecords.contains { record in
            record.lightningAddress == normalized
        }

        return alreadyKnown ? nil : normalized
    }

    private var shouldOfferTypedRecipientCandidate: Bool {
        let trimmedQuery = trimmedRecipientQuery
        guard !trimmedQuery.isEmpty else { return false }
        return trimmedQuery.contains("@") || recipientSuggestions.isEmpty
    }

    private var showsUsernameHint: Bool {
        selectedRecipient == nil
            && !recipientQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !trimmedRecipientQuery.contains("@")
            && Self.normalizeRecipientInput(recipientQuery) != nil
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                VStack(alignment: .leading, spacing: 20) {
                    recipientSection
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomComposerBar
                .ignoresSafeArea(.container, edges: .bottom)
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
        .sheet(isPresented: $showingAttachmentImagePicker) {
            ImagePicker(image: $pickedAttachmentImage)
        }
        .sheet(isPresented: $showingAttachmentVideoPicker) {
            VideoPicker(videoURL: $pickedAttachmentVideoURL)
        }
        .fileImporter(
            isPresented: $showingAttachmentFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleAttachmentFileSelection(result)
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await loadRecipientRecords()
        }
        .onAppear {
            updateFocus()
        }
        .onChange(of: selectedRecipient?.lightningAddress) { _, _ in
            updateFocus()
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
        .toolbar(.hidden, for: .navigationBar)
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("To")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.72))

            VStack(alignment: .leading, spacing: 10) {
                if let selectedRecipient {
                    RecipientSelectionChip(
                        recipient: selectedRecipient,
                        onClear: clearSelectedRecipient
                    )
                } else {
                    TextField(
                        "Name or Lightning Address",
                        text: Binding(
                            get: { recipientQuery },
                            set: { setRecipientQuery($0) }
                        )
                    )
                    .focused($focusedField, equals: .recipient)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.next)
                    .foregroundColor(.white)
                    .onSubmit {
                        handleRecipientSubmit()
                    }
                }

                if showsUsernameHint {
                    Text("Typing only a Split username will send to \(lightningDomainSuffix).")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.52))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(fieldSurface)
            )

            if showsRecipientSuggestions {
                recipientSuggestionsDropdown
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showsRecipientSuggestions)
    }

    private var recipientSuggestionsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(recipientSuggestions) { recipient in
                Button(action: {
                    selectRecipient(recipient)
                }) {
                    HStack(spacing: 12) {
                        RecipientAvatar(profilePicURL: recipient.profilePicURL)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipient.displayName)
                                .font(.body.weight(.medium))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Text(recipient.lightningAddress)
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.62))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if recipient.id != recipientSuggestions.last?.id || typedRecipientCandidate != nil {
                    separator
                        .frame(height: 1)
                        .padding(.leading, 62)
                }
            }

            if let typedRecipientCandidate {
                Button(action: {
                    selectTypedRecipientCandidate()
                }) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.splitBrandPink.opacity(0.16))
                                .frame(width: 36, height: 36)

                            Image(systemName: "paperplane.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.splitBrandPink)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Use Lightning Address")
                                .font(.body.weight(.medium))
                                .foregroundColor(.white)

                            Text(typedRecipientCandidate)
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.62))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(fieldSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var bottomComposerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isSending {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)

                    Text("Sending encrypted message...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))
                }
            }

            if let sendError {
                Text(sendError)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
            }

            HStack(alignment: .bottom, spacing: 12) {
                Button(action: {
                    guard !isSending, resolvedRecipientAddress != nil else { return }
                    showAttachmentOptions = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(resolvedRecipientAddress != nil ? .white.opacity(0.86) : .white.opacity(0.18))
                }
                .buttonStyle(.plain)
                .disabled(resolvedRecipientAddress == nil || isSending)

                TextField(
                    "Type an encrypted message...",
                    text: $messageText,
                    axis: .vertical
                )
                .focused($focusedField, equals: .message)
                .lineLimit(1...5)
                .textInputAutocapitalization(.sentences)
                .foregroundColor(.white)
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
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundColor(canSend ? .splitBrandPink : .white.opacity(0.18))
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

    @MainActor
    private func sendMessage() async {
        guard !isSending else { return }

        guard let address = resolvedRecipientAddress else {
            sendError = "Enter a valid Lightning Address."
            return
        }

        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        isSending = true
        sendError = nil

        do {
            let result = try await MessagingSendCoordinator.sendTextMessage(
                lightningAddress: address,
                plaintext: trimmedMessage,
                authManager: authManager,
                walletManager: walletManager
            )

            resetComposer()
            onSent?(result)
            dismiss()
        } catch {
            sendError = error.localizedDescription
        }

        isSending = false
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
                maximumBytes: MessageAttachmentManager.shared.maximumAttachmentBytes
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
                            maximumBytes: MessageAttachmentManager.shared.maximumAttachmentBytes
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
        guard !isSending else { return }

        guard let address = resolvedRecipientAddress else {
            sendError = "Enter a Lightning Address before sending an attachment."
            return
        }

        guard fileData.count <= MessageAttachmentManager.shared.maximumAttachmentBytes else {
            sendError = MessageAttachmentManager.AttachmentManagerError
                .fileTooLarge(maxBytes: MessageAttachmentManager.shared.maximumAttachmentBytes)
                .localizedDescription
            return
        }

        isSending = true
        sendError = nil

        do {
            let result = try await MessagingSendCoordinator.sendAttachment(
                lightningAddress: address,
                fileData: fileData,
                fileName: fileName,
                mimeType: mimeType,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                authManager: authManager,
                walletManager: walletManager
            )

            resetComposer()
            onSent?(result)
            dismiss()
        } catch {
            sendError = error.localizedDescription
        }

        isSending = false
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

            Text("New Message")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            Spacer()

            Color.clear
                .frame(width: 52, height: 1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    @MainActor
    private func loadRecipientRecords() async {
        var mergedByAddress: [String: MessageRecipientRecord] = [:]
        var contactNamesByAddress: [String: String] = [:]

        do {
            let contacts = try await walletManager.listContacts()
            for contact in contacts {
                let normalizedAddress = Self.normalizeLightningAddress(contact.paymentIdentifier)
                guard !normalizedAddress.isEmpty else { continue }

                let trimmedName = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
                contactNamesByAddress[normalizedAddress] = trimmedName

                upsertRecipientRecord(
                    MessageRecipientRecord(
                        lightningAddress: normalizedAddress,
                        displayName: trimmedName.isEmpty ? normalizedAddress : trimmedName,
                        profilePicURL: mergedByAddress[normalizedAddress]?.profilePicURL,
                        lastInteractedAt: mergedByAddress[normalizedAddress]?.lastInteractedAt,
                        source: .contact
                    ),
                    into: &mergedByAddress
                )
            }
        } catch {
            print("Failed to load contacts for compose recipient suggestions: \(error.localizedDescription)")
        }

        for conversation in messageStore.conversationPreviews() {
            guard let lightningAddress = lightningAddress(for: conversation) else { continue }

            let existing = mergedByAddress[lightningAddress]
            let displayName = contactNamesByAddress[lightningAddress]
                ?? existing?.displayName
                ?? conversation.title

            upsertRecipientRecord(
                MessageRecipientRecord(
                    lightningAddress: lightningAddress,
                    displayName: displayName,
                    profilePicURL: existing?.profilePicURL,
                    lastInteractedAt: conversation.latestAt,
                    source: .conversation
                ),
                into: &mergedByAddress
            )
        }

        allRecipientRecords = mergedByAddress.values.sorted { lhs, rhs in
            let lhsDate = lhs.lastInteractedAt ?? .distantPast
            let rhsDate = rhs.lastInteractedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        if let selectedRecipient,
           let resolvedMatch = allRecipientRecords.first(where: { $0.lightningAddress == selectedRecipient.lightningAddress }) {
            self.selectedRecipient = resolvedMatch
        }

        refreshRecipientSuggestions()
    }

    private func upsertRecipientRecord(
        _ record: MessageRecipientRecord,
        into records: inout [String: MessageRecipientRecord]
    ) {
        let normalizedAddress = Self.normalizeLightningAddress(record.lightningAddress)
        guard !normalizedAddress.isEmpty else { return }

        let normalizedDisplayName = record.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = MessageRecipientRecord(
            lightningAddress: normalizedAddress,
            displayName: normalizedDisplayName.isEmpty ? normalizedAddress : normalizedDisplayName,
            profilePicURL: Self.normalizedProfileURL(record.profilePicURL),
            lastInteractedAt: record.lastInteractedAt,
            source: record.source
        )

        if let existing = records[normalizedAddress] {
            records[normalizedAddress] = Self.mergeRecipientRecords(existing: existing, incoming: candidate)
        } else {
            records[normalizedAddress] = candidate
        }
    }

    private func refreshRecipientSuggestions() {
        guard selectedRecipient == nil else {
            recipientSuggestions = []
            return
        }

        let trimmedQuery = trimmedRecipientQuery
        guard !trimmedQuery.isEmpty else {
            recipientSuggestions = []
            return
        }

        let matches = allRecipientRecords
            .compactMap { record -> (record: MessageRecipientRecord, score: Int)? in
                guard let score = recipientMatchScore(for: record, query: trimmedQuery) else {
                    return nil
                }

                return (record, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                let lhsDate = lhs.record.lastInteractedAt ?? .distantPast
                let rhsDate = rhs.record.lastInteractedAt ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }

                return lhs.record.displayName.localizedCaseInsensitiveCompare(rhs.record.displayName) == .orderedAscending
            }
            .prefix(8)
            .map(\.record)

        recipientSuggestions = Array(matches)
    }

    private func recipientMatchScore(
        for record: MessageRecipientRecord,
        query: String
    ) -> Int? {
        let displayName = Self.normalizedSearchText(record.displayName)
        let displayNameKey = Self.compactSearchKey(record.displayName)
        let lightningAddress = Self.normalizedSearchText(record.lightningAddress)
        let username = lightningAddress.split(separator: "@").first.map(String.init) ?? ""
        let displayNameTokens = displayName.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let queryKey = Self.compactSearchKey(query)

        var bestScore = 0

        if displayName == query {
            bestScore = max(bestScore, 140)
        } else if !queryKey.isEmpty, displayNameKey == queryKey {
            bestScore = max(bestScore, 138)
        } else if displayName.hasPrefix(query) {
            bestScore = max(bestScore, 125)
        } else if !queryKey.isEmpty, displayNameKey.hasPrefix(queryKey) {
            bestScore = max(bestScore, 123)
        } else if displayNameTokens.contains(where: { $0.hasPrefix(query) }) {
            bestScore = max(bestScore, 115)
        } else if !queryKey.isEmpty,
                  displayNameTokens.contains(where: { Self.compactSearchKey(String($0)).hasPrefix(queryKey) }) {
            bestScore = max(bestScore, 113)
        } else if displayName.contains(query) {
            bestScore = max(bestScore, 100)
        } else if !queryKey.isEmpty, displayNameKey.contains(queryKey) {
            bestScore = max(bestScore, 98)
        }

        if lightningAddress == query {
            bestScore = max(bestScore, 96)
        } else if username == query {
            bestScore = max(bestScore, 94)
        } else if lightningAddress.hasPrefix(query) {
            bestScore = max(bestScore, 90)
        } else if username.hasPrefix(query) {
            bestScore = max(bestScore, 88)
        } else if lightningAddress.contains(query) || username.contains(query) {
            bestScore = max(bestScore, 80)
        }

        return bestScore > 0 ? bestScore : nil
    }

    private func setRecipientQuery(_ value: String) {
        guard selectedRecipient == nil else { return }
        recipientQuery = value
        sendError = nil
        refreshRecipientSuggestions()
    }

    private func selectRecipient(_ recipient: MessageRecipientRecord) {
        selectedRecipient = recipient
        recipientQuery = ""
        sendError = nil
        refreshRecipientSuggestions()
    }

    private func selectTypedRecipientCandidate() {
        guard let typedRecipientCandidate else { return }

        selectRecipient(
            MessageRecipientRecord(
                lightningAddress: typedRecipientCandidate,
                displayName: typedRecipientCandidate,
                profilePicURL: nil,
                lastInteractedAt: nil,
                source: .conversation
            )
        )
    }

    private func clearSelectedRecipient() {
        selectedRecipient = nil
        sendError = nil
        refreshRecipientSuggestions()
    }

    private func handleRecipientSubmit() {
        if let exactMatch = exactRecipientMatch(for: recipientQuery) {
            selectRecipient(exactMatch)
            return
        }

        if recipientSuggestions.count == 1, let onlySuggestion = recipientSuggestions.first {
            selectRecipient(onlySuggestion)
            return
        }

        if typedRecipientCandidate != nil {
            selectTypedRecipientCandidate()
            return
        }

        if let resolvedRecipientAddress {
            selectRecipient(
                MessageRecipientRecord(
                    lightningAddress: resolvedRecipientAddress,
                    displayName: resolvedRecipientAddress,
                    profilePicURL: nil,
                    lastInteractedAt: nil,
                    source: .conversation
                )
            )
        }
    }

    private func exactRecipientMatch(for rawQuery: String) -> MessageRecipientRecord? {
        let normalizedQuery = Self.normalizedSearchText(rawQuery)
        if let normalizedAddress = Self.normalizeRecipientInput(rawQuery),
           let exactAddressMatch = allRecipientRecords.first(where: { $0.lightningAddress == normalizedAddress }) {
            return exactAddressMatch
        }

        return allRecipientRecords.first { record in
            Self.normalizedSearchText(record.displayName) == normalizedQuery
        }
    }

    private func resetComposer() {
        messageText = ""
        recipientQuery = ""
        selectedRecipient = nil
        refreshRecipientSuggestions()
    }

    private func imageDimensions(from data: Data) -> (width: Int, height: Int)? {
        guard let image = UIImage(data: data) else { return nil }
        let width = image.cgImage?.width ?? Int(image.size.width)
        let height = image.cgImage?.height ?? Int(image.size.height)
        return (width, height)
    }

    private func updateFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            focusedField = resolvedRecipientAddress == nil ? .recipient : .message
        }
    }

    private func lightningAddress(for conversation: MessageConversationPreview) -> String? {
        let normalizedTitle = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedTitle.contains("@") ? normalizedTitle : nil
    }

    private func mimeTypeForFile(at url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = values.contentType,
           let mimeType = contentType.preferredMIMEType {
            return mimeType
        }

        return "application/octet-stream"
    }
}

private extension ComposeMessage {
    static func normalizedSearchText(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    static func compactSearchKey(_ rawValue: String) -> String {
        normalizedSearchText(rawValue)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    static func normalizeLightningAddress(_ lightningAddress: String) -> String {
        lightningAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func normalizeRecipientInput(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let normalized: String
        if trimmed.contains("@") {
            normalized = trimmed
        } else {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
            guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                return nil
            }
            normalized = "\(trimmed)@\(AppConfig.lightningAddressDomain)"
        }

        let pieces = normalized.split(separator: "@", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              !pieces[0].isEmpty,
              !pieces[1].isEmpty else {
            return nil
        }

        return normalized
    }

    static func normalizedProfileURL(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func mergeRecipientRecords(
        existing: MessageRecipientRecord,
        incoming: MessageRecipientRecord
    ) -> MessageRecipientRecord {
        let preferredDisplayName: String
        switch (existing.source, incoming.source) {
        case (.contact, _):
            preferredDisplayName = existing.displayName
        case (_, .contact):
            preferredDisplayName = incoming.displayName
        default:
            preferredDisplayName = existing.displayName.count >= incoming.displayName.count
                ? existing.displayName
                : incoming.displayName
        }

        let preferredProfilePicURL = normalizedProfileURL(incoming.profilePicURL) ?? normalizedProfileURL(existing.profilePicURL)

        let preferredDate: Date?
        switch (existing.lastInteractedAt, incoming.lastInteractedAt) {
        case let (lhs?, rhs?):
            preferredDate = max(lhs, rhs)
        case let (lhs?, nil):
            preferredDate = lhs
        case let (nil, rhs?):
            preferredDate = rhs
        default:
            preferredDate = nil
        }

        let preferredSource: MessageRecipientRecord.Source =
            existing.source == .contact || incoming.source == .contact ? .contact : .conversation

        return MessageRecipientRecord(
            lightningAddress: existing.lightningAddress,
            displayName: preferredDisplayName,
            profilePicURL: preferredProfilePicURL,
            lastInteractedAt: preferredDate,
            source: preferredSource
        )
    }
}

private struct RecipientSelectionChip: View {
    let recipient: MessageRecipientRecord
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RecipientAvatar(profilePicURL: recipient.profilePicURL, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(recipient.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)

                Text(recipient.lightningAddress)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

private struct RecipientAvatar: View {
    let profilePicURL: String?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: size, height: size)

            if let profilePicURL,
               let url = URL(string: profilePicURL),
               !profilePicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
    }
}

#Preview {
    NavigationStack {
        ComposeMessage()
    }
}
