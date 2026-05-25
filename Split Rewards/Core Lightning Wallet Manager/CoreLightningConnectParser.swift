//
//  CoreLightningConnectParser.swift
//  Split Rewards
//
//  Created by TeeVee on 5/9/26.
//

import Foundation

enum CoreLightningConnectParser {
    static func parse(_ rawValue: String) throws -> CoreLightningNodeCredentials {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CoreLightningWalletError.invalidConnectionURL
        }

        if let jsonCredentials = try parseJSON(trimmed) {
            return jsonCredentials
        }

        guard let components = URLComponents(string: trimmed),
              let rawScheme = components.scheme?.lowercased() else {
            throw CoreLightningWalletError.invalidConnectionURL
        }

        switch rawScheme {
        case "clnrest+https", "clnrest+http":
            return try parseURLComponents(components, scheme: String(rawScheme.dropFirst("clnrest+".count)))
        case "clnrest":
            if let embeddedURLCredentials = try parseEmbeddedURL(from: trimmed, schemePrefix: "clnrest://") {
                return embeddedURLCredentials
            }

            let queryItems = components.queryItems ?? []
            let scheme = queryItems.firstValue(named: "scheme")?.lowercased()
                ?? queryItems.firstValue(named: "protocol")?.lowercased()
                ?? "https"
            return try parseURLComponents(components, scheme: scheme)
        case "https", "http":
            return try parseURLComponents(components, scheme: rawScheme)
        default:
            throw CoreLightningWalletError.invalidConnectionURL
        }
    }

    private static func parseURLComponents(
        _ components: URLComponents,
        scheme: String
    ) throws -> CoreLightningNodeCredentials {
        guard scheme == "https" || scheme == "http" else {
            throw CoreLightningWalletError.invalidConnectionURL
        }

        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            throw CoreLightningWalletError.missingNodeHost
        }

        try CoreLightningHostAccessPolicy.validate(host: host)

        let queryItems = components.queryItems ?? []
        let rune = try normalizedRune(
            queryItems.firstValue(named: "rune")
                ?? queryItems.firstValue(named: "token")
                ?? queryItems.firstValue(named: "auth")
                ?? components.user
        )

        let certValue = certificateValue(from: queryItems)
        let tlsCertificateDERBase64 = try certValue.map(decodeCertificateToBase64)

        return CoreLightningNodeCredentials(
            scheme: scheme,
            host: host,
            port: components.port ?? 3010,
            rune: rune,
            tlsCertificateDERBase64: tlsCertificateDERBase64,
            label: queryItems.firstValue(named: "name")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            nodeId: nil,
            nodeAlias: nil,
            connectedAt: Date(),
            lastVerifiedAt: nil
        )
    }

    private static func parseJSON(_ value: String) throws -> CoreLightningNodeCredentials? {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let urlString = stringValue(object, keys: ["url", "baseUrl", "base_url", "restUrl", "rest_url"])
        let scheme = stringValue(object, keys: ["scheme", "protocol"])?.lowercased()
        let host = stringValue(object, keys: ["host", "hostname"])
        let port = intValue(object, keys: ["port"])
        let rune = stringValue(object, keys: ["rune", "token", "auth"])
        let cert = stringValue(object, keys: certificateFieldNames)
        let label = stringValue(object, keys: ["name", "label"])

        if let urlString,
           var components = URLComponents(string: urlString) {
            var queryItems = components.queryItems ?? []
            if let rune, !queryItems.contains(where: { $0.name.caseInsensitiveCompare("rune") == .orderedSame }) {
                queryItems.append(URLQueryItem(name: "rune", value: rune))
            }
            if let cert, !queryItems.contains(where: { $0.name.caseInsensitiveCompare("cert") == .orderedSame }) {
                queryItems.append(URLQueryItem(name: "cert", value: cert))
            }
            if let label, !queryItems.contains(where: { $0.name.caseInsensitiveCompare("name") == .orderedSame }) {
                queryItems.append(URLQueryItem(name: "name", value: label))
            }
            components.queryItems = queryItems

            let resolvedScheme = components.scheme?.lowercased().replacingOccurrences(of: "clnrest+", with: "") ?? scheme ?? "https"
            return try parseURLComponents(components, scheme: resolvedScheme)
        }

        guard let host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoreLightningWalletError.missingNodeHost
        }

        let resolvedScheme = scheme ?? "https"
        guard resolvedScheme == "https" || resolvedScheme == "http" else {
            throw CoreLightningWalletError.invalidConnectionURL
        }

        try CoreLightningHostAccessPolicy.validate(host: host)

        return CoreLightningNodeCredentials(
            scheme: resolvedScheme,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port ?? 3010,
            rune: try normalizedRune(rune),
            tlsCertificateDERBase64: try cert.map(decodeCertificateToBase64),
            label: label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            nodeId: nil,
            nodeAlias: nil,
            connectedAt: Date(),
            lastVerifiedAt: nil
        )
    }

    private static func parseEmbeddedURL(
        from value: String,
        schemePrefix: String
    ) throws -> CoreLightningNodeCredentials? {
        let prefixLength = schemePrefix.count
        guard value.count > prefixLength else {
            return nil
        }

        let embedded = String(value.dropFirst(prefixLength))
        guard embedded.lowercased().hasPrefix("http://") || embedded.lowercased().hasPrefix("https://") else {
            return nil
        }

        guard let embeddedComponents = URLComponents(string: embedded),
              let embeddedScheme = embeddedComponents.scheme?.lowercased() else {
            throw CoreLightningWalletError.invalidConnectionURL
        }

        return try parseURLComponents(embeddedComponents, scheme: embeddedScheme)
    }

    private static func normalizedRune(_ value: String?) throws -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw CoreLightningWalletError.missingRune
        }

        guard !value.contains(where: { $0.isWhitespace }) else {
            throw CoreLightningWalletError.invalidRune
        }

        return value
    }

    private static let certificateFieldNames = [
        "cert",
        "certificate",
        "tlsCert",
        "tls_cert",
        "tlsCertificate",
        "tls_certificate",
        "ca",
        "caCert",
        "ca_cert",
        "rootCert",
        "root_cert"
    ]

    private static func certificateValue(from queryItems: [URLQueryItem]) -> String? {
        for name in certificateFieldNames {
            if let value = queryItems.firstValue(named: name) {
                return value
            }
        }

        return nil
    }

    private static func decodeCertificateToBase64(_ value: String) throws -> String {
        let trimmed = value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\r")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CoreLightningWalletError.invalidCertificate
        }

        if let hexData = Data(clnHexString: trimmed) {
            return hexData.base64EncodedString()
        }

        if let pemData = Data(clnPEMCertificateString: trimmed) {
            return pemData.base64EncodedString()
        }

        if let data = Data(clnBase64URLString: trimmed) ?? Data(base64Encoded: trimmed) {
            return data.base64EncodedString()
        }

        throw CoreLightningWalletError.invalidCertificate
    }

    private static func stringValue(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                return value
            }
        }
        return nil
    }

    private static func intValue(_ object: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = object[key] as? Int {
                return value
            }
            if let value = object[key] as? String,
               let int = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return int
            }
        }
        return nil
    }
}

private extension Array where Element == URLQueryItem {
    func firstValue(named name: String) -> String? {
        first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private extension Data {
    init?(clnBase64URLString value: String) {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }

        self.init(base64Encoded: normalized)
    }

    init?(clnHexString value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("0x") || normalized.hasPrefix("0X") {
            normalized.removeFirst(2)
        }

        guard !normalized.isEmpty,
              normalized.count.isMultiple(of: 2),
              normalized.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else {
            return nil
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(normalized.count / 2)

        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }

        self.init(bytes)
    }

    init?(clnPEMCertificateString value: String) {
        guard value.contains("-----BEGIN CERTIFICATE-----") else {
            return nil
        }

        let base64 = value
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard !base64.isEmpty else {
            return nil
        }

        self.init(base64Encoded: base64)
    }
}
