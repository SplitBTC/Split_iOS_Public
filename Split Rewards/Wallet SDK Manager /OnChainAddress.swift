//
//  OnChainAddress.swift
//  Split Rewards
//
//  Created by TeeVee on 1/16/26.
//
import BreezSdkSpark

extension WalletManager {

    /// Returns a fresh Bitcoin on-chain receive address.
    func getOnchainReceiveAddress() async throws -> String {
        guard let sdk else {
            throw WalletError.sdkNotInitialized
        }

        let response = try await sdk.receivePayment(
            request: ReceivePaymentRequest(
                paymentMethod: ReceivePaymentMethod.bitcoinAddress(newAddress: true)
            )
        )
       
        print("🧪 SDK bitcoin receive address: \(response.paymentRequest)")

        // This is the BTC address string (bc1…)
        return response.paymentRequest
    }
}
