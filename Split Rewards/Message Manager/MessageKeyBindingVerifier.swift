//
//  MessageKeyBindingVerifier.swift
//  Split Rewards
//
//  Created by TeeVee on 3/21/26.
//

import Foundation
import CryptoKit
import secp256k1

struct MessagingIdentityBindingPayload: Codable, Hashable {
    let walletPubkey: String
    let lightningAddress: String
    let messagingPubkey: String
    let messagingIdentitySignature: String
    let messagingIdentitySignatureVersion: Int
    let messagingIdentitySignedAt: Int
}

enum MessageRecipientTrustStore {
    enum TrustError: LocalizedError {
        case invalidLightningAddress
        case conflictingWallet(lightningAddress: String, expectedWalletPubkey: String, receivedWalletPubkey: String)

        var errorDescription: String? {
            switch self {
            case .invalidLightningAddress:
                return "The recipient Lightning address is invalid."
            case .conflictingWallet(let lightningAddress, _, _):
                return "This Lightning address no longer matches the wallet you previously verified: \(lightningAddress)"
            }
        }
    }

    private static var pinnedRecipientsDefaultsKey: String {
        "split.messaging.trustedRecipientsByLightningAddress.\(AppConfig.messagingPushEnvironment)"
    }

    static func enforceOrPin(_ binding: MessagingIdentityBindingPayload) throws {
        let normalizedLightningAddress = try normalizeLightningAddress(binding.lightningAddress)
        let normalizedWalletPubkey = binding.walletPubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedWalletPubkey.isEmpty else {
            throw TrustError.invalidLightningAddress
        }

        var pinnedRecipients = UserDefaults.standard.dictionary(
            forKey: pinnedRecipientsDefaultsKey
        ) as? [String: String] ?? [:]

        if let existingWalletPubkey = pinnedRecipients[normalizedLightningAddress],
           existingWalletPubkey.lowercased() != normalizedWalletPubkey {
            throw TrustError.conflictingWallet(
                lightningAddress: normalizedLightningAddress,
                expectedWalletPubkey: existingWalletPubkey,
                receivedWalletPubkey: normalizedWalletPubkey
            )
        }

        if pinnedRecipients[normalizedLightningAddress] == nil {
            pinnedRecipients[normalizedLightningAddress] = normalizedWalletPubkey
            UserDefaults.standard.set(pinnedRecipients, forKey: pinnedRecipientsDefaultsKey)
        }
    }

    static func pinnedWalletPubkey(for lightningAddress: String) -> String? {
        guard let normalizedLightningAddress = try? normalizeLightningAddress(lightningAddress) else {
            return nil
        }

        return (UserDefaults.standard.dictionary(
            forKey: pinnedRecipientsDefaultsKey
        ) as? [String: String])?[normalizedLightningAddress]
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: pinnedRecipientsDefaultsKey)
    }

    private static func normalizeLightningAddress(_ value: String) throws -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard normalized.contains("@"), !normalized.isEmpty else {
            throw TrustError.invalidLightningAddress
        }

        return normalized
    }
}

enum MessageKeyBindingVerifier {
    private static let supportedSignatureVersions: Set<Int> = [1, 2]
    private static let supportedEnvelopeSignatureVersions: Set<Int> = [1, 2]
    private static let messagingIdentityDomain = AppConfig.messagingIdentityDomain

    enum VerificationError: LocalizedError {
        case missingBinding
        case missingEnvelopeSignature
        case missingCreatedAtClient
        case unsupportedSignatureVersion
        case unsupportedEnvelopeSignatureVersion
        case invalidWalletPubkey
        case invalidMessagingSigningPubkey
        case invalidSignatureEncoding
        case invalidSignature
        case invalidEnvelopeSignature

        var errorDescription: String? {
            switch self {
            case .missingBinding:
                return "Recipient messaging identity is incomplete."
            case .missingEnvelopeSignature:
                return "The sender message envelope signature is incomplete."
            case .missingCreatedAtClient:
                return "The message timestamp is missing."
            case .unsupportedSignatureVersion:
                return "Unsupported messaging identity signature version."
            case .unsupportedEnvelopeSignatureVersion:
                return "Unsupported messaging envelope signature version."
            case .invalidWalletPubkey:
                return "Recipient wallet pubkey is invalid."
            case .invalidMessagingSigningPubkey:
                return "Sender messaging signing key is invalid."
            case .invalidSignatureEncoding:
                return "Recipient messaging identity signature format is invalid."
            case .invalidSignature:
                return "Recipient messaging identity signature could not be verified."
            case .invalidEnvelopeSignature:
                return "The sender message signature could not be verified."
            }
        }
    }

    static func verifyRecipientBinding(_ recipient: MessagingRecipient) throws {
        try verifyBinding(recipient.identityBindingPayload)
    }

    static func verifyRegistration(_ registration: MessageKeyManager.RegistrationResponse) throws {
        guard let binding = registration.identityBindingPayload else {
            throw VerificationError.missingBinding
        }

        try verifyBinding(binding)
    }

    static func verifyBinding(_ binding: MessagingIdentityBindingPayload) throws {
        try verifyBinding(
            walletPubkey: binding.walletPubkey,
            lightningAddress: binding.lightningAddress,
            messagingPubkey: binding.messagingPubkey,
            messagingIdentitySignature: binding.messagingIdentitySignature,
            messagingIdentitySignatureVersion: binding.messagingIdentitySignatureVersion,
            signedAt: binding.messagingIdentitySignedAt
        )
    }

    static func verifyBinding(
        walletPubkey: String,
        lightningAddress: String,
        messagingPubkey: String,
        messagingIdentitySignature: String,
        messagingIdentitySignatureVersion: Int,
        signedAt: Int
    ) throws {
        guard supportedSignatureVersions.contains(messagingIdentitySignatureVersion) else {
            throw VerificationError.unsupportedSignatureVersion
        }

        let canonicalMessage = buildMessagingIdentityBindingMessage(
            version: messagingIdentitySignatureVersion,
            walletPubkey: walletPubkey,
            lightningAddress: lightningAddress,
            messagingPubkey: messagingPubkey,
            signedAt: signedAt
        )
        try verifySignedMessage(
            canonicalMessage,
            signatureHex: messagingIdentitySignature,
            walletPubkey: walletPubkey,
            invalidSignatureError: .invalidSignature
        )
    }

    static func buildMessagingIdentityBindingMessage(
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

    static func buildDirectoryLeafMessage(_ binding: MessagingIdentityBindingPayload) -> String {
        """
        SplitRewards Messaging Directory Leaf
        version=\(binding.messagingIdentitySignatureVersion)
        walletPubkey=\(binding.walletPubkey)
        lightningAddress=\(binding.lightningAddress)
        messagingPubkey=\(binding.messagingPubkey)
        signature=\(binding.messagingIdentitySignature)
        signedAt=\(binding.messagingIdentitySignedAt)
        """
    }

    static func buildMessagingDeviceRegistrationMessage(
        version: Int,
        walletPubkey: String,
        messagingPubkey: String,
        platform: String,
        environment: String,
        deviceToken: String,
        signedAt: Int
    ) -> String {
        """
        SplitRewards Messaging Device Registration
        version=\(version)
        domain=\(messagingIdentityDomain)
        walletPubkey=\(walletPubkey)
        messagingPubkey=\(messagingPubkey)
        platform=\(platform)
        environment=\(environment)
        deviceToken=\(deviceToken)
        signedAt=\(signedAt)
        """
    }

    static func buildMessagingSigningKeyBindingMessage(
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

    static func verifyMessagingSigningCertificate(
        _ certificate: MessageSigningCertificate
    ) throws {
        guard certificate.messagingSigningPubkeySignatureVersion == 1 else {
            throw VerificationError.unsupportedSignatureVersion
        }

        let canonicalMessage = buildMessagingSigningKeyBindingMessage(
            version: certificate.messagingSigningPubkeySignatureVersion,
            walletPubkey: certificate.walletPubkey,
            lightningAddress: certificate.lightningAddress,
            messagingPubkey: certificate.messagingPubkey,
            messagingSigningPubkey: certificate.messagingSigningPubkey,
            signedAt: certificate.messagingSigningPubkeySignedAt
        )
        try verifySignedMessage(
            canonicalMessage,
            signatureHex: certificate.messagingSigningPubkeySignature,
            walletPubkey: certificate.walletPubkey,
            invalidSignatureError: .invalidSignature
        )
    }

    static func buildMessagingEnvelopeSignatureMessage(
        version: Int,
        clientMessageId: String,
        senderBinding: MessagingIdentityBindingPayload,
        recipientWalletPubkey: String,
        recipientLightningAddress: String,
        recipientMessagingPubkey: String,
        messageType: String,
        plaintext: String? = nil,
        ciphertext: String? = nil,
        nonce: String? = nil,
        senderEphemeralPubkey: String? = nil,
        createdAtClientMs: Int64,
        envelopeVersion: Int
    ) -> String {
        if version >= 2 {
            return """
            SplitRewards Messaging Envelope Authorization
            version=\(version)
            domain=\(messagingIdentityDomain)
            clientMessageId=\(clientMessageId)
            senderWalletPubkey=\(senderBinding.walletPubkey)
            senderLightningAddress=\(senderBinding.lightningAddress)
            senderMessagingPubkey=\(senderBinding.messagingPubkey)
            recipientWalletPubkey=\(recipientWalletPubkey)
            recipientLightningAddress=\(recipientLightningAddress)
            recipientMessagingPubkey=\(recipientMessagingPubkey)
            messageType=\(messageType)
            plaintext=\(plaintext ?? "")
            createdAtClientMs=\(createdAtClientMs)
            envelopeVersion=\(envelopeVersion)
            """
        }

        return """
        SplitRewards Messaging Envelope Authorization
        version=\(version)
        domain=\(messagingIdentityDomain)
        clientMessageId=\(clientMessageId)
        senderWalletPubkey=\(senderBinding.walletPubkey)
        senderLightningAddress=\(senderBinding.lightningAddress)
        senderMessagingPubkey=\(senderBinding.messagingPubkey)
        recipientWalletPubkey=\(recipientWalletPubkey)
        recipientLightningAddress=\(recipientLightningAddress)
        recipientMessagingPubkey=\(recipientMessagingPubkey)
        messageType=\(messageType)
        ciphertext=\(ciphertext ?? "")
        nonce=\(nonce ?? "")
        senderEphemeralPubkey=\(senderEphemeralPubkey ?? "")
        createdAtClientMs=\(createdAtClientMs)
        envelopeVersion=\(envelopeVersion)
        """
    }

    static func verifyIncomingEnvelope(_ message: InboxMessage) throws {
        guard message.envelopeVersion == 2 else {
            return
        }

        guard let senderBinding = message.senderIdentityBindingPayload else {
            throw VerificationError.missingBinding
        }

        guard let senderEnvelopeSignature = message.senderEnvelopeSignature?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !senderEnvelopeSignature.isEmpty,
              let senderEnvelopeSignatureVersion = message.senderEnvelopeSignatureVersion
        else {
            throw VerificationError.missingEnvelopeSignature
        }

        guard supportedEnvelopeSignatureVersions.contains(senderEnvelopeSignatureVersion) else {
            throw VerificationError.unsupportedEnvelopeSignatureVersion
        }

        guard let ciphertext = message.ciphertext,
              let nonce = message.nonce,
              let senderEphemeralPubkey = message.senderEphemeralPubkey,
              let createdAtClientMs = message.createdAtClientMilliseconds
        else {
            throw VerificationError.missingCreatedAtClient
        }

        try verifyBinding(senderBinding)

        let canonicalMessage = buildMessagingEnvelopeSignatureMessage(
            version: senderEnvelopeSignatureVersion,
            clientMessageId: message.clientMessageId,
            senderBinding: senderBinding,
            recipientWalletPubkey: message.recipientWalletPubkey,
            recipientLightningAddress: message.recipientLightningAddress,
            recipientMessagingPubkey: message.recipientMessagingPubkey,
            messageType: message.messageType,
            ciphertext: ciphertext,
            nonce: nonce,
            senderEphemeralPubkey: senderEphemeralPubkey,
            createdAtClientMs: createdAtClientMs,
            envelopeVersion: message.envelopeVersion
        )

        try verifySignedMessage(
            canonicalMessage,
            signatureHex: senderEnvelopeSignature,
            walletPubkey: senderBinding.walletPubkey,
            invalidSignatureError: .invalidEnvelopeSignature
        )
    }

    static func verifySealedIncomingEnvelope(
        _ message: InboxMessage,
        sealedPayload: SealedSenderMessagePayload
    ) throws {
        guard supportedEnvelopeSignatureVersions.contains(sealedPayload.messageSignatureVersion) else {
            throw VerificationError.unsupportedEnvelopeSignatureVersion
        }

        guard let createdAtClientMs = message.createdAtClientMilliseconds else {
            throw VerificationError.missingCreatedAtClient
        }

        try verifyBinding(sealedPayload.sender)
        try verifyMessagingSigningCertificate(
            MessageSigningCertificate(
                walletPubkey: sealedPayload.sender.walletPubkey,
                lightningAddress: sealedPayload.sender.lightningAddress,
                messagingPubkey: sealedPayload.sender.messagingPubkey,
                messagingSigningPubkey: sealedPayload.messagingSigningPubkey,
                messagingSigningPubkeySignature: sealedPayload.messagingSigningPubkeySignature,
                messagingSigningPubkeySignatureVersion: sealedPayload.messagingSigningPubkeySignatureVersion,
                messagingSigningPubkeySignedAt: sealedPayload.messagingSigningPubkeySignedAt
            )
        )

        let canonicalMessage = buildMessagingEnvelopeSignatureMessage(
            version: sealedPayload.messageSignatureVersion,
            clientMessageId: message.clientMessageId,
            senderBinding: sealedPayload.sender,
            recipientWalletPubkey: message.recipientWalletPubkey,
            recipientLightningAddress: message.recipientLightningAddress,
            recipientMessagingPubkey: message.recipientMessagingPubkey,
            messageType: message.messageType,
            plaintext: sealedPayload.body,
            createdAtClientMs: createdAtClientMs,
            envelopeVersion: message.envelopeVersion
        )
        try verifyMessagingSignature(
            canonicalMessage,
            signatureHex: sealedPayload.messageSignature,
            messagingSigningPubkey: sealedPayload.messagingSigningPubkey
        )
    }

    private static func verifyMessagingSignature(
        _ canonicalMessage: String,
        signatureHex: String,
        messagingSigningPubkey: String
    ) throws {
        guard let pubkeyData = strictHexData(messagingSigningPubkey) else {
            throw VerificationError.invalidMessagingSigningPubkey
        }

        guard let signatureData = strictHexData(signatureHex) else {
            throw VerificationError.invalidSignatureEncoding
        }

        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubkeyData)
        } catch {
            throw VerificationError.invalidMessagingSigningPubkey
        }

        guard publicKey.isValidSignature(signatureData, for: Data(canonicalMessage.utf8)) else {
            throw VerificationError.invalidEnvelopeSignature
        }
    }

    private static func compactSignatureCandidates(from signatureHex: String) throws -> [[UInt8]] {
        guard let signatureData = strictHexData(signatureHex) else {
            throw VerificationError.invalidSignatureEncoding
        }

        switch signatureData.count {
        case 64:
            return [Array(signatureData)]
        case 65:
            return [
                Array(signatureData.prefix(64)),
                Array(signatureData.dropFirst()),
            ]
        default:
            throw VerificationError.invalidSignatureEncoding
        }
    }

    private static func normalizedWalletPubkeyBytes(_ hex: String) -> [UInt8]? {
        guard let normalizedHex = normalizeWalletPubkeyHex(hex) else {
            return nil
        }

        return [UInt8](Data(hex: normalizedHex))
    }

    private static func normalizeWalletPubkeyHex(_ hex: String) -> String? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("0x") || value.hasPrefix("0X") {
            value.removeFirst(2)
        }

        guard value.allSatisfy(\.isHexDigit) else {
            return nil
        }

        let lowercased = value.lowercased()
        if lowercased.count == 66 || lowercased.count == 130 {
            return lowercased
        }

        if lowercased.count == 128 {
            return "04" + lowercased
        }

        return nil
    }

    private static func strictHexData(_ hex: String) -> Data? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("0x") || value.hasPrefix("0X") {
            value.removeFirst(2)
        }

        guard !value.isEmpty, value.count.isMultiple(of: 2), value.allSatisfy(\.isHexDigit) else {
            return nil
        }

        return Data(hex: value)
    }

    private static func verifySignedMessage(
        _ canonicalMessage: String,
        signatureHex: String,
        walletPubkey: String,
        invalidSignatureError: VerificationError
    ) throws {
        guard let pubkeyBytes = normalizedWalletPubkeyBytes(walletPubkey) else {
            throw VerificationError.invalidWalletPubkey
        }

        let messageDigest = Array(SHA256.hash(data: Data(canonicalMessage.utf8)))
        let signatureCandidates = try compactSignatureCandidates(from: signatureHex)
        let isValid = signatureCandidates.contains { signatureBytes in
            verifyCompactSignature(
                signatureBytes: signatureBytes,
                digestBytes: messageDigest,
                pubkeyBytes: pubkeyBytes
            )
        }

        if !isValid {
            throw invalidSignatureError
        }
    }

    private static func verifyCompactSignature(
        signatureBytes: [UInt8],
        digestBytes: [UInt8],
        pubkeyBytes: [UInt8]
    ) -> Bool {
        guard signatureBytes.count == 64 else {
            return false
        }

        var parsedSignature = secp256k1_ecdsa_signature()
        var parsedPublicKey = secp256k1_pubkey()

        return secp256k1_ecdsa_signature_parse_compact(
            secp256k1.Context.raw,
            &parsedSignature,
            signatureBytes
        ) != 0 &&
        secp256k1_ec_pubkey_parse(
            secp256k1.Context.raw,
            &parsedPublicKey,
            pubkeyBytes,
            pubkeyBytes.count
        ) != 0 &&
        secp256k1_ecdsa_verify(
            secp256k1.Context.raw,
            &parsedSignature,
            digestBytes,
            &parsedPublicKey
        ) != 0
    }
}

private extension Data {
    init(hex: String) {
        self.init()
        self.reserveCapacity(hex.count / 2)

        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<next]
            self.append(UInt8(byteString, radix: 16) ?? 0)
            index = next
        }
    }
}
