//  LNURL.swift
//  Split Rewards
//
//  Created by TeeVee on 3/11/26.
//

import Foundation
import BreezSdkSpark

@MainActor
extension WalletManager {
    private static let cachedLightningAddressDefaultsKey = "split.cachedLightningAddress"

    // MARK: - Types

    struct LightningAddressInfo: Equatable {
        let lightningAddress: String
        let username: String
        let description: String?
        let lnurlUrl: String
        let lnurlBech32: String
    }

    enum LightningAddressError: LocalizedError {
        case sdkNotInitialized
        case invalidUsername
        case usernameUnavailable
        case emptyUsername

        var errorDescription: String? {
            switch self {
            case .sdkNotInitialized:
                return "Wallet SDK is not initialized."
            case .invalidUsername:
                return "Lightning address names can only use letters, numbers, underscores, hyphens, and periods."
            case .usernameUnavailable:
                return "That Lightning address is already taken."
            case .emptyUsername:
                return "Please enter a Lightning address name."
            }
        }
    }
    
    // MARK: - Public API

    /// Returns the currently registered Lightning address for this wallet, if one exists.
    func fetchLightningAddress() async throws -> LightningAddressInfo? {
        guard let sdk else {
            throw LightningAddressError.sdkNotInitialized
        }

        let addressInfoOpt = try await sdk.getLightningAddress()

        guard let addressInfo = addressInfoOpt else {
            return nil
        }

        cacheLightningAddress(addressInfo.lightningAddress)

        return LightningAddressInfo(
            lightningAddress: addressInfo.lightningAddress,
            username: addressInfo.username,
            description: addressInfo.description.nilIfBlank,
            lnurlUrl: addressInfo.lnurl.url,
            lnurlBech32: addressInfo.lnurl.bech32
        )
    }

    /// Quick availability check before trying to register.
    func isLightningAddressAvailable(username rawUsername: String) async throws -> Bool {
        guard let sdk else {
            throw LightningAddressError.sdkNotInitialized
        }

        let username = try normalizedLightningUsername(rawUsername)

        let request = CheckLightningAddressRequest(
            username: username
        )

        return try await sdk.checkLightningAddressAvailable(req: request)
    }

    /// Registers a new Lightning address for this wallet.
    ///
    /// Description is optional. If omitted, Breez will use its default description behavior.
    func createLightningAddress(
        username rawUsername: String,
        description rawDescription: String? = nil
    ) async throws -> LightningAddressInfo {
        guard let sdk else {
            throw LightningAddressError.sdkNotInitialized
        }

        let username = try normalizedLightningUsername(rawUsername)

        let available = try await isLightningAddressAvailable(username: username)
        guard available else {
            throw LightningAddressError.usernameUnavailable
        }

        let description = rawDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

        let request = RegisterLightningAddressRequest(
            username: username,
            description: description
        )

        let addressInfo = try await sdk.registerLightningAddress(request: request)

        cacheLightningAddress(addressInfo.lightningAddress)

        return LightningAddressInfo(
            lightningAddress: addressInfo.lightningAddress,
            username: addressInfo.username,
            description: addressInfo.description.nilIfBlank,
            lnurlUrl: addressInfo.lnurl.url,
            lnurlBech32: addressInfo.lnurl.bech32
        )
    }

    /// Deletes the currently registered Lightning address for this wallet.
    func deleteCurrentLightningAddress() async throws {
        guard let sdk else {
            throw LightningAddressError.sdkNotInitialized
        }

        try await sdk.deleteLightningAddress()
        clearCachedLightningAddress()
    }

    func cachedLightningAddress() -> String? {
        let cached = UserDefaults.standard.string(forKey: Self.cachedLightningAddressDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let cached, !cached.isEmpty else { return nil }
        return cached
    }

    func clearCachedLightningAddress() {
        UserDefaults.standard.removeObject(forKey: Self.cachedLightningAddressDefaultsKey)
    }

    private func cacheLightningAddress(_ lightningAddress: String) {
        let normalized = lightningAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        UserDefaults.standard.set(normalized, forKey: Self.cachedLightningAddressDefaultsKey)
    }

    // MARK: - Helpers

    /// Normalize to a safe username for `username@domain`.
    ///
    /// Breez docs show the SDK expects a username string; we normalize on the app side
    /// so ProfileView has a predictable rule set before hitting the SDK. :contentReference[oaicite:1]{index=1}
    func normalizedLightningUsername(_ input: String) throws -> String {
        let username = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !username.isEmpty else {
            throw LightningAddressError.emptyUsername
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        let scalars = username.unicodeScalars

        guard scalars.allSatisfy({ allowed.contains($0) }) else {
            throw LightningAddressError.invalidUsername
        }

        return username
    }
    
}

extension String {
    var nilIfBlank: String? {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
