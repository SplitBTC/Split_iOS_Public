//
//  CoreLightningWalletManager.swift
//  Split Rewards
//
//  Created by TeeVee on 5/9/26.
//

import Combine
import Darwin
import Foundation
import Network

@MainActor
final class CoreLightningWalletManager: ObservableObject {
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
    @Published private(set) var connectedNode: CoreLightningNodeCredentials?
    @Published private(set) var balanceSummary: BalanceSummary?
    @Published var lastErrorMessage: String?

    private let credentialStore: CoreLightningCredentialStore
    private var client: CoreLightningRestClient?

    init(credentialStore: CoreLightningCredentialStore = .shared) {
        self.credentialStore = credentialStore
    }

    var isConnected: Bool {
        if case .ready = state {
            return true
        }

        return false
    }

    var displayName: String {
        connectedNode?.displayName ?? "Core Lightning Node"
    }

    func connect(connectionString: String, label: String? = nil) async throws -> CoreLightningNodeCredentials {
        lastErrorMessage = nil
        state = .connecting

        do {
            let parsedCredentials = try CoreLightningConnectParser.parse(connectionString).withLabel(label)
            let (workingCredentials, info) = try await firstWorkingClient(
                for: parsedCredentials.restConnectionCandidates
            )
            let verifiedCredentials = workingCredentials.verified(with: info)
            let savedCredentials = credentialStore.saveNode(verifiedCredentials, makeActive: true)

            client = CoreLightningRestClient(credentials: savedCredentials)
            connectedNode = savedCredentials
            state = .ready

            _ = try? await refreshBalance()
            return savedCredentials
        } catch {
            let host = (try? CoreLightningConnectParser.parse(connectionString).host)
            let message = connectionErrorMessage(for: error, host: host)
            lastErrorMessage = message
            state = .error(message)
            throw error
        }
    }

    func restoreActiveNode() async throws {
        lastErrorMessage = nil

        guard let storedNode = credentialStore.activeNode() else {
            state = .disconnected
            connectedNode = nil
            client = nil
            balanceSummary = nil
            throw CoreLightningWalletError.noStoredNode
        }

        do {
            try await validateConnectionCandidate(storedNode)
        } catch {
            client = nil
            balanceSummary = nil
            connectedNode = storedNode
            let message = error.localizedDescription
            lastErrorMessage = message
            state = .error(message)
            throw error
        }

        state = .connecting
        let restClient = CoreLightningRestClient(credentials: storedNode)

        do {
            let info = try await restClient.getInfo()
            let verifiedNode = storedNode.verified(with: info)
            let savedNode = credentialStore.saveNode(verifiedNode, makeActive: false)

            client = CoreLightningRestClient(credentials: savedNode)
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
            await CoreLightningTransactionStore.clear(nodeId: id)
            await CoreLightningTransactionMetadataStore.clear(nodeId: id)
        }
    }

    func storedNodes() -> [CoreLightningNodeCredentials] {
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
    func refreshNodeInfo() async throws -> CoreLightningGetInfoResponse {
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
        let funds = try await requireClient().listFunds()
        let summary = BalanceSummary(
            channelBalanceSats: funds.spendableChannelBalanceSats,
            onChainBalanceSats: funds.onChainBalanceSats
        )

        balanceSummary = summary
        state = .ready
        return summary
    }

    func decodeInvoice(_ bolt11: String) async throws -> CoreLightningDecodeResponse {
        try await requireClient().decodeInvoice(bolt11)
    }

    func payInvoice(
        _ bolt11: String,
        amountSats: Int64? = nil
    ) async throws -> CoreLightningPayResponse {
        let response = try await requireClient().payInvoice(
            bolt11,
            amountSats: amountSats
        )
        _ = try? await refreshBalance()
        return response
    }

    func createInvoice(
        amountSats: Int64?,
        memo: String?,
        expirySecs: Int64 = 3600
    ) async throws -> CoreLightningInvoiceResponse {
        try await requireClient().createInvoice(
            amountSats: amountSats,
            memo: memo,
            expirySecs: expirySecs
        )
    }

    func listPays(limit: Int = 50) async throws -> [CoreLightningPay] {
        try await requireClient().listPays(limit: limit).pays
    }

    func listInvoices(limit: Int = 50) async throws -> [CoreLightningInvoice] {
        try await requireClient().listInvoices(limit: limit).invoices
    }

    func walletScopeIdentifier() -> String? {
        guard let nodeId = connectedNode?.id ?? credentialStore.activeNode()?.id else {
            return nil
        }

        return "core-lightning:\(nodeId)"
    }

    func activeNodeIdentifier() -> String? {
        connectedNode?.id ?? credentialStore.activeNode()?.id
    }

    func fetchTransactionRows(maxCount: Int = 100) async throws -> [WalletManager.TransactionRow] {
        let restClient = try requireClient()
        let nodeId = connectedNode?.id ?? credentialStore.activeNode()?.id ?? "active-core-lightning-node"
        return try await fetchTransactionRows(restClient: restClient, nodeId: nodeId, maxCount: maxCount)
    }

    func fetchTransactionRows(
        for node: CoreLightningNodeCredentials,
        maxCount: Int = 100
    ) async throws -> [WalletManager.TransactionRow] {
        let restClient = CoreLightningRestClient(credentials: node)
        return try await fetchTransactionRows(restClient: restClient, nodeId: node.id, maxCount: maxCount)
    }

    func cachedTransactionRows() async -> [WalletManager.TransactionRow] {
        guard let nodeId = connectedNode?.id ?? credentialStore.activeNode()?.id else {
            return []
        }

        return await CoreLightningTransactionStore.rows(forNodeId: nodeId)
    }

    private func requireClient() throws -> CoreLightningRestClient {
        guard let client else {
            throw CoreLightningWalletError.nodeNotConnected
        }

        return client
    }

    private func firstWorkingClient(
        for candidates: [CoreLightningNodeCredentials]
    ) async throws -> (CoreLightningNodeCredentials, CoreLightningGetInfoResponse) {
        var lastError: Error?

        for candidate in candidates {
            do {
                try await validateConnectionCandidate(candidate)
                let restClient = CoreLightningRestClient(
                    credentials: candidate,
                    requestTimeout: candidate.usesTor ? 20 : 8,
                    resourceTimeout: candidate.usesTor ? 75 : 15,
                    waitsForConnectivity: candidate.usesTor
                )
                let info = try await restClient.getInfo()
                let verifiedCandidate = candidate.withTLSCertificateDERBase64(
                    restClient.observedServerCertificateDERBase64
                )
                return (verifiedCandidate, info)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? CoreLightningWalletError.invalidResponse
    }

    private func fetchTransactionRows(
        restClient: CoreLightningRestClient,
        nodeId: String,
        maxCount: Int
    ) async throws -> [WalletManager.TransactionRow] {
        async let paysResponse = restClient.listPays(limit: maxCount)
        async let invoicesResponse = restClient.listInvoices(limit: maxCount)

        let (pays, invoices) = try await (
            paysResponse.pays,
            invoicesResponse.invoices
        )

        var rows: [WalletManager.TransactionRow] = []
        rows.append(contentsOf: pays.compactMap(coreLightningPaymentRow))
        rows.append(contentsOf: invoices.compactMap(coreLightningInvoiceRow))
        rows.sort { $0.transactionDate > $1.transactionDate }

        await CoreLightningTransactionStore.merge(rows, forNodeId: nodeId)
        return rows
    }

    private func validateConnectionCandidate(_ candidate: CoreLightningNodeCredentials) async throws {
        try CoreLightningHostAccessPolicy.validate(host: candidate.host)

        if candidate.usesTor {
            try await RemoteNodeTorManager.shared.bootstrapIfNeeded()
            return
        }

        let resolvedAddresses = try await CoreLightningHostResolver.resolve(host: candidate.host)
        try CoreLightningHostAccessPolicy.validateResolvedAddresses(resolvedAddresses)
    }

    private func connectionErrorMessage(for error: Error, host: String?) -> String {
        let normalizedHost = host?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                if normalizedHost?.hasSuffix(".onion") == true {
                    return "Split could not resolve this Tor Core Lightning address. Make sure the .onion address is correct and Tor can connect."
                }

                if normalizedHost?.hasSuffix(".local") == true {
                    return "Split could not resolve this .local hostname. Make sure your phone is on the same local network as the node and that Split has Local Network access in Settings."
                }

                return "Split could not resolve this Core Lightning host. Make sure the node is reachable from this phone over your private network or Tailscale."
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
                if normalizedHost?.hasSuffix(".onion") == true {
                    return "Split could not reach this Core Lightning node over Tor. Make sure the node's Tor service is online and the connection details are correct."
                }

                return "Split could not reach this Core Lightning node. Make sure the node is online and reachable from this phone over your private network or Tailscale."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private func coreLightningPaymentRow(_ payment: CoreLightningPay) -> WalletManager.TransactionRow? {
        let amountSats = max(payment.amountMsat?.satsRoundedDown ?? 0, 0)
        let feeSats = max((payment.amountSentMsat?.satsRoundedUp ?? amountSats) - amountSats, 0)
        let transactionDate = date(fromUnixSeconds: payment.completedAt?.value ?? payment.createdAt?.value)
        let status = paymentStatus(payment.status)

        return WalletManager.TransactionRow(
            id: "core-lightning-payment-\(payment.id)",
            transactionDate: transactionDate,
            direction: "sent",
            btcAmount: satsToBTCString(amountSats),
            feeBtcAmount: satsToBTCString(feeSats),
            network: "lightning",
            status: status,
            dateString: dateString(from: transactionDate),
            note: payment.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            userLog: nil,
            amountSats: amountSats,
            feeSats: feeSats,
            method: "Core Lightning",
            destinationPubkey: payment.destination,
            invoice: payment.bolt11,
            lnAddress: nil,
            lnurlDomain: nil,
            lnurlComment: nil,
            senderComment: nil,
            paymentHash: payment.paymentHash,
            preimage: payment.paymentPreimage,
            expiryDateString: nil,
            txReferenceLabel: "Payment Hash",
            txReference: payment.paymentHash,
            hasConversion: false
        )
    }

    private func coreLightningInvoiceRow(_ invoice: CoreLightningInvoice) -> WalletManager.TransactionRow? {
        guard invoice.isPaid else { return nil }

        let amountSats = max(
            invoice.amountReceivedMsat?.satsRoundedDown ?? invoice.amountMsat?.satsRoundedDown ?? 0,
            0
        )
        guard amountSats > 0 else { return nil }

        let transactionDate = date(fromUnixSeconds: invoice.paidAt?.value)

        return WalletManager.TransactionRow(
            id: "core-lightning-invoice-\(invoice.id)",
            transactionDate: transactionDate,
            direction: "received",
            btcAmount: satsToBTCString(amountSats),
            feeBtcAmount: satsToBTCString(0),
            network: "lightning",
            status: "Completed",
            dateString: dateString(from: transactionDate),
            note: invoice.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            userLog: nil,
            amountSats: amountSats,
            feeSats: 0,
            method: "Core Lightning",
            destinationPubkey: nil,
            invoice: invoice.bolt11,
            lnAddress: nil,
            lnurlDomain: nil,
            lnurlComment: nil,
            senderComment: nil,
            paymentHash: invoice.paymentHash,
            preimage: invoice.paymentPreimage,
            expiryDateString: nil,
            txReferenceLabel: "Payment Hash",
            txReference: invoice.paymentHash,
            hasConversion: false
        )
    }

    private func paymentStatus(_ status: String?) -> String {
        switch status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "complete", "completed", "paid", "succeeded", "success":
            return "Completed"
        case "pending", "in_flight":
            return "Pending"
        case "failed", "failure":
            return "Failed"
        default:
            return status ?? "Pending"
        }
    }

    private func date(fromUnixSeconds seconds: Int64?) -> Date {
        guard let seconds, seconds > 0 else {
            return Date()
        }

        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func satsToBTCString(_ sats: Int64) -> String {
        let btc = Double(max(sats, 0)) / 100_000_000.0
        return String(format: "%.8f", btc)
    }
}

private enum CoreLightningHostResolver {
    static func resolve(host: String) async throws -> [CoreLightningResolvedAddress] {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        if let ipv4Address = IPv4Address(trimmedHost) {
            return [.ipv4(ipv4Address)]
        }

        if let ipv6Address = IPv6Address(trimmedHost) {
            return [.ipv6(ipv6Address)]
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
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
                var resultPointer: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(trimmedHost, nil, &hints, &resultPointer)

                guard status == 0, let resultPointer else {
                    continuation.resume(throwing: URLError(.cannotFindHost))
                    return
                }

                defer { freeaddrinfo(resultPointer) }

                var resolvedAddresses: [CoreLightningResolvedAddress] = []
                var seenAddresses = Set<String>()
                var currentPointer: UnsafeMutablePointer<addrinfo>? = resultPointer

                while let currentInfoPointer = currentPointer {
                    let current = currentInfoPointer.pointee
                    if let numericHost = numericHostString(
                        from: current.ai_addr,
                        length: current.ai_addrlen
                    ) {
                        let normalizedHost = stripScopeIdentifier(from: numericHost)

                        if let ipv4Address = IPv4Address(normalizedHost) {
                            let key = "4:\(normalizedHost)"
                            if seenAddresses.insert(key).inserted {
                                resolvedAddresses.append(.ipv4(ipv4Address))
                            }
                        } else if let ipv6Address = IPv6Address(normalizedHost) {
                            let key = "6:\(normalizedHost)"
                            if seenAddresses.insert(key).inserted {
                                resolvedAddresses.append(.ipv6(ipv6Address))
                            }
                        }
                    }

                    currentPointer = current.ai_next
                }

                guard !resolvedAddresses.isEmpty else {
                    continuation.resume(throwing: URLError(.cannotFindHost))
                    return
                }

                continuation.resume(returning: resolvedAddresses)
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
