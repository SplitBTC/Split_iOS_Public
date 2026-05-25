//
//  NWCCommandClient.swift
//  Split Rewards
//
//  Created by TeeVee on 5/1/26.
//

import Foundation

final class NWCCommandClient {
    private let wallet: NWCWalletCredentials
    private let timeoutNanoseconds: UInt64
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(wallet: NWCWalletCredentials, timeoutNanoseconds: UInt64 = 15_000_000_000) {
        self.wallet = wallet
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func getBalance() async throws -> NWCGetBalanceResult {
        let response: NWCResponseEnvelope<NWCGetBalanceResult> = try await send(
            method: "get_balance",
            params: EmptyParams()
        )
        return try response.resultOrThrow()
    }

    func makeInvoice(amountSats: Int64?, description: String?, expirySecs: Int64 = 3600) async throws -> NWCTransactionResult {
        let response: NWCResponseEnvelope<NWCTransactionResult> = try await send(
            method: "make_invoice",
            params: NWCMakeInvoiceParams(
                amount: amountSats.map { $0 * 1_000 },
                description: description,
                expiry: expirySecs
            )
        )
        return try response.resultOrThrow()
    }

    func payInvoice(_ invoice: String, amountSats: Int64? = nil) async throws -> NWCPayInvoiceResult {
        let response: NWCResponseEnvelope<NWCPayInvoiceResult> = try await send(
            method: "pay_invoice",
            params: NWCPayInvoiceParams(
                invoice: invoice,
                amount: amountSats.map { $0 * 1_000 }
            )
        )
        return try response.resultOrThrow()
    }

    func lookupInvoice(invoice: String) async throws -> NWCTransactionResult {
        let response: NWCResponseEnvelope<NWCTransactionResult> = try await send(
            method: "lookup_invoice",
            params: NWCLookupInvoiceParams(invoice: invoice, paymentHash: nil)
        )
        return try response.resultOrThrow()
    }

    func lookupInvoice(paymentHash: String) async throws -> NWCTransactionResult {
        let response: NWCResponseEnvelope<NWCTransactionResult> = try await send(
            method: "lookup_invoice",
            params: NWCLookupInvoiceParams(invoice: nil, paymentHash: paymentHash)
        )
        return try response.resultOrThrow()
    }

    func listTransactions(limit: Int = 50) async throws -> [NWCTransactionResult] {
        let response: NWCResponseEnvelope<NWCListTransactionsResult> = try await send(
            method: "list_transactions",
            params: NWCListTransactionsParams(limit: limit)
        )
        return try response.resultOrThrow().transactions
    }

    private func send<Params: Encodable, Result: Decodable>(
        method: String,
        params: Params
    ) async throws -> NWCResponseEnvelope<Result> {
        try requireSupported(method)

        let request = NWCRequestEnvelope(method: method, params: params)
        let requestData = try encoder.encode(request)
        guard let requestJSONString = String(data: requestData, encoding: .utf8) else {
            throw NWCWalletError.invalidRelayResponse
        }

        let encryptionMode = wallet.capabilities?.preferredEncryptionMode ?? .nip04
        let encryptedContent: String
        switch encryptionMode {
        case .nip44V2:
            encryptedContent = try NWCNostrCryptography.nip44Encrypt(
                plaintext: requestJSONString,
                senderPrivateKeyHex: wallet.secret,
                recipientPublicKeyHex: wallet.walletPubkey
            )
        case .nip04:
            encryptedContent = try NWCNostrCryptography.nip04Encrypt(
                plaintext: requestJSONString,
                senderPrivateKeyHex: wallet.secret,
                recipientPublicKeyHex: wallet.walletPubkey
            )
        }

        let clientPubkey = try NWCNostrCryptography.publicKeyHex(privateKeyHex: wallet.secret)
        let createdAt = Int(Date().timeIntervalSince1970)
        var tags = [
            ["p", wallet.walletPubkey],
            ["expiration", String(createdAt + 60)],
        ]
        if encryptionMode == .nip44V2 {
            tags.append(["encryption", NWCEncryptionMode.nip44V2.rawValue])
        }

        let event = try NWCNostrCryptography.signEvent(
            privateKeyHex: wallet.secret,
            createdAt: createdAt,
            kind: 23194,
            tags: tags,
            content: encryptedContent
        )

        return try await sendEventAndAwaitResponse(
            event,
            clientPubkey: clientPubkey,
            responseType: NWCResponseEnvelope<Result>.self
        )
    }

    private func sendEventAndAwaitResponse<Response: Decodable>(
        _ event: NWCNostrEvent,
        clientPubkey: String,
        responseType: Response.Type
    ) async throws -> Response {
        let relayURLs = wallet.relayURLs.compactMap(URL.init(string:))
        guard !relayURLs.isEmpty else {
            throw NWCWalletError.invalidRelay
        }

        return try await withThrowingTaskGroup(of: Result<Response, Error>.self) { group in
            for relayURL in relayURLs {
                group.addTask {
                    do {
                        let response = try await self.sendEventAndAwaitResponseOnRelay(
                            relayURL: relayURL,
                            event: event,
                            clientPubkey: clientPubkey,
                            responseType: responseType
                        )
                        return .success(response)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: self.timeoutNanoseconds)
                    return .failure(NWCWalletError.relayTimedOut)
                } catch {
                    return .failure(error)
                }
            }

            var lastError: Error?
            var remainingRelayCount = relayURLs.count

            while let result = try await group.next() {
                switch result {
                case .success(let response):
                    group.cancelAll()
                    return response
                case .failure(let error):
                    if error is CancellationError {
                        continue
                    }

                    lastError = error
                    if (error as? NWCWalletError) == .relayTimedOut {
                        group.cancelAll()
                        throw error
                    }

                    remainingRelayCount -= 1
                    if remainingRelayCount <= 0 {
                        group.cancelAll()
                        throw lastError ?? NWCWalletError.relayConnectionFailed
                    }
                }
            }

            throw lastError ?? NWCWalletError.relayConnectionFailed
        }
    }

    private func sendEventAndAwaitResponseOnRelay<Response: Decodable>(
        relayURL: URL,
        event: NWCNostrEvent,
        clientPubkey: String,
        responseType: Response.Type
    ) async throws -> Response {
        let session = try await makeSession(relayURL: relayURL)
        let socket = session.webSocketTask(with: relayURL)
        let subscriptionId = "split-nwc-\(UUID().uuidString)"

        socket.resume()

        defer {
            let closePayload = try? JSONSerialization.data(withJSONObject: ["CLOSE", subscriptionId])
            if let closePayload,
               let closeMessage = String(data: closePayload, encoding: .utf8) {
                socket.send(.string(closeMessage)) { _ in }
            }
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        }

        let filter: [String: Any] = [
            "kinds": [23195],
            "authors": [wallet.walletPubkey],
            "#e": [event.id],
            "#p": [clientPubkey],
            "limit": 1,
        ]
        let request: [Any] = ["REQ", subscriptionId, filter]
        let requestData = try JSONSerialization.data(withJSONObject: request)
        guard let requestString = String(data: requestData, encoding: .utf8) else {
            throw NWCWalletError.invalidRelayResponse
        }

        try await socket.send(.string(requestString))

        let eventObject = try eventJSONObject(event)
        let eventMessageData = try JSONSerialization.data(withJSONObject: ["EVENT", eventObject])
        guard let eventMessage = String(data: eventMessageData, encoding: .utf8) else {
            throw NWCWalletError.invalidRelayResponse
        }
        try await socket.send(.string(eventMessage))

        return try await withThrowingTaskGroup(of: Response.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    if let response = try self.response(
                        from: message,
                        subscriptionId: subscriptionId,
                        requestEventId: event.id,
                        responseType: responseType
                    ) {
                        return response
                    }
                }

                throw CancellationError()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: self.timeoutNanoseconds)
                throw NWCWalletError.relayTimedOut
            }

            guard let response = try await group.next() else {
                throw NWCWalletError.invalidRelayResponse
            }

            group.cancelAll()
            return response
        }
    }

    private func makeSession(relayURL: URL) async throws -> URLSession {
        let transport = RemoteNodeTransport.preferred(forURL: relayURL)
        let configuration = try await RemoteNodeURLSessionFactory.configuration(
            transport: transport,
            requestTimeout: 20,
            resourceTimeout: 45,
            waitsForConnectivity: transport == .tor
        )
        return URLSession(configuration: configuration)
    }

    private func response<Response: Decodable>(
        from message: URLSessionWebSocketTask.Message,
        subscriptionId: String,
        requestEventId: String,
        responseType: Response.Type
    ) throws -> Response? {
        let data: Data
        switch message {
        case .string(let string):
            guard let stringData = string.data(using: .utf8) else {
                throw NWCWalletError.invalidRelayResponse
            }
            data = stringData
        case .data(let messageData):
            data = messageData
        @unknown default:
            return nil
        }

        guard let raw = try JSONSerialization.jsonObject(with: data) as? [Any],
              let type = raw.first as? String else {
            throw NWCWalletError.invalidRelayResponse
        }

        guard type == "EVENT" else {
            return nil
        }

        guard raw.count >= 3,
              (raw[1] as? String) == subscriptionId,
              JSONSerialization.isValidJSONObject(raw[2]) else {
            throw NWCWalletError.invalidRelayResponse
        }

        let eventData = try JSONSerialization.data(withJSONObject: raw[2])
        let event = try decoder.decode(NWCNostrEvent.self, from: eventData)
        guard event.kind == 23195,
              event.pubkey.lowercased() == wallet.walletPubkey.lowercased(),
              event.tags.contains(where: { $0.count > 1 && $0[0] == "e" && $0[1] == requestEventId }) else {
            return nil
        }

        guard try NWCNostrCryptography.verifyEvent(event) else {
            throw NWCNostrCryptographyError.invalidEvent
        }

        let plaintext: String
        switch wallet.capabilities?.preferredEncryptionMode ?? .nip04 {
        case .nip44V2:
            plaintext = try NWCNostrCryptography.nip44Decrypt(
                payload: event.content,
                recipientPrivateKeyHex: wallet.secret,
                senderPublicKeyHex: event.pubkey
            )
        case .nip04:
            plaintext = try NWCNostrCryptography.nip04Decrypt(
                payload: event.content,
                recipientPrivateKeyHex: wallet.secret,
                senderPublicKeyHex: event.pubkey
            )
        }
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw NWCWalletError.invalidRelayResponse
        }

        return try decoder.decode(responseType, from: plaintextData)
    }

    private func requireSupported(_ method: String) throws {
        guard wallet.capabilities?.supports(method) != false else {
            throw NWCWalletError.unsupportedMethod(method)
        }
    }

    private func eventJSONObject(_ event: NWCNostrEvent) throws -> Any {
        let data = try encoder.encode(event)
        return try JSONSerialization.jsonObject(with: data)
    }
}

private struct EmptyParams: Encodable {}

private struct NWCRequestEnvelope<Params: Encodable>: Encodable {
    let method: String
    let params: Params
}

struct NWCResponseEnvelope<Result: Decodable>: Decodable {
    let resultType: String?
    let result: Result?
    let error: NWCResponseError?

    enum CodingKeys: String, CodingKey {
        case resultType = "result_type"
        case result
        case error
    }

    func resultOrThrow() throws -> Result {
        if let error {
            throw NWCCommandError.walletError(code: error.code, message: error.message)
        }

        guard let result else {
            throw NWCWalletError.invalidRelayResponse
        }

        return result
    }
}

struct NWCResponseError: Decodable, Equatable {
    let code: String?
    let message: String?
}

enum NWCCommandError: LocalizedError, Equatable {
    case walletError(code: String?, message: String?)

    var errorDescription: String? {
        switch self {
        case .walletError(let code, let message):
            if let code, let message {
                return "\(code): \(message)"
            }

            return message ?? code ?? "The NWC wallet rejected the request."
        }
    }
}

private struct NWCMakeInvoiceParams: Encodable {
    let amount: Int64?
    let description: String?
    let expiry: Int64?
}

private struct NWCPayInvoiceParams: Encodable {
    let invoice: String
    let amount: Int64?
}

private struct NWCLookupInvoiceParams: Encodable {
    let invoice: String?
    let paymentHash: String?

    enum CodingKeys: String, CodingKey {
        case invoice
        case paymentHash = "payment_hash"
    }
}

private struct NWCListTransactionsParams: Encodable {
    let limit: Int?
}

struct NWCListTransactionsResult: Decodable, Equatable {
    let transactions: [NWCTransactionResult]
}

struct NWCGetBalanceResult: Decodable, Equatable {
    let balance: Int64

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        balance = try container.decodeFlexibleInt64(forKey: .balance)
    }

    private enum CodingKeys: String, CodingKey {
        case balance
    }

    var balanceSats: Int64 {
        balance / 1_000
    }
}

struct NWCPayInvoiceResult: Decodable, Equatable {
    let preimage: String?
    let feesPaid: Int64?

    enum CodingKeys: String, CodingKey {
        case preimage
        case feesPaid = "fees_paid"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preimage = try container.decodeIfPresent(String.self, forKey: .preimage)
        feesPaid = try container.decodeFlexibleInt64IfPresent(forKey: .feesPaid)
    }

    var feesPaidSats: Int64? {
        feesPaid.map { $0 / 1_000 }
    }
}

struct NWCTransactionResult: Decodable, Equatable {
    let type: String?
    let state: String?
    let invoice: String?
    let description: String?
    let descriptionHash: String?
    let preimage: String?
    let paymentHash: String?
    let amount: Int64?
    let feesPaid: Int64?
    let createdAt: Int?
    let expiresAt: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case state
        case invoice
        case description
        case descriptionHash = "description_hash"
        case preimage
        case paymentHash = "payment_hash"
        case amount
        case feesPaid = "fees_paid"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        invoice = try container.decodeIfPresent(String.self, forKey: .invoice)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        descriptionHash = try container.decodeIfPresent(String.self, forKey: .descriptionHash)
        preimage = try container.decodeIfPresent(String.self, forKey: .preimage)
        paymentHash = try container.decodeIfPresent(String.self, forKey: .paymentHash)
        amount = try container.decodeFlexibleInt64IfPresent(forKey: .amount)
        feesPaid = try container.decodeFlexibleInt64IfPresent(forKey: .feesPaid)
        createdAt = try container.decodeFlexibleIntIfPresent(forKey: .createdAt)
        expiresAt = try container.decodeFlexibleIntIfPresent(forKey: .expiresAt)
    }

    var amountSats: Int64? {
        amount.map { $0 / 1_000 }
    }

    var feesPaidSats: Int64? {
        feesPaid.map { $0 / 1_000 }
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt64(forKey key: Key) throws -> Int64 {
        if let int = try? decode(Int64.self, forKey: key) {
            return int
        }
        if let string = try? decode(String.self, forKey: key),
           let int = Int64(string) {
            return int
        }
        if let double = try? decode(Double.self, forKey: key) {
            return Int64(double)
        }
        return try decode(Int64.self, forKey: key)
    }

    func decodeFlexibleInt64IfPresent(forKey key: Key) throws -> Int64? {
        guard contains(key), !(try decodeNil(forKey: key)) else {
            return nil
        }
        return try decodeFlexibleInt64(forKey: key)
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        guard let int64 = try decodeFlexibleInt64IfPresent(forKey: key) else {
            return nil
        }
        return Int(int64)
    }
}
