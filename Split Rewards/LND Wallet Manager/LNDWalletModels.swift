//
//  LNDWalletModels.swift
//  Split Rewards
//
//  Created by TeeVee on 4/21/26.
//

import Foundation
import Network

enum LNDWalletError: LocalizedError, Equatable {
    case invalidLndConnectURL
    case missingNodeHost
    case missingMacaroon
    case invalidMacaroon
    case invalidCertificate
    case invalidBaseURL
    case publicInternetHostNotAllowed
    case noStoredNode
    case nodeNotConnected
    case invalidResponse
    case serverError(statusCode: Int, message: String)
    case tlsCertificateMismatch
    case missingServerTrust

    var errorDescription: String? {
        switch self {
        case .invalidLndConnectURL:
            return "The LND connection string is invalid."
        case .missingNodeHost:
            return "The LND connection string is missing a node host."
        case .missingMacaroon:
            return "The LND connection string is missing a macaroon."
        case .invalidMacaroon:
            return "The LND macaroon is invalid."
        case .invalidCertificate:
            return "The LND TLS certificate is invalid."
        case .invalidBaseURL:
            return "The LND node URL is invalid."
        case .publicInternetHostNotAllowed:
            return "This LND Connect QR uses a public host. Split supports private-network, .local, Tailscale, or Tor .onion LND connections."
        case .noStoredNode:
            return "No LND node is stored on this device."
        case .nodeNotConnected:
            return "LND node is not connected."
        case .invalidResponse:
            return "LND returned an invalid response."
        case .serverError(let statusCode, let message):
            return "LND server error \(statusCode): \(message)"
        case .tlsCertificateMismatch:
            return "The LND node certificate does not match the saved certificate."
        case .missingServerTrust:
            return "Unable to verify the LND node certificate."
        }
    }
}

enum LNDHostAccessPolicy {
    static func validate(host: String) throws {
        if let error = validationError(for: host) {
            throw error
        }
    }

    static func validationError(for host: String) -> LNDWalletError? {
        let normalizedHost = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedHost.isEmpty else {
            return .missingNodeHost
        }

        return nil
    }

    static func validateResolvedAddresses(_ addresses: [LNDResolvedAddress]) throws {
        if let error = resolvedAddressValidationError(for: addresses) {
            throw error
        }
    }

    static func resolvedAddressValidationError(for addresses: [LNDResolvedAddress]) -> LNDWalletError? {
        guard !addresses.isEmpty else {
            return .publicInternetHostNotAllowed
        }

        guard addresses.allSatisfy(isAllowedResolvedAddress) else {
            return .publicInternetHostNotAllowed
        }

        return nil
    }

    private static func isAllowedResolvedAddress(_ address: LNDResolvedAddress) -> Bool {
        switch address {
        case .ipv4(let ipv4Address):
            let octets = ipv4Address.rawValue
            let firstOctet = octets[0]
            let secondOctet = octets[1]

            switch firstOctet {
            case 10:
                return true
            case 172:
                return (16...31).contains(Int(secondOctet))
            case 192:
                return secondOctet == 168
            case 100:
                // Tailscale IPv4 addresses live inside 100.64.0.0/10.
                return (64...127).contains(Int(secondOctet))
            default:
                return false
            }
        case .ipv6(let ipv6Address):
            let bytes = ipv6Address.rawValue

            // Unique local IPv6 addresses (fc00::/7) include Tailscale's
            // fd7a:115c:a1e0::/48 range. Link-local addresses (fe80::/10)
            // are also acceptable for local network node connections.
            if (bytes[0] & 0xfe) == 0xfc {
                return true
            }

            return bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
        }
    }
}

enum LNDResolvedAddress: Hashable {
    case ipv4(IPv4Address)
    case ipv6(IPv6Address)
}

struct LNDFlexibleInt: Codable, Equatable {
    let value: Int64

    init(_ value: Int64) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int64.self) {
            value = int
            return
        }

        if let string = try? container.decode(String.self),
           let int = Int64(string) {
            value = int
            return
        }

        if let double = try? container.decode(Double.self) {
            value = Int64(double)
            return
        }

        value = 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(value))
    }
}

struct LNDNodeCredentials: Codable, Equatable, Identifiable {
    var id: String {
        if let nodePubkey = nodePubkey?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !nodePubkey.isEmpty {
            return nodePubkey
        }

        return "\(host.lowercased()):\(port)"
    }

    let host: String
    let port: Int
    let macaroonHex: String
    let tlsCertificateDERBase64: String?
    let label: String?
    let nodePubkey: String?
    let nodeAlias: String?
    let connectedAt: Date
    let lastVerifiedAt: Date?

    var baseURL: URL? {
        URL(string: "https://\(host):\(port)")
    }

    var transport: RemoteNodeTransport {
        .preferred(forHost: host)
    }

    var usesTor: Bool {
        transport == .tor
    }

    var tlsCertificateData: Data? {
        guard let tlsCertificateDERBase64 else { return nil }
        return Data(base64Encoded: tlsCertificateDERBase64)
    }

    var displayName: String {
        if let label = normalized(label) {
            return label
        }

        if let nodeAlias = normalized(nodeAlias) {
            return nodeAlias
        }

        return "\(host):\(port)"
    }

    func withLabel(_ label: String?) -> LNDNodeCredentials {
        LNDNodeCredentials(
            host: host,
            port: port,
            macaroonHex: macaroonHex,
            tlsCertificateDERBase64: tlsCertificateDERBase64,
            label: normalized(label),
            nodePubkey: nodePubkey,
            nodeAlias: nodeAlias,
            connectedAt: connectedAt,
            lastVerifiedAt: lastVerifiedAt
        )
    }

    func verified(with info: LNDGetInfoResponse) -> LNDNodeCredentials {
        LNDNodeCredentials(
            host: host,
            port: port,
            macaroonHex: macaroonHex,
            tlsCertificateDERBase64: tlsCertificateDERBase64,
            label: label,
            nodePubkey: normalized(info.identityPubkey) ?? nodePubkey,
            nodeAlias: normalized(info.alias) ?? nodeAlias,
            connectedAt: connectedAt,
            lastVerifiedAt: Date()
        )
    }

    func withPort(_ port: Int) -> LNDNodeCredentials {
        LNDNodeCredentials(
            host: host,
            port: port,
            macaroonHex: macaroonHex,
            tlsCertificateDERBase64: tlsCertificateDERBase64,
            label: label,
            nodePubkey: nodePubkey,
            nodeAlias: nodeAlias,
            connectedAt: connectedAt,
            lastVerifiedAt: lastVerifiedAt
        )
    }

    func withHost(_ host: String) -> LNDNodeCredentials {
        LNDNodeCredentials(
            host: host,
            port: port,
            macaroonHex: macaroonHex,
            tlsCertificateDERBase64: tlsCertificateDERBase64,
            label: label,
            nodePubkey: nodePubkey,
            nodeAlias: nodeAlias,
            connectedAt: connectedAt,
            lastVerifiedAt: lastVerifiedAt
        )
    }

    func withHost(_ host: String, port: Int) -> LNDNodeCredentials {
        withHost(host).withPort(port)
    }

    var restConnectionCandidates: [LNDNodeCredentials] {
        var candidates: [LNDNodeCredentials] = []
        var seen = Set<String>()

        for portCandidate in restPortCandidates {
            for hostCandidate in restHostCandidates {
                let candidate = withHost(hostCandidate, port: portCandidate)
                let key = "\(candidate.host.lowercased()):\(candidate.port)"
                guard !seen.contains(key) else { continue }

                candidates.append(candidate)
                seen.insert(key)
            }
        }

        return candidates
    }

    private var restHostCandidates: [String] {
        var candidates = [host]

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedHost = trimmedHost.lowercased()

        if lowercasedHost.hasSuffix(".local") {
            let fallbackHost = String(trimmedHost.dropLast(".local".count))
            if !fallbackHost.isEmpty {
                candidates.append(fallbackHost)
            }
        }

        return candidates
    }

    private var restPortCandidates: [Int] {
        guard port == 10009 else {
            return [port]
        }

        return [port, 8080, 8081]
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct LNDGetInfoResponse: Decodable, Equatable {
    let identityPubkey: String
    let alias: String?
    let color: String?
    let numPeers: Int?
    let blockHeight: Int?
    let blockHash: String?
    let syncedToChain: Bool?
    let syncedToGraph: Bool?
    let version: String?
    let uris: [String]?

    enum CodingKeys: String, CodingKey {
        case identityPubkey = "identity_pubkey"
        case alias
        case color
        case numPeers = "num_peers"
        case blockHeight = "block_height"
        case blockHash = "block_hash"
        case syncedToChain = "synced_to_chain"
        case syncedToGraph = "synced_to_graph"
        case version
        case uris
    }
}

struct LNDWalletBalanceResponse: Decodable, Equatable {
    let totalBalance: LNDFlexibleInt?
    let confirmedBalance: LNDFlexibleInt?
    let unconfirmedBalance: LNDFlexibleInt?
    let lockedBalance: LNDFlexibleInt?

    var totalBalanceSats: Int64 {
        totalBalance?.value ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case totalBalance = "total_balance"
        case confirmedBalance = "confirmed_balance"
        case unconfirmedBalance = "unconfirmed_balance"
        case lockedBalance = "locked_balance"
    }
}

struct LNDChannelBalanceResponse: Decodable, Equatable {
    struct Balance: Decodable, Equatable {
        let sat: LNDFlexibleInt?
        let msat: LNDFlexibleInt?
    }

    let balance: LNDFlexibleInt?
    let pendingOpenBalance: LNDFlexibleInt?
    let localBalance: Balance?
    let remoteBalance: Balance?
    let unsettledLocalBalance: Balance?

    var spendableBalanceSats: Int64 {
        localBalance?.sat?.value ?? balance?.value ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case balance
        case pendingOpenBalance = "pending_open_balance"
        case localBalance = "local_balance"
        case remoteBalance = "remote_balance"
        case unsettledLocalBalance = "unsettled_local_balance"
    }
}

struct LNDAddInvoiceResponse: Decodable, Equatable {
    let rHash: String?
    let paymentRequest: String
    let addIndex: LNDFlexibleInt?
    let paymentAddr: String?

    enum CodingKeys: String, CodingKey {
        case rHash = "r_hash"
        case paymentRequest = "payment_request"
        case addIndex = "add_index"
        case paymentAddr = "payment_addr"
    }
}

struct LNDPayInvoiceResponse: Decodable, Equatable {
    let paymentError: String?
    let paymentPreimage: String?
    let paymentHash: String?

    var didSucceed: Bool {
        paymentError?.isEmpty ?? true
    }

    enum CodingKeys: String, CodingKey {
        case paymentError = "payment_error"
        case paymentPreimage = "payment_preimage"
        case paymentHash = "payment_hash"
    }
}

struct LNDDecodePayReqResponse: Decodable, Equatable {
    let destination: String?
    let paymentHash: String?
    let numSatoshis: LNDFlexibleInt?
    let timestamp: LNDFlexibleInt?
    let expiry: LNDFlexibleInt?
    let description: String?

    var amountSats: Int64? {
        numSatoshis?.value
    }

    enum CodingKeys: String, CodingKey {
        case destination
        case paymentHash = "payment_hash"
        case numSatoshis = "num_satoshis"
        case timestamp
        case expiry
        case description
    }
}

struct LNDSignMessageResponse: Decodable, Equatable {
    let signature: String
}

struct LNDPayment: Decodable, Equatable, Identifiable {
    var id: String {
        paymentHash ?? paymentPreimage ?? paymentRequest ?? "\(creationDate?.value ?? 0)"
    }

    let paymentHash: String?
    let paymentPreimage: String?
    let paymentRequest: String?
    let valueSat: LNDFlexibleInt?
    let feeSat: LNDFlexibleInt?
    let creationDate: LNDFlexibleInt?
    let status: String?
    let failureReason: String?
    let description: String?
    let destination: String?

    enum CodingKeys: String, CodingKey {
        case paymentHash = "payment_hash"
        case paymentPreimage = "payment_preimage"
        case paymentRequest = "payment_request"
        case valueSat = "value_sat"
        case feeSat = "fee_sat"
        case creationDate = "creation_date"
        case status
        case failureReason = "failure_reason"
        case description
        case destination
    }
}

struct LNDListPaymentsResponse: Decodable, Equatable {
    let payments: [LNDPayment]
}

struct LNDInvoice: Decodable, Equatable, Identifiable {
    var id: String {
        rHash ?? paymentRequest ?? "\(creationDate?.value ?? 0)"
    }

    var isSettledInvoice: Bool {
        settled == true || state?.caseInsensitiveCompare("SETTLED") == .orderedSame
    }

    let memo: String?
    let rHash: String?
    let value: LNDFlexibleInt?
    let settled: Bool?
    let creationDate: LNDFlexibleInt?
    let settleDate: LNDFlexibleInt?
    let addIndex: LNDFlexibleInt?
    let settleIndex: LNDFlexibleInt?
    let paymentRequest: String?
    let state: String?
    let amtPaidSat: LNDFlexibleInt?

    enum CodingKeys: String, CodingKey {
        case memo
        case rHash = "r_hash"
        case value
        case settled
        case creationDate = "creation_date"
        case settleDate = "settle_date"
        case addIndex = "add_index"
        case settleIndex = "settle_index"
        case paymentRequest = "payment_request"
        case state
        case amtPaidSat = "amt_paid_sat"
    }
}

struct LNDListInvoicesResponse: Decodable, Equatable {
    let invoices: [LNDInvoice]
}
