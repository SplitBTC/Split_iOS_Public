//  SendPayments.swift
//  Split Rewards
//
//  Created by TeeVee on 1/11/25.
//
import Foundation
import BreezSdkSpark
import BigNumber

@MainActor
extension WalletManager {

    enum PreparedPaymentConfirmationResult: Equatable {
        case completed(paymentId: String)
        case pending
        case failed
    }

    // MARK: - Shared error copy

    private func sendFailureMessage(details: String) -> String {
        return """
        Unable to send payment.

        Details:
        \(details)
        """
    }

    // MARK: - Internal helpers

    private func buildSendPaymentRequest(
        prepareResponse: PrepareSendPaymentResponse,
        idempotencyKey: String
    ) -> SendPaymentRequest {
        switch prepareResponse.paymentMethod {
        case .bolt11Invoice:
            // Use SDK default behavior (do not override completion timeout)
            return SendPaymentRequest(
                prepareResponse: prepareResponse,
                idempotencyKey: idempotencyKey
            )

        case .bitcoinAddress:
            // Keep aligned with the preview fee calculation (speedMedium).
            let options = SendPaymentOptions.bitcoinAddress(confirmationSpeed: .medium)
            return SendPaymentRequest(
                prepareResponse: prepareResponse,
                options: options,
                idempotencyKey: idempotencyKey
            )

        case .sparkAddress, .sparkInvoice:
            // Spark-native sends use default behavior when options are omitted.
            return SendPaymentRequest(
                prepareResponse: prepareResponse,
                idempotencyKey: idempotencyKey
            )
        }
    }

    private func previewAmountSats(
        requestedAmountSats: UInt64,
        routingFeeSats: UInt64?,
        feesIncluded: Bool
    ) -> UInt64 {
        guard feesIncluded, let routingFeeSats else {
            return requestedAmountSats
        }

        return requestedAmountSats > routingFeeSats ? requestedAmountSats - routingFeeSats : 0
    }

    private func fiatUSD(for sats: UInt64) -> Double? {
        guard let rate = btcUsdRate, sats > 0 else { return nil }
        return (Double(sats) / 100_000_000.0) * rate
    }

    // MARK: - 2-step send flow (prepare + confirm)

    /// Prepare a payment and return a preview for a confirmation screen.
    ///
    /// Supports:
    /// - BOLT11 invoices (with or without amount)
    /// - Bitcoin addresses / BIP21 URIs
    /// - Spark addresses / Spark invoices
    /// - LNURL-Pay + Lightning addresses (via prepareLnurlPay)
    func preparePayment(
        paymentRequest: String,
        amountSatsOverride: UInt64? = nil,
        feesIncluded: Bool = false,
        lnurlComment: String? = nil
    ) async -> PaymentPreview? {
        lastErrorMessage = nil

        guard let sdk else {
            lastErrorMessage = "Wallet not initialized."
            return nil
        }

        do {
            if btcUsdRate == nil {
                await refreshBtcUsdRate()
            }

            let normalizedLnurlComment = lnurlComment?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
            let feePolicy: FeePolicy? = feesIncluded ? .feesIncluded : nil

            // First parse so we can route LNURL-Pay / Lightning address correctly.
            let inputType = try await sdk.parse(input: paymentRequest)

            // --- LNURL-Pay / Lightning address (Strike, Wallet of Satoshi, etc.)
            // Breez Spark requires prepareLnurlPay(...) + lnurlPay(...)
            if case .lightningAddress(v1: let details) = inputType {
                guard let amountSats = amountSatsOverride, amountSats > 0 else {
                    lastErrorMessage = "Enter an amount in sats."
                    return nil
                }

                let req = PrepareLnurlPayRequest(
                    amount: BInt(amountSats),
                    payRequest: details.payRequest,
                    comment: normalizedLnurlComment,
                    validateSuccessActionUrl: true,
                    feePolicy: feePolicy
                )

                let prepareResponse = try await sdk.prepareLnurlPay(request: req)

                let previewId = UUID()
                preparedPayments[previewId] = .lnurl(prepareResponse)

                let responseFeesIncluded = prepareResponse.feePolicy == .feesIncluded
                let previewSats = previewAmountSats(
                    requestedAmountSats: amountSats,
                    routingFeeSats: prepareResponse.feeSats,
                    feesIncluded: responseFeesIncluded
                )

                return PaymentPreview(
                    id: previewId,
                    paymentRequest: paymentRequest,
                    amountSats: previewSats,
                    amountFiatUSD: fiatUSD(for: previewSats),
                    routingFeeSats: prepareResponse.feeSats,
                    feesIncluded: responseFeesIncluded,
                    recipientName: nil
                )
            }

            if case .lnurlPay(v1: let details) = inputType {
                guard let amountSats = amountSatsOverride, amountSats > 0 else {
                    lastErrorMessage = "Enter an amount in sats."
                    return nil
                }

                let req = PrepareLnurlPayRequest(
                    amount: BInt(amountSats),
                    payRequest: details,                 // ✅ pass details, not String
                    comment: normalizedLnurlComment,
                    validateSuccessActionUrl: true,
                    feePolicy: feePolicy
                )

                let prepareResponse = try await sdk.prepareLnurlPay(request: req)

                let previewId = UUID()
                preparedPayments[previewId] = .lnurl(prepareResponse)

                let responseFeesIncluded = prepareResponse.feePolicy == .feesIncluded
                let previewSats = previewAmountSats(
                    requestedAmountSats: amountSats,
                    routingFeeSats: prepareResponse.feeSats,
                    feesIncluded: responseFeesIncluded
                )

                return PaymentPreview(
                    id: previewId,
                    paymentRequest: paymentRequest,
                    amountSats: previewSats,
                    amountFiatUSD: fiatUSD(for: previewSats),
                    routingFeeSats: prepareResponse.feeSats,
                    feesIncluded: responseFeesIncluded,
                    recipientName: nil
                )
            }

            // --- Standard send flow (BOLT11 / BTC address / Spark)
            let amountBInt: BInt? = amountSatsOverride.map { BInt($0) }

            let prepareResponse = try await sdk.prepareSendPayment(
                request: PrepareSendPaymentRequest(
                    paymentRequest: paymentRequest,
                    amount: amountBInt,
                    feePolicy: feePolicy
                )
            )

            let routingFeeSats: UInt64? = {
                switch prepareResponse.paymentMethod {
                case .bolt11Invoice(invoiceDetails: _, sparkTransferFeeSats: _, lightningFeeSats: let lightningFeeSats):
                    return lightningFeeSats

                case .bitcoinAddress(address: _, feeQuote: let feeQuote):
                    let mediumFee = feeQuote.speedMedium.userFeeSat + feeQuote.speedMedium.l1BroadcastFeeSat
                    return UInt64(mediumFee)

                case .sparkAddress(address: _, fee: let fee, tokenIdentifier: _):
                    return UInt64(fee.description)

                case .sparkInvoice(sparkInvoiceDetails: _, fee: let fee, tokenIdentifier: _):
                    return UInt64(fee.description)
                }
            }()

            // Determine sats for preview.
            let requestedSats: UInt64
            if let override = amountSatsOverride {
                requestedSats = override
            } else if case .bolt11Invoice(v1: let invoice) = inputType,
                      let msat = invoice.amountMsat {
                requestedSats = UInt64(msat / 1_000)
            } else {
                requestedSats = UInt64(prepareResponse.amount.description) ?? 0
            }

            let responseFeesIncluded = prepareResponse.feePolicy == .feesIncluded
            let sats = previewAmountSats(
                requestedAmountSats: requestedSats,
                routingFeeSats: routingFeeSats,
                feesIncluded: responseFeesIncluded
            )

            let previewId = UUID()
            preparedPayments[previewId] = .send(prepareResponse)
            let bolt11Metadata = bolt11PreviewMetadata(from: inputType)

            return PaymentPreview(
                id: previewId,
                paymentRequest: paymentRequest,
                amountSats: sats,
                amountFiatUSD: fiatUSD(for: sats),
                routingFeeSats: routingFeeSats,
                feesIncluded: responseFeesIncluded,
                recipientName: bolt11Metadata.recipientName,
                destinationPubkey: bolt11Metadata.destinationPubkey,
                paymentHash: bolt11Metadata.paymentHash
            )

        } catch {
            lastErrorMessage = sendFailureMessage(details: error.localizedDescription)
            return nil
        }
    }

    private func bolt11PreviewMetadata(from inputType: InputType) -> (
        recipientName: String?,
        destinationPubkey: String?,
        paymentHash: String?
    ) {
        guard case .bolt11Invoice(v1: let invoice) = inputType else {
            return (nil, nil, nil)
        }

        return (
            invoice.description?.nilIfBlank,
            invoice.payeePubkey.nilIfBlank,
            invoice.paymentHash.nilIfBlank
        )
    }

    /// Confirm and send a previously prepared payment.
    func confirmPreparedPayment(preview: PaymentPreview) async -> PreparedPaymentConfirmationResult {
        lastErrorMessage = nil

        guard let sdk else {
            lastErrorMessage = "Wallet not initialized."
            return .failed
        }

        guard let prepared = preparedPayments[preview.id] else {
            lastErrorMessage = "Missing prepared payment state. Please try again."
            return .failed
        }

        do {
            let idempotencyKey = UUID().uuidString
            let payment: Payment

            switch prepared {
            case .send(let prepareResponse):
                let sendReq = buildSendPaymentRequest(
                    prepareResponse: prepareResponse,
                    idempotencyKey: idempotencyKey
                )
                payment = try await sdk.sendPayment(request: sendReq).payment

            case .lnurl(let prepareLnurlResponse):
                payment = try await sdk.lnurlPay(
                    request: LnurlPayRequest(
                        prepareResponse: prepareLnurlResponse,
                        idempotencyKey: idempotencyKey
                    )
                ).payment
            }

            preparedPayments.removeValue(forKey: preview.id)

            switch payment.status {
            case .completed:
                suppressOutgoingSuccessToast(for: payment.id)
                return .completed(paymentId: payment.id)

            case .pending:
                return .pending

            case .failed:
                suppressOutgoingFailureToast(for: payment.id)
                lastErrorMessage = "Failed to send payment."
                return .failed
            }

        } catch {
            lastErrorMessage = sendFailureMessage(details: error.localizedDescription)
            return .failed
        }
    }

    // MARK: - 1-step legacy send helper

    func sendPayment(
        to paymentRequest: String,
        amountSatsOverride: UInt64? = nil
    ) async -> Bool {
        lastErrorMessage = nil

        guard let sdk else {
            lastErrorMessage = "Wallet not initialized."
            return false
        }

        do {
            let inputType = try await sdk.parse(input: paymentRequest)

            if case .lightningAddress(v1: let details) = inputType {
                guard let amountSats = amountSatsOverride, amountSats > 0 else {
                    lastErrorMessage = "Enter an amount in sats."
                    return false
                }
                let req = PrepareLnurlPayRequest(
                    amount: BInt(amountSats),
                    payRequest: details.payRequest,
                    comment: nil,
                    validateSuccessActionUrl: true
                )
                let prepare = try await sdk.prepareLnurlPay(request: req)
                let idempotencyKey = UUID().uuidString
                _ = try await sdk.lnurlPay(
                    request: LnurlPayRequest(
                        prepareResponse: prepare,
                        idempotencyKey: idempotencyKey
                    )
                )
                return true
            }

            if case .lnurlPay(v1: let details) = inputType {
                guard let amountSats = amountSatsOverride, amountSats > 0 else {
                    lastErrorMessage = "Enter an amount in sats."
                    return false
                }

                let req = PrepareLnurlPayRequest(
                    amount: BInt(amountSats),
                    payRequest: details,                 // ✅ pass details, not String
                    comment: nil,
                    validateSuccessActionUrl: true
                )

                let prepare = try await sdk.prepareLnurlPay(request: req)
                let idempotencyKey = UUID().uuidString

                _ = try await sdk.lnurlPay(
                    request: LnurlPayRequest(
                        prepareResponse: prepare,
                        idempotencyKey: idempotencyKey
                    )
                )
                return true
            }

            let amountBInt: BInt? = amountSatsOverride.map { BInt($0) }

            let prepareResponse = try await sdk.prepareSendPayment(
                request: PrepareSendPaymentRequest(
                    paymentRequest: paymentRequest,
                    amount: amountBInt
                )
            )

            let idempotencyKey = UUID().uuidString
            let sendReq = buildSendPaymentRequest(
                prepareResponse: prepareResponse,
                idempotencyKey: idempotencyKey
            )

            _ = try await sdk.sendPayment(request: sendReq)
            return true

        } catch {
            lastErrorMessage = sendFailureMessage(details: error.localizedDescription)
            return false
        }
    }

    // MARK: - Fiat helpers

    /// Refresh the cached BTC/USD rate from Breez and update fiat balance.
    func refreshBtcUsdRate() async {
        guard let sdk else { return }

        do {
            let response = try await sdk.listFiatRates()

            if let usdRate = response.rates.first(where: { $0.coin == "USD" }) {
                btcUsdRate = usdRate.value
                updateFiatBalance()
            } else {
                print("⚠️ USD rate not found in fiat rates.")
            }
        } catch {
            print("⚠️ Failed to refresh BTC/USD rate: \(error)")
        }
    }
    
    // MARK: - Fiat helpers

    /// Convert a USD amount to BTC using the cached Breez BTC/USD rate.
    /// Returns nil if the rate is missing/unavailable.
    func convertUsdToBtc(usdAmount: Double) async -> Double? {
        if btcUsdRate == nil {
            await refreshBtcUsdRate()
        }
        guard let rate = btcUsdRate, rate > 0 else { return nil }
        return usdAmount / rate
    }

    // MARK: - Input helpers

    /// Returns the preset amount (in sats) if the payment request is a BOLT11 invoice
    /// that encodes a fixed amount. Returns nil for amountless invoices,
    /// LNURL / Lightning addresses, and on-chain addresses.
    func presetAmountSatsIfBolt11(_ paymentRequest: String) async -> UInt64? {
        guard let sdk else { return nil }

        do {
            let parsed = try await sdk.parse(input: paymentRequest)

            if case .bolt11Invoice(v1: let invoice) = parsed,
               let msat = invoice.amountMsat,
               msat > 0 {
                return UInt64(msat / 1_000)
            }

            return nil
        } catch {
            return nil
        }
    }

    func decodeBolt11InvoiceMetadata(_ paymentRequest: String) async -> (
        destinationPubkey: String?,
        paymentHash: String?,
        description: String?
    )? {
        guard let sdk else { return nil }

        do {
            let parsed = try await sdk.parse(input: paymentRequest)
            guard case .bolt11Invoice(v1: let invoice) = parsed else {
                return nil
            }

            return (
                invoice.payeePubkey.nilIfBlank,
                invoice.paymentHash.nilIfBlank,
                invoice.description?.nilIfBlank
            )
        } catch {
            return nil
        }
    }
}
