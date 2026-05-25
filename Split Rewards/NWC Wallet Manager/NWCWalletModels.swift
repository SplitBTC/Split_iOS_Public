//
//  NWCWalletModels.swift
//  Split Rewards
//
//  Created by TeeVee on 5/1/26.
//

import Foundation

enum NWCWalletError: LocalizedError, Equatable {
    case invalidConnectionURL
    case missingWalletPubkey
    case invalidWalletPubkey
    case missingRelay
    case invalidRelay
    case missingSecret
    case invalidSecret
    case noStoredConnection
    case walletNotConnected
    case relayConnectionFailed
    case relayTimedOut
    case invalidRelayResponse
    case walletInfoUnavailable
    case unsupportedMethod(String)
    case unsupportedEncryption
    case rewardsMetadataUnavailable
    case insufficientCapabilities

    var errorDescription: String? {
        switch self {
        case .invalidConnectionURL:
            return "The NWC connection string is invalid."
        case .missingWalletPubkey:
            return "The NWC connection string is missing the wallet pubkey."
        case .invalidWalletPubkey:
            return "The NWC wallet pubkey is invalid."
        case .missingRelay:
            return "The NWC connection string is missing a relay."
        case .invalidRelay:
            return "The NWC relay URL is invalid."
        case .missingSecret:
            return "The NWC connection string is missing the client secret."
        case .invalidSecret:
            return "The NWC client secret is invalid."
        case .noStoredConnection:
            return "No NWC wallet is stored on this device."
        case .walletNotConnected:
            return "NWC wallet is not connected."
        case .relayConnectionFailed:
            return "Split could not connect to the NWC relay."
        case .relayTimedOut:
            return "The NWC relay did not respond in time."
        case .invalidRelayResponse:
            return "The NWC relay returned an invalid response."
        case .walletInfoUnavailable:
            return "Split could not verify this NWC wallet's capabilities."
        case .unsupportedMethod(let method):
            return "This NWC wallet does not support \(method)."
        case .unsupportedEncryption:
            return "This NWC wallet does not advertise a compatible encryption mode."
        case .rewardsMetadataUnavailable:
            return "This connected NWC wallet cannot provide the invoice metadata Split needs for rewards. Split needs the Lightning destination pubkey and payment hash before sending."
        case .insufficientCapabilities:
            return "This wallet does not support the NWC features Split needs. Connect an NWC wallet or node with payments, invoices, balance, history, invoice lookup, and live payment notifications."
        }
    }
}

enum NWCEncryptionMode: String, Codable, Equatable {
    case nip44V2 = "nip44_v2"
    case nip04 = "nip04"
}

struct NWCWalletCapabilities: Codable, Equatable {
    let methods: [String]
    let notifications: [String]
    let encryptionModes: [String]
    let walletAlias: String?

    var supportsBalance: Bool { supports("get_balance") }
    var supportsPayments: Bool { supports("pay_invoice") }
    var supportsInvoices: Bool { supports("make_invoice") }
    var supportsInvoiceLookup: Bool { supports("lookup_invoice") }
    var supportsTransactions: Bool { supports("list_transactions") }
    var supportsPaymentReceivedNotifications: Bool { supportsNotification("payment_received") }
    var supportsPaymentSentNotifications: Bool { supportsNotification("payment_sent") }
    var supportsPaymentNotifications: Bool {
        supportsPaymentReceivedNotifications && supportsPaymentSentNotifications
    }
    var supportsSplitBaseline: Bool {
        supportsPayments && supportsInvoices && supportsBalance && supportsInvoiceLookup && supportsTransactions
    }
    var supportsSplitRequiredCapabilities: Bool {
        supportsSplitBaseline && supportsPaymentNotifications
    }
    var preferredEncryptionMode: NWCEncryptionMode {
        if encryptionModes.contains(where: { $0.caseInsensitiveCompare(NWCEncryptionMode.nip44V2.rawValue) == .orderedSame }) {
            return .nip44V2
        }

        return .nip04
    }
    var supportsCompatibleEncryption: Bool {
        encryptionModes.isEmpty ||
            encryptionModes.contains { $0.caseInsensitiveCompare(NWCEncryptionMode.nip44V2.rawValue) == .orderedSame } ||
            encryptionModes.contains { $0.caseInsensitiveCompare(NWCEncryptionMode.nip04.rawValue) == .orderedSame }
    }
    var supportsNIP44Encryption: Bool {
        preferredEncryptionMode == .nip44V2
    }

    func supports(_ method: String) -> Bool {
        methods.contains { $0.caseInsensitiveCompare(method) == .orderedSame }
    }

    func supportsNotification(_ notification: String) -> Bool {
        notifications.contains { $0.caseInsensitiveCompare(notification) == .orderedSame }
    }
}

struct NWCWalletCredentials: Codable, Equatable, Identifiable {
    var id: String { walletPubkey }

    let walletPubkey: String
    let relayURLs: [String]
    let secret: String
    let lud16: String?
    let label: String?
    let connectedAt: Date
    let lastVerifiedAt: Date?
    let capabilities: NWCWalletCapabilities?

    var displayName: String {
        label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ??
            capabilities?.walletAlias?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ??
            "NWC Wallet"
    }

    func withLabel(_ label: String?) -> NWCWalletCredentials {
        NWCWalletCredentials(
            walletPubkey: walletPubkey,
            relayURLs: relayURLs,
            secret: secret,
            lud16: lud16,
            label: label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            connectedAt: connectedAt,
            lastVerifiedAt: lastVerifiedAt,
            capabilities: capabilities
        )
    }

    var primaryRelayHost: String {
        guard let firstRelay = relayURLs.first,
              let host = URL(string: firstRelay)?.host else {
            return "Relay unavailable"
        }

        return host
    }

    var usesTor: Bool {
        relayURLs.contains { relay in
            guard let url = URL(string: relay) else { return false }
            return RemoteNodeTransport.preferred(forURL: url) == .tor
        }
    }

    func verified(with capabilities: NWCWalletCapabilities) -> NWCWalletCredentials {
        NWCWalletCredentials(
            walletPubkey: walletPubkey,
            relayURLs: relayURLs,
            secret: secret,
            lud16: lud16,
            label: label,
            connectedAt: connectedAt,
            lastVerifiedAt: Date(),
            capabilities: capabilities
        )
    }
}

struct NWCWalletInfoEvent: Decodable, Equatable {
    let id: String?
    let pubkey: String
    let createdAt: Int?
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

    var capabilities: NWCWalletCapabilities {
        let parsedMethods = content
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" })
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0 != "notifications" }

        let encryptionModes = tagValues(named: "encryption")
            .flatMap { $0.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        let notifications = tagValues(named: "notifications")
            .flatMap { $0.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return NWCWalletCapabilities(
            methods: Array(Set(parsedMethods)).sorted(),
            notifications: Array(Set(notifications)).sorted(),
            encryptionModes: Array(Set(encryptionModes)).sorted(),
            walletAlias: tagValue(named: "name") ?? tagValue(named: "alias")
        )
    }

    var nostrEvent: NWCNostrEvent? {
        guard let id, let createdAt else {
            return nil
        }

        return NWCNostrEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: sig
        )
    }

    private func tagValue(named name: String) -> String? {
        tagValues(named: name).first
    }

    private func tagValues(named name: String) -> [String] {
        tags.compactMap { tag in
            guard let first = tag.first,
                  first.caseInsensitiveCompare(name) == .orderedSame,
                  tag.count > 1 else {
                return nil
            }

            return tag[1]
        }
    }
}
