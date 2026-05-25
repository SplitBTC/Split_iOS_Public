//
//  LNDRestClient.swift
//  Split Rewards
//
//  Created by TeeVee on 4/21/26.
//

import Foundation
import Security

final class LNDRestClient: NSObject {
    private let credentials: LNDNodeCredentials
    private let requestTimeout: TimeInterval
    private let resourceTimeout: TimeInterval
    private let waitsForConnectivity: Bool
    private let transport: RemoteNodeTransport
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var session: URLSession?

    init(
        credentials: LNDNodeCredentials,
        requestTimeout: TimeInterval = 20,
        resourceTimeout: TimeInterval = 45,
        waitsForConnectivity: Bool = true,
        transport: RemoteNodeTransport? = nil
    ) {
        self.credentials = credentials
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.waitsForConnectivity = waitsForConnectivity
        self.transport = transport ?? .preferred(forHost: credentials.host)
        super.init()
    }

    deinit {
        session?.invalidateAndCancel()
    }

    func getInfo() async throws -> LNDGetInfoResponse {
        try await perform(path: "/v1/getinfo")
    }

    func walletBalance() async throws -> LNDWalletBalanceResponse {
        try await perform(path: "/v1/balance/blockchain")
    }

    func channelBalance() async throws -> LNDChannelBalanceResponse {
        try await perform(path: "/v1/balance/channels")
    }

    func addInvoice(
        amountSats: Int64?,
        memo: String?,
        expirySecs: Int64 = 3600
    ) async throws -> LNDAddInvoiceResponse {
        let body = AddInvoiceRequest(
            memo: memo,
            value: amountSats.map(String.init),
            expiry: String(expirySecs)
        )

        return try await perform(
            path: "/v1/invoices",
            method: "POST",
            bodyData: encoder.encode(body)
        )
    }

    func decodePayReq(_ bolt11: String) async throws -> LNDDecodePayReqResponse {
        try await perform(path: "/v1/payreq/\(bolt11)")
    }

    func payInvoice(
        _ bolt11: String,
        amountSats: Int64? = nil
    ) async throws -> LNDPayInvoiceResponse {
        let body = PayInvoiceRequest(
            paymentRequest: bolt11,
            amountSats: amountSats.map(String.init)
        )

        return try await perform(
            path: "/v1/channels/transactions",
            method: "POST",
            bodyData: encoder.encode(body)
        )
    }

    func estimateRouteFee(destinationPubkey: String, amountSats: Int64) async throws -> Int64 {
        guard amountSats > 0 else {
            throw LNDWalletError.invalidResponse
        }

        do {
            return try await estimateRouteFeeWithRouter(
                destinationPubkey: destinationPubkey,
                amountSats: amountSats
            )
        } catch {
            return try await estimateRouteFeeWithQueryRoutes(
                destinationPubkey: destinationPubkey,
                amountSats: amountSats
            )
        }
    }

    func signMessage(_ message: String) async throws -> LNDSignMessageResponse {
        let body = SignMessageRequest(
            msg: Data(message.utf8).base64EncodedString(),
            singleHash: false
        )

        return try await perform(
            path: "/v1/signmessage",
            method: "POST",
            bodyData: encoder.encode(body)
        )
    }

    func listPayments(maxPayments: Int = 50) async throws -> LNDListPaymentsResponse {
        try await perform(
            path: "/v1/payments",
            queryItems: [
                URLQueryItem(name: "max_payments", value: String(maxPayments))
            ]
        )
    }

    func listInvoices(maxInvoices: Int = 50) async throws -> LNDListInvoicesResponse {
        try await perform(
            path: "/v1/invoices",
            queryItems: [
                URLQueryItem(name: "num_max_invoices", value: String(maxInvoices))
            ]
        )
    }

    func subscribeInvoices(settleIndex: Int64?) -> AsyncThrowingStream<LNDInvoice, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var queryItems: [URLQueryItem] = []
                    if let settleIndex {
                        queryItems.append(URLQueryItem(name: "settle_index", value: String(settleIndex)))
                    }

                    let request = try makeRequest(
                        path: "/v1/invoices/subscribe",
                        queryItems: queryItems
                    )
                    let session = try await self.resolvedSession()
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw LNDWalletError.invalidResponse
                    }

                    guard (200...299).contains(http.statusCode) else {
                        throw LNDWalletError.serverError(
                            statusCode: http.statusCode,
                            message: "Invoice listener connection failed."
                        )
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()

                        if let invoice = try decodeStreamingInvoiceLine(line) {
                            continuation.yield(invoice)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func perform<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        bodyData: Data? = nil
    ) async throws -> Response {
        let request = try makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: bodyData
        )

        let session = try await resolvedSession()
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LNDWalletError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw LNDWalletError.serverError(
                statusCode: http.statusCode,
                message: serverErrorMessage(from: data)
            )
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            throw LNDWalletError.serverError(
                statusCode: http.statusCode,
                message: "Unable to decode LND response: \(raw)"
            )
        }
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        bodyData: Data? = nil
    ) throws -> URLRequest {
        let url = try makeURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(credentials.macaroonHex, forHTTPHeaderField: "Grpc-Metadata-macaroon")

        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func resolvedSession() async throws -> URLSession {
        if let session {
            return session
        }

        let configuration = try await RemoteNodeURLSessionFactory.configuration(
            transport: transport,
            requestTimeout: requestTimeout,
            resourceTimeout: resourceTimeout,
            waitsForConnectivity: waitsForConnectivity
        )
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        return session
    }

    private func decodeStreamingInvoiceLine(_ line: String) throws -> LNDInvoice? {
        var trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return nil }

        if trimmedLine.hasPrefix("data:") {
            trimmedLine = String(trimmedLine.dropFirst("data:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let data = Data(trimmedLine.utf8)

        if let envelope = try? decoder.decode(LNDStreamEnvelope<LNDInvoice>.self, from: data) {
            if let errorMessage = envelope.errorMessage {
                throw LNDWalletError.serverError(statusCode: 200, message: errorMessage)
            }

            if let result = envelope.result {
                return result
            }
        }

        if let serverError = try? decoder.decode(LNDServerErrorResponse.self, from: data),
           let message = serverError.message ?? serverError.error {
            throw LNDWalletError.serverError(statusCode: 200, message: message)
        }

        return try decoder.decode(LNDInvoice.self, from: data)
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard credentials.baseURL != nil else {
            throw LNDWalletError.invalidBaseURL
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = credentials.host
        components.port = credentials.port
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw LNDWalletError.invalidBaseURL
        }

        return url
    }

    private func serverErrorMessage(from data: Data) -> String {
        if let decoded = try? decoder.decode(LNDServerErrorResponse.self, from: data) {
            return decoded.message ?? decoded.error ?? "Unknown LND error"
        }

        return String(data: data, encoding: .utf8) ?? "Unknown LND error"
    }

    private func estimateRouteFeeWithRouter(
        destinationPubkey: String,
        amountSats: Int64
    ) async throws -> Int64 {
        let normalizedDestination = destinationPubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard normalizedDestination.count.isMultiple(of: 2),
              let destinationData = hexData(from: normalizedDestination),
              !destinationData.isEmpty else {
            throw LNDWalletError.invalidResponse
        }

        let body = EstimateRouteFeeRequest(
            destination: destinationData.base64EncodedString(),
            amountSats: String(amountSats)
        )

        let response: EstimateRouteFeeResponse = try await perform(
            path: "/v2/router/route/estimatefee",
            method: "POST",
            bodyData: encoder.encode(body)
        )

        guard let routingFeeMsats = response.routingFeeMsats?.value,
              routingFeeMsats >= 0 else {
            throw LNDWalletError.invalidResponse
        }

        return msatsToSatsCeiling(routingFeeMsats)
    }

    private func estimateRouteFeeWithQueryRoutes(
        destinationPubkey: String,
        amountSats: Int64
    ) async throws -> Int64 {
        let normalizedDestination = destinationPubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedDestination.isEmpty else {
            throw LNDWalletError.invalidResponse
        }

        let response: QueryRoutesResponse = try await perform(
            path: "/v1/graph/routes/\(normalizedDestination)/\(amountSats)"
        )

        let feeOptions = response.routes.compactMap { route -> Int64? in
            if let totalFeesMsats = route.totalFeesMsats?.value,
               totalFeesMsats >= 0 {
                return msatsToSatsCeiling(totalFeesMsats)
            }

            if let totalFeesSats = route.totalFeesSats?.value,
               totalFeesSats >= 0 {
                return totalFeesSats
            }

            return nil
        }

        guard let lowestFee = feeOptions.min() else {
            throw LNDWalletError.invalidResponse
        }

        return lowestFee
    }

    private func msatsToSatsCeiling(_ msats: Int64) -> Int64 {
        guard msats > 0 else { return 0 }
        let wholeSats = msats / 1_000
        return msats % 1_000 == 0 ? wholeSats : wholeSats + 1
    }

    private func hexData(from value: String) -> Data? {
        guard value.count.isMultiple(of: 2) else { return nil }

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

        return Data(bytes)
    }
}

extension LNDRestClient: URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let pinnedCertificateData = credentials.tlsCertificateData else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard serverTrustContainsPinnedCertificate(
            serverTrust,
            pinnedCertificateData: pinnedCertificateData
        ) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private func serverTrustContainsPinnedCertificate(
        _ serverTrust: SecTrust,
        pinnedCertificateData: Data
    ) -> Bool {
        let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] ?? []
        guard !certificateChain.isEmpty else { return false }

        for certificate in certificateChain {
            let certificateData = SecCertificateCopyData(certificate) as Data
            if certificateData == pinnedCertificateData {
                return true
            }
        }

        return false
    }
}

private struct LNDServerErrorResponse: Decodable {
    let error: String?
    let message: String?
}

private struct LNDStreamEnvelope<Result: Decodable>: Decodable {
    let result: Result?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case result
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        result = try container.decodeIfPresent(Result.self, forKey: .result)

        if let stringError = try? container.decodeIfPresent(String.self, forKey: .error) {
            errorMessage = stringError
        } else if let serverError = try? container.decodeIfPresent(LNDServerErrorResponse.self, forKey: .error) {
            errorMessage = serverError.message ?? serverError.error
        } else {
            errorMessage = nil
        }
    }
}

private struct AddInvoiceRequest: Encodable {
    let memo: String?
    let value: String?
    let expiry: String?
}

private struct PayInvoiceRequest: Encodable {
    let paymentRequest: String
    let amountSats: String?

    enum CodingKeys: String, CodingKey {
        case paymentRequest = "payment_request"
        case amountSats = "amt"
    }
}

private struct EstimateRouteFeeRequest: Encodable {
    let destination: String
    let amountSats: String

    enum CodingKeys: String, CodingKey {
        case destination = "dest"
        case amountSats = "amt_sat"
    }
}

private struct EstimateRouteFeeResponse: Decodable {
    let routingFeeMsats: LNDFlexibleInt?

    enum CodingKeys: String, CodingKey {
        case routingFeeMsats = "routing_fee_msat"
    }
}

private struct QueryRoutesResponse: Decodable {
    let routes: [QueryRoute]
}

private struct QueryRoute: Decodable {
    let totalFeesSats: LNDFlexibleInt?
    let totalFeesMsats: LNDFlexibleInt?

    enum CodingKeys: String, CodingKey {
        case totalFeesSats = "total_fees"
        case totalFeesMsats = "total_fees_msat"
    }
}

private struct SignMessageRequest: Encodable {
    let msg: String
    let singleHash: Bool

    enum CodingKeys: String, CodingKey {
        case msg
        case singleHash = "single_hash"
    }
}
