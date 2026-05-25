//
//  LNDLightningPaymentResolver.swift
//  Split Rewards
//
//  Created by TeeVee on 4/21/26.
//

import Foundation

enum LNDLightningPaymentResolver {
    struct ResolvedInvoice {
        let invoice: String
    }

    enum ResolverError: LocalizedError {
        case unsupportedRequest
        case invalidLightningAddress
        case invalidLNURL
        case invalidResponse
        case amountOutOfRange(minSats: Int64, maxSats: Int64)
        case serverError(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedRequest:
                return "Node wallet sends support Lightning invoices, LNURL, and Lightning addresses."
            case .invalidLightningAddress:
                return "The Lightning address is invalid."
            case .invalidLNURL:
                return "The LNURL is invalid."
            case .invalidResponse:
                return "The LNURL server returned an invalid response."
            case .amountOutOfRange(let minSats, let maxSats):
                return "Amount must be between \(minSats) and \(maxSats) sats."
            case .serverError(let message):
                return message
            }
        }
    }

    static func resolveInvoice(
        from paymentRequest: String,
        amountSats: Int64,
        comment: String?
    ) async throws -> ResolvedInvoice {
        let trimmed = paymentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("lnbc") || lower.hasPrefix("lntb") || lower.hasPrefix("lnbcrt") {
            return ResolvedInvoice(invoice: trimmed)
        }

        if lower.hasPrefix("lnurl") {
            let url = try decodeLNURL(trimmed)
            return try await resolveLNURLPay(url: url, amountSats: amountSats, comment: comment)
        }

        if trimmed.contains("@"), !trimmed.contains(" ") {
            let url = try lightningAddressURL(trimmed)
            return try await resolveLNURLPay(url: url, amountSats: amountSats, comment: comment)
        }

        throw ResolverError.unsupportedRequest
    }

    static func isBolt11(_ paymentRequest: String) -> Bool {
        let lower = paymentRequest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("lnbc") || lower.hasPrefix("lntb") || lower.hasPrefix("lnbcrt")
    }

    private static func resolveLNURLPay(
        url: URL,
        amountSats: Int64,
        comment: String?
    ) async throws -> ResolvedInvoice {
        let payRequest: LNURLPayRequest = try await fetchJSON(url: url)

        if let status = payRequest.status,
           status.caseInsensitiveCompare("ERROR") == .orderedSame {
            throw ResolverError.serverError(payRequest.reason ?? "LNURL server returned an error.")
        }

        guard payRequest.tag?.caseInsensitiveCompare("payRequest") == .orderedSame,
              let callback = URL(string: payRequest.callback ?? "") else {
            throw ResolverError.invalidResponse
        }

        guard amountSats <= Int64.max / 1_000 else {
            throw ResolverError.amountOutOfRange(minSats: 1, maxSats: Int64.max / 1_000)
        }

        let amountMsats = amountSats * 1_000
        if let minSendable = payRequest.minSendable,
           let maxSendable = payRequest.maxSendable,
           (amountMsats < minSendable || amountMsats > maxSendable) {
            throw ResolverError.amountOutOfRange(
                minSats: max(1, minSendable / 1_000),
                maxSats: max(1, maxSendable / 1_000)
            )
        }

        var components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "amount", value: String(amountMsats)))

        if let normalizedComment = normalizedComment(comment, allowedLength: payRequest.commentAllowed) {
            queryItems.append(URLQueryItem(name: "comment", value: normalizedComment))
        }

        components?.queryItems = queryItems

        guard let callbackURL = components?.url else {
            throw ResolverError.invalidResponse
        }

        let callbackResponse: LNURLPayCallbackResponse = try await fetchJSON(url: callbackURL)

        if let status = callbackResponse.status,
           status.caseInsensitiveCompare("ERROR") == .orderedSame {
            throw ResolverError.serverError(callbackResponse.reason ?? "LNURL payment request failed.")
        }

        guard let invoice = callbackResponse.pr?.trimmingCharacters(in: .whitespacesAndNewlines),
              !invoice.isEmpty else {
            throw ResolverError.invalidResponse
        }

        return ResolvedInvoice(invoice: invoice)
    }

    private static func fetchJSON<Response: Decodable>(url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw ResolverError.invalidResponse
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func lightningAddressURL(_ value: String) throws -> URL {
        let parts = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "@", maxSplits: 1)

        guard parts.count == 2 else {
            throw ResolverError.invalidLightningAddress
        }

        let username = String(parts[0])
        let domain = String(parts[1])

        guard !username.isEmpty,
              !domain.isEmpty,
              let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://\(domain)/.well-known/lnurlp/\(encodedUsername)") else {
            throw ResolverError.invalidLightningAddress
        }

        return url
    }

    private static func normalizedComment(_ value: String?, allowedLength: Int?) -> String? {
        guard let allowedLength, allowedLength > 0 else { return nil }
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return String(value.prefix(allowedLength))
    }

    private static func decodeLNURL(_ value: String) throws -> URL {
        guard let decoded = Bech32.decode(value),
              decoded.hrp.lowercased() == "lnurl",
              let text = String(data: Data(convertBits(decoded.data, fromBits: 5, toBits: 8, pad: false)), encoding: .utf8),
              let url = URL(string: text) else {
            throw ResolverError.invalidLNURL
        }

        return url
    }

    private static func convertBits(
        _ data: [UInt8],
        fromBits: Int,
        toBits: Int,
        pad: Bool
    ) -> [UInt8] {
        var acc = 0
        var bits = 0
        var result: [UInt8] = []
        let maxv = (1 << toBits) - 1
        let maxAcc = (1 << (fromBits + toBits - 1)) - 1

        for value in data {
            acc = ((acc << fromBits) | Int(value)) & maxAcc
            bits += fromBits

            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }

        if pad, bits > 0 {
            result.append(UInt8((acc << (toBits - bits)) & maxv))
        }

        return result
    }
}

private struct LNURLPayRequest: Decodable {
    let tag: String?
    let callback: String?
    let minSendable: Int64?
    let maxSendable: Int64?
    let commentAllowed: Int?
    let status: String?
    let reason: String?

    fileprivate struct CodingKeyValue: CodingKey {
        var stringValue: String
        var intValue: Int?

        init(_ stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeyValue.self)
        tag = try container.decodeIfPresent(String.self, forKey: CodingKeyValue("tag"))
        callback = try container.decodeIfPresent(String.self, forKey: CodingKeyValue("callback"))
        minSendable = try container.decodeFlexibleInt(forKeys: "minSendable", "min_sendable")
        maxSendable = try container.decodeFlexibleInt(forKeys: "maxSendable", "max_sendable")
        commentAllowed = try container.decodeFlexibleInt(forKeys: "commentAllowed", "comment_allowed").map(Int.init)
        status = try container.decodeIfPresent(String.self, forKey: CodingKeyValue("status"))
        reason = try container.decodeIfPresent(String.self, forKey: CodingKeyValue("reason"))
    }
}

private struct LNURLPayCallbackResponse: Decodable {
    let pr: String?
    let status: String?
    let reason: String?
}

private extension KeyedDecodingContainer where Key == LNURLPayRequest.CodingKeyValue {
    func decodeFlexibleInt(forKeys keys: String...) throws -> Int64? {
        for key in keys {
            let codingKey = LNURLPayRequest.CodingKeyValue(key)

            if let intValue = try decodeIfPresent(Int64.self, forKey: codingKey) {
                return intValue
            }

            if let stringValue = try decodeIfPresent(String.self, forKey: codingKey),
               let intValue = Int64(stringValue) {
                return intValue
            }
        }

        return nil
    }
}

private enum Bech32 {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    static func decode(_ value: String) -> (hrp: String, data: [UInt8])? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let separatorIndex = normalized.lastIndex(of: "1") else {
            return nil
        }

        let hrp = String(normalized[..<separatorIndex])
        let dataPart = normalized[normalized.index(after: separatorIndex)...]
        guard !hrp.isEmpty, dataPart.count > 6 else {
            return nil
        }

        let payloadPart = dataPart.dropLast(6)
        var payload: [UInt8] = []
        payload.reserveCapacity(payloadPart.count)

        for character in payloadPart {
            guard let index = charset.firstIndex(of: character) else {
                return nil
            }
            payload.append(UInt8(index))
        }

        return (hrp, payload)
    }
}
