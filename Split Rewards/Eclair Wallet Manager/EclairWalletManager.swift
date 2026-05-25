//
//  EclairWalletManager.swift
//  Split Rewards
//
//  Created by TeeVee on 5/19/26.
//

import Combine
import Darwin
import Foundation
import Network

@MainActor
final class EclairWalletManager: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case ready
        case error(String)
    }

    struct BalanceSummary: Equatable {
        let channelBalanceSats: Int64
        let onChainBalanceSats: Int64

        var spendableSats: Int64 {
            max(channelBalanceSats, 0)
        }
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var connectedNode: EclairNodeCredentials?
    @Published private(set) var balanceSummary: BalanceSummary?
    @Published var lastErrorMessage: String?

    private let credentialStore: EclairCredentialStore
    private var client: EclairRestClient?

    init(credentialStore: EclairCredentialStore = .shared) {
        self.credentialStore = credentialStore
    }

    var isConnected: Bool {
        if case .ready = state {
            return true
        }

        return false
    }

    var displayName: String {
        connectedNode?.displayName ?? "Eclair Node"
    }

    func connect(
        scheme: String,
        host: String,
        port: String,
        apiPassword: String,
        label: String? = nil
    ) async throws -> EclairNodeCredentials {
        let parsed = try EclairConnectParser.parse(
            scheme: scheme,
            host: host,
            port: port,
            apiPassword: apiPassword,
            label: label
        )
        return try await connect(parsedCredentials: parsed)
    }

    func connect(connectionString: String, label: String? = nil) async throws -> EclairNodeCredentials {
        let parsed = try EclairConnectParser.parse(connectionString: connectionString, label: label)
        return try await connect(parsedCredentials: parsed)
    }

    func restoreActiveNode() async throws {
        lastErrorMessage = nil

        guard let storedNode = credentialStore.activeNode() else {
            state = .disconnected
            connectedNode = nil
            client = nil
            balanceSummary = nil
            throw EclairWalletError.noStoredNode
        }

        do {
            try await validateConnectionCandidate(storedNode)
        } catch {
            client = nil
            balanceSummary = nil
            connectedNode = storedNode
            let message = connectionErrorMessage(for: error, host: storedNode.host)
            lastErrorMessage = message
            state = .error(message)
            throw error
        }

        state = .connecting
        let restClient = EclairRestClient(credentials: storedNode)

        do {
            let info = try await restClient.getInfo()
            let verifiedNode = storedNode.verified(with: info)
            let savedNode = credentialStore.saveNode(verifiedNode, makeActive: false)

            client = EclairRestClient(credentials: savedNode)
            connectedNode = savedNode
            state = .ready

            _ = try? await refreshBalance()
        } catch {
            let message = connectionErrorMessage(for: error, host: storedNode.host)
            lastErrorMessage = message
            connectedNode = storedNode
            client = restClient
            state = .error(message)
            throw error
        }
    }

    func disconnectFromActiveNode() {
        client = nil
        connectedNode = nil
        balanceSummary = nil
        lastErrorMessage = nil
        state = .disconnected
    }

    func forgetNode(id: String) {
        if connectedNode?.id == id {
            disconnectFromActiveNode()
        }

        credentialStore.deleteNode(id: id)

        Task {
            await EclairTransactionStore.clear(nodeId: id)
            await EclairTransactionMetadataStore.clear(nodeId: id)
        }
    }

    func storedNodes() -> [EclairNodeCredentials] {
        credentialStore.loadNodes()
    }

    func setActiveStoredNode(id: String) async throws {
        credentialStore.setActiveNode(id: id)
        try await restoreActiveNode()
    }

    func renameNode(id: String, label: String) {
        credentialStore.renameNode(id: id, label: label)
        if connectedNode?.id == id,
           let updated = credentialStore.loadNodes().first(where: { $0.id == id }) {
            connectedNode = updated
        }
    }

    @discardableResult
    func refreshNodeInfo() async throws -> EclairGetInfoResponse {
        let restClient = try requireClient()
        let info = try await restClient.getInfo()

        if let current = connectedNode {
            let verified = current.verified(with: info)
            let saved = credentialStore.saveNode(verified, makeActive: false)
            connectedNode = saved
        }

        state = .ready
        return info
    }

    @discardableResult
    func refreshBalance() async throws -> BalanceSummary {
        let restClient = try requireClient()
        async let channelsTask = restClient.channelBalances()
        async let onChainTask = restClient.onChainBalance()
        let (channels, onChain) = try await (channelsTask, onChainTask)
        let summary = BalanceSummary(
            channelBalanceSats: channels.map { $0.canSend?.satsRoundedDown ?? 0 }.reduce(0, +),
            onChainBalanceSats: max(onChain.confirmed ?? 0, 0)
        )

        balanceSummary = summary
        state = .ready
        return summary
    }

    func decodeInvoice(_ bolt11: String) async throws -> EclairParseInvoiceResponse {
        try await requireClient().parseInvoice(bolt11)
    }

    func payInvoice(
        _ bolt11: String,
        amountSats: Int64? = nil
    ) async throws -> EclairPayResponse {
        let decoded = try? await decodeInvoice(bolt11)
        let response = try await requireClient().payInvoice(
            bolt11,
            amountSats: amountSats
        )
        _ = try? await refreshBalance()

        if let nodeId = activeNodeIdentifier() {
            await mergeSentPaymentRow(response: response, decoded: decoded, nodeId: nodeId)
        }

        return response
    }

    func getSentInfo(paymentHash: String) async throws -> [EclairSentPayment] {
        try await requireClient().getSentInfo(paymentHash: paymentHash)
    }

    func createInvoice(
        amountSats: Int64?,
        memo: String?,
        expirySecs: Int64 = 3600
    ) async throws -> EclairInvoiceResponse {
        try await requireClient().createInvoice(
            amountSats: amountSats,
            memo: memo,
            expirySecs: expirySecs
        )
    }

    func walletScopeIdentifier() -> String? {
        guard let nodeId = connectedNode?.id ?? credentialStore.activeNode()?.id else {
            return nil
        }

        return "eclair:\(nodeId)"
    }

    func activeNodeIdentifier() -> String? {
        connectedNode?.id ?? credentialStore.activeNode()?.id
    }

    func fetchTransactionRows(maxCount: Int = 100) async throws -> [WalletManager.TransactionRow] {
        let restClient = try requireClient()
        let nodeId = connectedNode?.id ?? credentialStore.activeNode()?.id ?? "active-eclair-node"
        return try await fetchTransactionRows(restClient: restClient, nodeId: nodeId, maxCount: maxCount)
    }

    func fetchTransactionRows(
        for node: EclairNodeCredentials,
        maxCount: Int = 100
    ) async throws -> [WalletManager.TransactionRow] {
        let restClient = EclairRestClient(credentials: node)
        return try await fetchTransactionRows(restClient: restClient, nodeId: node.id, maxCount: maxCount)
    }

    func cachedTransactionRows() async -> [WalletManager.TransactionRow] {
        guard let nodeId = connectedNode?.id ?? credentialStore.activeNode()?.id else {
            return []
        }

        return await EclairTransactionStore.rows(forNodeId: nodeId)
    }

    private func connect(parsedCredentials: EclairNodeCredentials) async throws -> EclairNodeCredentials {
        lastErrorMessage = nil
        state = .connecting

        do {
            let (workingCredentials, info) = try await firstWorkingClient(
                for: parsedCredentials.restConnectionCandidates
            )
            let verifiedCredentials = workingCredentials.verified(with: info)
            let savedCredentials = credentialStore.saveNode(verifiedCredentials, makeActive: true)

            client = EclairRestClient(credentials: savedCredentials)
            connectedNode = savedCredentials
            state = .ready

            _ = try? await refreshBalance()
            return savedCredentials
        } catch {
            let message = connectionErrorMessage(for: error, host: parsedCredentials.host)
            lastErrorMessage = message
            state = .error(message)
            throw error
        }
    }

    private func requireClient() throws -> EclairRestClient {
        guard let client else {
            throw EclairWalletError.nodeNotConnected
        }

        return client
    }

    private func firstWorkingClient(
        for candidates: [EclairNodeCredentials]
    ) async throws -> (EclairNodeCredentials, EclairGetInfoResponse) {
        var lastError: Error?

        for candidate in candidates {
            do {
                try await validateConnectionCandidate(candidate)
                let restClient = EclairRestClient(
                    credentials: candidate,
                    requestTimeout: candidate.usesTor ? 20 : 8,
                    resourceTimeout: candidate.usesTor ? 75 : 15,
                    waitsForConnectivity: candidate.usesTor
                )
                let info = try await restClient.getInfo()
                return (candidate, info)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? EclairWalletError.invalidResponse
    }

    private func fetchTransactionRows(
        restClient: EclairRestClient,
        nodeId: String,
        maxCount: Int
    ) async throws -> [WalletManager.TransactionRow] {
        async let receivedResponse = restClient.listReceivedPayments(limit: maxCount)
        let cachedSentRows = await EclairTransactionStore.rows(forNodeId: nodeId)
            .filter { $0.direction.caseInsensitiveCompare("sent") == .orderedSame }

        var rows: [WalletManager.TransactionRow] = cachedSentRows
        rows.append(contentsOf: try await receivedResponse.compactMap(eclairReceivedPaymentRow))
        rows.sort { $0.transactionDate > $1.transactionDate }
        rows = Array(rows.prefix(maxCount))

        await EclairTransactionStore.merge(rows, forNodeId: nodeId)
        return rows
    }

    private func validateConnectionCandidate(_ candidate: EclairNodeCredentials) async throws {
        try EclairHostAccessPolicy.validate(host: candidate.host)

        if candidate.usesTor {
            try await RemoteNodeTorManager.shared.bootstrapIfNeeded()
            return
        }

        let resolvedAddresses = try await EclairHostResolver.resolve(host: candidate.host)
        try EclairHostAccessPolicy.validateResolvedAddresses(resolvedAddresses)
    }

    private func connectionErrorMessage(for error: Error, host: String?) -> String {
        let normalizedHost = host?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                if normalizedHost?.hasSuffix(".onion") == true {
                    return "Split could not resolve this Tor Eclair address. Make sure the .onion address is correct and Tor can connect."
                }

                if normalizedHost?.hasSuffix(".local") == true {
                    return "Split could not resolve this .local hostname. Make sure your phone is on the same local network as the node and that Split has Local Network access in Settings."
                }

                return "Split could not resolve this Eclair host. Make sure the node is reachable from this phone over your private network or Tailscale."
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
                if normalizedHost?.hasSuffix(".onion") == true {
                    return "Split could not reach this Eclair node over Tor. Make sure the node's Tor service is online and the connection details are correct."
                }

                return "Split could not reach this Eclair node. Make sure the node is online and reachable from this phone over your private network or Tailscale."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private func mergeSentPaymentRow(
        response: EclairPayResponse,
        decoded: EclairParseInvoiceResponse?,
        nodeId: String
    ) async {
        guard let row = eclairSentPaymentRow(response: response, decoded: decoded) else { return }
        await EclairTransactionStore.merge([row], forNodeId: nodeId)
    }

    private func eclairSentPaymentRow(
        response: EclairPayResponse,
        decoded: EclairParseInvoiceResponse?
    ) -> WalletManager.TransactionRow? {
        let amountSats = max(
            response.recipientAmount?.satsRoundedDown ?? response.amount?.satsRoundedDown ?? decoded?.amountSats ?? 0,
            0
        )
        let feeSats = max(response.feesPaid?.satsRoundedUp ?? response.status?.feesPaid?.satsRoundedUp ?? 0, 0)
        let paymentHash = response.paymentHash ?? decoded?.paymentHash
        let paymentPreimage = response.paymentPreimage ?? response.status?.paymentPreimage
        let transactionDate = date(fromUnixSeconds: response.status?.completedAt?.unix)

        guard amountSats > 0 || paymentHash != nil else { return nil }

        return WalletManager.TransactionRow(
            id: "eclair-payment-\(paymentHash ?? response.paymentId ?? UUID().uuidString)",
            transactionDate: transactionDate,
            direction: "sent",
            btcAmount: satsToBTCString(amountSats),
            feeBtcAmount: satsToBTCString(feeSats),
            network: "lightning",
            status: "Completed",
            dateString: dateString(from: transactionDate),
            note: decoded?.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            userLog: nil,
            amountSats: amountSats,
            feeSats: feeSats,
            method: "Eclair",
            destinationPubkey: decoded?.nodeId,
            invoice: decoded?.serialized,
            lnAddress: nil,
            lnurlDomain: nil,
            lnurlComment: nil,
            senderComment: nil,
            paymentHash: paymentHash,
            preimage: paymentPreimage,
            expiryDateString: nil,
            txReferenceLabel: "Payment Hash",
            txReference: paymentHash,
            hasConversion: false
        )
    }

    private func eclairReceivedPaymentRow(_ payment: EclairReceivedPayment) -> WalletManager.TransactionRow? {
        let invoice = payment.invoice
        let amountSats = max(
            payment.receivedAmount?.satsRoundedDown ?? payment.amount?.satsRoundedDown ?? invoice?.amountSats ?? 0,
            0
        )
        guard amountSats > 0 else { return nil }

        let transactionDate = date(fromUnixSeconds: payment.status?.completedAt?.unix ?? payment.receivedAt?.unix ?? payment.createdAt?.unix ?? invoice?.timestamp)
        let paymentHash = payment.paymentHash ?? invoice?.paymentHash

        return WalletManager.TransactionRow(
            id: "eclair-invoice-\(paymentHash ?? invoice?.serialized ?? UUID().uuidString)",
            transactionDate: transactionDate,
            direction: "received",
            btcAmount: satsToBTCString(amountSats),
            feeBtcAmount: satsToBTCString(0),
            network: "lightning",
            status: "Completed",
            dateString: dateString(from: transactionDate),
            note: invoice?.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            userLog: nil,
            amountSats: amountSats,
            feeSats: 0,
            method: "Eclair",
            destinationPubkey: nil,
            invoice: invoice?.serialized,
            lnAddress: nil,
            lnurlDomain: nil,
            lnurlComment: nil,
            senderComment: nil,
            paymentHash: paymentHash,
            preimage: payment.status?.paymentPreimage,
            expiryDateString: nil,
            txReferenceLabel: "Payment Hash",
            txReference: paymentHash,
            hasConversion: false
        )
    }

    private func date(fromUnixSeconds seconds: Int64?) -> Date {
        guard let seconds, seconds > 0 else {
            return Date()
        }

        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private func dateString(from date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    private func satsToBTCString(_ sats: Int64) -> String {
        String(format: "%.8f", Double(max(sats, 0)) / 100_000_000.0)
    }
}

private enum EclairHostResolver {
    static func resolve(host: String) async throws -> [EclairResolvedAddress] {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        if let ipv4Address = IPv4Address(normalizedHost) {
            return [.ipv4(ipv4Address)]
        }

        if let ipv6Address = IPv6Address(normalizedHost) {
            return [.ipv6(ipv6Address)]
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[EclairResolvedAddress], Error>) in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo(
                    ai_flags: AI_ADDRCONFIG,
                    ai_family: AF_UNSPEC,
                    ai_socktype: SOCK_STREAM,
                    ai_protocol: IPPROTO_TCP,
                    ai_addrlen: 0,
                    ai_canonname: nil,
                    ai_addr: nil,
                    ai_next: nil
                )
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(normalizedHost, nil, &hints, &result)

                guard status == 0, let result else {
                    continuation.resume(throwing: URLError(.cannotFindHost))
                    return
                }

                defer { freeaddrinfo(result) }

                var addresses = Set<EclairResolvedAddress>()
                var pointer: UnsafeMutablePointer<addrinfo>? = result

                while let current = pointer {
                    let currentInfo = current.pointee
                    if let numericHost = numericHostString(
                        from: currentInfo.ai_addr,
                        length: currentInfo.ai_addrlen
                    ) {
                        let normalizedAddress = stripScopeIdentifier(from: numericHost)

                        if let ipv4Address = IPv4Address(normalizedAddress) {
                            addresses.insert(.ipv4(ipv4Address))
                        } else if let ipv6Address = IPv6Address(normalizedAddress) {
                            addresses.insert(.ipv6(ipv6Address))
                        }
                    }

                    pointer = currentInfo.ai_next
                }

                continuation.resume(returning: Array(addresses))
            }
        }
    }

    private static func numericHostString(
        from address: UnsafeMutablePointer<sockaddr>?,
        length: socklen_t
    ) -> String? {
        guard let address else { return nil }

        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            address,
            length,
            &hostBuffer,
            socklen_t(hostBuffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )

        guard status == 0 else { return nil }
        return String(cString: hostBuffer)
    }

    private static func stripScopeIdentifier(from host: String) -> String {
        guard let percentIndex = host.firstIndex(of: "%") else {
            return host
        }

        return String(host[..<percentIndex])
    }
}
