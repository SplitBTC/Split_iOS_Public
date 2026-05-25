//
//  MessageAttachmentManager.swift
//  Split Rewards
//
//  Created by TeeVee on 3/23/26.
//

import Foundation

struct CachedMessageAttachment: Identifiable, Equatable {
    let attachmentId: String
    let fileName: String
    let localURL: URL

    var id: String { attachmentId }
}

@MainActor
final class MessageAttachmentManager: ObservableObject {
    static let shared = MessageAttachmentManager()

    @Published private(set) var cachedAttachmentIds: Set<String> = []

    private let directoryURL: URL
    private let previewDirectoryURL: URL

    enum AttachmentManagerError: LocalizedError {
        case fileTooLarge(maxBytes: Int)
        case invalidFileData
        case failedToCreateDirectory
        case failedToPersist

        var errorDescription: String? {
            switch self {
            case .fileTooLarge(let maxBytes):
                return "Attachments must be smaller than \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file))."
            case .invalidFileData:
                return "The attachment data is invalid."
            case .failedToCreateDirectory:
                return "Could not prepare local attachment storage."
            case .failedToPersist:
                return "Could not save the attachment locally."
            }
        }
    }

    let maximumAttachmentBytes = 50 * 1024 * 1024

    private init() {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let attachmentsDirectory = baseDirectory
            .appendingPathComponent("Messaging", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        let previewDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MessagingAttachmentPreviews", isDirectory: true)

        directoryURL = attachmentsDirectory
        previewDirectoryURL = previewDirectory
        clearTemporaryPreviewFiles()
        try? ensureDirectoryExists()
        try? migrateLegacyPlaintextAttachmentsIfNeeded()
        cachedAttachmentIds = Self.loadCachedAttachmentIds(from: attachmentsDirectory)
    }

    func hasCachedAttachment(_ payload: AttachmentMessagePayload) -> Bool {
        cachedAttachmentIds.contains(payload.attachmentId) &&
        FileManager.default.fileExists(atPath: fileURL(for: payload.attachmentId, fileName: payload.fileName).path)
    }

    func cachedAttachment(for payload: AttachmentMessagePayload) -> CachedMessageAttachment? {
        guard let plaintextData = cachedAttachmentData(for: payload),
              let previewURL = try? writePreviewFile(
                attachmentId: payload.attachmentId,
                fileName: payload.fileName,
                plaintextData: plaintextData
              ) else {
            return nil
        }

        return CachedMessageAttachment(
            attachmentId: payload.attachmentId,
            fileName: payload.fileName,
            localURL: previewURL
        )
    }

    func cachedAttachmentData(for payload: AttachmentMessagePayload) -> Data? {
        let localURL = fileURL(for: payload.attachmentId, fileName: payload.fileName)

        guard FileManager.default.fileExists(atPath: localURL.path) else {
            return nil
        }

        return try? decryptedCachedData(
            attachmentId: payload.attachmentId,
            fileName: payload.fileName
        )
    }

    func cacheOutgoingAttachment(
        attachmentId: String,
        fileName: String,
        plaintextData: Data
    ) throws {
        try cacheAttachmentData(
            attachmentId: attachmentId,
            fileName: fileName,
            data: plaintextData
        )
    }

    func prepareAttachmentForPreview(
        payload: AttachmentMessagePayload,
        recipientMessagingPubkeyHex: String,
        shouldMarkReceived: Bool,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> CachedMessageAttachment {
        if let cached = cachedAttachment(for: payload) {
            return cached
        }

        let encryptedData = try await MessageAttachmentDownloadAPI.downloadEncryptedAttachment(
            attachmentId: payload.attachmentId,
            authManager: authManager,
            walletManager: walletManager
        )

        let decryptedData = try MessageCryptoManager.shared.decryptAttachmentData(
            ciphertextData: encryptedData,
            nonceBase64: payload.attachmentNonce,
            senderEphemeralPubkeyHex: payload.attachmentSenderEphemeralPubkey,
            recipientMessagingPubkeyHex: recipientMessagingPubkeyHex
        )

        try cacheAttachmentData(
            attachmentId: payload.attachmentId,
            fileName: payload.fileName,
            data: decryptedData
        )

        let previewURL = try writePreviewFile(
            attachmentId: payload.attachmentId,
            fileName: payload.fileName,
            plaintextData: decryptedData
        )

        let previewAttachment = CachedMessageAttachment(
            attachmentId: payload.attachmentId,
            fileName: payload.fileName,
            localURL: previewURL
        )

        if shouldMarkReceived {
            do {
                try await MessageAttachmentReceiptAPI.markReceived(
                    attachmentIds: [payload.attachmentId],
                    authManager: authManager,
                    walletManager: walletManager
                )
            } catch {
                print("Failed to mark attachment \(payload.attachmentId) received: \(error.localizedDescription)")
            }
        }

        return previewAttachment
    }

    func clearAll() {
        do {
            if FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.removeItem(at: directoryURL)
            }
            if FileManager.default.fileExists(atPath: previewDirectoryURL.path) {
                try FileManager.default.removeItem(at: previewDirectoryURL)
            }
            cachedAttachmentIds = []
        } catch {
            print("Failed to clear cached attachments: \(error.localizedDescription)")
        }
    }

    func cleanupTemporaryPreview(_ attachment: CachedMessageAttachment) {
        do {
            if FileManager.default.fileExists(atPath: attachment.localURL.path) {
                try FileManager.default.removeItem(at: attachment.localURL)
            }
        } catch {
            print("Failed to clean up attachment preview: \(error.localizedDescription)")
        }
    }

    private func cacheAttachmentData(
        attachmentId: String,
        fileName: String,
        data: Data
    ) throws {
        guard !data.isEmpty else {
            throw AttachmentManagerError.invalidFileData
        }

        guard data.count <= maximumAttachmentBytes else {
            throw AttachmentManagerError.fileTooLarge(maxBytes: maximumAttachmentBytes)
        }

        try ensureDirectoryExists()

        let localURL = fileURL(for: attachmentId, fileName: fileName)

        do {
            let encryptedData = try SecureMessagingStorage.shared.encrypt(data)
            try encryptedData.write(to: localURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: localURL.path
            )
        } catch {
            throw AttachmentManagerError.failedToPersist
        }

        var updatedIds = cachedAttachmentIds
        updatedIds.insert(attachmentId)
        cachedAttachmentIds = updatedIds
    }

    private func ensureDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw AttachmentManagerError.failedToCreateDirectory
        }
    }

    private func ensurePreviewDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(
                at: previewDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw AttachmentManagerError.failedToCreateDirectory
        }
    }

    private func fileURL(for attachmentId: String, fileName: String) -> URL {
        let safeName = Self.sanitizedFileName(fileName)
        return directoryURL.appendingPathComponent("\(attachmentId)__\(safeName)")
    }

    private func previewFileURL(for attachmentId: String, fileName: String) -> URL {
        let safeName = Self.sanitizedFileName(fileName)
        return previewDirectoryURL.appendingPathComponent("\(attachmentId)__\(safeName)")
    }

    private func decryptedCachedData(
        attachmentId: String,
        fileName: String
    ) throws -> Data {
        let localURL = fileURL(for: attachmentId, fileName: fileName)
        let storedData = try Data(contentsOf: localURL)

        if SecureMessagingStorage.shared.isEncryptedPayload(storedData) {
            return try SecureMessagingStorage.shared.decrypt(storedData)
        }

        let encryptedData = try SecureMessagingStorage.shared.encrypt(storedData)
        try encryptedData.write(to: localURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: localURL.path
        )
        return storedData
    }

    private func writePreviewFile(
        attachmentId: String,
        fileName: String,
        plaintextData: Data
    ) throws -> URL {
        try ensurePreviewDirectoryExists()

        let previewURL = previewFileURL(for: attachmentId, fileName: fileName)
        try plaintextData.write(to: previewURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: previewURL.path
        )
        return previewURL
    }

    private func clearTemporaryPreviewFiles() {
        guard FileManager.default.fileExists(atPath: previewDirectoryURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: previewDirectoryURL)
        } catch {
            print("Failed to clear attachment preview files: \(error.localizedDescription)")
        }
    }

    private func migrateLegacyPlaintextAttachmentsIfNeeded() throws {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in urls {
            let storedData = try Data(contentsOf: url)
            guard !SecureMessagingStorage.shared.isEncryptedPayload(storedData) else {
                continue
            }

            let encryptedData = try SecureMessagingStorage.shared.encrypt(storedData)
            try encryptedData.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        }
    }

    private static func loadCachedAttachmentIds(from directoryURL: URL) -> Set<String> {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return Set(
            urls.compactMap { url in
                let fileName = url.lastPathComponent
                guard let separatorRange = fileName.range(of: "__") else {
                    return nil
                }
                return String(fileName[..<separatorRange.lowerBound])
            }
        )
    }

    private static func sanitizedFileName(_ fileName: String) -> String {
        let candidate = URL(fileURLWithPath: fileName).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = candidate.isEmpty ? "attachment" : candidate
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return fallback.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
}
