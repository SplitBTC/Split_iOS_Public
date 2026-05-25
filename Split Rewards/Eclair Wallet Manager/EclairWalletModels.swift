//
//  EclairWalletModels.swift
//  Split Rewards
//
//  Created by TeeVee on 5/19/26.
//

import Foundation
import Network

enum EclairWalletError: LocalizedError, Equatable {
    case invalidConnection
    case missingNodeHost
    case missingPassword
    case invalidBaseURL
    case publicInternetHostNotAllowed
    case noStoredNode
    case nodeNotConnected
    case invalidResponse
    case paymentFailed(String?)
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidConnection:
            return "The Eclair connection details are invalid."
        case .missingNodeHost:
            return "The Eclair connection is missing a node host."
        case .missingPassword:
            return "The Eclair API password is missing."
        case .invalidBaseURL:
            return "The Eclair node URL is invalid."
        case .publicInternetHostNotAllowed:
            return "This Eclair connection uses a public host. Split supports private-network, .local, Tailscale, or Tor .onion Eclair connections."
        case .noStoredNode:
            return "No Eclair node is stored on this device."
        case .nodeNotConnected:
            return "Eclair node is not connected."
        case .invalidResponse:
            return "Eclair returned an invalid response."
        case .paymentFailed(let message):
            return message?.nilIfBlank ?? "Eclair payment failed."
        case .serverError(let statusCode, let message):
            return "Eclair server error \(statusCode): \(message)"
        }
    }
}

enum EclairHostAccessPolicy {
    static func validate(host: String) throws {
        let normalizedHost = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedHost.isEmpty else {
            throw EclairWalletError.missingNodeHost
        }
    }

    static func validateResolvedAddresses(_ addresses: [EclairResolvedAddress]) throws {
        guard !addresses.isEmpty,
              addresses.allSatisfy(isAllowedResolvedAddress) else {
            throw EclairWalletError.publicInternetHostNotAllowed
        }
    }

    private static func isAllowedResolvedAddress(_ address: EclairResolvedAddress) -> Bool {
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

enum EclairResolvedAddress: Hashable {
    case ipv4(IPv4Address)
    case ipv6(IPv6Address)
}

struct EclairMilliSatoshi: Codable, Equatable {
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
           let parsed = Int64(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            msats = parsed
            return
        }

        msats = 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(msats)
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
        "\(max(sats, 0) * 1_000)"
    }
}

struct EclairTimestamp: Codable, Equatable {
    let iso: String?
    let unix: Int64?

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            iso = try container.decodeIfPresent(String.self, forKey: .iso)
            unix = try container.decodeIfPresent(Int64.self, forKey: .unix)
            return
        }

        let container = try decoder.singleValueContainer()
        iso = nil
        if let int = try? container.decode(Int64.self) {
            unix = int
        } else if let double = try? container.decode(Double.self) {
            unix = Int64(double)
        } else {
            unix = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(iso, forKey: .iso)
        try container.encodeIfPresent(unix, forKey: .unix)
    }

    enum CodingKeys: String, CodingKey {
        case iso
        case unix
    }
}

struct EclairNodeCredentials: Codable, Equatable, Identifiable {
    var id: String {
        if let nodeId = normalized(nodeId)?.lowercased() {
            return nodeId
        }

        return "\(scheme.lowercased())://\(host.lowercased()):\(port)"
    }

    let scheme: String
    let host: String
    let port: Int
    let apiPassword: String
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

    var displayName: String {
        if let label = normalized(label) {
            return label
        }

        if let nodeAlias = normalized(nodeAlias) {
            return nodeAlias
        }

        return "\(host):\(port)"
    }

    func withLabel(_ label: String?) -> EclairNodeCredentials {
        EclairNodeCredentials(
            scheme: scheme,
            host: host,
            port: port,
            apiPassword: apiPassword,
            label: normalized(label),
            nodeId: nodeId,
            nodeAlias: nodeAlias,
            connectedAt: connectedAt,
            lastVerifiedAt: lastVerifiedAt
        )
    }

    func withHost(_ host: String) -> EclairNodeCredentials {
        EclairNodeCredentials(
            scheme: scheme,
            host: host,
            port: port,
            apiPassword: apiPassword,
            label: label,
            nodeId: nodeId,
            nodeAlias: nodeAlias,
            connectedAt: connectedAt,
            lastVerifiedAt: lastVerifiedAt
        )
    }

    func verified(with info: EclairGetInfoResponse) -> EclairNodeCredentials {
        EclairNodeCredentials(
            scheme: scheme,
            host: host,
            port: port,
            apiPassword: apiPassword,
            label: label,
            nodeId: normalized(info.nodeId) ?? nodeId,
            nodeAlias: normalized(info.alias) ?? nodeAlias,
            connectedAt: connectedAt,
            lastVerifiedAt: Date()
        )
    }

    var restConnectionCandidates: [EclairNodeCredentials] {
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

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct EclairGetInfoResponse: Decodable, Equatable {
    let nodeId: String
    let alias: String?
    let version: String?
    let blockHeight: Int?

    enum CodingKeys: String, CodingKey {
        case nodeId
        case alias
        case version
        case blockHeight
    }
}

struct EclairInvoiceResponse: Decodable, Equatable {
    let nodeId: String?
    let serialized: String
    let description: String?
    let paymentHash: String?
    let expiry: Int64?
    let amount: EclairMilliSatoshi?
    let timestamp: Int64?

    var amountSats: Int64? {
        amount?.satsRoundedDown
    }
}

typealias EclairParseInvoiceResponse = EclairInvoiceResponse

struct EclairPayResponse: Decodable, Equatable {
    let paymentHash: String?
    let paymentPreimage: String?
    let status: EclairPaymentStatus?
    let recipientAmount: EclairMilliSatoshi?
    let amount: EclairMilliSatoshi?
    let feesPaid: EclairMilliSatoshi?
    let parts: [EclairSentPaymentPart]?
    let paymentId: String?

    var didSucceed: Bool {
        status?.type?.caseInsensitiveCompare("sent") == .orderedSame
    }

    enum CodingKeys: String, CodingKey {
        case paymentHash
        case paymentPreimage
        case status
        case recipientAmount
        case amount
        case feesPaid
        case parts
        case paymentId = "id"
    }
}

struct EclairPaymentStatus: Decodable, Equatable {
    let type: String?
    let paymentPreimage: String?
    let feesPaid: EclairMilliSatoshi?
    let completedAt: EclairTimestamp?
    let failures: [EclairFailure]?
}

struct EclairFailure: Decodable, Equatable {
    let failureMessage: String?
    let reason: String?
}

struct EclairSentPaymentPart: Decodable, Equatable {
    let id: String?
    let parentId: String?
}

struct EclairSentPayment: Decodable, Equatable, Identifiable {
    var id: String {
        paymentHash ?? paymentId ?? payment?.paymentHash ?? UUID().uuidString
    }

    let paymentId: String?
    let paymentHash: String?
    let paymentPreimage: String?
    let payment: EclairInvoiceResponse?
    let status: EclairPaymentStatus?
    let recipientAmount: EclairMilliSatoshi?
    let amount: EclairMilliSatoshi?
    let feesPaid: EclairMilliSatoshi?
    let createdAt: EclairTimestamp?
    let completedAt: EclairTimestamp?

    enum CodingKeys: String, CodingKey {
        case paymentId = "id"
        case paymentHash
        case paymentPreimage
        case payment
        case status
        case recipientAmount
        case amount
        case feesPaid
        case createdAt
        case completedAt
    }
}

struct EclairReceivedPayment: Decodable, Equatable, Identifiable {
    var id: String {
        paymentHash ?? invoice?.paymentHash ?? invoice?.serialized ?? UUID().uuidString
    }

    let invoice: EclairInvoiceResponse?
    let paymentHash: String?
    let amount: EclairMilliSatoshi?
    let receivedAmount: EclairMilliSatoshi?
    let feesPaid: EclairMilliSatoshi?
    let status: EclairPaymentStatus?
    let receivedAt: EclairTimestamp?
    let createdAt: EclairTimestamp?
}

struct EclairChannelBalance: Decodable, Equatable {
    let canSend: EclairMilliSatoshi?
    let canReceive: EclairMilliSatoshi?
    let isEnabled: Bool?
}

struct EclairOnChainBalance: Decodable, Equatable {
    let confirmed: Int64?
    let unconfirmed: Int64?
}

struct EclairServerErrorResponse: Decodable {
    let error: String?
    let message: String?
    let details: String?
}
