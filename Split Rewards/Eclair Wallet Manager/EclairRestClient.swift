//
//  EclairRestClient.swift
//  Split Rewards
//
//  Created by TeeVee on 5/19/26.
//

import Foundation

final class EclairRestClient {
    private let credentials: EclairNodeCredentials
    private let requestTimeout: TimeInterval
    private let resourceTimeout: TimeInterval
    private let waitsForConnectivity: Bool
    private let transport: RemoteNodeTransport
    private let decoder = JSONDecoder()
    private var session: URLSession?

    init(
        credentials: EclairNodeCredentials,
        requestTimeout: TimeInterval = 20,
        resourceTimeout: TimeInterval = 75,
        waitsForConnectivity: Bool = true,
        transport: RemoteNodeTransport? = nil
    ) {
        self.credentials = credentials
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.waitsForConnectivity = waitsForConnectivity
        self.transport = transport ?? .preferred(forHost: credentials.host)
    }

    deinit {
        session?.invalidateAndCancel()
    }

    func getInfo() async throws -> EclairGetInfoResponse {
        try await requestJSON(path: "getinfo")
    }

    func channelBalances() async throws -> [EclairChannelBalance] {
        try await requestJSON(path: "channelbalances")
    }

    func onChainBalance() async throws -> EclairOnChainBalance {
        try await requestJSON(path: "onchainbalance")
    }

    func createInvoice(
        amountSats: Int64?,
        memo: String?,
        expirySecs: Int64 = 3600
    ) async throws -> EclairInvoiceResponse {
        var form = [
            "description": memo?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "Split payment",
            "expireIn": "\(expirySecs)"
        ]

        if let amountSats, amountSats > 0 {
            form["amountMsat"] = EclairMilliSatoshi.sats(amountSats)
        }

        return try await requestJSON(path: "createinvoice", form: form)
    }

    func parseInvoice(_ bolt11: String) async throws -> EclairParseInvoiceResponse {
        try await requestJSON(path: "parseinvoice", form: ["invoice": bolt11])
    }

    func payInvoice(
        _ bolt11: String,
        amountSats: Int64? = nil
    ) async throws -> EclairPayResponse {
        var form = [
            "invoice": bolt11,
            "blocking": "true"
        ]

        if let amountSats, amountSats > 0 {
            form["amountMsat"] = EclairMilliSatoshi.sats(amountSats)
        }

        let response: EclairPayResponse = try await requestJSON(
            path: "payinvoice",
            form: form,
            resourceTimeout: max(resourceTimeout, 120)
        )

        guard response.didSucceed else {
            throw EclairWalletError.paymentFailed(response.failureMessage)
        }

        return response
    }

    func getSentInfo(paymentHash: String) async throws -> [EclairSentPayment] {
        try await requestJSON(path: "getsentinfo", form: ["paymentHash": paymentHash])
    }

    func getReceivedInfo(paymentHash: String) async throws -> EclairReceivedPayment {
        try await requestJSON(path: "getreceivedinfo", form: ["paymentHash": paymentHash])
    }

    func listReceivedPayments(limit: Int = 50) async throws -> [EclairReceivedPayment] {
        try await requestJSON(path: "listreceivedpayments", form: ["count": "\(limit)"])
    }

    func listInvoices(limit: Int = 50) async throws -> [EclairInvoiceResponse] {
        try await requestJSON(path: "listinvoices", form: ["count": "\(limit)"])
    }

    private func requestJSON<Response: Decodable>(
        path: String,
        form: [String: String] = [:],
        resourceTimeout: TimeInterval? = nil
    ) async throws -> Response {
        let request = try makeRequest(path: path, form: form)
        let session = try await resolvedSession(resourceTimeout: resourceTimeout)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw EclairWalletError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw EclairWalletError.serverError(
                statusCode: http.statusCode,
                message: serverErrorMessage(from: data)
            )
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            throw EclairWalletError.serverError(
                statusCode: http.statusCode,
                message: "Unable to decode Eclair response: \(raw)"
            )
        }
    }

    private func makeRequest(path: String, form: [String: String]) throws -> URLRequest {
        let url = try makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.httpBody = formURLEncodedBody(form)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeaderValue(), forHTTPHeaderField: "Authorization")
        return request
    }

    private func makeURL(path: String) throws -> URL {
        guard credentials.baseURL != nil else {
            throw EclairWalletError.invalidBaseURL
        }

        var components = URLComponents()
        components.scheme = credentials.scheme
        components.host = credentials.host
        components.port = credentials.port
        components.path = "/\(path)"

        guard let url = components.url else {
            throw EclairWalletError.invalidBaseURL
        }

        return url
    }

    private func resolvedSession(resourceTimeout: TimeInterval?) async throws -> URLSession {
        if let session, resourceTimeout == nil {
            return session
        }

        let configuration = try await RemoteNodeURLSessionFactory.configuration(
            transport: transport,
            requestTimeout: requestTimeout,
            resourceTimeout: resourceTimeout ?? self.resourceTimeout,
            waitsForConnectivity: waitsForConnectivity
        )
        let session = URLSession(configuration: configuration)
        if resourceTimeout == nil {
            self.session = session
        }
        return session
    }

    private func basicAuthHeaderValue() -> String {
        let authString = ":\(credentials.apiPassword)"
        let encoded = Data(authString.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private func formURLEncodedBody(_ form: [String: String]) -> Data? {
        form
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(urlFormEncode(key))=\(urlFormEncode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8)
    }

    private func urlFormEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func serverErrorMessage(from data: Data) -> String {
        if let decoded = try? decoder.decode(EclairServerErrorResponse.self, from: data) {
            return decoded.message ?? decoded.error ?? decoded.details ?? "Unknown Eclair error"
        }

        return String(data: data, encoding: .utf8) ?? "Unknown Eclair error"
    }
}

private extension EclairPayResponse {
    var failureMessage: String? {
        status?.failures?.compactMap { $0.failureMessage ?? $0.reason }.joined(separator: "\n").nilIfBlank
    }
}
