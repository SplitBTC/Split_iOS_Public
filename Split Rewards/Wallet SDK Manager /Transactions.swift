//  Transactions.swift
//  Split Rewards
//
//  Created by TeeVee on 12/17/25.
//
import Foundation
import BreezSdkSpark

@MainActor
extension WalletManager {

    // MARK: - UI-friendly transaction row

    struct TransactionRow: Identifiable, Equatable {
        let id: String

        // Raw date for sorting / filtering / export
        let transactionDate: Date

        // Display fields
        let direction: String           // "sent" / "received"
        let btcAmount: String           // "0.00001234"
        let feeBtcAmount: String        // "0.00000001"
        let network: String             // "lightning" / "bitcoin" / "unknown"
        let status: String              // "Pending" / "Completed" / "Failed"
        let dateString: String          // "Dec 17, 2025 at 9:42 PM"

        // Canonical user-facing memo/description from Breez payment details
        let note: String
        let userLog: String?

        // Raw sats for sorting / math / export
        let amountSats: Int64
        let feeSats: Int64

        // Expanded technical details
        let method: String
        let destinationPubkey: String?
        let invoice: String?
        let lnAddress: String?
        let lnurlDomain: String?
        let lnurlComment: String?
        let senderComment: String?
        let paymentHash: String?
        let preimage: String?
        let expiryDateString: String?
        let txReferenceLabel: String?
        let txReference: String?
        let hasConversion: Bool

        func withUserLog(_ userLog: String?) -> TransactionRow {
            TransactionRow(
                id: id,
                transactionDate: transactionDate,
                direction: direction,
                btcAmount: btcAmount,
                feeBtcAmount: feeBtcAmount,
                network: network,
                status: status,
                dateString: dateString,
                note: note,
                userLog: Self.normalizedUserLog(userLog),
                amountSats: amountSats,
                feeSats: feeSats,
                method: method,
                destinationPubkey: destinationPubkey,
                invoice: invoice,
                lnAddress: lnAddress,
                lnurlDomain: lnurlDomain,
                lnurlComment: lnurlComment,
                senderComment: senderComment,
                paymentHash: paymentHash,
                preimage: preimage,
                expiryDateString: expiryDateString,
                txReferenceLabel: txReferenceLabel,
                txReference: txReference,
                hasConversion: hasConversion
            )
        }

        func withDestinationMetadata(
            destinationPubkey: String?,
            paymentHash: String?
        ) -> TransactionRow {
            TransactionRow(
                id: id,
                transactionDate: transactionDate,
                direction: direction,
                btcAmount: btcAmount,
                feeBtcAmount: feeBtcAmount,
                network: network,
                status: status,
                dateString: dateString,
                note: note,
                userLog: userLog,
                amountSats: amountSats,
                feeSats: feeSats,
                method: method,
                destinationPubkey: destinationPubkey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? self.destinationPubkey,
                invoice: invoice,
                lnAddress: lnAddress,
                lnurlDomain: lnurlDomain,
                lnurlComment: lnurlComment,
                senderComment: senderComment,
                paymentHash: paymentHash?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? self.paymentHash,
                preimage: preimage,
                expiryDateString: expiryDateString,
                txReferenceLabel: txReferenceLabel,
                txReference: txReference,
                hasConversion: hasConversion
            )
        }

        private static func normalizedUserLog(_ value: String?) -> String? {
            guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !normalized.isEmpty else {
                return nil
            }

            return normalized
        }
    }

    // MARK: - Transaction rows

    /// Convert Breez Spark `Payment` models into UI-friendly rows.
    ///
    /// In Spark, `Payment.fees` is the canonical fee field for the payment row regardless of method.
    func transactionRow(from payment: Payment) -> TransactionRow {
        let (direction, amountSats) = paymentDirectionAndAmount(payment)
        let feeSats = paymentFeeSats(payment)

        let btcAmountString = satsToBTCString(amountSats)
        let feeBtcAmountString = satsToBTCString(feeSats)

        let network = paymentNetworkString(payment)
        let status = paymentStatusString(payment)

        let transactionDate = paymentDate(payment)
        let dateString = paymentDateString(from: transactionDate)

        let note = paymentUserNote(payment)
        let details = paymentExpandedDetails(payment)

        return TransactionRow(
            id: payment.id,
            transactionDate: transactionDate,
            direction: direction,
            btcAmount: btcAmountString,
            feeBtcAmount: feeBtcAmountString,
            network: network,
            status: status,
            dateString: dateString,
            note: note,
            userLog: nil,
            amountSats: amountSats,
            feeSats: feeSats,
            method: paymentMethodString(payment),
            destinationPubkey: details.destinationPubkey,
            invoice: details.invoice,
            lnAddress: details.lnAddress,
            lnurlDomain: details.lnurlDomain,
            lnurlComment: details.lnurlComment,
            senderComment: details.senderComment,
            paymentHash: details.paymentHash,
            preimage: details.preimage,
            expiryDateString: details.expiryDateString,
            txReferenceLabel: details.txReferenceLabel,
            txReference: details.txReference,
            hasConversion: payment.conversionDetails != nil
        )
    }

    // MARK: - Memo / description extraction

    private func paymentUserNote(_ payment: Payment) -> String {
        guard let details = payment.details else { return "" }

        switch details {
        case .lightning(let description, _, _, _, let lnurlPayInfo, _, _):
            let normalizedDescription = cleaned(description)
            let normalizedLnurlComment = cleaned(lnurlPayInfo?.comment)

            if let normalizedLnurlComment,
               normalizedLnurlComment.range(of: "zap from ", options: [.caseInsensitive, .anchored]) != nil {
                return normalizedLnurlComment
            }

            return normalizedDescription ?? normalizedLnurlComment ?? ""

        case .spark(let invoiceDetails, _, _):
            return (invoiceDetails?.description ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

        case .token(_, _, _, let invoiceDetails, _):
            return (invoiceDetails?.description ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

        default:
            return ""
        }
    }

    // MARK: - Timestamp

    private func paymentDate(_ payment: Payment) -> Date {
        let raw = UInt64(payment.timestamp)

        let seconds: TimeInterval
        if raw > 10_000_000_000 { // likely ms
            seconds = TimeInterval(Double(raw) / 1000.0)
        } else {
            seconds = TimeInterval(raw)
        }

        return Date(timeIntervalSince1970: seconds)
    }

    private func paymentDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Status

    private func paymentStatusString(_ payment: Payment) -> String {
        let raw = String(describing: payment.status)

        if raw.localizedCaseInsensitiveContains("pending") { return "Pending" }
        if raw.localizedCaseInsensitiveContains("complete") { return "Completed" }
        if raw.localizedCaseInsensitiveContains("success") { return "Completed" }
        if raw.localizedCaseInsensitiveContains("fail") { return "Failed" }

        return raw
    }

    private func paymentMethodString(_ payment: Payment) -> String {
        switch payment.method {
        case .lightning:
            return "Lightning"
        case .spark:
            return "Spark"
        case .token:
            return "Token"
        case .deposit:
            return "Deposit"
        case .withdraw:
            return "Withdraw"
        case .unknown:
            return "Unknown"
        }
    }

    // MARK: - Network

    private func paymentNetworkString(_ payment: Payment) -> String {
        // Prefer method; SDK notes details can be empty.
        switch payment.method {
        case .lightning, .spark, .token:
            return "lightning"
        case .deposit, .withdraw:
            return "bitcoin"
        case .unknown:
            break
        }

        // Defensive fallback if method is unknown.
        guard let details = payment.details else { return "unknown" }
        switch details {
        case .lightning, .spark, .token:
            return "lightning"
        case .deposit, .withdraw:
            return "bitcoin"
        }
    }

    // MARK: - Direction & amount

    private func paymentDirectionAndAmount(_ payment: Payment) -> (String, Int64) {
        let direction: String
        switch payment.paymentType {
        case .send:
            direction = "sent"
        case .receive:
            direction = "received"
        @unknown default:
            direction = "sent"
        }

        let u = UInt64(payment.amount)
        let capped = min(u, UInt64(Int64.max))
        return (direction, Int64(capped))
    }

    // MARK: - Fees

    private func paymentFeeSats(_ payment: Payment) -> Int64 {
        let u = UInt64(payment.fees)
        let capped = min(u, UInt64(Int64.max))
        return Int64(capped)
    }

    // MARK: - Formatting

    private func satsToBTCString(_ sats: Int64) -> String {
        let btc = Double(sats) / 100_000_000.0
        return String(format: "%.8f", btc)
    }

    private struct ExpandedPaymentDetails {
        let destinationPubkey: String?
        let invoice: String?
        let lnAddress: String?
        let lnurlDomain: String?
        let lnurlComment: String?
        let senderComment: String?
        let paymentHash: String?
        let preimage: String?
        let expiryDateString: String?
        let txReferenceLabel: String?
        let txReference: String?
    }

    private func paymentExpandedDetails(_ payment: Payment) -> ExpandedPaymentDetails {
        guard let details = payment.details else {
            return ExpandedPaymentDetails(
                destinationPubkey: nil,
                invoice: nil,
                lnAddress: nil,
                lnurlDomain: nil,
                lnurlComment: nil,
                senderComment: nil,
                paymentHash: nil,
                preimage: nil,
                expiryDateString: nil,
                txReferenceLabel: nil,
                txReference: nil
            )
        }

        switch details {
        case let .lightning(
            description: _,
            invoice: invoice,
            destinationPubkey: destinationPubkey,
            htlcDetails: htlcDetails,
            lnurlPayInfo: lnurlPayInfo,
            lnurlWithdrawInfo: _,
            lnurlReceiveMetadata: lnurlReceiveMetadata
        ):
            return ExpandedPaymentDetails(
                destinationPubkey: cleaned(destinationPubkey),
                invoice: cleaned(invoice),
                lnAddress: cleaned(lnurlPayInfo?.lnAddress),
                lnurlDomain: cleaned(lnurlPayInfo?.domain),
                lnurlComment: cleaned(lnurlPayInfo?.comment),
                senderComment: cleaned(lnurlReceiveMetadata?.senderComment),
                paymentHash: cleaned(htlcDetails.paymentHash),
                preimage: cleaned(htlcDetails.preimage),
                expiryDateString: paymentDateString(from: paymentDate(fromUnixSeconds: htlcDetails.expiryTime)),
                txReferenceLabel: nil,
                txReference: nil
            )

        case let .spark(invoiceDetails, htlcDetails, _):
            return ExpandedPaymentDetails(
                destinationPubkey: nil,
                invoice: cleaned(invoiceDetails?.invoice),
                lnAddress: nil,
                lnurlDomain: nil,
                lnurlComment: nil,
                senderComment: nil,
                paymentHash: cleaned(htlcDetails?.paymentHash),
                preimage: cleaned(htlcDetails?.preimage),
                expiryDateString: htlcDetails.map {
                    paymentDateString(from: paymentDate(fromUnixSeconds: $0.expiryTime))
                },
                txReferenceLabel: nil,
                txReference: nil
            )

        case let .token(_, txHash, _, invoiceDetails, _):
            return ExpandedPaymentDetails(
                destinationPubkey: nil,
                invoice: cleaned(invoiceDetails?.invoice),
                lnAddress: nil,
                lnurlDomain: nil,
                lnurlComment: nil,
                senderComment: nil,
                paymentHash: nil,
                preimage: nil,
                expiryDateString: nil,
                txReferenceLabel: "Tx Hash",
                txReference: cleaned(txHash)
            )

        case let .withdraw(txId):
            return ExpandedPaymentDetails(
                destinationPubkey: nil,
                invoice: nil,
                lnAddress: nil,
                lnurlDomain: nil,
                lnurlComment: nil,
                senderComment: nil,
                paymentHash: nil,
                preimage: nil,
                expiryDateString: nil,
                txReferenceLabel: "Txid",
                txReference: cleaned(txId)
            )

        case let .deposit(txId):
            return ExpandedPaymentDetails(
                destinationPubkey: nil,
                invoice: nil,
                lnAddress: nil,
                lnurlDomain: nil,
                lnurlComment: nil,
                senderComment: nil,
                paymentHash: nil,
                preimage: nil,
                expiryDateString: nil,
                txReferenceLabel: "Txid",
                txReference: cleaned(txId)
            )
        }
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func paymentDate(fromUnixSeconds seconds: UInt64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    // MARK: - Fetch transactions from Breez

    func fetchTransactionRowsFromBreez() async throws -> [TransactionRow] {
        guard let sdk else {
            throw WalletError.sdkNotInitialized
        }

        let response = try await sdk.listPayments(request: ListPaymentsRequest())
        let payments = response.payments

        let rows = payments
            .map { self.transactionRow(from: $0) }
            .sorted { $0.transactionDate > $1.transactionDate }

        scheduleUsdSnapshotBackfill(for: rows)
        return rows
    }

    func persistUsdSnapshotIfNeeded(for payment: Payment) async {
        let row = transactionRow(from: payment)
        await persistUsdSnapshotIfNeeded(for: row)
    }

    func scheduleUsdSnapshotBackfill(for rows: [TransactionRow]) {
        guard usdSnapshotSyncTask == nil else { return }

        usdSnapshotSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.usdSnapshotSyncTask = nil }
            await self.ensureUsdSnapshots(for: rows)
        }
    }

    func ensureUsdSnapshots(for rows: [TransactionRow]) async {
        await persistMissingUsdSnapshots(for: rows)
    }

    private func persistMissingUsdSnapshots(for rows: [TransactionRow]) async {
        guard let walletPubkey = try? await MessageKeyManager.shared.currentWalletPubkey(walletManager: self) else {
            return
        }

        let completedRows = rows
            .filter { $0.status == "Completed" && ($0.direction == "sent" || $0.direction == "received") }
            .sorted { $0.transactionDate < $1.transactionDate }

        for row in completedRows {
            if Task.isCancelled { return }
            await persistUsdSnapshotIfNeeded(for: row, walletPubkey: walletPubkey)
        }
    }

    private func persistUsdSnapshotIfNeeded(
        for row: TransactionRow,
        walletPubkey: String? = nil
    ) async {
        guard row.status == "Completed" else { return }
        guard row.direction == "sent" || row.direction == "received" else { return }
        guard row.amountSats > 0 else { return }

        let resolvedWalletPubkey: String
        if let walletPubkey {
            resolvedWalletPubkey = walletPubkey
        } else if let fetchedWalletPubkey = try? await MessageKeyManager.shared.currentWalletPubkey(walletManager: self) {
            resolvedWalletPubkey = fetchedWalletPubkey
        } else {
            return
        }

        if await PaymentUsdSnapshotStore.shared.containsSnapshot(
            walletPubkey: resolvedWalletPubkey,
            paymentId: row.id
        ) {
            return
        }

        let rate: Double
        do {
            rate = try await usdRateForSnapshot(at: row.transactionDate)
        } catch {
            print("⚠️ [WalletManager \(instanceId)] Failed to fetch BTC/USD snapshot for \(row.id): \(error.localizedDescription)")
            return
        }

        guard rate > 0 else { return }

        let usdValue = (Double(row.amountSats) / 100_000_000.0) * rate
        let paymentType: PaymentUsdSnapshot.PaymentType = row.direction == "sent" ? .sent : .received

        await PaymentUsdSnapshotStore.shared.upsert(
            PaymentUsdSnapshot(
                walletPubkey: resolvedWalletPubkey,
                paymentId: row.id,
                paymentType: paymentType,
                usdValueAtTransaction: usdValue,
                btcUsdRateAtTransaction: rate
            )
        )
    }

    private func usdRateForSnapshot(at transactionDate: Date) async throws -> Double {
        let now = Date()
        if abs(now.timeIntervalSince(transactionDate)) <= 300,
           let currentRate = btcUsdRate,
           currentRate > 0 {
            return currentRate
        }

        return try await fetchBitcoinPriceUSD(at: transactionDate)
    }
}
