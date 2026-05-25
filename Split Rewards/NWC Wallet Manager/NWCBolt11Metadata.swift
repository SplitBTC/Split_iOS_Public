//
//  NWCBolt11Metadata.swift
//  Split Rewards
//
//  Created by TeeVee on 5/1/26.
//

import CryptoKit
import Foundation
import secp256k1

struct NWCBolt11Metadata: Equatable {
    let amountSats: UInt64?
    let paymentHash: String?
    let destinationPubkey: String?
    let description: String?
}

enum NWCBolt11MetadataDecoder {
    private static let timestampBase32Length = 7
    private static let signatureBase32Length = 104
    private static let signatureByteCount = 65

    static func decode(_ invoice: String) -> NWCBolt11Metadata? {
        let normalized = invoice
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = Bech32.decode(normalized),
              decoded.hrp.hasPrefix("lnbc") else {
            return nil
        }

        let amountSats = parseAmountSats(fromHrp: decoded.hrp)
        guard decoded.data.count > timestampBase32Length else {
            return NWCBolt11Metadata(
                amountSats: amountSats,
                paymentHash: nil,
                destinationPubkey: nil,
                description: nil
            )
        }

        let taggedFields = Array(decoded.data.dropFirst(timestampBase32Length))
        let fieldsEnd = max(taggedFields.count - signatureBase32Length, 0)
        var index = 0
        var paymentHash: String?
        var destinationPubkey: String?
        var description: String?

        while index + 3 <= fieldsEnd {
            let tag = taggedFields[index]
            let dataLength = (Int(taggedFields[index + 1]) << 5) + Int(taggedFields[index + 2])
            index += 3

            guard index + dataLength <= fieldsEnd else {
                break
            }

            let fieldData = Array(taggedFields[index..<(index + dataLength)])
            index += dataLength

            guard let fieldBytes = convertBits(fieldData, fromBits: 5, toBits: 8, pad: false) else {
                continue
            }

            switch tag {
            case 1:
                if fieldBytes.count == 32 {
                    paymentHash = Data(fieldBytes).nwcBolt11HexString.nilIfBlank
                }
            case 13:
                description = String(data: Data(fieldBytes), encoding: .utf8)?.nilIfBlank
            case 19:
                if fieldBytes.count == 33 {
                    destinationPubkey = Data(fieldBytes).nwcBolt11HexString.nilIfBlank
                }
            default:
                break
            }
        }

        let signaturePayload = invoiceSignaturePayload(hrp: decoded.hrp, data: decoded.data)
        let verifiedDestinationPubkey: String?

        if let destinationPubkey {
            guard signaturePayload.flatMap({ verifyExplicitDestinationPubkey(destinationPubkey, payload: $0) }) == true else {
                return nil
            }

            verifiedDestinationPubkey = destinationPubkey
        } else {
            verifiedDestinationPubkey = signaturePayload.flatMap { recoverDestinationPubkey(payload: $0) }
        }

        return NWCBolt11Metadata(
            amountSats: amountSats,
            paymentHash: paymentHash,
            destinationPubkey: verifiedDestinationPubkey,
            description: description
        )
    }

    private static func parseAmountSats(fromHrp hrp: String) -> UInt64? {
        guard hrp.hasPrefix("lnbc") else { return nil }
        let amountPart = String(hrp.dropFirst("lnbc".count))
        guard !amountPart.isEmpty else { return nil }

        let multiplier = amountPart.last.flatMap { character -> Character? in
            ["m", "u", "n", "p"].contains(character) ? character : nil
        }
        let numericPart = multiplier == nil ? amountPart : String(amountPart.dropLast())
        guard let amount = Decimal(string: numericPart), amount > 0 else {
            return nil
        }

        let btc: Decimal
        switch multiplier {
        case "m":
            btc = amount / Decimal(1_000)
        case "u":
            btc = amount / Decimal(1_000_000)
        case "n":
            btc = amount / Decimal(1_000_000_000)
        case "p":
            btc = amount / Decimal(1_000_000_000_000)
        default:
            btc = amount
        }

        let satsDecimal = btc * Decimal(100_000_000)
        return NSDecimalNumber(decimal: satsDecimal).uint64Value
    }

    private static func invoiceSignaturePayload(hrp: String, data: [UInt8]) -> InvoiceSignaturePayload? {
        guard data.count >= signatureBase32Length,
              let signatureBytes = convertBits(Array(data.suffix(signatureBase32Length)), fromBits: 5, toBits: 8, pad: false),
              signatureBytes.count == signatureByteCount,
              let messageBytes = convertBits(Array(data.dropLast(signatureBase32Length)), fromBits: 5, toBits: 8, pad: true),
              let hrpData = hrp.data(using: .utf8) else {
            return nil
        }

        var signedPayload = Data()
        signedPayload.append(hrpData)
        signedPayload.append(contentsOf: messageBytes)

        return InvoiceSignaturePayload(
            messageHash: Data(SHA256.hash(data: signedPayload)),
            compactSignature: Array(signatureBytes.prefix(64)),
            recoveryId: Int32(signatureBytes[64])
        )
    }

    private static func verifyExplicitDestinationPubkey(_ destinationPubkey: String, payload: InvoiceSignaturePayload) -> Bool {
        guard let pubkeyData = Data(nwcBolt11Hex: destinationPubkey),
              pubkeyData.count == 33 else {
            return false
        }

        var signature = secp256k1_ecdsa_signature()
        var pubkey = secp256k1_pubkey()

        guard secp256k1_ecdsa_signature_parse_compact(
            secp256k1.Context.raw,
            &signature,
            payload.compactSignature
        ) != 0,
              secp256k1_ec_pubkey_parse(
                secp256k1.Context.raw,
                &pubkey,
                Array(pubkeyData),
                pubkeyData.count
              ) != 0 else {
            return false
        }

        return secp256k1_ecdsa_verify(
            secp256k1.Context.raw,
            &signature,
            Array(payload.messageHash),
            &pubkey
        ) != 0
    }

    private static func recoverDestinationPubkey(payload: InvoiceSignaturePayload) -> String? {
        let compactSignature = payload.compactSignature
        let recoveryId = payload.recoveryId
        guard (0...3).contains(recoveryId) else {
            return nil
        }

        var recoverableSignature = secp256k1_ecdsa_recoverable_signature()
        guard secp256k1_ecdsa_recoverable_signature_parse_compact(
            secp256k1.Context.raw,
            &recoverableSignature,
            compactSignature,
            recoveryId
        ) != 0 else {
            return nil
        }

        var recoveredPubkey = secp256k1_pubkey()
        guard secp256k1_ecdsa_recover(
            secp256k1.Context.raw,
            &recoveredPubkey,
            &recoverableSignature,
            Array(payload.messageHash)
        ) != 0 else {
            return nil
        }

        var output = [UInt8](repeating: 0, count: 33)
        var outputLength = output.count
        guard secp256k1_ec_pubkey_serialize(
            secp256k1.Context.raw,
            &output,
            &outputLength,
            &recoveredPubkey,
            UInt32(SECP256K1_EC_COMPRESSED)
        ) != 0 else {
            return nil
        }

        return Data(output.prefix(outputLength)).nwcBolt11HexString.nilIfBlank
    }

    private static func convertBits(_ data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var acc = 0
        var bits = 0
        let maxv = (1 << toBits) - 1
        var result: [UInt8] = []

        for value in data {
            guard (Int(value) >> fromBits) == 0 else {
                return nil
            }

            acc = (acc << fromBits) | Int(value)
            bits += fromBits

            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }

        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }

        return result
    }
}

private struct InvoiceSignaturePayload {
    let messageHash: Data
    let compactSignature: [UInt8]
    let recoveryId: Int32
}

private enum Bech32 {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let checksumLength = 6
    private static let checksumConstant: UInt32 = 1
    private static let generator: [UInt32] = [
        0x3b6a57b2,
        0x26508e6d,
        0x1ea119fa,
        0x3d4233dd,
        0x2a1462b3,
    ]

    static func decode(_ value: String) -> (hrp: String, data: [UInt8])? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == trimmed.lowercased() || trimmed == trimmed.uppercased() else {
            return nil
        }

        let normalized = trimmed.lowercased()
        guard let separatorIndex = normalized.lastIndex(of: "1") else {
            return nil
        }

        let hrp = String(normalized[..<separatorIndex])
        let dataPart = normalized[normalized.index(after: separatorIndex)...]
        guard !hrp.isEmpty,
              hrp.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }),
              dataPart.count > checksumLength else {
            return nil
        }

        var values: [UInt8] = []
        values.reserveCapacity(dataPart.count)

        for character in dataPart {
            guard let index = charset.firstIndex(of: character) else {
                return nil
            }
            values.append(UInt8(index))
        }

        guard verifyChecksum(hrp: hrp, values: values) else {
            return nil
        }

        return (hrp, Array(values.dropLast(checksumLength)))
    }

    private static func verifyChecksum(hrp: String, values: [UInt8]) -> Bool {
        polymod(hrpExpand(hrp) + values) == checksumConstant
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let scalarValues = hrp.unicodeScalars.map(\.value)
        guard scalarValues.allSatisfy({ $0 <= 0x7f }) else {
            return []
        }

        let scalars = scalarValues.map { UInt8($0) }
        return scalars.map { $0 >> 5 } + [0] + scalars.map { $0 & 31 }
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var checksum: UInt32 = 1

        for value in values {
            let top = checksum >> 25
            checksum = ((checksum & 0x1ffffff) << 5) ^ UInt32(value)

            for index in 0..<5 {
                if ((top >> UInt32(index)) & 1) != 0 {
                    checksum ^= generator[index]
                }
            }
        }

        return checksum
    }
}

private extension Data {
    init?(nwcBolt11Hex value: String) {
        guard !value.isEmpty,
              value.count.isMultiple(of: 2),
              value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else {
            return nil
        }

        self.init()
        reserveCapacity(value.count / 2)

        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else {
                return nil
            }
            append(byte)
            index = next
        }
    }

    var nwcBolt11HexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
