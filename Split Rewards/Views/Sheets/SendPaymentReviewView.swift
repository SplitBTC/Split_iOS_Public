//  SendPaymentReviewView.swift
//  Split
//
//  Step 2 of the send flow: review BTC + USD amounts and fees, then confirm.
//

import SwiftUI

struct SendPaymentReviewView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var lndWalletManager: LNDWalletManager
    @EnvironmentObject private var nwcWalletManager: NWCWalletManager
    @EnvironmentObject private var coreLightningWalletManager: CoreLightningWalletManager
    @EnvironmentObject private var eclairWalletManager: EclairWalletManager
    @EnvironmentObject private var sparkSubwalletManager: SparkSubwalletManager
    @EnvironmentObject private var toastManager: ToastManager

    let preview: WalletManager.PaymentPreview
    /// Called when the user wants to exit the entire send flow
    /// and return to the main customer index view
    /// (e.g., after a successful send or tapping the X).
    let onExitFlow: () -> Void

    @State private var isSending: Bool = false
    @State private var errorMessage: String?

    // MARK: - Derived values for UI

    private var amountBTC: Double {
        Double(preview.amountSats) / 100_000_000.0
    }

    /// Implied BTC/USD rate from the preview (if we have USD + BTC).
    private var impliedBtcUsdRate: Double? {
        guard preview.amountSats > 0,
              let usd = preview.amountFiatUSD else {
            return nil
        }
        let btc = amountBTC
        guard btc > 0 else { return nil }
        return usd / btc
    }

    private var routingFeeUSD: Double? {
        guard let feeSats = preview.routingFeeSats,
              let rate = impliedBtcUsdRate else {
            return nil
        }
        let feeBTC = Double(feeSats) / 100_000_000.0
        return feeBTC * rate
    }

    private var totalBTC: Double? {
        guard preview.amountSats > 0 else { return nil }
        let feeSats = preview.routingFeeSats ?? 0
        let totalSats = preview.amountSats + feeSats
        return Double(totalSats) / 100_000_000.0
    }

    private var totalUSD: Double? {
        guard let rate = impliedBtcUsdRate,
              let totalBTC = totalBTC else { return nil }
        return totalBTC * rate
    }

    private var networkFeeLabel: String {
        preview.feesIncluded ? "Network fee (included)" : "Network fee"
    }

    private var rewardStatusText: String {
        preview.rewardEligible == true
            ? "Reward payment."
            : "Payment not eligible for rewards."
    }

    private var rewardStatusBackground: Color {
        preview.rewardEligible == true
            ? Color.splitBrandPink
            : Color.black
    }

    private var rewardStatusPill: some View {
        Text(rewardStatusText)
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.86)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(rewardStatusBackground)
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.97)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Top bar with X and title (mirrors ReceiveInvoiceView)
                HStack {
                    Button(action: { onExitFlow() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("Confirm Payment")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Color.clear
                        .frame(width: 32, height: 32)
                }
                .padding(.top, 8)

                // Recipient
                VStack(alignment: .leading, spacing: 8) {
                    Text("To")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text(recipientTitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.88))

                    if let recipientSubtitle, !recipientSubtitle.isEmpty {
                        Text(recipientSubtitle)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.88))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Main amount card
                VStack(spacing: 12) {
                    Text("Amount")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if preview.amountSats > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            if let usd = preview.amountFiatUSD {
                                Text(formatUSD(usd))
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            } else {
                                Text("\(formatBTC(amountBTC)) BTC")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }

                            Text("\(formatBTC(amountBTC)) BTC")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Amount set in invoice")
                                .font(.subheadline)
                                .foregroundColor(.white)

                            Text("The Lightning invoice you scanned includes the amount.")
                                .font(.footnote)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .background(Color.splitInputSurface)
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 10) {
                    // Fee & total card
                    VStack(spacing: 12) {
                        HStack {
                            Text("Details")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                        }

                        VStack(spacing: 8) {
                            // Payment row
                            HStack {
                                Text("Payment")
                                    .foregroundColor(.white)
                                Spacer()
                                if let usd = preview.amountFiatUSD {
                                    Text(formatUSD(usd))
                                        .foregroundColor(.white)
                                } else if preview.amountSats > 0 {
                                    Text("\(formatBTC(amountBTC)) BTC")
                                        .foregroundColor(.white)
                                } else {
                                    Text("—")
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .font(.subheadline)

                            // Fee row (USD only if possible)
                            HStack {
                                Text(networkFeeLabel)
                                    .foregroundColor(.white)
                                Spacer()
                                if let feeUSD = routingFeeUSD {
                                    Text(formatUSD(feeUSD))
                                        .foregroundColor(.white)
                                } else if preview.routingFeeSats != nil {
                                    Text("Fee calculated on send")
                                        .foregroundColor(.white.opacity(0.7))
                                } else {
                                    Text("—")
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .font(.subheadline)

                            Divider()
                                .background(Color.white.opacity(0.15))

                            // Total row
                            HStack {
                                Text("Total")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    if let totalUSD = totalUSD {
                                        Text(formatUSD(totalUSD))
                                            .foregroundColor(.white)
                                    } else if let totalBTC = totalBTC {
                                        Text("\(formatBTC(totalBTC)) BTC")
                                            .foregroundColor(.white)
                                    } else {
                                        Text("—")
                                            .foregroundColor(.white.opacity(0.7))
                                    }

                                    if let totalBTC = totalBTC {
                                        Text("\(formatBTC(totalBTC)) BTC")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.splitInputSurfaceSecondary)
                    .cornerRadius(16)

                    rewardStatusPill
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Send button
                Button(action: send) {
                    HStack {
                        Spacer()
                        if isSending {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Send")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.white.opacity(isSending ? 0.3 : 1.0))
                    .foregroundColor(.black)
                    .cornerRadius(18)
                }
                .disabled(isSending)

                Text("Payments can’t be reversed. Double-check the recipient and amount before sending.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if isSending {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Helpers

    private var recipientName: String? {
        preview.recipientName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }

    private var normalizedPaymentRequest: String {
        let trimmed = preview.paymentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("lightning:") {
            return String(trimmed.dropFirst("lightning:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private var isLightningInvoice: Bool {
        let lower = normalizedPaymentRequest.lowercased()
        return lower.hasPrefix("lnbc") || lower.hasPrefix("lntb") || lower.hasPrefix("lnbcrt")
    }

    private var recipientTitle: String {
        if let recipientName {
            return recipientName
        }

        if isLightningInvoice {
            return "Lightning Invoice"
        }

        return normalizedPaymentRequest
    }

    private var recipientSubtitle: String? {
        guard recipientName != nil else { return nil }
        guard !isLightningInvoice else { return nil }
        return normalizedPaymentRequest.nilIfBlank
    }

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }

    private func formatBTC(_ btc: Double) -> String {
        String(format: "%.8f", btc)
    }

    // MARK: - Send

    private func send() {
        guard !isSending else { return }

        errorMessage = nil
        isSending = true
        toastManager.showPaymentPending(direction: .sent)
        onExitFlow()

        Task {
            switch preview.backend {
            case .spark:
                await sendSparkPayment()
            case .lnd:
                await sendLNDPayment()
            case .nwc:
                await sendNWCPayment()
            case .coreLightning:
                await sendCoreLightningPayment()
            case .eclair:
                await sendEclairPayment()
            case .sparkSubwallet:
                await sendSparkSubwalletPayment()
            }
        }
    }

    private func sendSparkPayment() async {
        let result = await walletManager.confirmPreparedPayment(preview: preview)

        await MainActor.run {
            switch result {
            case .completed:
                toastManager.showPaymentSuccess(direction: .sent)

            case .pending:
                break

            case .failed:
                let message = walletManager.lastErrorMessage?.nilIfBlank
                    ?? "Failed to send payment."
                toastManager.showPaymentFailure(direction: .sent, subtitle: message)
            }
        }
    }

    private func sendSparkSubwalletPayment() async {
        do {
            if !sparkSubwalletManager.isConnected {
                try await sparkSubwalletManager.restoreWalletIfNeeded()
            }

            if preview.amountFiatUSD == nil, walletManager.btcUsdRate == nil {
                await walletManager.refreshBtcUsdRate()
            }

            let result = await sparkSubwalletManager.confirmPreparedPayment(preview: preview)

            await MainActor.run {
                switch result {
                case .completed:
                    toastManager.showPaymentSuccess(direction: .sent)

                case .pending:
                    break

                case .failed:
                    let message = sparkSubwalletManager.lastErrorMessage?.nilIfBlank
                        ?? "Failed to send payment."
                    toastManager.showPaymentFailure(direction: .sent, subtitle: message)
                }
            }
        } catch {
            await MainActor.run {
                toastManager.showPaymentFailure(direction: .sent, subtitle: error.localizedDescription)
            }
        }
    }

    private func sendLNDPayment() async {
        do {
            if !lndWalletManager.isConnected {
                try await lndWalletManager.restoreActiveNode()
            }

            if preview.amountFiatUSD == nil, walletManager.btcUsdRate == nil {
                await walletManager.refreshBtcUsdRate()
            }

            let response = try await lndWalletManager.payInvoice(
                preview.paymentRequest,
                amountSats: preview.lndAmountOverrideSats
            )

            guard response.didSucceed else {
                throw LNDWalletError.serverError(
                    statusCode: 400,
                    message: response.paymentError?.nilIfBlank ?? "Payment failed."
                )
            }

            launchLNDPostSendReconciliation(response: response)

            await MainActor.run {
                toastManager.showPaymentSuccess(direction: .sent)
            }
        } catch {
            await MainActor.run {
                toastManager.showPaymentFailure(direction: .sent, subtitle: error.localizedDescription)
            }
        }
    }

    private func launchLNDPostSendReconciliation(response: LNDPayInvoiceResponse) {
        Task(priority: .utility) {
            do {
                _ = try await lndWalletManager.refreshBalance()
            } catch {
                print("Failed to refresh LND balance after send: \(error.localizedDescription)")
            }

            do {
                _ = try await lndWalletManager.fetchTransactionRows()
            } catch {
                print("Failed to refresh LND transactions after send: \(error.localizedDescription)")
            }

            await MainActor.run {
                NotificationCenter.default.post(name: .walletTransactionsDidChange, object: nil)
                postCompletedLNDRewardSpend(response: response)
            }
        }
    }

    private func sendNWCPayment() async {
        do {
            if !nwcWalletManager.isConnected {
                try await nwcWalletManager.restoreActiveWallet()
            }

            if preview.amountFiatUSD == nil, walletManager.btcUsdRate == nil {
                await walletManager.refreshBtcUsdRate()
            }

            let response = try await nwcWalletManager.payInvoice(
                preview.paymentRequest,
                amountSats: preview.lndAmountOverrideSats
            )

            await MainActor.run {
                toastManager.showPaymentSuccess(direction: .sent)
            }

            launchNWCPostSendReconciliation(response: response)
        } catch {
            await MainActor.run {
                toastManager.showPaymentFailure(direction: .sent, subtitle: error.localizedDescription)
            }
        }
    }

    private func launchNWCPostSendReconciliation(response: NWCPayInvoiceResult) {
        Task(priority: .utility) {
            do {
                _ = try await nwcWalletManager.refreshBalance()
            } catch {
                print("Failed to refresh NWC balance after send: \(error.localizedDescription)")
            }

            do {
                _ = try await nwcWalletManager.fetchTransactionRows()
            } catch {
                print("Failed to refresh NWC transactions after send: \(error.localizedDescription)")
            }

            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                _ = try await nwcWalletManager.fetchTransactionRows()
            } catch {
                if !Task.isCancelled {
                    print("Failed to confirm NWC transactions after send: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                NotificationCenter.default.post(name: .walletTransactionsDidChange, object: nil)
                postCompletedNWCRewardSpend(response: response)
            }
        }
    }

    private func sendCoreLightningPayment() async {
        do {
            if !coreLightningWalletManager.isConnected {
                try await coreLightningWalletManager.restoreActiveNode()
            }

            if preview.amountFiatUSD == nil, walletManager.btcUsdRate == nil {
                await walletManager.refreshBtcUsdRate()
            }

            let response = try await coreLightningWalletManager.payInvoice(
                preview.paymentRequest,
                amountSats: preview.lndAmountOverrideSats
            )

            guard response.didSucceed else {
                throw CoreLightningWalletError.serverError(
                    statusCode: 400,
                    message: "Payment did not complete."
                )
            }

            await MainActor.run {
                toastManager.showPaymentSuccess(direction: .sent)
            }

            launchCoreLightningPostSendReconciliation(response: response)
        } catch {
            await MainActor.run {
                toastManager.showPaymentFailure(direction: .sent, subtitle: error.localizedDescription)
            }
        }
    }

    private func launchCoreLightningPostSendReconciliation(response: CoreLightningPayResponse) {
        Task(priority: .utility) {
            do {
                _ = try await coreLightningWalletManager.refreshBalance()
            } catch {
                print("Failed to refresh Core Lightning balance after send: \(error.localizedDescription)")
            }

            do {
                _ = try await coreLightningWalletManager.fetchTransactionRows()
            } catch {
                print("Failed to refresh Core Lightning transactions after send: \(error.localizedDescription)")
            }

            await MainActor.run {
                NotificationCenter.default.post(name: .walletTransactionsDidChange, object: nil)
                postCompletedCoreLightningRewardSpend(response: response)
            }
        }
    }

    private func sendEclairPayment() async {
        do {
            if !eclairWalletManager.isConnected {
                try await eclairWalletManager.restoreActiveNode()
            }

            if preview.amountFiatUSD == nil, walletManager.btcUsdRate == nil {
                await walletManager.refreshBtcUsdRate()
            }

            let response = try await eclairWalletManager.payInvoice(
                preview.paymentRequest,
                amountSats: preview.lndAmountOverrideSats
            )

            guard response.didSucceed else {
                throw EclairWalletError.paymentFailed("Payment did not complete.")
            }

            await MainActor.run {
                toastManager.showPaymentSuccess(direction: .sent)
            }

            launchEclairPostSendReconciliation(response: response)
        } catch {
            await MainActor.run {
                toastManager.showPaymentFailure(direction: .sent, subtitle: error.localizedDescription)
            }
        }
    }

    private func launchEclairPostSendReconciliation(response: EclairPayResponse) {
        Task(priority: .utility) {
            do {
                _ = try await eclairWalletManager.refreshBalance()
            } catch {
                print("Failed to refresh Eclair balance after send: \(error.localizedDescription)")
            }

            do {
                _ = try await eclairWalletManager.fetchTransactionRows()
            } catch {
                print("Failed to refresh Eclair transactions after send: \(error.localizedDescription)")
            }

            await MainActor.run {
                NotificationCenter.default.post(name: .walletTransactionsDidChange, object: nil)
                postCompletedEclairRewardSpend(response: response)
            }
        }
    }

    @MainActor
    private func postCompletedNWCRewardSpend(response: NWCPayInvoiceResult) {
        guard shouldPostCompletedRewardSpend else { return }

        postCompletedEncryptedRewardSpendClaim(
            paymentHash: preview.paymentHash?.nilIfBlank,
            preimage: response.preimage?.nilIfBlank
        )
    }

    @MainActor
    private func postCompletedLNDRewardSpend(response: LNDPayInvoiceResponse) {
        guard shouldPostCompletedRewardSpend else { return }

        let paymentHash = response.paymentHash?.nilIfBlank ?? preview.paymentHash?.nilIfBlank

        postCompletedEncryptedRewardSpendClaim(
            paymentHash: paymentHash,
            preimage: response.paymentPreimage?.nilIfBlank
        )
    }

    @MainActor
    private func postCompletedCoreLightningRewardSpend(response: CoreLightningPayResponse) {
        guard shouldPostCompletedRewardSpend else { return }

        let paymentHash = response.paymentHash?.nilIfBlank ?? preview.paymentHash?.nilIfBlank

        postCompletedEncryptedRewardSpendClaim(
            paymentHash: paymentHash,
            preimage: response.paymentPreimage?.nilIfBlank
        )
    }

    @MainActor
    private func postCompletedEclairRewardSpend(response: EclairPayResponse) {
        guard shouldPostCompletedRewardSpend else { return }

        let paymentHash = response.paymentHash?.nilIfBlank ?? preview.paymentHash?.nilIfBlank
        let preimage = response.paymentPreimage?.nilIfBlank ?? response.status?.paymentPreimage?.nilIfBlank

        postCompletedEncryptedRewardSpendClaim(
            paymentHash: paymentHash,
            preimage: preimage
        )
    }

    @MainActor
    private func postCompletedEncryptedRewardSpendClaim(paymentHash: String?, preimage: String?) {
        guard shouldPostCompletedRewardSpend else { return }

        postEncryptedRewardSpendClaim(
            walletManager: walletManager,
            authManager: authManager,
            merchantPubkeyHash: preview.merchantPubkeyHash?.nilIfBlank,
            paymentHash: paymentHash,
            preimage: preimage,
            btcAmountSats: rewardSpendAmountSats(),
            usdAmountCents: rewardSpendUSDCents(),
            invoice: preview.paymentRequest,
            onSuccess: { _ in },
            onError: { [weak walletManager, weak toastManager] message in
                walletManager?.lastErrorMessage = message
                toastManager?.showInfo(
                    title: "Payment sent",
                    subtitle: "Reward could not be credited. \(message)",
                    duration: 5.0
                )
            }
        )
    }

    private var shouldPostCompletedRewardSpend: Bool {
        preview.rewardEligible == true
    }

    private func rewardSpendUSDCents() -> Int {
        if let amountFiatUSD = preview.amountFiatUSD, amountFiatUSD.isFinite {
            return Int((amountFiatUSD * 100.0).rounded())
        }

        guard let rate = walletManager.btcUsdRate, rate > 0 else {
            return 0
        }

        let usd = (Double(preview.amountSats) / 100_000_000.0) * rate
        return Int((usd * 100.0).rounded())
    }

    private func rewardSpendAmountSats() -> Int {
        guard preview.amountSats <= UInt64(Int.max) else {
            return Int.max
        }

        return Int(preview.amountSats)
    }
}
