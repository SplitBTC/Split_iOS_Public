//
//  LNDConnectParser.swift
//  Split Rewards
//
//  Created by TeeVee on 4/21/26.
//

import Foundation

enum LNDConnectParser {
    static func parse(_ rawValue: String) throws -> LNDNodeCredentials {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "lndconnect" else {
            throw LNDWalletError.invalidLndConnectURL
        }

        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            throw LNDWalletError.missingNodeHost
        }

        try LNDHostAccessPolicy.validate(host: host)

        let queryItems = components.queryItems ?? []
        guard let macaroonValue = queryItems.firstValue(named: "macaroon") else {
            throw LNDWalletError.missingMacaroon
        }

        guard let macaroonHex = decodeMacaroonToHex(macaroonValue) else {
            throw LNDWalletError.invalidMacaroon
        }

        let tlsCertificateDERBase64: String?
        if let certValue = queryItems.firstValue(named: "cert") {
            guard let certData = decodeBinaryValue(certValue) else {
                throw LNDWalletError.invalidCertificate
            }
            tlsCertificateDERBase64 = certData.base64EncodedString()
        } else {
            tlsCertificateDERBase64 = nil
        }

        return LNDNodeCredentials(
            host: host,
            port: components.port ?? 8080,
            macaroonHex: macaroonHex,
            tlsCertificateDERBase64: tlsCertificateDERBase64,
            label: nil,
            nodePubkey: nil,
            nodeAlias: nil,
            connectedAt: Date(),
            lastVerifiedAt: nil
        )
    }

    private static func decodeMacaroonToHex(_ value: String) -> String? {
        if let hex = normalizedHex(value) {
            return hex
        }

        return decodeBinaryValue(value)?.lndHexString
    }

    private static func decodeBinaryValue(_ value: String) -> Data? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hex = normalizedHex(trimmed) {
            return Data(lndHexString: hex)
        }

        return Data(lndBase64URLString: trimmed) ?? Data(base64Encoded: trimmed)
    }

    private static func normalizedHex(_ value: String) -> String? {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("0x") || normalized.hasPrefix("0X") {
            normalized.removeFirst(2)
        }

        guard !normalized.isEmpty,
              normalized.count.isMultiple(of: 2),
              normalized.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else {
            return nil
        }

        return normalized.lowercased()
    }
}

private extension Array where Element == URLQueryItem {
    func firstValue(named name: String) -> String? {
        first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private extension Data {
    init?(lndBase64URLString value: String) {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }

        self.init(base64Encoded: normalized)
    }

    init?(lndHexString value: String) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.count / 2)

        var index = value.startIndex
        while index < value.endIndex {
            let nextIndex = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }

        self.init(bytes)
    }

    var lndHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
