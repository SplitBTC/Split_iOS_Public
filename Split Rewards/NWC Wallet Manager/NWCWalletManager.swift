//
//  NWCWalletManager.swift
//  Split Rewards
//
//  Created by TeeVee on 5/1/26.
//

import Foundation
import Combine

@MainActor
final class NWCWalletManager: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case ready
        case error(String)
    }

    struct BalanceSummary: Equatable {
        let spendableSats: Int64
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var connectedWallet: NWCWalletCredentials?
    @Published private(set) var balanceSummary: BalanceSummary?
    @Published var lastErrorMessage: String?

    private let credentialStore: NWCCredentialStore
    private var client: NWCCommandClient?
    private var notificationListenerTask: Task<Void, Never>?
    private var notificationListenerWalletId: String?
    private let notificationListenerInitialBackoffNanos: UInt64 = 2_000_000_000
    private let notificationListenerMaxBackoffNanos: UInt64 = 30_000_000_000

    init(credentialStore: NWCCredentialStore = .shared) {
        self.credentialStore = credentialStore
    }

    var isConnected: Bool {
        if case .ready = state {
            return true
        }

        return false
    }

    var displayName: String {
        connectedWallet?.displayName ?? "NWC Wallet"
    }

    func connect(nwcConnectionString: String, label: String? = nil) async throws -> NWCWalletCredentials {
        lastErrorMessage = nil
        state = .connecting

        do {
            let parsedCredentials = try NWCConnectParser.parse(nwcConnectionString).withLabel(label)
            let capabilities = try await fetchCapabilities(for: parsedCredentials)
            let verifiedCredentials = parsedCredentials.verified(with: capabilities)

            let savedCredentials = credentialStore.saveWallet(verifiedCredentials, makeActive: true)
            connectedWallet = savedCredentials
            client = NWCCommandClient(wallet: savedCredentials)
            state = .ready
            await startNotificationListenerIfPossible()

            return savedCredentials
        } catch {
            let message = connectionErrorMessage(for: error)
            lastErrorMessage = message
            state = .error(message)
            throw error
        }
    }

    func restoreActiveWallet() async throws {
        lastErrorMessage = nil

        guard let storedWallet = credentialStore.activeWallet() else {
            state = .disconnected
            connectedWallet = nil
            balanceSummary = nil
            client = nil
            stopNotificationListener()
            throw NWCWalletError.noStoredConnection
        }

        state = .connecting

        do {
            let capabilities = try await fetchCapabilities(for: storedWallet)
            let verifiedWallet = storedWallet.verified(with: capabilities)
            let savedWallet = credentialStore.saveWallet(verifiedWallet, makeActive: false)

            connectedWallet = savedWallet
            client = NWCCommandClient(wallet: savedWallet)
            state = .ready
            await startNotificationListenerIfPossible()
        } catch {
            let message = connectionErrorMessage(for: error)
            lastErrorMessage = message
            connectedWallet = storedWallet
            client = NWCCommandClient(wallet: storedWallet)
            state = .error(message)
            stopNotificationListener()
            throw error
        }
    }

    func disconnectFromActiveWallet() {
        stopNotificationListener()
        connectedWallet = nil
        balanceSummary = nil
        lastErrorMessage = nil
        client = nil
        state = .disconnected
    }

    func forgetWallet(id: String) {
        if connectedWallet?.id == id {
            disconnectFromActiveWallet()
        }

        credentialStore.deleteWallet(id: id)

        Task {
            await NWCTransactionMetadataStore.shared.clear(walletId: id)
        }
    }

    func storedWallets() -> [NWCWalletCredentials] {
        credentialStore.loadWallets()
    }

    func setActiveStoredWallet(id: String) async throws {
        credentialStore.setActiveWallet(id: id)
        try await restoreActiveWallet()
    }

    func renameWallet(id: String, label: String) {
        credentialStore.renameWallet(id: id, label: label)
        if connectedWallet?.id == id,
           let updated = credentialStore.loadWallets().first(where: { $0.id == id }) {
            connectedWallet = updated
            client = NWCCommandClient(wallet: updated)
        }
    }

    @discardableResult
    func refreshWalletInfo() async throws -> NWCWalletCapabilities {
        let wallet = try requireWallet()
        let capabilities = try await fetchCapabilities(for: wallet)
        let verifiedWallet = wallet.verified(with: capabilities)
        let savedWallet = credentialStore.saveWallet(verifiedWallet, makeActive: false)
        connectedWallet = savedWallet
        client = NWCCommandClient(wallet: savedWallet)
        state = .ready
        await startNotificationListenerIfPossible()
        return capabilities
    }

    @discardableResult
    func refreshBalance() async throws -> BalanceSummary {
        let commandClient = try requireClient()
        let result = try await commandClient.getBalance()
        let summary = BalanceSummary(spendableSats: result.balanceSats)
        balanceSummary = summary
        state = .ready
        return summary
    }

    func createInvoice(
        amountSats: Int64?,
        memo: String?,
        expirySecs: Int64 = 3600
    ) async throws -> NWCTransactionResult {
        try await requireClient().makeInvoice(
            amountSats: amountSats,
            description: memo,
            expirySecs: expirySecs
        )
    }

    func payInvoice(
        _ bolt11: String,
        amountSats: Int64? = nil
    ) async throws -> NWCPayInvoiceResult {
        let result = try await requireClient().payInvoice(
            bolt11,
            amountSats: amountSats
        )
        _ = try? await refreshBalance()
        return result
    }

    func lookupInvoice(_ bolt11: String) async throws -> NWCTransactionResult {
        try await requireClient().lookupInvoice(invoice: bolt11)
    }

    func lookupInvoice(paymentHash: String) async throws -> NWCTransactionResult {
        try await requireClient().lookupInvoice(paymentHash: paymentHash)
    }

    func fetchTransactionRows(maxCount: Int = 50) async throws -> [WalletManager.TransactionRow] {
        let transactions = try await requireClient().listTransactions(limit: maxCount)
        var rows = transactions.compactMap(nwcTransactionRow)
        rows.sort { $0.transactionDate > $1.transactionDate }
        return rows
    }

    func fetchTransactionRows(for wallet: NWCWalletCredentials, maxCount: Int = 50) async throws -> [WalletManager.TransactionRow] {
        let transactions = try await NWCCommandClient(wallet: wallet).listTransactions(limit: maxCount)
        var rows = transactions.compactMap(nwcTransactionRow)
        rows.sort { $0.transactionDate > $1.transactionDate }
        return rows
    }

    func walletScopeIdentifier() -> String? {
        guard let walletId = connectedWallet?.id ?? credentialStore.activeWallet()?.id else {
            return nil
        }

        return "nwc:\(walletId)"
    }

    func activeWalletIdentifier() -> String? {
        connectedWallet?.id ?? credentialStore.activeWallet()?.id
    }

    func startNotificationListenerIfPossible() async {
        guard let wallet = connectedWallet ?? credentialStore.activeWallet() else {
            stopNotificationListener()
            return
        }

        guard wallet.capabilities?.supportsPaymentNotifications == true else {
            stopNotificationListener()
            return
        }

        if notificationListenerWalletId == wallet.id, notificationListenerTask != nil {
            return
        }

        stopNotificationListener()
        notificationListenerWalletId = wallet.id
        notificationListenerTask = Task { [weak self] in
            await self?.runNotificationListener(wallet: wallet)
        }
    }

    func stopNotificationListener() {
        notificationListenerTask?.cancel()
        notificationListenerTask = nil
        notificationListenerWalletId = nil
    }

    private func requireWallet() throws -> NWCWalletCredentials {
        guard let wallet = connectedWallet ?? credentialStore.activeWallet() else {
            throw NWCWalletError.walletNotConnected
        }

        return wallet
    }

    private func requireClient() throws -> NWCCommandClient {
        if let client {
            return client
        }

        let wallet = try requireWallet()
        let commandClient = NWCCommandClient(wallet: wallet)
        client = commandClient
        return commandClient
    }

    private func runNotificationListener(wallet: NWCWalletCredentials) async {
        var reconnectDelayNanos = notificationListenerInitialBackoffNanos
        let relayURLs = wallet.relayURLs.compactMap(URL.init(string:))

        guard !relayURLs.isEmpty else {
            return
        }

        while !Task.isCancelled {
            let manager = self
            await withTaskGroup(of: Void.self) { group in
                for relayURL in relayURLs {
                    group.addTask {
                        do {
                            try await NWCNotificationListener().listen(
                                wallet: wallet,
                                relayURL: relayURL,
                                onNotification: { notification in
                                    await manager.handleNotification(notification, walletId: wallet.id)
                                }
                            )
                        } catch {
                            if !Task.isCancelled {
                                print("NWC notification listener disconnected: \(error.localizedDescription)")
                            }
                        }
                    }
                }

                await group.waitForAll()
            }

            if Task.isCancelled {
                return
            }

            do {
                try await Task.sleep(nanoseconds: reconnectDelayNanos)
            } catch {
                return
            }

            reconnectDelayNanos = min(reconnectDelayNanos * 2, notificationListenerMaxBackoffNanos)
        }
    }

    private func handleNotification(_ notification: NWCNotification, walletId: String) async {
        let normalizedType = notification.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedType == "payment_received" || normalizedType == "payment_sent" else {
            return
        }

        if normalizedType == "payment_received",
           let invoice = notification.transaction.invoice?.trimmingCharacters(in: .whitespacesAndNewlines),
           !invoice.isEmpty {
            NotificationCenter.default.post(
                name: .paymentRequestInvoiceSettled,
                object: nil,
                userInfo: ["invoice": invoice]
            )
        }

        _ = try? await refreshBalance()
        _ = try? await fetchTransactionRows()

        await NWCTransactionMetadataStore.shared.ensureUsdSnapshots(
            for: [nwcTransactionRow(notification.transaction)].compactMap { $0 },
            walletId: walletId,
            currentBtcUsdRate: nil
        )

        NotificationCenter.default.post(name: .walletTransactionsDidChange, object: nil)
    }

    private func fetchCapabilities(for wallet: NWCWalletCredentials) async throws -> NWCWalletCapabilities {
        var lastError: Error?

        for relayString in wallet.relayURLs {
            guard let relayURL = URL(string: relayString) else {
                lastError = NWCWalletError.invalidRelay
                continue
            }

            do {
                let event = try await NWCRelayClient(relayURL: relayURL).fetchWalletInfo(
                    walletPubkey: wallet.walletPubkey
                )

                guard event.pubkey.lowercased() == wallet.walletPubkey.lowercased() else {
                    throw NWCWalletError.invalidRelayResponse
                }

                let capabilities = event.capabilities
                guard capabilities.supportsCompatibleEncryption else {
                    throw NWCWalletError.unsupportedEncryption
                }

                return capabilities
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NWCWalletError.walletInfoUnavailable
    }

    private func connectionErrorMessage(for error: Error) -> String {
        if let walletError = error as? NWCWalletError {
            return walletError.localizedDescription
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return "Split could not reach the NWC relay."
            case .timedOut:
                return "The NWC relay did not respond in time."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private func nwcTransactionRow(_ transaction: NWCTransactionResult) -> WalletManager.TransactionRow? {
        let amountSats = max(transaction.amountSats ?? 0, 0)
        guard amountSats > 0 else { return nil }

        let feeSats = max(transaction.feesPaidSats ?? 0, 0)
        let direction = transactionDirection(transaction.type)
        let status = transactionStatus(transaction.state)
        let transactionDate = date(fromUnixSeconds: transaction.createdAt)
        let invoiceMetadata = transaction.invoice.flatMap(NWCBolt11MetadataDecoder.decode)
        let paymentHash = transaction.paymentHash?.nilIfBlank ?? invoiceMetadata?.paymentHash?.nilIfBlank
        let destinationPubkey = invoiceMetadata?.destinationPubkey?.nilIfBlank
        let identifier = paymentHash ??
            transaction.preimage?.nilIfBlank ??
            transaction.invoice?.nilIfBlank ??
            "\(transaction.createdAt ?? 0)-\(amountSats)-\(direction)"

        return WalletManager.TransactionRow(
            id: "nwc-\(identifier)",
            transactionDate: transactionDate,
            direction: direction,
            btcAmount: satsToBTCString(amountSats),
            feeBtcAmount: satsToBTCString(feeSats),
            network: "lightning",
            status: status,
            dateString: dateString(from: transactionDate),
            note: transaction.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            userLog: nil,
            amountSats: amountSats,
            feeSats: feeSats,
            method: "NWC",
            destinationPubkey: destinationPubkey,
            invoice: transaction.invoice,
            lnAddress: nil,
            lnurlDomain: nil,
            lnurlComment: nil,
            senderComment: nil,
            paymentHash: paymentHash,
            preimage: transaction.preimage,
            expiryDateString: expiryDateString(fromUnixSeconds: transaction.expiresAt),
            txReferenceLabel: paymentHash == nil ? nil : "Payment Hash",
            txReference: paymentHash,
            hasConversion: false
        )
    }

    private func transactionDirection(_ type: String?) -> String {
        let normalized = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "incoming" {
            return "received"
        }

        return "sent"
    }

    private func transactionStatus(_ state: String?) -> String {
        switch state?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "settled", "succeeded", "success", "completed", "paid":
            return "Completed"
        case "pending", "in_flight":
            return "Pending"
        case "failed", "failure", "expired":
            return "Failed"
        default:
            return "Pending"
        }
    }

    private func satsToBTCString(_ sats: Int64) -> String {
        String(format: "%.8f", Double(max(sats, 0)) / 100_000_000.0)
    }

    private func date(fromUnixSeconds seconds: Int?) -> Date {
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

    private func expiryDateString(fromUnixSeconds seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else {
            return nil
        }

        return dateString(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }
}
