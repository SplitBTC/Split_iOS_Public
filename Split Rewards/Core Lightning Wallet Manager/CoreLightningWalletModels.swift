//
//  CoreLightningWalletModels.swift
//  Split Rewards
//
//  Created by TeeVee on 5/9/26.
//

import Foundation
import Network

enum CoreLightningWalletError: LocalizedError, Equatable {
    case invalidConnectionURL
    case missingNodeHost
    case missingRune
    case invalidRune
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
        case .invalidConnectionURL:
            return "The Core Lightning connection string is invalid."
        case .missingNodeHost:
            return "The Core Lightning connection string is missing a node host."
        case .missingRune:
            return "The Core Lightning connection string is missing a rune."
        case .invalidRune:
            return "The Core Lightning rune is invalid."
        case .invalidCertificate:
            return "The Core Lightning TLS certificate is invalid."
        case .invalidBaseURL:
            return "The Core Lightning node URL is invalid."
        case .publicInternetHostNotAllowed:
            return "This Core Lightning REST connection uses a public host. Split supports private-network, .local, Tailscale, or Tor .onion Core Lightning REST connections."
        case .noStoredNode:
            return "No Core Lightning node is stored on this device."
        case .nodeNotConnected:
            return "Core Lightning node is not connected."
        case .invalidResponse:
            return "Core Lightning returned an invalid response."
        case .serverError(let statusCode, let message):
            return "Core Lightning server error \(statusCode): \(message)"
        case .tlsCertificateMismatch:
            return "The Core Lightning node certificate does not match the saved certificate."
        case .missingServerTrust:
            return "Unable to verify the Core Lightning node certificate."
        }
    }
}

enum CoreLightningHostAccessPolicy {
    static func validate(host: String) throws {
        if let error = validationError(for: host) {
            throw error
        }
    }

    static func validationError(for host: String) -> CoreLightningWalletError? {
        let normalizedHost = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedHost.isEmpty else {
            return .missingNodeHost
        }

        return nil
    }

    static func validateResolvedAddresses(_ addresses: [CoreLightningResolvedAddress]) throws {
        if let error = resolvedAddressValidationError(for: addresses) {
            throw error
        }
    }

    static func resolvedAddressValidationError(for addresses: [CoreLightningResolvedAddress]) -> CoreLightningWalletError? {
        guard !addresses.isEmpty else {
            return .publicInternetHostNotAllowed
        }

        guard addresses.allSatisfy(isAllowedResolvedAddress) else {
            return .publicInternetHostNotAllowed
        }

        return nil
    }

    private static func isAllowedResolvedAddress(_ address: CoreLightningResolvedAddress) -> Bool {
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
                return (64...127).contains(Int(secondOctet))
            default:
                return false
            }
        case .ipv6(let ipv6Address):
            let bytes = ipv6Address.rawValue
            if (bytes[0] & 0xfe) == 0xfc {
                return true
            }

            return bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
        }
    }
}

enum CoreLightningResolvedAddress: Hashable {
    case ipv4(IPv4Address)
    case ipv6(IPv6Address)
}

struct CoreLightningMilliSatoshi: Codable, Equatable {
    let msats: Int64

    init(msats: Int64) {
        self.msats = msats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int64.self) {
            msats = int
            return
        }

        if let double = try? container.decode(Double.self) {
            msats = Int64(double)
            return
        }

        if let string = try? container.decode(String.self),
           let parsed = Self.parse(string) {
            msats = parsed
            return
        }

        msats = 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("\(msats)msat")
    }

    var satsRoundedDown: Int64 {
        max(msats, 0) / 1_000
    }

    var satsRoundedUp: Int64 {
        guard msats > 0 else { return 0 }
        let sats = msats / 1_000
        return msats % 1_000 == 0 ? sats : sats + 1
    }

    static func sats(_ sats: Int64) -> String {
        "\(max(sats, 0) * 1_000)msat"
    }

    static func parse(_ value: String) -> Int64? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return nil }

        if normalized.hasSuffix("msat") {
            return Int64(normalized.dropLast(4))
        }

        if normalized.hasSuffix("sat") {
            guard let sats = Decimal(string: String(normalized.dropLast(3))) else { return nil }
            return decimalToMsats(sats * 1_000)
        }

        if normalized.hasSuffix("btc") {
            guard let btc = Decimal(string: String(normalized.dropLast(3))) else { return nil }
            return decimalToMsats(btc * 100_000_000_000)
        }

        return Int64(normalized)
    }

    private static func decimalToMsats(_ decimal: Decimal) -> Int64? {
        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}

struct CoreLightningFlexibleInt: Codable, Equatable {
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

        if let double = try? container.decode(Double.self) {
            value = Int64(double)
            return
        }

        if let string = try? container.decode(String.self),
           let double = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            value = Int64(double)
            return
        }

        value = 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct CoreLightningNodeCredentials: Codable, Equatable, Identifiable {
    var id: String {
        if let nodeId = normalized(nodeId)?.lowercased() {
            return nodeId
        }

        return "\(scheme.lowercased())://\(host.lowercased()):\(port)"
    }

    let scheme: String
    let host: String
    let port: Int
    let rune: String
    let tlsCertificateDERBase64: String?
    let label: String?
    let nodeId: String?
    let nodeAlias: String?
    let connectedAt: Date
    let lastVerifiedAt: Date?

    var baseURL: URL? {
        URL(string: "\(scheme)://\(host):\(port)")
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

    func withLabel(_ label: String?) -> CoreLightningNodeCredentials {
        CoreLightningNodeCredentials(
            scheme: scheme,
            host: host,
            port: port,
            rune: rune,
            tlsCertificateDERBase64: tlsCertificateDERBase64,
            label: normalized(label),
            nodeId: nodeId,
            nodeAlias: nodeAlias,
            connectedAt: connectedAt,
            lastVerifiedAt: lastVerifiedAt
        )
    }

    func withHost(_ host: String) -> CoreLightningNodeCredentials {
        CoreLightningNodeCredentials(
            scheme: scheme,
            host: host,
            port: port,
            rune: rune,
            tlsCertificateDERBase64: tlsCertificateDERBase64,
            label: label,
            nodeId: nodeId,
            nodeAlias: nodeAlias,
            connectedAt: connectedAt,
            lastVerifiedAt: lastVerifiedAt
        )
    }

    func withTLSCertificateDERBase64(_ certificate: String?) -> CoreLightningNodeCredentials {
        CoreLightningNodeCredentials(
            scheme: scheme,
            host: host,
            port: port,
            rune: rune,
            tlsCertificateDERBase64: normalized(certificate) ?? tlsCertificateDERBase64,
            label: label,
            nodeId: nodeId,
            nodeAlias: nodeAlias,
            connectedAt: connectedAt,
            lastVerifiedAt: lastVerifiedAt
        )
    }

    func verified(with info: CoreLightningGetInfoResponse) -> CoreLightningNodeCredentials {
        CoreLightningNodeCredentials(
            scheme: scheme,
            host: host,
            port: port,
            rune: rune,
            tlsCertificateDERBase64: tlsCertificateDERBase64,
            label: label,
            nodeId: normalized(info.id) ?? nodeId,
            nodeAlias: normalized(info.alias) ?? nodeAlias,
            connectedAt: connectedAt,
            lastVerifiedAt: Date()
        )
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var restConnectionCandidates: [CoreLightningNodeCredentials] {
        var candidates = [self]
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedHost = trimmedHost.lowercased()

        if lowercasedHost.hasSuffix(".local") {
            let fallbackHost = String(trimmedHost.dropLast(".local".count))
            if !fallbackHost.isEmpty {
                candidates.append(withHost(fallbackHost))
            }
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = "\(candidate.scheme.lowercased())://\(candidate.host.lowercased()):\(candidate.port)"
            return seen.insert(key).inserted
        }
    }
}

struct CoreLightningGetInfoResponse: Decodable, Equatable {
    let id: String
    let alias: String?
    let color: String?
    let numPeers: Int?
    let numPendingChannels: Int?
    let numActiveChannels: Int?
    let numInactiveChannels: Int?
    let blockHeight: Int?
    let network: String?
    let version: String?

    enum CodingKeys: String, CodingKey {
        case id
        case alias
        case color
        case numPeers = "num_peers"
        case numPendingChannels = "num_pending_channels"
        case numActiveChannels = "num_active_channels"
        case numInactiveChannels = "num_inactive_channels"
        case blockHeight = "blockheight"
        case network
        case version
    }
}

struct CoreLightningListFundsResponse: Decodable, Equatable {
    struct Output: Decodable, Equatable {
        let amountMsat: CoreLightningMilliSatoshi?
        let status: String?
        let reserved: Bool?

        enum CodingKeys: String, CodingKey {
            case amountMsat = "amount_msat"
            case status
            case reserved
        }
    }

    struct Channel: Decodable, Equatable {
        let ourAmountMsat: CoreLightningMilliSatoshi?
        let amountMsat: CoreLightningMilliSatoshi?
        let state: String?

        enum CodingKeys: String, CodingKey {
            case ourAmountMsat = "our_amount_msat"
            case amountMsat = "amount_msat"
            case state
        }
    }

    let outputs: [Output]
    let channels: [Channel]

    var spendableChannelBalanceSats: Int64 {
        channels
            .filter { $0.state?.caseInsensitiveCompare("CHANNELD_NORMAL") == .orderedSame }
            .map { $0.ourAmountMsat?.satsRoundedDown ?? 0 }
            .reduce(0, +)
    }

    var onChainBalanceSats: Int64 {
        outputs
            .filter { $0.status?.caseInsensitiveCompare("confirmed") == .orderedSame }
            .filter { $0.reserved != true }
            .map { $0.amountMsat?.satsRoundedDown ?? 0 }
            .reduce(0, +)
    }
}

struct CoreLightningInvoiceResponse: Decodable, Equatable {
    let bolt11: String
    let paymentHash: String?
    let expiresAt: CoreLightningFlexibleInt?

    enum CodingKeys: String, CodingKey {
        case bolt11
        case paymentHash = "payment_hash"
        case expiresAt = "expires_at"
    }
}

struct CoreLightningPayResponse: Decodable, Equatable {
    let paymentPreimage: String?
    let paymentHash: String?
    let createdAt: CoreLightningFlexibleInt?
    let parts: Int?
    let amountMsat: CoreLightningMilliSatoshi?
    let amountSentMsat: CoreLightningMilliSatoshi?
    let status: String?

    var didSucceed: Bool {
        status?.caseInsensitiveCompare("complete") == .orderedSame
    }

    enum CodingKeys: String, CodingKey {
        case paymentPreimage = "payment_preimage"
        case paymentHash = "payment_hash"
        case createdAt = "created_at"
        case parts
        case amountMsat = "amount_msat"
        case amountSentMsat = "amount_sent_msat"
        case status
    }
}

struct CoreLightningDecodeResponse: Decodable, Equatable {
    let type: String?
    let valid: Bool?
    let payee: String?
    let paymentHash: String?
    let amountMsat: CoreLightningMilliSatoshi?
    let description: String?
    let createdAt: CoreLightningFlexibleInt?
    let expiry: CoreLightningFlexibleInt?

    var amountSats: Int64? {
        amountMsat?.satsRoundedDown
    }

    enum CodingKeys: String, CodingKey {
        case type
        case valid
        case payee
        case paymentHash = "payment_hash"
        case amountMsat = "amount_msat"
        case description
        case createdAt = "created_at"
        case expiry
    }
}

struct CoreLightningPay: Decodable, Equatable, Identifiable {
    var id: String {
        paymentHash ?? bolt11 ?? "\(createdAt?.value ?? 0)"
    }

    let paymentHash: String?
    let paymentPreimage: String?
    let bolt11: String?
    let description: String?
    let destination: String?
    let status: String?
    let amountMsat: CoreLightningMilliSatoshi?
    let amountSentMsat: CoreLightningMilliSatoshi?
    let createdAt: CoreLightningFlexibleInt?
    let completedAt: CoreLightningFlexibleInt?

    enum CodingKeys: String, CodingKey {
        case paymentHash = "payment_hash"
        case paymentPreimage = "payment_preimage"
        case bolt11
        case description
        case destination
        case status
        case amountMsat = "amount_msat"
        case amountSentMsat = "amount_sent_msat"
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }
}

struct CoreLightningListPaysResponse: Decodable, Equatable {
    let pays: [CoreLightningPay]
}

struct CoreLightningInvoice: Decodable, Equatable, Identifiable {
    var id: String {
        paymentHash ?? bolt11 ?? label ?? "\(createdIndex?.value ?? 0)"
    }

    var isPaid: Bool {
        status?.caseInsensitiveCompare("paid") == .orderedSame
    }

    let label: String?
    let paymentHash: String?
    let status: String?
    let expiresAt: CoreLightningFlexibleInt?
    let createdIndex: CoreLightningFlexibleInt?
    let updatedIndex: CoreLightningFlexibleInt?
    let description: String?
    let amountMsat: CoreLightningMilliSatoshi?
    let amountReceivedMsat: CoreLightningMilliSatoshi?
    let paidAt: CoreLightningFlexibleInt?
    let bolt11: String?
    let paymentPreimage: String?

    enum CodingKeys: String, CodingKey {
        case label
        case paymentHash = "payment_hash"
        case status
        case expiresAt = "expires_at"
        case createdIndex = "created_index"
        case updatedIndex = "updated_index"
        case description
        case amountMsat = "amount_msat"
        case amountReceivedMsat = "amount_received_msat"
        case paidAt = "paid_at"
        case bolt11
        case paymentPreimage = "payment_preimage"
    }
}

struct CoreLightningListInvoicesResponse: Decodable, Equatable {
    let invoices: [CoreLightningInvoice]
}
