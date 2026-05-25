//
//  MessageCryptoManager.swift
//  Split Rewards
//
//  Created by TeeVee on 3/20/26.
//

import Foundation
import CryptoKit

@MainActor
final class MessageCryptoManager {
    static let shared = MessageCryptoManager()

    private init() {}

    enum MessageCryptoError: LocalizedError {
        case missingEnvelope
        case invalidBase64
        case invalidRecipientPublicKey
        case invalidEphemeralPublicKey
        case invalidCiphertext
        case invalidPlaintext

        var errorDescription: String? {
            switch self {
            case .missingEnvelope:
                return "The encrypted message envelope is incomplete."
            case .invalidBase64:
                return "The encrypted message payload is invalid."
            case .invalidRecipientPublicKey:
                return "The recipient messaging public key is invalid."
            case .invalidEphemeralPublicKey:
                return "The sender ephemeral public key is invalid."
            case .invalidCiphertext:
                return "The encrypted message could not be decrypted."
            case .invalidPlaintext:
                return "The decrypted message is not valid text."
            }
        }
    }

    func decrypt(_ message: InboxMessage) throws -> String {
        guard
            let ciphertext = message.ciphertext,
            let nonce = message.nonce,
            let senderEphemeralPubkey = message.senderEphemeralPubkey
        else {
            throw MessageCryptoError.missingEnvelope
        }

        guard
            let ciphertextData = Data(base64Encoded: ciphertext),
            let nonceData = Data(base64Encoded: nonce)
        else {
            throw MessageCryptoError.invalidBase64
        }

        let senderEphemeralData = try data(fromHex: senderEphemeralPubkey)

        let recipientPrivateKey = try MessageKeyManager.shared.messagingPrivateKey(
            forRecipientMessagingPubkey: message.recipientMessagingPubkey
        )
        let senderEphemeralKey: Curve25519.KeyAgreement.PublicKey

        do {
            senderEphemeralKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderEphemeralData)
        } catch {
            throw MessageCryptoError.invalidEphemeralPublicKey
        }

        let sharedSecret = try recipientPrivateKey.sharedSecretFromKeyAgreement(with: senderEphemeralKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("split.messaging.v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        let plaintextData = try decryptPayload(
            ciphertextData: ciphertextData,
            nonceData: nonceData,
            symmetricKey: symmetricKey
        )

        guard let plaintext = String(data: plaintextData, encoding: .utf8) else {
            throw MessageCryptoError.invalidPlaintext
        }

        return plaintext
    }

    func decryptAttachmentData(
        ciphertextData: Data,
        nonceBase64: String,
        senderEphemeralPubkeyHex: String,
        recipientMessagingPubkeyHex: String
    ) throws -> Data {
        guard let nonceData = Data(base64Encoded: nonceBase64) else {
            throw MessageCryptoError.invalidBase64
        }

        let senderEphemeralData = try data(fromHex: senderEphemeralPubkeyHex)

        let recipientPrivateKey = try MessageKeyManager.shared.messagingPrivateKey(
            forRecipientMessagingPubkey: recipientMessagingPubkeyHex
        )
        let senderEphemeralKey: Curve25519.KeyAgreement.PublicKey

        do {
            senderEphemeralKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderEphemeralData)
        } catch {
            throw MessageCryptoError.invalidEphemeralPublicKey
        }

        let sharedSecret = try recipientPrivateKey.sharedSecretFromKeyAgreement(with: senderEphemeralKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("split.messaging.v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        return try decryptPayload(
            ciphertextData: ciphertextData,
            nonceData: nonceData,
            symmetricKey: symmetricKey
        )
    }

    func encrypt(
        plaintext: String,
        recipientMessagingPubkeyHex: String
    ) throws -> SendMessageEnvelopePayload {
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw MessageCryptoError.invalidPlaintext
        }

        let encryptedPayload = try encryptPayload(
            plaintextData: plaintextData,
            recipientMessagingPubkeyHex: recipientMessagingPubkeyHex
        )

        return SendMessageEnvelopePayload(
            ciphertext: encryptedPayload.ciphertext.base64EncodedString(),
            nonce: encryptedPayload.nonce.base64EncodedString(),
            senderEphemeralPubkey: encryptedPayload.senderEphemeralPubkey,
            envelopeVersion: 3
        )
    }

    func encryptAttachmentData(
        _ data: Data,
        recipientMessagingPubkeyHex: String
    ) throws -> EncryptedAttachmentPayload {
        let encryptedPayload = try encryptPayload(
            plaintextData: data,
            recipientMessagingPubkeyHex: recipientMessagingPubkeyHex
        )

        return EncryptedAttachmentPayload(
            ciphertext: encryptedPayload.ciphertext,
            nonce: encryptedPayload.nonce.base64EncodedString(),
            senderEphemeralPubkey: encryptedPayload.senderEphemeralPubkey
        )
    }

    private func encryptPayload(
        plaintextData: Data,
        recipientMessagingPubkeyHex: String
    ) throws -> EncryptedBinaryPayload {
        let recipientPublicKeyData = try data(fromHex: recipientMessagingPubkeyHex)
        let recipientPublicKey: Curve25519.KeyAgreement.PublicKey

        do {
            recipientPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKeyData)
        } catch {
            throw MessageCryptoError.invalidRecipientPublicKey
        }

        let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("split.messaging.v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        let sealedBox = try ChaChaPoly.seal(plaintextData, using: symmetricKey)
        let ciphertextWithTag = sealedBox.ciphertext + sealedBox.tag
        let nonceData = Data(Array(sealedBox.nonce))

        return EncryptedBinaryPayload(
            ciphertext: ciphertextWithTag,
            nonce: nonceData,
            senderEphemeralPubkey: hexString(for: ephemeralPrivateKey.publicKey.rawRepresentation)
        )
    }

    private func decryptPayload(
        ciphertextData: Data,
        nonceData: Data,
        symmetricKey: SymmetricKey
    ) throws -> Data {
        if ciphertextData.count >= 16 {
            do {
                let nonce = try ChaChaPoly.Nonce(data: nonceData)
                let ciphertext = Data(ciphertextData.dropLast(16))
                let tag = Data(ciphertextData.suffix(16))
                let sealedBox = try ChaChaPoly.SealedBox(
                    nonce: nonce,
                    ciphertext: ciphertext,
                    tag: tag
                )
                return try ChaChaPoly.open(sealedBox, using: symmetricKey)
            } catch {
                // Fall through to the combined-format attempt below.
            }
        }

        do {
            let sealedBox = try ChaChaPoly.SealedBox(combined: ciphertextData)
            return try ChaChaPoly.open(sealedBox, using: symmetricKey)
        } catch {
            throw MessageCryptoError.invalidCiphertext
        }
    }

    private func data(fromHex hex: String) throws -> Data {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count.isMultiple(of: 2) else {
            throw MessageCryptoError.invalidEphemeralPublicKey
        }

        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex

        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<nextIndex]

            guard let byte = UInt8(String(byteString), radix: 16) else {
                throw MessageCryptoError.invalidEphemeralPublicKey
            }

            data.append(byte)
            index = nextIndex
        }

        return data
    }

    private func hexString(for data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

struct SendMessageEnvelopePayload {
    let ciphertext: String
    let nonce: String
    let senderEphemeralPubkey: String
    let envelopeVersion: Int
}

struct EncryptedAttachmentPayload {
    let ciphertext: Data
    let nonce: String
    let senderEphemeralPubkey: String
}

private struct EncryptedBinaryPayload {
    let ciphertext: Data
    let nonce: Data
    let senderEphemeralPubkey: String
}
