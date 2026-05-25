//
//  ReceivePayments.swift
//  Split Rewards
//
//  Created by TeeVee on 1/11/25.
//
import Foundation
import BreezSdkSpark

@MainActor
extension WalletManager {

    // MARK: - BOLT11 invoice (Lightning)

    /// Generate a BOLT11 invoice for the given description and amount.
    ///
    /// - Parameters:
    ///   - description: Shown to the payer in most wallets.
    ///   - amountSats: Amount to request, in sats.
    /// - Returns: The BOLT11 invoice string, or `nil` on failure.
    func generateBolt11Invoice(
        description: String,
        amountSats: UInt64?,
        expirySecs: UInt32 = 3600
    ) async -> String? {
        lastErrorMessage = nil

        guard let sdk else {
            lastErrorMessage = "Wallet not initialized."
            return nil
        }

        do {
            let response = try await sdk.receivePayment(
                request: ReceivePaymentRequest(
                        paymentMethod: .bolt11Invoice(
                            description: description,
                            amountSats: amountSats,
                            expirySecs: expirySecs,
                            paymentHash: nil
                        )
                )
            )

            let invoice = response.paymentRequest

            // NOTE:
            // We do not create any local record here; inbound payments are
            // tracked via Breez events and mirrored to the backend.
            return invoice
        } catch {
            lastErrorMessage = "Failed to generate invoice: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - On-chain address

    /// Generate a new on-chain Bitcoin address for receiving funds.
    ///
    /// - Returns: A bech32/base58 BTC address string, or `nil` on failure.
    func generateBitcoinAddress() async -> String? {
        lastErrorMessage = nil

        guard let sdk else {
            lastErrorMessage = "Wallet not initialized."
            return nil
        }

        do {
            let response = try await sdk.receivePayment(
                request: ReceivePaymentRequest(
                    paymentMethod: .bitcoinAddress(newAddress: true)
                )
            )

            let address = response.paymentRequest
            return address
        } catch {
            lastErrorMessage = "Failed to get Bitcoin address: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Spark address

    /// Generate a Spark address for receiving via the Spark overlay network.
    ///
    /// - Returns: A Spark address string, or `nil` on failure.
    func generateSparkAddress() async -> String? {
        lastErrorMessage = nil

        guard let sdk else {
            lastErrorMessage = "Wallet not initialized."
            return nil
        }

        do {
            let response = try await sdk.receivePayment(
                request: ReceivePaymentRequest(
                    paymentMethod: .sparkAddress
                )
            )

            let address = response.paymentRequest
            return address
        } catch {
            lastErrorMessage = "Failed to get Spark address: \(error.localizedDescription)"
            return nil
        }
    }
}
