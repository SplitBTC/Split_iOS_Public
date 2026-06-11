import Foundation

struct MessagingBlockedUser: Identifiable, Codable, Hashable {
    let blockId: String
    let blockedMessagingAccountId: String?
    let blockedUserId: String
    let blockedWalletPubkey: String
    let blockedLightningAddress: String?
    let blockedProfilePicUrl: String?
    let createdAt: Date?
    let updatedAt: Date?

    var id: String { blockId }

    var normalizedLightningAddress: String? {
        let normalized = blockedLightningAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }

    enum CodingKeys: String, CodingKey {
        case blockId
        case blockedMessagingAccountId
        case blockedUserId
        case blockedWalletPubkey
        case blockedLightningAddress
        case blockedProfilePicUrl
        case createdAt
        case updatedAt
    }

    init(
        blockId: String,
        blockedMessagingAccountId: String?,
        blockedUserId: String,
        blockedWalletPubkey: String,
        blockedLightningAddress: String?,
        blockedProfilePicUrl: String?,
        createdAt: Date?,
        updatedAt: Date?
    ) {
        self.blockId = blockId
        self.blockedMessagingAccountId = blockedMessagingAccountId
        self.blockedUserId = blockedUserId
        self.blockedWalletPubkey = blockedWalletPubkey
        self.blockedLightningAddress = blockedLightningAddress
        self.blockedProfilePicUrl = blockedProfilePicUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockId = try container.decode(String.self, forKey: .blockId)
        blockedMessagingAccountId = try container.decodeIfPresent(
            String.self,
            forKey: .blockedMessagingAccountId
        )
        blockedUserId = try container.decodeIfPresent(String.self, forKey: .blockedUserId)
            ?? blockedMessagingAccountId
            ?? blockId
        blockedWalletPubkey = try container.decodeIfPresent(String.self, forKey: .blockedWalletPubkey)
            ?? blockedMessagingAccountId
            ?? ""
        blockedLightningAddress = try container.decodeIfPresent(
            String.self,
            forKey: .blockedLightningAddress
        )
        blockedProfilePicUrl = try container.decodeIfPresent(String.self, forKey: .blockedProfilePicUrl)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func withLocalMetadata(walletPubkey: String?, lightningAddress: String?) -> MessagingBlockedUser {
        MessagingBlockedUser(
            blockId: blockId,
            blockedMessagingAccountId: blockedMessagingAccountId,
            blockedUserId: blockedUserId,
            blockedWalletPubkey: walletPubkey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? blockedWalletPubkey,
            blockedLightningAddress: lightningAddress?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? blockedLightningAddress,
            blockedProfilePicUrl: blockedProfilePicUrl,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct MessagingBlockListResponse: Decodable {
    let ok: Bool
    let blocks: [MessagingBlockedUser]
}

private struct MessagingBlockMutationResponse: Decodable {
    let ok: Bool
    let didUpdate: Bool?
    let didDelete: Bool?
    let block: MessagingBlockedUser?
    let blockedWalletPubkey: String?
    let error: String?
}

enum MessagingBlockAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid messaging blocks endpoint URL."
        case .invalidResponse:
            return "Invalid messaging blocks response."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}

enum MessagingBlockAPI {
    private struct CachedBlockMetadata: Codable {
        let blockId: String
        let blockedMessagingAccountId: String?
        let blockedWalletPubkey: String?
        let blockedLightningAddress: String?
    }

    private static var cacheKey: String {
        "split.messaging.v4.blockMetadata.\(AppConfig.messagingPushEnvironment)"
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    @MainActor
    static func fetchBlocks(
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> [MessagingBlockedUser] {
        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/blocks") else {
            throw MessagingBlockAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await perform(request, authManager: authManager, walletManager: walletManager)

        do {
            return try decoder().decode(MessagingBlockListResponse.self, from: data).blocks
                .map(applyCachedMetadata)
        } catch {
            throw MessagingBlockAPIError.invalidResponse
        }
    }

    @MainActor
    static func blockUser(
        walletPubkey: String?,
        lightningAddress: String?,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> MessagingBlockedUser {
        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/blocks") else {
            throw MessagingBlockAPIError.invalidURL
        }

        struct RequestBody: Encodable {
            let lightningAddressHash: String
            let lightningAddressHashScheme: String
        }

        let normalizedWalletPubkey = walletPubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
        guard let normalizedLightningAddress = try? MessagingPrivacyV4.normalizeLightningAddress(lightningAddress ?? ""),
              let lightningAddressHash = try? MessagingPrivacyV4.lightningAddressClientHash(
                for: normalizedLightningAddress
              ) else {
            throw MessagingBlockAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                lightningAddressHash: lightningAddressHash,
                lightningAddressHashScheme: MessagingPrivacyV4.lightningAddressClientHashScheme
            )
        )

        let data = try await perform(request, authManager: authManager, walletManager: walletManager)

        do {
            let decoded = try decoder().decode(MessagingBlockMutationResponse.self, from: data)
            guard let block = decoded.block else {
                throw MessagingBlockAPIError.invalidResponse
            }
            let augmentedBlock = block.withLocalMetadata(
                walletPubkey: normalizedWalletPubkey,
                lightningAddress: normalizedLightningAddress
            )
            cacheMetadata(for: augmentedBlock)
            NotificationCenter.default.post(name: .messagingBlocksDidChange, object: nil)
            return augmentedBlock
        } catch let error as MessagingBlockAPIError {
            throw error
        } catch {
            throw MessagingBlockAPIError.invalidResponse
        }
    }

    @MainActor
    static func unblockUser(
        blockedWalletPubkey: String,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> Bool {
        let targetHash = try blockTargetHash(for: blockedWalletPubkey)
        guard let encodedTarget = targetHash.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw MessagingBlockAPIError.invalidURL
        }
        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/v4/blocks/\(encodedTarget)") else {
            throw MessagingBlockAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await perform(request, authManager: authManager, walletManager: walletManager)

        do {
            let decoded = try decoder().decode(MessagingBlockMutationResponse.self, from: data)
            if decoded.didDelete == true {
                removeCachedMetadata(forTarget: blockedWalletPubkey)
            }
            NotificationCenter.default.post(name: .messagingBlocksDidChange, object: nil)
            return decoded.didDelete ?? false
        } catch {
            throw MessagingBlockAPIError.invalidResponse
        }
    }

    private static func blockTargetHash(for target: String) throws -> String {
        let normalizedTarget = target
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedTarget.contains("@") {
            return try MessagingPrivacyV4.lightningAddressClientHash(for: normalizedTarget)
        }

        if let cached = cachedMetadata().first(where: { metadata in
            metadata.blockedWalletPubkey == normalizedTarget ||
                metadata.blockedMessagingAccountId == normalizedTarget ||
                metadata.blockId == normalizedTarget
        }),
           let lightningAddress = cached.blockedLightningAddress {
            return try MessagingPrivacyV4.lightningAddressClientHash(for: lightningAddress)
        }

        throw MessagingBlockAPIError.invalidResponse
    }

    @MainActor
    private static func perform(
        _ request: URLRequest,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> Data {
        try await authManager.ensureSession(walletManager: walletManager)
        var authenticatedRequest = request
        try await MessagingAuthenticatedWalletHeader.apply(
            to: &authenticatedRequest,
            walletManager: walletManager
        )

        var (data, response) = try await URLSession.shared.data(for: authenticatedRequest)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)
            (data, response) = try await URLSession.shared.data(for: authenticatedRequest)
        }

        guard let http = response as? HTTPURLResponse else {
            throw MessagingBlockAPIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let serverMessage: String

            if let decoded = try? decoder().decode(MessagingBlockMutationResponse.self, from: data),
               let error = decoded.error,
               !error.isEmpty {
                serverMessage = error
            } else {
                serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            }

            throw MessagingBlockAPIError.serverError(
                statusCode: http.statusCode,
                message: serverMessage
            )
        }

        return data
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            if let date = standardFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return decoder
    }

    private static func cachedMetadata() -> [CachedBlockMetadata] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([CachedBlockMetadata].self, from: data) else {
            return []
        }

        return decoded
    }

    private static func saveCachedMetadata(_ entries: [CachedBlockMetadata]) {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }

        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private static func cacheMetadata(for block: MessagingBlockedUser) {
        var entries = cachedMetadata()
        entries.removeAll { entry in
            entry.blockId == block.blockId ||
                (block.blockedMessagingAccountId != nil &&
                    entry.blockedMessagingAccountId == block.blockedMessagingAccountId) ||
                (block.blockedWalletPubkey.nilIfBlank != nil &&
                    entry.blockedWalletPubkey == block.blockedWalletPubkey)
        }
        entries.append(CachedBlockMetadata(
            blockId: block.blockId,
            blockedMessagingAccountId: block.blockedMessagingAccountId,
            blockedWalletPubkey: block.blockedWalletPubkey.nilIfBlank,
            blockedLightningAddress: block.blockedLightningAddress?.nilIfBlank
        ))
        saveCachedMetadata(entries)
    }

    private static func removeCachedMetadata(forTarget target: String) {
        let normalizedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = cachedMetadata().filter { entry in
            entry.blockId != normalizedTarget &&
                entry.blockedMessagingAccountId != normalizedTarget &&
                entry.blockedWalletPubkey != normalizedTarget &&
                entry.blockedLightningAddress != normalizedTarget
        }
        saveCachedMetadata(entries)
    }

    private static func applyCachedMetadata(_ block: MessagingBlockedUser) -> MessagingBlockedUser {
        guard let cached = cachedMetadata().first(where: { entry in
            entry.blockId == block.blockId ||
                (block.blockedMessagingAccountId != nil &&
                    entry.blockedMessagingAccountId == block.blockedMessagingAccountId)
        }) else {
            return block
        }

        return block.withLocalMetadata(
            walletPubkey: cached.blockedWalletPubkey,
            lightningAddress: cached.blockedLightningAddress
        )
    }
}

extension Notification.Name {
    static let messagingBlocksDidChange = Notification.Name("messagingBlocksDidChange")
}
