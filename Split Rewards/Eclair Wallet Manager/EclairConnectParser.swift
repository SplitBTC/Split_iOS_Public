//
//  EclairConnectParser.swift
//  Split Rewards
//
//  Created by TeeVee on 5/19/26.
//

import Foundation

enum EclairConnectParser {
    static func parse(
        scheme: String,
        host: String,
        port: String,
        apiPassword: String,
        label: String? = nil
    ) throws -> EclairNodeCredentials {
        let normalizedScheme = scheme
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfBlank ?? "http"
        guard normalizedScheme == "http" || normalizedScheme == "https" else {
            throw EclairWalletError.invalidConnection
        }

        let hostInfo = try normalizedHostInfo(from: host)

        try EclairHostAccessPolicy.validate(host: hostInfo.host)

        let normalizedPassword = apiPassword
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPassword.isEmpty else {
            throw EclairWalletError.missingPassword
        }

        let parsedPort = resolvedPort(explicit: port, embedded: hostInfo.port, fallback: 8080)
        guard (1...65_535).contains(parsedPort) else {
            throw EclairWalletError.invalidConnection
        }

        return EclairNodeCredentials(
            scheme: normalizedScheme,
            host: hostInfo.host,
            port: parsedPort,
            apiPassword: normalizedPassword,
            label: label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            nodeId: nil,
            nodeAlias: nil,
            connectedAt: Date(),
            lastVerifiedAt: nil
        )
    }

    static func parse(connectionString rawValue: String, label: String? = nil) throws -> EclairNodeCredentials {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EclairWalletError.invalidConnection
        }

        if let jsonCredentials = try parseJSON(trimmed, label: label) {
            return jsonCredentials
        }

        guard let components = URLComponents(string: trimmed),
              let rawScheme = components.scheme?.lowercased() else {
            throw EclairWalletError.invalidConnection
        }

        switch rawScheme {
        case "eclair+http", "eclair+https":
            return try parseURLComponents(
                components,
                scheme: String(rawScheme.dropFirst("eclair+".count)),
                label: label
            )
        case "http", "https":
            return try parseURLComponents(components, scheme: rawScheme, label: label)
        case "eclair":
            let queryItems = components.queryItems ?? []
            let scheme = queryItems.firstValue(named: "scheme")?.lowercased()
                ?? queryItems.firstValue(named: "protocol")?.lowercased()
                ?? "http"
            return try parseURLComponents(components, scheme: scheme, label: label)
        default:
            throw EclairWalletError.invalidConnection
        }
    }

    private static func parseURLComponents(
        _ components: URLComponents,
        scheme: String,
        label: String?
    ) throws -> EclairNodeCredentials {
        guard scheme == "http" || scheme == "https" else {
            throw EclairWalletError.invalidConnection
        }

        let queryItems = components.queryItems ?? []
        let queryHost = queryItems.firstValue(named: "host")
            ?? queryItems.firstValue(named: "hostname")
            ?? queryItems.firstValue(named: "address")
        let componentHost = components.host?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let prefersQueryConnection = components.scheme?.lowercased() == "eclair" && queryHost != nil
        let host = prefersQueryConnection
            ? queryHost ?? componentHost ?? ""
            : componentHost ?? queryHost ?? ""
        let queryPort = queryItems.firstIntValue(named: "port")
        let port = prefersQueryConnection
            ? queryPort ?? components.port ?? defaultPort(for: scheme)
            : components.port ?? queryPort ?? defaultPort(for: scheme)
        let password = components.password?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? components.user?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? queryItems.firstValue(named: "password")
            ?? queryItems.firstValue(named: "apiPassword")
            ?? queryItems.firstValue(named: "api_password")
            ?? ""

        return try parse(
            scheme: scheme,
            host: host,
            port: "\(port)",
            apiPassword: password,
            label: label
                ?? queryItems.firstValue(named: "name")
                ?? queryItems.firstValue(named: "label")
        )
    }

    private static func parseJSON(_ value: String, label: String?) throws -> EclairNodeCredentials? {
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else {
            return nil
        }

        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EclairWalletError.invalidConnection
        }

        let urlString = stringValue(object, keys: ["url", "baseUrl", "base_url", "restUrl", "rest_url"])
        let scheme = stringValue(object, keys: ["scheme", "protocol"])?.lowercased()
        let host = stringValue(object, keys: ["host", "hostname", "address"])
        let port = intValue(object, keys: ["port"])
        let password = stringValue(object, keys: ["password", "apiPassword", "api_password"])
        let resolvedLabel = label ?? stringValue(object, keys: ["label", "name"])

        if let urlString,
           let components = urlLikeComponents(urlString) {
            let queryItems = components.queryItems ?? []
            let componentScheme = transportScheme(from: components.scheme)
            if components.scheme != nil,
               componentScheme == nil,
               components.scheme?.lowercased() != "eclair" {
                throw EclairWalletError.invalidConnection
            }
            let resolvedScheme = scheme
                ?? componentScheme
                ?? queryItems.firstValue(named: "scheme")?.lowercased()
                ?? queryItems.firstValue(named: "protocol")?.lowercased()
                ?? "http"
            let resolvedHost = components.host?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? host
                ?? queryItems.firstValue(named: "host")
                ?? queryItems.firstValue(named: "hostname")
                ?? queryItems.firstValue(named: "address")
                ?? ""
            let resolvedPort = port
                ?? components.port
                ?? queryItems.firstIntValue(named: "port")
                ?? defaultPort(for: resolvedScheme)
            let resolvedPassword = password
                ?? components.password?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? components.user?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? queryItems.firstValue(named: "password")
                ?? queryItems.firstValue(named: "apiPassword")
                ?? queryItems.firstValue(named: "api_password")
                ?? ""

            return try parse(
                scheme: resolvedScheme,
                host: resolvedHost,
                port: "\(resolvedPort)",
                apiPassword: resolvedPassword,
                label: resolvedLabel
            )
        }

        return try parse(
            scheme: scheme ?? "http",
            host: host ?? "",
            port: "\(port ?? defaultPort(for: scheme ?? "http"))",
            apiPassword: password ?? "",
            label: resolvedLabel
        )
    }

    private struct HostInfo {
        let host: String
        let port: Int?
    }

    private static func normalizedHostInfo(from value: String) throws -> HostInfo {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EclairWalletError.missingNodeHost
        }

        if let components = urlLikeComponents(trimmed),
           let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            return HostInfo(host: host, port: components.port)
        }

        let withoutPath = trimmed
            .split(separator: "/", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? trimmed

        if withoutPath.hasPrefix("["),
           let closingBracket = withoutPath.firstIndex(of: "]") {
            let host = String(withoutPath[withoutPath.index(after: withoutPath.startIndex)..<closingBracket])
            let remainder = String(withoutPath[withoutPath.index(after: closingBracket)...])
            let port = remainder.hasPrefix(":") ? Int(remainder.dropFirst()) : nil
            return HostInfo(host: host, port: port)
        }

        if withoutPath.filter({ $0 == ":" }).count == 1 {
            let parts = withoutPath.split(separator: ":", maxSplits: 1).map(String.init)
            return HostInfo(host: parts[0], port: parts.count > 1 ? Int(parts[1]) : nil)
        }

        return HostInfo(host: withoutPath, port: nil)
    }

    private static func urlLikeComponents(_ value: String) -> URLComponents? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("://") {
            return URLComponents(string: trimmed)
        }

        return URLComponents(string: "http://\(trimmed)")
    }

    private static func resolvedPort(explicit: String, embedded: Int?, fallback: Int) -> Int {
        let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        if let embedded, trimmed.isEmpty || trimmed == "\(fallback)" {
            return embedded
        }

        return Int(trimmed) ?? embedded ?? fallback
    }

    private static func defaultPort(for scheme: String) -> Int {
        scheme == "https" ? 443 : 8080
    }

    private static func transportScheme(from rawScheme: String?) -> String? {
        switch rawScheme?.lowercased() {
        case "eclair+http":
            return "http"
        case "eclair+https":
            return "https"
        case "http", "https":
            return rawScheme?.lowercased()
        case "eclair":
            return nil
        default:
            return nil
        }
    }

    private static func stringValue(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String,
               let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                return normalized
            }
        }
        return nil
    }

    private static func intValue(_ object: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = object[key] as? Int {
                return value
            }
            if let value = object[key] as? NSNumber {
                return value.intValue
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
        first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }

    func firstIntValue(named name: String) -> Int? {
        firstValue(named: name).flatMap(Int.init)
    }
}
