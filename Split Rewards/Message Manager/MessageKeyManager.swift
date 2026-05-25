//
//  MessageKeyManager.swift
//  Split Rewards
//
//  Created by TeeVee on 3/20/26.
//

import Foundation
import CryptoKit
import BreezSdkSpark

struct MessageSigningCertificate: Codable, Hashable {
    let walletPubkey: String
    let lightningAddress: String
    let messagingPubkey: String
    let messagingSigningPubkey: String
    let messagingSigningPubkeySignature: String
    let messagingSigningPubkeySignatureVersion: Int
    let messagingSigningPubkeySignedAt: Int
}

@MainActor
final class MessageKeyManager {
    static let shared = MessageKeyManager()

    private let messagingV2PrivateKeyKeychainKeyBase = "split.messaging.v2.privateKey"
    private let messagingSigningPrivateKeyKeychainKeyBase = "split.messaging.v3.signingPrivateKey"
    private let messagingSigningCertificateKeychainKeyBase = "split.messaging.v3.signingCertificate"
    private let messagingIdentityDomain = AppConfig.messagingIdentityDomain
    private let selfHealingRotationCooldownSeconds: TimeInterval = 60 * 60 * 12
    private let lightningAddressLookupRetryDelayNanoseconds: UInt64 = 500_000_000
    private let lightningAddressLookupMaxAttempts = 4

    private init() {}

    struct RegistrationResponse: Decodable {
        let ok: Bool
        let walletPubkey: String?
        let lightningAddress: String?
        let didUpdate: Bool?
        let didRotate: Bool?
        let messagingPubkey: String?
        let messagingIdentitySignature: String?
        let messagingIdentitySignatureVersion: Int?
        let messagingIdentitySignedAt: Date?
        let messagingIdentityUpdatedAt: Date?
        let directory: MessagingDirectoryProofPayload?
        let error: String?

        var normalizedLightningAddress: String? {
            let normalized = lightningAddress?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard let normalized, !normalized.isEmpty else { return nil }
            return normalized
        }

        var identityBindingPayload: MessagingIdentityBindingPayload? {
            guard let walletPubkey = walletPubkey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !walletPubkey.isEmpty,
                  let lightningAddress = normalizedLightningAddress,
                  let messagingPubkey = messagingPubkey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !messagingPubkey.isEmpty,
                  let messagingIdentitySignature = messagingIdentitySignature?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !messagingIdentitySignature.isEmpty,
                  let messagingIdentitySignatureVersion,
                  let messagingIdentitySignedAt
            else {
                return nil
            }

            return MessagingIdentityBindingPayload(
                walletPubkey: walletPubkey,
                lightningAddress: lightningAddress,
                messagingPubkey: messagingPubkey,
                messagingIdentitySignature: messagingIdentitySignature,
                messagingIdentitySignatureVersion: messagingIdentitySignatureVersion,
                messagingIdentitySignedAt: Int(messagingIdentitySignedAt.timeIntervalSince1970)
            )
        }
    }

    enum MessageKeyError: LocalizedError {
        case invalidURL
        case invalidStoredKey
        case invalidResponse
        case inactiveOnAnotherDevice
        case missingLightningAddress
        case serverError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid messaging key registration URL."
            case .invalidStoredKey:
                return "Stored messaging key is invalid."
            case .invalidResponse:
                return "Invalid messaging key registration response."
            case .inactiveOnAnotherDevice:
                return "Messaging is active on another device."
            case .missingLightningAddress:
                return "Create a Lightning Address before activating messaging."
            case .serverError(let statusCode, let message):
                return "Server error (\(statusCode)): \(message)"
            }
        }
    }

    private enum IdentityEndpoint {
        case v3

        var path: String {
            switch self {
            case .v3:
                return "/messaging/v3/identity"
            }
        }

        var signatureVersion: Int {
            switch self {
            case .v3:
                return 2
            }
        }

        var enforcesInactiveDeviceCheck: Bool {
            false
        }

        var claimsActiveBinding: Bool {
            true
        }
    }

    private enum MessagingKeyVersion {
        case v2

        var baseKeychainKey: String {
            switch self {
            case .v2:
                return "split.messaging.v2.privateKey"
            }
        }
    }

    private struct KeyState {
        let privateKey: Curve25519.KeyAgreement.PrivateKey
        let didCreate: Bool
    }

    private struct LocalIdentity {
        let walletPubkey: String
        let lightningAddress: String
        let messagingPubkey: String
    }

    private struct MessagingIdentityRegistrationRequest: Encodable {
        let walletPubkey: String
        let lightningAddress: String
        let messagingPubkey: String
        let messagingIdentitySignature: String
        let messagingIdentitySignatureVersion: Int
        let messagingIdentitySignedAt: Int
    }

    func ensureRegistered(
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> RegistrationResponse {
        let identityEndpoint: IdentityEndpoint = .v3

        try await authManager.ensureSession(walletManager: walletManager)

        let walletPubkey = try await currentWalletPubkey(walletManager: walletManager)
        guard let lightningAddress = try await fetchLocalLightningAddressWithRetry(
            walletManager: walletManager
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !lightningAddress.isEmpty else {
            throw MessageKeyError.missingLightningAddress
        }

        let currentRegistration = try await fetchCurrentRegistration(
            for: identityEndpoint,
            authManager: authManager,
            walletManager: walletManager
        )
        let v2KeyState = try loadOrCreatePrivateKey(
            for: .v2,
            matchingServerPubkey: currentRegistration.messagingPubkey
        )

        let v2LocalIdentity = LocalIdentity(
            walletPubkey: walletPubkey,
            lightningAddress: lightningAddress,
            messagingPubkey: hexString(for: v2KeyState.privateKey.publicKey.rawRepresentation)
        )

        let v2Registration = try await ensureRegistration(
            for: identityEndpoint,
            localIdentity: v2LocalIdentity,
            keyState: v2KeyState,
            currentRegistration: currentRegistration,
            authManager: authManager,
            walletManager: walletManager
        )

        return v2Registration
    }

    func currentMessagingPublicKeyHex() throws -> String {
        let keyState = try loadOrCreatePrivateKey(for: .v2)
        return hexString(for: keyState.privateKey.publicKey.rawRepresentation)
    }

    func currentMessagingPrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        try loadOrCreatePrivateKey(for: .v2).privateKey
    }

    func currentMessageSigningCertificate(
        senderBinding: MessagingIdentityBindingPayload,
        walletManager: WalletManager
    ) async throws -> MessageSigningCertificate {
        let signingKey = try loadOrCreateSigningPrivateKey()
        let signingPubkey = hexString(for: signingKey.publicKey.rawRepresentation)

        if let certificate = try loadSigningCertificateIfPresent(),
           isSigningCertificateValid(
            certificate,
            senderBinding: senderBinding,
            signingPubkey: signingPubkey
           ) {
            return certificate
        }

        let signedAt = Int(Date().timeIntervalSince1970)
        let canonicalMessage = buildMessagingSigningKeyBindingMessage(
            version: 1,
            walletPubkey: senderBinding.walletPubkey,
            lightningAddress: senderBinding.lightningAddress,
            messagingPubkey: senderBinding.messagingPubkey,
            messagingSigningPubkey: signingPubkey,
            signedAt: signedAt
        )
        let signed = try await walletManager.signAuthMessage(canonicalMessage)

        guard signed.pubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == senderBinding.walletPubkey.lowercased() else {
            throw MessageKeyError.invalidResponse
        }

        let certificate = MessageSigningCertificate(
            walletPubkey: senderBinding.walletPubkey,
            lightningAddress: senderBinding.lightningAddress,
            messagingPubkey: senderBinding.messagingPubkey,
            messagingSigningPubkey: signingPubkey,
            messagingSigningPubkeySignature: signed.signature,
            messagingSigningPubkeySignatureVersion: 1,
            messagingSigningPubkeySignedAt: signedAt
        )
        try saveSigningCertificate(certificate)
        return certificate
    }

    func signMessageEnvelope(_ canonicalMessage: String) throws -> String {
        let signingKey = try loadOrCreateSigningPrivateKey()
        let signature = try signingKey.signature(for: Data(canonicalMessage.utf8))
        return hexString(for: signature)
    }

    func rotateMessagingIdentityAfterSameKeyFailure(
        authManager: AuthManager,
        walletManager: WalletManager,
        reason: String
    ) async throws -> RegistrationResponse? {
        let cooldownKey = "split.messaging.lastSelfHealingRotation.\(AppConfig.messagingPushEnvironment)"
        let lastRotation = UserDefaults.standard.double(forKey: cooldownKey)
        let now = Date().timeIntervalSince1970

        if lastRotation > 0, now - lastRotation < selfHealingRotationCooldownSeconds {
            return nil
        }

        let response = try await rotateMessagingIdentity(
            authManager: authManager,
            walletManager: walletManager,
            reason: reason
        )
        UserDefaults.standard.set(now, forKey: cooldownKey)
        return response
    }

    func messagingPrivateKey(
        forRecipientMessagingPubkey recipientMessagingPubkey: String
    ) throws -> Curve25519.KeyAgreement.PrivateKey {
        let normalizedRecipientMessagingPubkey = recipientMessagingPubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let v2PrivateKey = try loadPrivateKeyIfPresent(for: .v2),
           hexString(for: v2PrivateKey.publicKey.rawRepresentation) == normalizedRecipientMessagingPubkey {
            return v2PrivateKey
        }

        throw MessageKeyError.invalidStoredKey
    }

    func currentWalletPubkey(walletManager: WalletManager) async throws -> String {
        guard let sdk = walletManager.sdk else {
            throw AuthManager.AuthError.missingSigningProvider
        }

        let info = try await sdk.getInfo(request: GetInfoRequest(ensureSynced: false))
        return info.identityPubkey
    }

    func clearStoredMessagingKey() {
        allKeychainKeys(for: .v2).forEach { key in
            KeychainHelper.delete(forKey: key)
        }
        clearSigningMaterial()
        UserDefaults.standard.removeObject(
            forKey: "split.messaging.lastSelfHealingRotation.\(AppConfig.messagingPushEnvironment)"
        )
        MessageDirectoryCheckpointStore.clear()
    }

    private func clearSigningMaterial() {
        allSigningPrivateKeychainKeys().forEach { key in
            KeychainHelper.delete(forKey: key)
        }
        allSigningCertificateKeychainKeys().forEach { key in
            KeychainHelper.delete(forKey: key)
        }
    }

    func shouldSilentlyDeferActivation(for error: Error) -> Bool {
        if let messageKeyError = error as? MessageKeyError {
            switch messageKeyError {
            case .missingLightningAddress, .inactiveOnAnotherDevice:
                return true
            default:
                return false
            }
        }

        let description = error.localizedDescription.lowercased()
        return description.contains("lightningaddress must exist before messaging can be activated") ||
            description.contains("messaging identity is not registered") ||
            description.contains("messaging key is not registered") ||
            description.contains("messaging is active on another device")
    }

    func buildMessagingIdentityBindingMessage(
        version: Int,
        walletPubkey: String,
        lightningAddress: String,
        messagingPubkey: String,
        signedAt: Int
    ) -> String {
        """
        SplitRewards Messaging Identity Authorization
        version=\(version)
        domain=\(messagingIdentityDomain)
        walletPubkey=\(walletPubkey)
        lightningAddress=\(lightningAddress)
        messagingPubkey=\(messagingPubkey)
        signedAt=\(signedAt)
        """
    }

    func buildMessagingSigningKeyBindingMessage(
        version: Int,
        walletPubkey: String,
        lightningAddress: String,
        messagingPubkey: String,
        messagingSigningPubkey: String,
        signedAt: Int
    ) -> String {
        """
        SplitRewards Messaging Signing Key Authorization
        version=\(version)
        domain=\(messagingIdentityDomain)
        walletPubkey=\(walletPubkey)
        lightningAddress=\(lightningAddress)
        messagingPubkey=\(messagingPubkey)
        messagingSigningPubkey=\(messagingSigningPubkey)
        signedAt=\(signedAt)
        """
    }

    private func ensureRegistration(
        for endpoint: IdentityEndpoint,
        localIdentity: LocalIdentity,
        keyState: KeyState,
        currentRegistration: RegistrationResponse,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> RegistrationResponse {
        var localIdentity = localIdentity
        var keyState = keyState
        let current = currentRegistration

        if isRegistrationValid(
            current,
            for: endpoint,
            localIdentity: localIdentity
        ) {
            return current
        }

        if endpoint.enforcesInactiveDeviceCheck,
           let currentMessagingPubkey = current.messagingPubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !currentMessagingPubkey.isEmpty,
           currentMessagingPubkey != localIdentity.messagingPubkey,
           !keyState.didCreate {
            throw MessageKeyError.inactiveOnAnotherDevice
        }

        if endpoint.claimsActiveBinding,
           let currentMessagingPubkey = current.messagingPubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !currentMessagingPubkey.isEmpty,
           currentMessagingPubkey != localIdentity.messagingPubkey {
            let rotatedPrivateKey = Curve25519.KeyAgreement.PrivateKey()
            savePrivateKey(rotatedPrivateKey, for: .v2)
            keyState = KeyState(privateKey: rotatedPrivateKey, didCreate: true)
            localIdentity = LocalIdentity(
                walletPubkey: localIdentity.walletPubkey,
                lightningAddress: localIdentity.lightningAddress,
                messagingPubkey: hexString(for: rotatedPrivateKey.publicKey.rawRepresentation)
            )
        }

        let signedAt = Int(Date().timeIntervalSince1970)
        let canonicalMessage = buildMessagingIdentityBindingMessage(
            version: endpoint.signatureVersion,
            walletPubkey: localIdentity.walletPubkey,
            lightningAddress: localIdentity.lightningAddress,
            messagingPubkey: localIdentity.messagingPubkey,
            signedAt: signedAt
        )
        let signed = try await walletManager.signAuthMessage(canonicalMessage)

        let normalizedSignedWalletPubkey = signed.pubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedSignedWalletPubkey != localIdentity.walletPubkey.lowercased() {
            throw MessageKeyError.invalidResponse
        }

        let response = try await postRegistration(
            to: endpoint,
            requestBody: MessagingIdentityRegistrationRequest(
                walletPubkey: signed.pubkey,
                lightningAddress: localIdentity.lightningAddress,
                messagingPubkey: localIdentity.messagingPubkey,
                messagingIdentitySignature: signed.signature,
                messagingIdentitySignatureVersion: endpoint.signatureVersion,
                messagingIdentitySignedAt: signedAt
            ),
            authManager: authManager,
            walletManager: walletManager
        )

        guard isRegistrationValid(
            response,
            for: endpoint,
            localIdentity: localIdentity
        ) else {
            throw MessageKeyError.invalidResponse
        }

        return response
    }

    private func rotateMessagingIdentity(
        authManager: AuthManager,
        walletManager: WalletManager,
        reason: String
    ) async throws -> RegistrationResponse {
        try await authManager.ensureSession(walletManager: walletManager)

        let walletPubkey = try await currentWalletPubkey(walletManager: walletManager)
        guard let lightningAddress = try await fetchLocalLightningAddressWithRetry(
            walletManager: walletManager
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !lightningAddress.isEmpty else {
            throw MessageKeyError.missingLightningAddress
        }

        let endpoint: IdentityEndpoint = .v3
        let rotatedPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        savePrivateKey(rotatedPrivateKey, for: .v2)
        clearSigningMaterial()

        let localIdentity = LocalIdentity(
            walletPubkey: walletPubkey,
            lightningAddress: lightningAddress,
            messagingPubkey: hexString(for: rotatedPrivateKey.publicKey.rawRepresentation)
        )
        let signedAt = Int(Date().timeIntervalSince1970)
        let canonicalMessage = buildMessagingIdentityBindingMessage(
            version: endpoint.signatureVersion,
            walletPubkey: localIdentity.walletPubkey,
            lightningAddress: localIdentity.lightningAddress,
            messagingPubkey: localIdentity.messagingPubkey,
            signedAt: signedAt
        )
        let signed = try await walletManager.signAuthMessage(canonicalMessage)

        guard signed.pubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == localIdentity.walletPubkey.lowercased() else {
            throw MessageKeyError.invalidResponse
        }

        let response = try await postRegistration(
            to: endpoint,
            requestBody: MessagingIdentityRegistrationRequest(
                walletPubkey: signed.pubkey,
                lightningAddress: localIdentity.lightningAddress,
                messagingPubkey: localIdentity.messagingPubkey,
                messagingIdentitySignature: signed.signature,
                messagingIdentitySignatureVersion: endpoint.signatureVersion,
                messagingIdentitySignedAt: signedAt
            ),
            authManager: authManager,
            walletManager: walletManager
        )

        guard isRegistrationValid(
            response,
            for: endpoint,
            localIdentity: localIdentity
        ) else {
            throw MessageKeyError.invalidResponse
        }

        print("Rotated messaging identity after same-key failure: \(reason)")
        return response
    }

    private func fetchCurrentRegistration(
        for endpoint: IdentityEndpoint,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> RegistrationResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)\(endpoint.path)") else {
            throw MessageKeyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MessageKeyError.invalidResponse
        }

        do {
            return try registrationDecoder().decode(RegistrationResponse.self, from: data)
        } catch {
            throw MessageKeyError.invalidResponse
        }
    }

    private func postRegistration(
        to endpoint: IdentityEndpoint,
        requestBody: MessagingIdentityRegistrationRequest,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> RegistrationResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)\(endpoint.path)") else {
            throw MessageKeyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(requestBody)

        var (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MessageKeyError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let serverMessage: String

            if let decoded = try? registrationDecoder().decode(RegistrationResponse.self, from: data),
               let error = decoded.error,
               !error.isEmpty {
                serverMessage = error
            } else {
                serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            }

            throw MessageKeyError.serverError(
                statusCode: httpResponse.statusCode,
                message: serverMessage
            )
        }

        do {
            return try registrationDecoder().decode(RegistrationResponse.self, from: data)
        } catch {
            throw MessageKeyError.invalidResponse
        }
    }

    private func isRegistrationValid(
        _ response: RegistrationResponse,
        for endpoint: IdentityEndpoint,
        localIdentity: LocalIdentity
    ) -> Bool {
        guard let binding = response.identityBindingPayload,
              binding.messagingIdentitySignatureVersion == endpoint.signatureVersion,
              binding.walletPubkey.lowercased() == localIdentity.walletPubkey.lowercased(),
              binding.lightningAddress == localIdentity.lightningAddress,
              binding.messagingPubkey == localIdentity.messagingPubkey
        else {
            return false
        }

        do {
            try MessageKeyBindingVerifier.verifyBinding(binding)
            return true
        } catch {
            return false
        }
    }

    private func fetchLocalLightningAddressWithRetry(
        walletManager: WalletManager
    ) async throws -> String? {
        var lastResult: String?

        for attempt in 1...lightningAddressLookupMaxAttempts {
            lastResult = try await walletManager.fetchLightningAddress()?.lightningAddress

            if let lastResult,
               !lastResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return lastResult
            }

            if let cachedLightningAddress = walletManager.cachedLightningAddress(),
               !cachedLightningAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cachedLightningAddress
            }

            guard attempt < lightningAddressLookupMaxAttempts else {
                break
            }

            try? await Task.sleep(nanoseconds: lightningAddressLookupRetryDelayNanoseconds)
        }

        return lastResult
    }

    private func registrationDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let standardFormatter = ISO8601DateFormatter()
            standardFormatter.formatOptions = [.withInternetDateTime]

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

    private func loadPrivateKeyIfPresent(
        for version: MessagingKeyVersion
    ) throws -> Curve25519.KeyAgreement.PrivateKey? {
        let preferredKey = preferredKeychainKey(for: version)

        guard let stored = KeychainHelper.read(forKey: preferredKey) else {
            return nil
        }

        do {
            return try decodePrivateKey(from: stored)
        } catch {
            KeychainHelper.delete(forKey: preferredKey)
            return nil
        }
    }

    private func loadLegacyPrivateKeyIfPresent(
        for version: MessagingKeyVersion
    ) throws -> Curve25519.KeyAgreement.PrivateKey? {
        guard let stored = KeychainHelper.read(forKey: version.baseKeychainKey) else {
            return nil
        }

        do {
            return try decodePrivateKey(from: stored)
        } catch {
            KeychainHelper.delete(forKey: version.baseKeychainKey)
            return nil
        }
    }

    private func decodePrivateKey(
        from stored: String
    ) throws -> Curve25519.KeyAgreement.PrivateKey {
        guard let data = Data(base64Encoded: stored) else {
            throw MessageKeyError.invalidStoredKey
        }

        do {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        } catch {
            throw MessageKeyError.invalidStoredKey
        }
    }

    private func preferredKeychainKey(for version: MessagingKeyVersion) -> String {
        switch version {
        case .v2:
            return "\(messagingV2PrivateKeyKeychainKeyBase).\(AppConfig.messagingPushEnvironment)"
        }
    }

    private func readableKeychainKeys(for version: MessagingKeyVersion) -> [String] {
        let preferredKey = preferredKeychainKey(for: version)

        switch version {
        case .v2:
            return [preferredKey]
        }
    }

    private func allKeychainKeys(for version: MessagingKeyVersion) -> [String] {
        switch version {
        case .v2:
            return [
                version.baseKeychainKey,
                "\(messagingV2PrivateKeyKeychainKeyBase).dev",
                "\(messagingV2PrivateKeyKeychainKeyBase).prod"
            ]
        }
    }

    private func savePrivateKey(
        _ privateKey: Curve25519.KeyAgreement.PrivateKey,
        for version: MessagingKeyVersion
    ) {
        let encoded = privateKey.rawRepresentation.base64EncodedString()
        KeychainHelper.save(encoded, forKey: preferredKeychainKey(for: version))
    }

    private func loadSigningCertificateIfPresent() throws -> MessageSigningCertificate? {
        let preferredKey = preferredSigningCertificateKeychainKey()

        for key in readableSigningCertificateKeychainKeys() {
            guard let stored = KeychainHelper.read(forKey: key),
                  let data = stored.data(using: .utf8) else {
                continue
            }

            do {
                let certificate = try JSONDecoder().decode(MessageSigningCertificate.self, from: data)
                if key != preferredKey,
                   KeychainHelper.read(forKey: preferredKey) == nil {
                    KeychainHelper.save(stored, forKey: preferredKey)
                }
                return certificate
            } catch {
                KeychainHelper.delete(forKey: key)
            }
        }

        return nil
    }

    private func saveSigningCertificate(_ certificate: MessageSigningCertificate) throws {
        let data = try JSONEncoder().encode(certificate)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw MessageKeyError.invalidStoredKey
        }
        KeychainHelper.save(encoded, forKey: preferredSigningCertificateKeychainKey())
    }

    private func isSigningCertificateValid(
        _ certificate: MessageSigningCertificate,
        senderBinding: MessagingIdentityBindingPayload,
        signingPubkey: String
    ) -> Bool {
        guard certificate.walletPubkey.lowercased() == senderBinding.walletPubkey.lowercased(),
              certificate.lightningAddress == senderBinding.lightningAddress,
              certificate.messagingPubkey == senderBinding.messagingPubkey,
              certificate.messagingSigningPubkey.lowercased() == signingPubkey.lowercased(),
              certificate.messagingSigningPubkeySignatureVersion == 1 else {
            return false
        }

        do {
            try MessageKeyBindingVerifier.verifyMessagingSigningCertificate(certificate)
            return true
        } catch {
            return false
        }
    }

    private func loadSigningPrivateKeyIfPresent() throws -> Curve25519.Signing.PrivateKey? {
        let preferredKey = preferredSigningPrivateKeychainKey()

        for key in readableSigningPrivateKeychainKeys() {
            guard let stored = KeychainHelper.read(forKey: key) else {
                continue
            }

            guard let data = Data(base64Encoded: stored) else {
                KeychainHelper.delete(forKey: key)
                continue
            }

            do {
                let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
                if key != preferredKey,
                   KeychainHelper.read(forKey: preferredKey) == nil {
                    KeychainHelper.save(stored, forKey: preferredKey)
                }
                return privateKey
            } catch {
                KeychainHelper.delete(forKey: key)
            }
        }

        return nil
    }

    private func loadOrCreateSigningPrivateKey() throws -> Curve25519.Signing.PrivateKey {
        if let privateKey = try loadSigningPrivateKeyIfPresent() {
            return privateKey
        }

        let privateKey = Curve25519.Signing.PrivateKey()
        KeychainHelper.save(
            privateKey.rawRepresentation.base64EncodedString(),
            forKey: preferredSigningPrivateKeychainKey()
        )
        return privateKey
    }

    private func preferredSigningPrivateKeychainKey() -> String {
        "\(messagingSigningPrivateKeyKeychainKeyBase).\(AppConfig.messagingPushEnvironment)"
    }

    private func readableSigningPrivateKeychainKeys() -> [String] {
        [
            preferredSigningPrivateKeychainKey()
        ]
    }

    private func allSigningPrivateKeychainKeys() -> [String] {
        [
            messagingSigningPrivateKeyKeychainKeyBase,
            "\(messagingSigningPrivateKeyKeychainKeyBase).dev",
            "\(messagingSigningPrivateKeyKeychainKeyBase).prod"
        ]
    }

    private func preferredSigningCertificateKeychainKey() -> String {
        "\(messagingSigningCertificateKeychainKeyBase).\(AppConfig.messagingPushEnvironment)"
    }

    private func readableSigningCertificateKeychainKeys() -> [String] {
        [
            preferredSigningCertificateKeychainKey()
        ]
    }

    private func allSigningCertificateKeychainKeys() -> [String] {
        [
            messagingSigningCertificateKeychainKeyBase,
            "\(messagingSigningCertificateKeychainKeyBase).dev",
            "\(messagingSigningCertificateKeychainKeyBase).prod"
        ]
    }

    private func loadOrCreatePrivateKey(
        for version: MessagingKeyVersion,
        matchingServerPubkey serverPubkey: String? = nil
    ) throws -> KeyState {
        if let privateKey = try loadPrivateKeyIfPresent(for: version) {
            return KeyState(privateKey: privateKey, didCreate: false)
        }

        let normalizedServerPubkey = serverPubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let normalizedServerPubkey,
           !normalizedServerPubkey.isEmpty,
           let legacyPrivateKey = try loadLegacyPrivateKeyIfPresent(for: version),
           hexString(for: legacyPrivateKey.publicKey.rawRepresentation) == normalizedServerPubkey {
            savePrivateKey(legacyPrivateKey, for: version)
            return KeyState(privateKey: legacyPrivateKey, didCreate: false)
        }

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        savePrivateKey(privateKey, for: version)
        return KeyState(privateKey: privateKey, didCreate: true)
    }

    private func hexString(for data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
