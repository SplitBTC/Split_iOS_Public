//
//  LNDWalletManager.swift
//  Split Rewards
//
//  Created by TeeVee on 4/21/26.
//

import Foundation
import Combine
import Darwin
import Network

@MainActor
final class LNDWalletManager: ObservableObject {
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
    @Published private(set) var connectedNode: LNDNodeCredentials?
    @Published private(set) var balanceSummary: BalanceSummary?
    @Published var lastErrorMessage: String?

    var toastManager: ToastManager?

    private let credentialStore: LNDCredentialStore
    private var client: LNDRestClient?
    private var invoiceListenerTask: Task<Void, Never>?
    private var invoiceListenerNodeId: String?
    private var invoiceEventRefreshTask: Task<Void, Never>?
    private var processedSettledInvoiceKeys = Set<String>()
    private let invoiceEventRefreshDebounceNanos: UInt64 = 300_000_000
    private let invoiceListenerInitialBackoffNanos: UInt64 = 2_000_000_000
    private let invoiceListenerMaxBackoffNanos: UInt64 = 30_000_000_000

    init(credentialStore: LNDCredentialStore = .shared) {
        self.credentialStore = credentialStore
    }

    var isConnected: Bool {
        if case .ready = state {
            return true
        }

        return false
    }

    var displayName: String {
        connectedNode?.displayName ?? "LND Node"
    }

    func connect(lndConnectString: String, label: String? = nil) async throws -> LNDNodeCredentials {
        lastErrorMessage = nil
        state = .connecting

        do {
            let parsedCredentials = try LNDConnectParser.parse(lndConnectString).withLabel(label)
            let (workingCredentials, info) = try await firstWorkingClient(
                for: parsedCredentials.restConnectionCandidates
            )
            let verifiedCredentials = workingCredentials.verified(with: info)

            let savedCredentials = credentialStore.saveNode(verifiedCredentials, makeActive: true)

            client = LNDRestClient(credentials: savedCredentials)
            connectedNode = savedCredentials
            state = .ready

            _ = try? await refreshBalance()
            await startInvoiceEventListenerIfPossible()
            return savedCredentials
        } catch {
            let host = (try? LNDConnectParser.parse(lndConnectString).host)
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
            throw LNDWalletError.noStoredNode
        }

        do {
            try await validateConnectionCandidate(storedNode)
        } catch {
            stopInvoiceEventListener()
            client = nil
            balanceSummary = nil
            connectedNode = storedNode
            let message = error.localizedDescription
            lastErrorMessage = message
            state = .error(message)
            throw error
        }

        state = .connecting
        let restClient = LNDRestClient(credentials: storedNode)

        do {
            let info = try await restClient.getInfo()
            let verifiedNode = storedNode.verified(with: info)
            let savedNode = credentialStore.saveNode(verifiedNode, makeActive: false)

            client = LNDRestClient(credentials: savedNode)
            connectedNode = savedNode
            state = .ready

            _ = try? await refreshBalance()
            await startInvoiceEventListenerIfPossible()
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
        stopInvoiceEventListener()
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

        LNDInvoiceEventCursorStore.clear(forNodeId: id)
        credentialStore.deleteNode(id: id)

        Task {
            await LNDTransactionStore.shared.clear(nodeId: id)
            await LNDTransactionMetadataStore.shared.clear(nodeId: id)
        }
    }

    func storedNodes() -> [LNDNodeCredentials] {
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
    func refreshNodeInfo() async throws -> LNDGetInfoResponse {
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

        let resolvedChannelBalance = try await restClient.channelBalance()
        let resolvedWalletBalance = try await restClient.walletBalance()

        let summary = BalanceSummary(
            channelBalanceSats: resolvedChannelBalance.spendableBalanceSats,
            onChainBalanceSats: resolvedWalletBalance.totalBalanceSats
        )

        balanceSummary = summary
        state = .ready
        return summary
    }

    func decodeInvoice(_ bolt11: String) async throws -> LNDDecodePayReqResponse {
        try await requireClient().decodePayReq(bolt11)
    }

    func payInvoice(
        _ bolt11: String,
        amountSats: Int64? = nil
    ) async throws -> LNDPayInvoiceResponse {
        try await requireClient().payInvoice(
            bolt11,
            amountSats: amountSats
        )
    }

    func estimateRouteFee(
        destinationPubkey: String,
        amountSats: Int64
    ) async throws -> Int64 {
        try await requireClient().estimateRouteFee(
            destinationPubkey: destinationPubkey,
            amountSats: amountSats
        )
    }

    func createInvoice(
        amountSats: Int64?,
        memo: String?,
        expirySecs: Int64 = 3600
    ) async throws -> LNDAddInvoiceResponse {
        try await requireClient().addInvoice(
            amountSats: amountSats,
            memo: memo,
            expirySecs: expirySecs
        )
    }

    func signNodeMessage(_ message: String) async throws -> LNDSignMessageResponse {
        try await requireClient().signMessage(message)
    }

    func listPayments(maxPayments: Int = 50) async throws -> [LNDPayment] {
        try await requireClient().listPayments(maxPayments: maxPayments).payments
    }

    func listInvoices(maxInvoices: Int = 50) async throws -> [LNDInvoice] {
        try await requireClient().listInvoices(maxInvoices: maxInvoices).invoices
    }

    func walletScopeIdentifier() -> String? {
        guard let nodeId = connectedNode?.id ?? credentialStore.activeNode()?.id else {
            return nil
        }

        return "lnd:\(nodeId)"
    }

    func activeNodeIdentifier() -> String? {
        connectedNode?.id ?? credentialStore.activeNode()?.id
    }

    func startInvoiceEventListenerIfPossible() async {
        guard isConnected, let node = connectedNode else {
            return
        }

        let nodeId = node.id
        if invoiceListenerNodeId == nodeId, invoiceListenerTask != nil {
            return
        }

        stopInvoiceEventListenerTask()

        let startSettleIndex = await invoiceListenerStartSettleIndex(forNodeId: nodeId)
        invoiceListenerNodeId = nodeId
        invoiceListenerTask = Task { [weak self] in
            await self?.runInvoiceEventListener(
                credentials: node,
                nodeId: nodeId,
                startSettleIndex: startSettleIndex
            )
        }
    }

    func stopInvoiceEventListener() {
        stopInvoiceEventListenerTask()
        invoiceEventRefreshTask?.cancel()
        invoiceEventRefreshTask = nil
    }

    func fetchTransactionRows(maxCount: Int = 100) async throws -> [WalletManager.TransactionRow] {
        let restClient = try requireClient()
        let nodeId = connectedNode?.id ?? credentialStore.activeNode()?.id ?? "active-node"
        return try await fetchTransactionRows(restClient: restClient, nodeId: nodeId, maxCount: maxCount)
    }

    func fetchTransactionRows(for node: LNDNodeCredentials, maxCount: Int = 100) async throws -> [WalletManager.TransactionRow] {
        let restClient = LNDRestClient(credentials: node)
        return try await fetchTransactionRows(restClient: restClient, nodeId: node.id, maxCount: maxCount)
    }

    private func fetchTransactionRows(
        restClient: LNDRestClient,
        nodeId: String,
        maxCount: Int
    ) async throws -> [WalletManager.TransactionRow] {
        async let paymentsResponse = restClient.listPayments(maxPayments: maxCount)
        async let invoicesResponse = restClient.listInvoices(maxInvoices: maxCount)

        let (payments, invoices) = try await (
            paymentsResponse.payments,
            invoicesResponse.invoices
        )

        var rows: [WalletManager.TransactionRow] = []
        rows.append(contentsOf: payments.compactMap(lndPaymentRow))
        rows.append(contentsOf: invoices.compactMap(lndInvoiceRow))
        rows.sort { $0.transactionDate > $1.transactionDate }

        await LNDTransactionStore.shared.merge(rows, forNodeId: nodeId)
        return rows
    }

    func cachedTransactionRows() async -> [WalletManager.TransactionRow] {
        guard let nodeId = connectedNode?.id ?? credentialStore.activeNode()?.id else {
            return []
        }

        return await LNDTransactionStore.shared.rows(forNodeId: nodeId)
    }

    private func requireClient() throws -> LNDRestClient {
        guard let client else {
            throw LNDWalletError.nodeNotConnected
        }

        return client
    }

    private func firstWorkingClient(
        for candidates: [LNDNodeCredentials]
    ) async throws -> (LNDNodeCredentials, LNDGetInfoResponse) {
        var lastError: Error?

        for candidate in candidates {
            do {
                try await validateConnectionCandidate(candidate)
                let restClient = LNDRestClient(
                    credentials: candidate,
                    requestTimeout: candidate.usesTor ? 20 : 6,
                    resourceTimeout: candidate.usesTor ? 45 : 10,
                    waitsForConnectivity: candidate.usesTor
                )
                let info = try await restClient.getInfo()
                return (candidate, info)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? LNDWalletError.invalidResponse
    }

    private func validateConnectionCandidate(_ candidate: LNDNodeCredentials) async throws {
        try LNDHostAccessPolicy.validate(host: candidate.host)

        if candidate.usesTor {
            try await RemoteNodeTorManager.shared.bootstrapIfNeeded()
            return
        }

        let resolvedAddresses = try await LNDHostResolver.resolve(host: candidate.host)
        try LNDHostAccessPolicy.validateResolvedAddresses(resolvedAddresses)
    }

    private func connectionErrorMessage(for error: Error, host: String?) -> String {
        let normalizedHost = host?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                if normalizedHost?.hasSuffix(".onion") == true {
                    return "Split could not resolve this Tor node address. Make sure the .onion address is correct and Tor can connect."
                }

                if normalizedHost?.hasSuffix(".local") == true {
                    return "Split could not resolve this .local hostname. Make sure your phone is on the same local network as the node and that Split has Local Network access in Settings."
                }

                return "Split could not resolve this node host. Make sure the node is reachable from this phone over your private network or Tailscale."
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
                if normalizedHost?.hasSuffix(".onion") == true {
                    return "Split could not reach this LND node over Tor. Make sure the node's Tor service is online and the connection details are correct."
                }

                return "Split could not reach this node. Make sure the node is online and reachable from this phone over your private network or Tailscale."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private func stopInvoiceEventListenerTask() {
        invoiceListenerTask?.cancel()
        invoiceListenerTask = nil
        invoiceListenerNodeId = nil
        processedSettledInvoiceKeys.removeAll()
    }

    private func invoiceListenerStartSettleIndex(forNodeId nodeId: String) async -> Int64? {
        if let storedSettleIndex = LNDInvoiceEventCursorStore.lastSettleIndex(forNodeId: nodeId) {
            return storedSettleIndex
        }

        do {
            let invoices = try await listInvoices(maxInvoices: 100)
            var maxSettleIndex: Int64?

            for invoice in invoices where invoice.isSettledInvoice {
                processedSettledInvoiceKeys.insert(settledInvoiceKey(invoice, nodeId: nodeId))

                if let settleIndex = invoice.settleIndex?.value {
                    maxSettleIndex = max(maxSettleIndex ?? settleIndex, settleIndex)
                }
            }

            if let maxSettleIndex {
                LNDInvoiceEventCursorStore.setLastSettleIndex(maxSettleIndex, forNodeId: nodeId)
            }

            return maxSettleIndex
        } catch {
            print("Failed to seed LND invoice listener cursor: \(error.localizedDescription)")
            return nil
        }
    }

    private func runInvoiceEventListener(
        credentials: LNDNodeCredentials,
        nodeId: String,
        startSettleIndex: Int64?
    ) async {
        var currentSettleIndex = startSettleIndex
        var reconnectDelayNanos = invoiceListenerInitialBackoffNanos

        while !Task.isCancelled {
            let listenerClient = LNDRestClient(
                credentials: credentials,
                requestTimeout: 20,
                resourceTimeout: 86_400,
                waitsForConnectivity: true
            )

            do {
                for try await invoice in listenerClient.subscribeInvoices(settleIndex: currentSettleIndex) {
                    try Task.checkCancellation()

                    if let updatedSettleIndex = handleInvoiceEvent(invoice, nodeId: nodeId) {
                        currentSettleIndex = updatedSettleIndex
                    } else if let storedSettleIndex = LNDInvoiceEventCursorStore.lastSettleIndex(forNodeId: nodeId) {
                        currentSettleIndex = storedSettleIndex
                    }

                    reconnectDelayNanos = invoiceListenerInitialBackoffNanos
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled {
                    return
                }

                print("LND invoice listener disconnected: \(error.localizedDescription)")
            }

            do {
                try await Task.sleep(nanoseconds: reconnectDelayNanos)
            } catch {
                return
            }

            reconnectDelayNanos = min(reconnectDelayNanos * 2, invoiceListenerMaxBackoffNanos)
            currentSettleIndex = LNDInvoiceEventCursorStore.lastSettleIndex(forNodeId: nodeId) ?? currentSettleIndex
        }
    }

    @discardableResult
    private func handleInvoiceEvent(_ invoice: LNDInvoice, nodeId: String) -> Int64? {
        guard invoice.isSettledInvoice else {
            return nil
        }

        let currentSettleIndex = updateStoredSettleIndex(with: invoice, nodeId: nodeId)
        let invoiceKey = settledInvoiceKey(invoice, nodeId: nodeId)

        guard processedSettledInvoiceKeys.insert(invoiceKey).inserted else {
            return currentSettleIndex
        }

        toastManager?.showPaymentSuccess(direction: .received)
        if let paymentRequest = invoice.paymentRequest?.trimmingCharacters(in: .whitespacesAndNewlines),
           !paymentRequest.isEmpty {
            NotificationCenter.default.post(
                name: .paymentRequestInvoiceSettled,
                object: nil,
                userInfo: ["invoice": paymentRequest]
            )
        }
        scheduleInvoiceEventRefresh()

        return currentSettleIndex
    }

    private func scheduleInvoiceEventRefresh() {
        if invoiceEventRefreshTask != nil { return }

        invoiceEventRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: self.invoiceEventRefreshDebounceNanos)

            defer {
                self.invoiceEventRefreshTask = nil
            }

            do {
                _ = try await self.refreshBalance()
                _ = try await self.fetchTransactionRows()
            } catch {
                self.lastErrorMessage = error.localizedDescription
                print("Failed to refresh LND wallet after invoice event: \(error.localizedDescription)")
            }

            NotificationCenter.default.post(name: .walletTransactionsDidChange, object: nil)
        }
    }

    private func updateStoredSettleIndex(with invoice: LNDInvoice, nodeId: String) -> Int64? {
        guard let settleIndex = invoice.settleIndex?.value else {
            return LNDInvoiceEventCursorStore.lastSettleIndex(forNodeId: nodeId)
        }

        let currentSettleIndex = LNDInvoiceEventCursorStore.lastSettleIndex(forNodeId: nodeId)
        let nextSettleIndex = max(currentSettleIndex ?? settleIndex, settleIndex)
        LNDInvoiceEventCursorStore.setLastSettleIndex(nextSettleIndex, forNodeId: nodeId)
        return nextSettleIndex
    }

    private func settledInvoiceKey(_ invoice: LNDInvoice, nodeId: String) -> String {
        if let rHash = normalizedString(invoice.rHash) {
            return "\(nodeId):rhash:\(rHash)"
        }

        if let paymentRequest = normalizedString(invoice.paymentRequest) {
            return "\(nodeId):invoice:\(paymentRequest)"
        }

        if let settleIndex = invoice.settleIndex?.value {
            return "\(nodeId):settle:\(settleIndex)"
        }

        return "\(nodeId):fallback:\(invoice.id)"
    }

    private func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func lndPaymentRow(_ payment: LNDPayment) -> WalletManager.TransactionRow? {
        let amountSats = max(payment.valueSat?.value ?? 0, 0)
        let feeSats = max(payment.feeSat?.value ?? 0, 0)
        let transactionDate = date(fromUnixSeconds: payment.creationDate?.value)
        let status = paymentStatus(payment.status, failureReason: payment.failureReason)

        let note = payment.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return WalletManager.TransactionRow(
            id: "lnd-payment-\(payment.id)",
            transactionDate: transactionDate,
            direction: "sent",
            btcAmount: satsToBTCString(amountSats),
            feeBtcAmount: satsToBTCString(feeSats),
            network: "lightning",
            status: status,
            dateString: dateString(from: transactionDate),
            note: note,
            userLog: nil,
            amountSats: amountSats,
            feeSats: feeSats,
            method: "LND",
            destinationPubkey: payment.destination,
            invoice: payment.paymentRequest,
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

    private func lndInvoiceRow(_ invoice: LNDInvoice) -> WalletManager.TransactionRow? {
        guard invoice.isSettledInvoice else { return nil }

        let amountSats = max(invoice.amtPaidSat?.value ?? invoice.value?.value ?? 0, 0)
        guard amountSats > 0 else { return nil }

        let transactionDate = date(fromUnixSeconds: invoice.settleDate?.value ?? invoice.creationDate?.value)

        return WalletManager.TransactionRow(
            id: "lnd-invoice-\(invoice.id)",
            transactionDate: transactionDate,
            direction: "received",
            btcAmount: satsToBTCString(amountSats),
            feeBtcAmount: satsToBTCString(0),
            network: "lightning",
            status: "Completed",
            dateString: dateString(from: transactionDate),
            note: invoice.memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            userLog: nil,
            amountSats: amountSats,
            feeSats: 0,
            method: "LND",
            destinationPubkey: nil,
            invoice: invoice.paymentRequest,
            lnAddress: nil,
            lnurlDomain: nil,
            lnurlComment: nil,
            senderComment: nil,
            paymentHash: invoice.rHash,
            preimage: nil,
            expiryDateString: nil,
            txReferenceLabel: "Invoice Hash",
            txReference: invoice.rHash,
            hasConversion: false
        )
    }

    private func paymentStatus(_ status: String?, failureReason: String?) -> String {
        if let failureReason,
           !failureReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           failureReason.caseInsensitiveCompare("FAILURE_REASON_NONE") != .orderedSame {
            return "Failed"
        }

        guard let status else { return "Completed" }

        if status.localizedCaseInsensitiveContains("fail") { return "Failed" }
        if status.localizedCaseInsensitiveContains("in_flight") { return "Pending" }
        if status.localizedCaseInsensitiveContains("initiated") { return "Pending" }
        if status.localizedCaseInsensitiveContains("pending") { return "Pending" }
        if status.localizedCaseInsensitiveContains("succeed") { return "Completed" }
        if status.localizedCaseInsensitiveContains("complete") { return "Completed" }

        return status
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

private enum LNDHostResolver {
    static func resolve(host: String) async throws -> [LNDResolvedAddress] {
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

                var resolvedAddresses: [LNDResolvedAddress] = []
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

        guard status == 0 else {
            return nil
        }

        return String(cString: hostBuffer)
    }

    private static func stripScopeIdentifier(from host: String) -> String {
        if let percentIndex = host.firstIndex(of: "%") {
            return String(host[..<percentIndex])
        }

        return host
    }
}

private enum LNDInvoiceEventCursorStore {
    private static let keyPrefix = "split.lnd.invoiceListener.lastSettleIndex."

    static func lastSettleIndex(forNodeId nodeId: String) -> Int64? {
        let key = key(forNodeId: nodeId)

        if let number = UserDefaults.standard.object(forKey: key) as? NSNumber {
            return number.int64Value
        }

        if let string = UserDefaults.standard.string(forKey: key),
           let value = Int64(string) {
            return value
        }

        return nil
    }

    static func setLastSettleIndex(_ settleIndex: Int64, forNodeId nodeId: String) {
        UserDefaults.standard.set(NSNumber(value: settleIndex), forKey: key(forNodeId: nodeId))
    }

    static func clear(forNodeId nodeId: String) {
        UserDefaults.standard.removeObject(forKey: key(forNodeId: nodeId))
    }

    private static func key(forNodeId nodeId: String) -> String {
        "\(keyPrefix)\(nodeId)"
    }
}
