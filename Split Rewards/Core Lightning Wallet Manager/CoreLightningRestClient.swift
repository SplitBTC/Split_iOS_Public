//
//  CoreLightningRestClient.swift
//  Split Rewards
//
//  Created by TeeVee on 5/9/26.
//

import Foundation
import Security

final class CoreLightningRestClient: NSObject {
    private let credentials: CoreLightningNodeCredentials
    private let requestTimeout: TimeInterval
    private let resourceTimeout: TimeInterval
    private let waitsForConnectivity: Bool
    private let transport: RemoteNodeTransport
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var observedServerCertificateData: Data?
    private var session: URLSession?

    init(
        credentials: CoreLightningNodeCredentials,
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
        super.init()
    }

    deinit {
        session?.invalidateAndCancel()
    }

    var observedServerCertificateDERBase64: String? {
        observedServerCertificateData?.base64EncodedString()
    }

    func getInfo() async throws -> CoreLightningGetInfoResponse {
        try await rpc("getinfo", params: EmptyParams())
    }

    func listFunds() async throws -> CoreLightningListFundsResponse {
        try await rpc("listfunds", params: EmptyParams())
    }

    func createInvoice(
        amountSats: Int64?,
        memo: String?,
        expirySecs: Int64 = 3600
    ) async throws -> CoreLightningInvoiceResponse {
        try await rpc(
            "invoice",
            params: InvoiceParams(
                amountMsat: amountSats.map(CoreLightningMilliSatoshi.sats) ?? "any",
                label: "split-\(UUID().uuidString)",
                description: memo?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "Split payment",
                expiry: expirySecs
            )
        )
    }

    func decodeInvoice(_ bolt11: String) async throws -> CoreLightningDecodeResponse {
        try await rpc("decode", params: DecodeParams(string: bolt11))
    }

    func payInvoice(
        _ bolt11: String,
        amountSats: Int64? = nil
    ) async throws -> CoreLightningPayResponse {
        try await rpc(
            "pay",
            params: PayParams(
                bolt11: bolt11,
                amountMsat: amountSats.map(CoreLightningMilliSatoshi.sats),
                retryFor: 60
            )
        )
    }

    func listPays(limit: Int = 50) async throws -> CoreLightningListPaysResponse {
        let response: CoreLightningListPaysResponse = try await rpc("listpays", params: EmptyParams())
        return CoreLightningListPaysResponse(pays: Array(response.pays.prefix(limit)))
    }

    func listInvoices(limit: Int = 50) async throws -> CoreLightningListInvoicesResponse {
        let response: CoreLightningListInvoicesResponse = try await rpc("listinvoices", params: EmptyParams())
        return CoreLightningListInvoicesResponse(invoices: Array(response.invoices.prefix(limit)))
    }

    func estimateRouteFee(
        bolt11: String,
        amountSats: Int64?
    ) async -> Int64? {
        // CLN's pay fee is route-dependent and randomized. For v1 preview we only
        // show the final fee after payment appears in listpays.
        nil
    }

    private func rpc<Params: Encodable, Response: Decodable>(
        _ method: String,
        params: Params
    ) async throws -> Response {
        let body = try encoder.encode(params)
        let request = try makeRequest(method: method, bodyData: body)
        let session = try await resolvedSession()
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw CoreLightningWalletError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw CoreLightningWalletError.serverError(
                statusCode: http.statusCode,
                message: serverErrorMessage(from: data)
            )
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            throw CoreLightningWalletError.serverError(
                statusCode: http.statusCode,
                message: "Unable to decode Core Lightning response: \(raw)"
            )
        }
    }

    private func makeRequest(method: String, bodyData: Data) throws -> URLRequest {
        let url = try makeURL(method: method)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.rune, forHTTPHeaderField: "rune")
        return request
    }

    private func makeURL(method: String) throws -> URL {
        guard credentials.baseURL != nil else {
            throw CoreLightningWalletError.invalidBaseURL
        }

        var components = URLComponents()
        components.scheme = credentials.scheme
        components.host = credentials.host
        components.port = credentials.port
        components.path = "/v1/\(method)"

        guard let url = components.url else {
            throw CoreLightningWalletError.invalidBaseURL
        }

        return url
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

    private func serverErrorMessage(from data: Data) -> String {
        if let decoded = try? decoder.decode(CoreLightningServerErrorResponse.self, from: data) {
            return decoded.message ?? decoded.error ?? decoded.description ?? "Unknown Core Lightning error"
        }

        return String(data: data, encoding: .utf8) ?? "Unknown Core Lightning error"
    }
}

extension CoreLightningRestClient: URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let leafCertificate = leafCertificate(from: serverTrust) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let leafCertificateData = SecCertificateCopyData(leafCertificate) as Data

        if let pinnedCertificateData = credentials.tlsCertificateData,
           !serverTrustContainsPinnedCertificate(serverTrust, pinnedCertificateData: pinnedCertificateData) {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        observedServerCertificateData = leafCertificateData

        guard let credential = makePinnedCredential(
            serverTrust: serverTrust,
            certificate: leafCertificate
        ) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, credential)
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

    private func leafCertificate(from serverTrust: SecTrust) -> SecCertificate? {
        (SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate])?.first
    }

    private func makePinnedCredential(
        serverTrust: SecTrust,
        certificate: SecCertificate
    ) -> URLCredential? {
        let certificates = [certificate] as CFArray
        guard SecTrustSetAnchorCertificates(serverTrust, certificates) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(serverTrust, true) == errSecSuccess else {
            return nil
        }

        return URLCredential(trust: serverTrust)
    }
}

private struct EmptyParams: Encodable {}

private struct InvoiceParams: Encodable {
    let amountMsat: String
    let label: String
    let description: String
    let expiry: Int64

    enum CodingKeys: String, CodingKey {
        case amountMsat = "amount_msat"
        case label
        case description
        case expiry
    }
}

private struct DecodeParams: Encodable {
    let string: String
}

private struct PayParams: Encodable {
    let bolt11: String
    let amountMsat: String?
    let retryFor: Int

    enum CodingKeys: String, CodingKey {
        case bolt11
        case amountMsat = "amount_msat"
        case retryFor = "retry_for"
    }
}

private struct CoreLightningServerErrorResponse: Decodable {
    let code: Int?
    let message: String?
    let error: String?
    let description: String?
}
