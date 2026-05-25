//
//  NWCConnectParser.swift
//  Split Rewards
//
//  Created by TeeVee on 5/1/26.
//

import Foundation

enum NWCConnectParser {
    static func parse(_ rawValue: String) throws -> NWCWalletCredentials {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "nostr+walletconnect" else {
            throw NWCWalletError.invalidConnectionURL
        }

        let walletPubkey = normalizedHex(
            components.host ?? components.path.replacingOccurrences(of: "/", with: "")
        )

        guard let walletPubkey else {
            if (components.host ?? components.path).isEmpty {
                throw NWCWalletError.missingWalletPubkey
            }

            throw NWCWalletError.invalidWalletPubkey
        }

        guard walletPubkey.count == 64 else {
            throw NWCWalletError.invalidWalletPubkey
        }

        let queryItems = components.queryItems ?? []
        let relayURLs = queryItems
            .values(named: "relay")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(normalizedRelayURL)

        guard !relayURLs.isEmpty else {
            throw NWCWalletError.missingRelay
        }

        guard relayURLs.allSatisfy({ $0 != nil }) else {
            throw NWCWalletError.invalidRelay
        }

        guard let secretValue = queryItems.firstValue(named: "secret") else {
            throw NWCWalletError.missingSecret
        }

        guard let secret = normalizedHex(secretValue),
              secret.count == 64 else {
            throw NWCWalletError.invalidSecret
        }

        let lud16 = queryItems.firstValue(named: "lud16")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfBlank

        let label = queryItems.firstValue(named: "name")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank

        return NWCWalletCredentials(
            walletPubkey: walletPubkey,
            relayURLs: relayURLs.compactMap { $0 },
            secret: secret,
            lud16: lud16,
            label: label,
            connectedAt: Date(),
            lastVerifiedAt: nil,
            capabilities: nil
        )
    }

    private static func normalizedRelayURL(_ value: String) -> String? {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              components.host?.isEmpty == false,
              let url = components.url else {
            return nil
        }

        guard scheme == "wss" || isAllowedOnionWebSocketRelay(components) || isAllowedDebugWebSocketRelay(components) else {
            return nil
        }

        return url.absoluteString
    }

    private static func isAllowedOnionWebSocketRelay(_ components: URLComponents) -> Bool {
        guard components.scheme?.lowercased() == "ws",
              components.host?.lowercased().hasSuffix(".onion") == true else {
            return false
        }

        return true
    }

    private static func isAllowedDebugWebSocketRelay(_ components: URLComponents) -> Bool {
        #if DEBUG
        guard components.scheme?.lowercased() == "ws",
              let host = components.host?.lowercased() else {
            return false
        }

        return host == "localhost" || host == "127.0.0.1" || host == "::1"
        #else
        return false
        #endif
    }

    private static func normalizedHex(_ value: String?) -> String? {
        guard var normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }

        if normalized.hasPrefix("0x") || normalized.hasPrefix("0X") {
            normalized.removeFirst(2)
        }

        guard normalized.count.isMultiple(of: 2),
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

    func values(named name: String) -> [String] {
        compactMap { item in
            guard item.name.caseInsensitiveCompare(name) == .orderedSame else { return nil }
            return item.value
        }
    }
}
