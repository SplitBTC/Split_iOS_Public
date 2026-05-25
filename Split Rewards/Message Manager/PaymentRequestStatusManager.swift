//
//  PaymentRequestStatusManager.swift
//  Split Rewards
//
//  Created by TeeVee on 3/23/26.
//

import Foundation
import BreezSdkSpark

@MainActor
final class PaymentRequestStatusManager {
    static let shared = PaymentRequestStatusManager()

    private init() {}

    func handleSucceededPaymentEvent(
        _ payment: Payment,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async {
        guard case .receive = payment.paymentType else { return }

        guard let details = payment.details else { return }

        let invoice: String?
        switch details {
        case .lightning(
            description: _,
            invoice: let lightningInvoice,
            destinationPubkey: _,
            htlcDetails: _,
            lnurlPayInfo: _,
            lnurlWithdrawInfo: _,
            lnurlReceiveMetadata: _
        ):
            invoice = lightningInvoice
        default:
            invoice = nil
        }

        guard let invoice else {
            return
        }

        await handleSettledInvoice(
            invoice,
            authManager: authManager,
            walletManager: walletManager
        )
    }

    func handleSettledInvoice(
        _ invoice: String,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async {
        let normalizedInvoice = invoice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedInvoice.isEmpty else {
            return
        }

        guard let originalRequest = MessageStore.shared.outgoingPaymentRequestMessage(forInvoice: normalizedInvoice) else {
            return
        }

        guard !MessageStore.shared.hasPaymentRequestPaidMarker(forRequestMessageId: originalRequest.id) else {
            return
        }

        let paidPayload = PaymentRequestPaidMessagePayload(
            requestMessageId: originalRequest.id,
            invoice: normalizedInvoice,
            paidAt: Date()
        )

        do {
            _ = try await MessagingSendCoordinator.sendPaymentRequestPaid(
                lightningAddress: originalRequest.recipientLightningAddress,
                payload: paidPayload,
                authManager: authManager,
                walletManager: walletManager
            )
        } catch {
            print("Failed to sync paid payment request status: \(error.localizedDescription)")
        }
    }
}

extension Notification.Name {
    static let paymentRequestInvoiceSettled = Notification.Name("paymentRequestInvoiceSettled")
}
