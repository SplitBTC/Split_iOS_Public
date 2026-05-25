//
//  NWCNostrCryptography.swift
//  Split Rewards
//
//  Created by TeeVee on 5/1/26.
//

import CryptoKit
import CommonCrypto
import Foundation
import Security
import secp256k1

enum NWCNostrCryptographyError: LocalizedError {
    case invalidPrivateKey
    case invalidPublicKey
    case signingFailed
    case invalidPlaintext
    case invalidPayload
    case unsupportedPayloadVersion
    case invalidMac
    case invalidPadding
    case invalidEvent

    var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            return "The NWC private key is invalid."
        case .invalidPublicKey:
            return "The NWC public key is invalid."
        case .signingFailed:
            return "Unable to sign the NWC event."
        case .invalidPlaintext:
            return "The NWC request payload is invalid."
        case .invalidPayload:
            return "The encrypted NWC payload is invalid."
        case .unsupportedPayloadVersion:
            return "The encrypted NWC payload version is not supported."
        case .invalidMac:
            return "The encrypted NWC payload could not be authenticated."
        case .invalidPadding:
            return "The encrypted NWC payload padding is invalid."
        case .invalidEvent:
            return "The NWC event is invalid."
        }
    }
}

enum NWCNostrCryptography {
    static func publicKeyHex(privateKeyHex: String) throws -> String {
        let secretKey = try normalizedSecretKey(privateKeyHex)

        var keypair = secp256k1_keypair()
        guard secp256k1_keypair_create(secp256k1.Context.raw, &keypair, Array(secretKey)) != 0 else {
            throw NWCNostrCryptographyError.invalidPrivateKey
        }

        var xOnlyPubkey = secp256k1_xonly_pubkey()
        var parity: Int32 = 0
        guard secp256k1_keypair_xonly_pub(secp256k1.Context.raw, &xOnlyPubkey, &parity, &keypair) != 0 else {
            throw NWCNostrCryptographyError.invalidPrivateKey
        }

        var output = [UInt8](repeating: 0, count: 32)
        guard secp256k1_xonly_pubkey_serialize(secp256k1.Context.raw, &output, &xOnlyPubkey) != 0 else {
            throw NWCNostrCryptographyError.invalidPublicKey
        }

        return Data(output).nwcHexString
    }

    static func signEvent(
        privateKeyHex: String,
        createdAt: Int,
        kind: Int,
        tags: [[String]],
        content: String
    ) throws -> NWCNostrEvent {
        let pubkey = try publicKeyHex(privateKeyHex: privateKeyHex)
        let id = try eventId(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
        let signature = try schnorrSignature(privateKeyHex: privateKeyHex, messageIdHex: id)

        return NWCNostrEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: signature
        )
    }

    static func verifyEvent(_ event: NWCNostrEvent) throws -> Bool {
        let expectedId = try eventId(
            pubkey: event.pubkey,
            createdAt: event.createdAt,
            kind: event.kind,
            tags: event.tags,
            content: event.content
        )
        guard expectedId == event.id else { return false }

        guard let signature = Data(nwcHex: event.sig),
              signature.count == 64,
              let message = Data(nwcHex: event.id),
              message.count == 32,
              let pubkeyData = Data(nwcHex: event.pubkey),
              pubkeyData.count == 32 else {
            return false
        }

        var xOnlyPubkey = secp256k1_xonly_pubkey()
        guard secp256k1_xonly_pubkey_parse(
            secp256k1.Context.raw,
            &xOnlyPubkey,
            Array(pubkeyData)
        ) != 0 else {
            return false
        }

        return secp256k1_schnorrsig_verify(
            secp256k1.Context.raw,
            Array(signature),
            Array(message),
            message.count,
            &xOnlyPubkey
        ) != 0
    }

    static func nip44Encrypt(
        plaintext: String,
        senderPrivateKeyHex: String,
        recipientPublicKeyHex: String
    ) throws -> String {
        let plaintextData = Data(plaintext.utf8)
        guard !plaintextData.isEmpty, plaintextData.count <= 65_535 else {
            throw NWCNostrCryptographyError.invalidPlaintext
        }

        let conversationKey = try conversationKey(
            privateKeyHex: senderPrivateKeyHex,
            publicKeyHex: recipientPublicKeyHex
        )
        let nonce = try secureRandomData(count: 32)
        let keys = try messageKeys(conversationKey: conversationKey, nonce: nonce)
        let padded = try pad(plaintextData)
        let ciphertext = chacha20(data: padded, key: keys.chachaKey, nonce: keys.chachaNonce)
        let mac = Data(CryptoKit.HMAC<CryptoKit.SHA256>.authenticationCode(for: nonce + ciphertext, using: CryptoKit.SymmetricKey(data: keys.hmacKey)))

        return (Data([0x02]) + nonce + ciphertext + mac).base64EncodedString()
    }

    static func nip44Decrypt(
        payload: String,
        recipientPrivateKeyHex: String,
        senderPublicKeyHex: String
    ) throws -> String {
        guard !payload.hasPrefix("#"),
              let decoded = Data(base64Encoded: payload),
              decoded.count >= 99 else {
            throw NWCNostrCryptographyError.invalidPayload
        }

        guard decoded.first == 0x02 else {
            throw NWCNostrCryptographyError.unsupportedPayloadVersion
        }

        let nonce = decoded.subdata(in: 1..<33)
        let mac = decoded.suffix(32)
        let ciphertext = decoded.subdata(in: 33..<(decoded.count - 32))

        let conversationKey = try conversationKey(
            privateKeyHex: recipientPrivateKeyHex,
            publicKeyHex: senderPublicKeyHex
        )
        let keys = try messageKeys(conversationKey: conversationKey, nonce: nonce)
        let expectedMac = Data(CryptoKit.HMAC<CryptoKit.SHA256>.authenticationCode(for: nonce + ciphertext, using: CryptoKit.SymmetricKey(data: keys.hmacKey)))
        guard constantTimeEquals(mac, expectedMac) else {
            throw NWCNostrCryptographyError.invalidMac
        }

        let padded = chacha20(data: ciphertext, key: keys.chachaKey, nonce: keys.chachaNonce)
        let plaintext = try unpad(padded)
        guard let string = String(data: plaintext, encoding: .utf8) else {
            throw NWCNostrCryptographyError.invalidPayload
        }

        return string
    }

    static func nip04Encrypt(
        plaintext: String,
        senderPrivateKeyHex: String,
        recipientPublicKeyHex: String
    ) throws -> String {
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw NWCNostrCryptographyError.invalidPlaintext
        }

        let sharedSecret = try sharedSecretX(
            privateKeyHex: senderPrivateKeyHex,
            publicKeyHex: recipientPublicKeyHex
        )
        let iv = try secureRandomData(count: kCCBlockSizeAES128)
        let ciphertext = try aesCBC(
            operation: CCOperation(kCCEncrypt),
            data: plaintextData,
            key: sharedSecret,
            iv: iv
        )

        return "\(ciphertext.base64EncodedString())?iv=\(iv.base64EncodedString())"
    }

    static func nip04Decrypt(
        payload: String,
        recipientPrivateKeyHex: String,
        senderPublicKeyHex: String
    ) throws -> String {
        let parts = payload.components(separatedBy: "?iv=")
        guard parts.count == 2,
              let ciphertext = Data(base64Encoded: parts[0]),
              let iv = Data(base64Encoded: parts[1]),
              iv.count == kCCBlockSizeAES128 else {
            throw NWCNostrCryptographyError.invalidPayload
        }

        let sharedSecret = try sharedSecretX(
            privateKeyHex: recipientPrivateKeyHex,
            publicKeyHex: senderPublicKeyHex
        )
        let plaintextData = try aesCBC(
            operation: CCOperation(kCCDecrypt),
            data: ciphertext,
            key: sharedSecret,
            iv: iv
        )

        guard let plaintext = String(data: plaintextData, encoding: .utf8) else {
            throw NWCNostrCryptographyError.invalidPayload
        }

        return plaintext
    }

    private static func eventId(
        pubkey: String,
        createdAt: Int,
        kind: Int,
        tags: [[String]],
        content: String
    ) throws -> String {
        let eventPayload: [Any] = [0, pubkey, createdAt, kind, tags, content]
        let data = try JSONSerialization.data(withJSONObject: eventPayload, options: [.withoutEscapingSlashes])
        return Data(CryptoKit.SHA256.hash(data: data)).nwcHexString
    }

    private static func schnorrSignature(privateKeyHex: String, messageIdHex: String) throws -> String {
        let secretKey = try normalizedSecretKey(privateKeyHex)
        guard let message = Data(nwcHex: messageIdHex), message.count == 32 else {
            throw NWCNostrCryptographyError.invalidEvent
        }

        var keypair = secp256k1_keypair()
        guard secp256k1_keypair_create(secp256k1.Context.raw, &keypair, Array(secretKey)) != 0 else {
            throw NWCNostrCryptographyError.invalidPrivateKey
        }

        var signature = [UInt8](repeating: 0, count: 64)
        guard secp256k1_schnorrsig_sign32(
            secp256k1.Context.raw,
            &signature,
            Array(message),
            &keypair,
            nil
        ) != 0 else {
            throw NWCNostrCryptographyError.signingFailed
        }

        return Data(signature).nwcHexString
    }

    private static func conversationKey(privateKeyHex: String, publicKeyHex: String) throws -> Data {
        let sharedX = try sharedSecretX(privateKeyHex: privateKeyHex, publicKeyHex: publicKeyHex)
        return hkdfExtract(ikm: sharedX, salt: Data("nip44-v2".utf8))
    }

    private static func sharedSecretX(privateKeyHex: String, publicKeyHex: String) throws -> Data {
        let secretKey = try normalizedSecretKey(privateKeyHex)
        guard let publicKey = Data(nwcHex: publicKeyHex), publicKey.count == 32 else {
            throw NWCNostrCryptographyError.invalidPublicKey
        }

        var compressedPublicKey = Data([0x02])
        compressedPublicKey.append(publicKey)

        var parsedPublicKey = secp256k1_pubkey()
        guard secp256k1_ec_pubkey_parse(
            secp256k1.Context.raw,
            &parsedPublicKey,
            Array(compressedPublicKey),
            compressedPublicKey.count
        ) != 0 else {
            throw NWCNostrCryptographyError.invalidPublicKey
        }

        var sharedPublicKey = parsedPublicKey
        guard secp256k1_ec_pubkey_tweak_mul(
            secp256k1.Context.raw,
            &sharedPublicKey,
            Array(secretKey)
        ) != 0 else {
            throw NWCNostrCryptographyError.invalidPublicKey
        }

        var output = [UInt8](repeating: 0, count: 33)
        var outputLength = output.count
        guard secp256k1_ec_pubkey_serialize(
            secp256k1.Context.raw,
            &output,
            &outputLength,
            &sharedPublicKey,
            UInt32(SECP256K1_EC_COMPRESSED)
        ) != 0 else {
            throw NWCNostrCryptographyError.invalidPublicKey
        }

        let sharedX = Data(output.prefix(outputLength).dropFirst())
        guard sharedX.count == 32 else {
            throw NWCNostrCryptographyError.invalidPublicKey
        }

        return sharedX
    }

    private static func aesCBC(
        operation: CCOperation,
        data: Data,
        key: Data,
        iv: Data
    ) throws -> Data {
        guard key.count == kCCKeySizeAES256, iv.count == kCCBlockSizeAES128 else {
            throw NWCNostrCryptographyError.invalidPayload
        }

        let outputCapacity = data.count + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { dataBuffer in
                key.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress,
                            key.count,
                            ivBuffer.baseAddress,
                            dataBuffer.baseAddress,
                            data.count,
                            outputBuffer.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw NWCNostrCryptographyError.invalidPayload
        }

        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private static func normalizedSecretKey(_ value: String) throws -> Data {
        guard let data = Data(nwcHex: value), data.count == 32 else {
            throw NWCNostrCryptographyError.invalidPrivateKey
        }

        return data
    }

    private static func messageKeys(conversationKey: Data, nonce: Data) throws -> (chachaKey: Data, chachaNonce: Data, hmacKey: Data) {
        guard conversationKey.count == 32, nonce.count == 32 else {
            throw NWCNostrCryptographyError.invalidPayload
        }

        let expanded = hkdfExpand(prk: conversationKey, info: nonce, length: 76)
        return (
            chachaKey: expanded.subdata(in: 0..<32),
            chachaNonce: expanded.subdata(in: 32..<44),
            hmacKey: expanded.subdata(in: 44..<76)
        )
    }

    private static func hkdfExtract(ikm: Data, salt: Data) -> Data {
        Data(CryptoKit.HMAC<CryptoKit.SHA256>.authenticationCode(for: ikm, using: CryptoKit.SymmetricKey(data: salt)))
    }

    private static func hkdfExpand(prk: Data, info: Data, length: Int) -> Data {
        var output = Data()
        var previous = Data()
        var counter: UInt8 = 1

        while output.count < length {
            var input = Data()
            input.append(previous)
            input.append(info)
            input.append(counter)

            previous = Data(CryptoKit.HMAC<CryptoKit.SHA256>.authenticationCode(for: input, using: CryptoKit.SymmetricKey(data: prk)))
            output.append(previous)
            counter += 1
        }

        return Data(output.prefix(length))
    }

    private static func pad(_ plaintext: Data) throws -> Data {
        guard plaintext.count > 0, plaintext.count <= 65_535 else {
            throw NWCNostrCryptographyError.invalidPlaintext
        }

        let paddedLength = calcPaddedLength(plaintext.count)
        var output = Data()
        output.append(UInt8((plaintext.count >> 8) & 0xff))
        output.append(UInt8(plaintext.count & 0xff))
        output.append(plaintext)
        output.append(Data(repeating: 0, count: paddedLength - plaintext.count))
        return output
    }

    private static func unpad(_ padded: Data) throws -> Data {
        guard padded.count >= 34 else {
            throw NWCNostrCryptographyError.invalidPadding
        }

        let length = (Int(padded[0]) << 8) + Int(padded[1])
        guard length > 0,
              length <= 65_535,
              padded.count == 2 + calcPaddedLength(length),
              padded.count >= 2 + length else {
            throw NWCNostrCryptographyError.invalidPadding
        }

        return padded.subdata(in: 2..<(2 + length))
    }

    private static func calcPaddedLength(_ length: Int) -> Int {
        guard length > 32 else { return 32 }

        let nextPower = 1 << Int(ceil(log2(Double(length))))
        let chunk = nextPower <= 256 ? 32 : nextPower / 8
        return chunk * Int(ceil(Double(length) / Double(chunk)))
    }

    private static func chacha20(data: Data, key: Data, nonce: Data) -> Data {
        var state = ChaCha20State(key: key, nonce: nonce)
        var output = Data()
        output.reserveCapacity(data.count)

        var offset = 0
        while offset < data.count {
            let block = state.nextBlock()
            let remaining = min(64, data.count - offset)
            for index in 0..<remaining {
                output.append(data[offset + index] ^ block[index])
            }
            offset += remaining
        }

        return output
    }

    private static func constantTimeEquals(_ lhs: Data.SubSequence, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            diff |= left ^ right
        }
        return diff == 0
    }

    private static func secureRandomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw NWCNostrCryptographyError.invalidPayload
        }
        return Data(bytes)
    }
}

struct NWCNostrEvent: Codable, Equatable {
    let id: String
    let pubkey: String
    let createdAt: Int
    let kind: Int
    let tags: [[String]]
    let content: String
    let sig: String

    enum CodingKeys: String, CodingKey {
        case id
        case pubkey
        case createdAt = "created_at"
        case kind
        case tags
        case content
        case sig
    }
}

private struct ChaCha20State {
    private var state: [UInt32]

    init(key: Data, nonce: Data) {
        let constants: [UInt8] = Array("expand 32-byte k".utf8)
        state = [
            Self.littleEndianWord(constants, 0),
            Self.littleEndianWord(constants, 4),
            Self.littleEndianWord(constants, 8),
            Self.littleEndianWord(constants, 12),
            Self.littleEndianWord(key, 0),
            Self.littleEndianWord(key, 4),
            Self.littleEndianWord(key, 8),
            Self.littleEndianWord(key, 12),
            Self.littleEndianWord(key, 16),
            Self.littleEndianWord(key, 20),
            Self.littleEndianWord(key, 24),
            Self.littleEndianWord(key, 28),
            0,
            Self.littleEndianWord(nonce, 0),
            Self.littleEndianWord(nonce, 4),
            Self.littleEndianWord(nonce, 8),
        ]
    }

    mutating func nextBlock() -> [UInt8] {
        var workingState = state

        for _ in 0..<10 {
            Self.quarterRound(&workingState, 0, 4, 8, 12)
            Self.quarterRound(&workingState, 1, 5, 9, 13)
            Self.quarterRound(&workingState, 2, 6, 10, 14)
            Self.quarterRound(&workingState, 3, 7, 11, 15)
            Self.quarterRound(&workingState, 0, 5, 10, 15)
            Self.quarterRound(&workingState, 1, 6, 11, 12)
            Self.quarterRound(&workingState, 2, 7, 8, 13)
            Self.quarterRound(&workingState, 3, 4, 9, 14)
        }

        for index in 0..<16 {
            workingState[index] = workingState[index] &+ state[index]
        }

        state[12] = state[12] &+ 1

        return workingState.flatMap(Self.bytes)
    }

    private static func quarterRound(_ state: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        state[a] = state[a] &+ state[b]
        state[d] ^= state[a]
        state[d] = state[d].rotatedLeft(16)

        state[c] = state[c] &+ state[d]
        state[b] ^= state[c]
        state[b] = state[b].rotatedLeft(12)

        state[a] = state[a] &+ state[b]
        state[d] ^= state[a]
        state[d] = state[d].rotatedLeft(8)

        state[c] = state[c] &+ state[d]
        state[b] ^= state[c]
        state[b] = state[b].rotatedLeft(7)
    }

    private static func littleEndianWord(_ data: Data, _ offset: Int) -> UInt32 {
        littleEndianWord(Array(data), offset)
    }

    private static func littleEndianWord(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) |
            (UInt32(bytes[offset + 1]) << 8) |
            (UInt32(bytes[offset + 2]) << 16) |
            (UInt32(bytes[offset + 3]) << 24)
    }

    private static func bytes(_ word: UInt32) -> [UInt8] {
        [
            UInt8(word & 0xff),
            UInt8((word >> 8) & 0xff),
            UInt8((word >> 16) & 0xff),
            UInt8((word >> 24) & 0xff),
        ]
    }
}

private extension UInt32 {
    func rotatedLeft(_ amount: UInt32) -> UInt32 {
        (self << amount) | (self >> (32 - amount))
    }
}

private extension Data {
    init?(nwcHex value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("0x") || normalized.hasPrefix("0X") {
            normalized.removeFirst(2)
        }

        guard !normalized.isEmpty,
              normalized.count.isMultiple(of: 2),
              normalized.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else {
            return nil
        }

        self.init()
        reserveCapacity(normalized.count / 2)

        var index = normalized.startIndex
        while index < normalized.endIndex {
            let next = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<next], radix: 16) else {
                return nil
            }
            append(byte)
            index = next
        }
    }

    var nwcHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
