//
//  UnclaimedDeposits.swift
//  Split Rewards
//
//  Created by TeeVee on 2/15/26.
//
//  Handles Bitcoin on-chain deposit discovery
//  and manual claiming.
//
import Foundation
import BreezSdkSpark

extension WalletManager {

    // MARK: - UI Model

    struct UnclaimedBitcoinDepositUI: Identifiable, Hashable {
        var id: String { "\(txid):\(vout)" }

        let txid: String
        let vout: UInt32
        let amountSats: UInt64

        /// Required fee to claim right now (in sats)
        let requiredFeeSats: UInt64?

        /// Required fee rate (sat/vB)
        let requiredFeeRateSatPerVbyte: UInt32?

        /// Description of current auto-claim cap (optional informational)
        let currentMaxFeeDescription: String?

        /// Failure reason if not claimable
        let failureReason: String?
    }

    // MARK: - Fetch Unclaimed Deposits

    func getUnclaimedBitcoinDeposits() async throws -> [UnclaimedBitcoinDepositUI] {

        guard let sdk else {
            throw WalletError.sdkNotInitialized
        }

        let info = try await sdk.getInfo(request: GetInfoRequest(ensureSynced: false))
        print("🧪 listUnclaimedDeposits pubkey: \(info.identityPubkey)")

        let response = try await sdk.listUnclaimedDeposits(
            request: ListUnclaimedDepositsRequest()
        )

        return response.deposits.map { deposit in
            
            print("🧪 deposit txid=\(deposit.txid) vout=\(deposit.vout) amount=\(deposit.amountSats)")
            print("🧪 deposit raw: \(String(describing: deposit))")

            var requiredFeeSats: UInt64? = nil
            var requiredFeeRate: UInt32? = nil
            var currentMaxFeeDescription: String? = nil
            var failureReason: String? = nil

            if let claimError = deposit.claimError {

                switch claimError {

                case .maxDepositClaimFeeExceeded(_, _, let maxFee, let reqSats, let reqRate):

                    requiredFeeSats = UInt64(reqSats)
                    requiredFeeRate = UInt32(reqRate)

                    if let maxFee = maxFee {
                        switch maxFee {
                        case .fixed(let amount):
                            currentMaxFeeDescription = "\(amount) sats"
                        case .rate(let satPerVbyte):
                            currentMaxFeeDescription = "\(satPerVbyte) sat/vB"
                        }
                    }

                case .missingUtxo(_, _):
                    failureReason = "UTXO not found. Try again later."

                case .generic(let message):
                    failureReason = message
                }
            }

            return UnclaimedBitcoinDepositUI(
                txid: deposit.txid,
                vout: deposit.vout,
                amountSats: UInt64(deposit.amountSats),
                requiredFeeSats: requiredFeeSats,
                requiredFeeRateSatPerVbyte: requiredFeeRate,
                currentMaxFeeDescription: currentMaxFeeDescription,
                failureReason: failureReason
            )
        }
    }

    // MARK: - Claim

    /// Claim using the required fee rate
    func claimDepositWithRate(
        txid: String,
        vout: UInt32,
        satPerVbyte: UInt32
    ) async throws {

        guard let sdk else {
            throw WalletError.sdkNotInitialized
        }

        let info = try await sdk.getInfo(request: GetInfoRequest(ensureSynced: false))
        print("🧪 claimDeposit pubkey: \(info.identityPubkey)")

        let request = ClaimDepositRequest(
            txid: txid,
            vout: vout,
            maxFee: .rate(satPerVbyte: UInt64(satPerVbyte))
        )
        
        print("🧪 listUnclaimedDeposits pubkey: \(info.identityPubkey)")

        _ = try await sdk.claimDeposit(request: request)
    }
}

