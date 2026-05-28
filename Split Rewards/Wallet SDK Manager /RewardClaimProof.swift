//
//  RewardClaimProof.swift
//  Split Rewards
//
//  Created by TeeVee on 5/27/26.
//

import BreezSdkSpark
import Foundation

struct RewardClaimProof {
    let destinationPubkey: String?
    let invoice: String?
    let paymentHash: String?
    let preimage: String?
}

func rewardClaimProof(from payment: Payment) -> RewardClaimProof? {
    guard let details = payment.details else { return nil }

    switch details {
    case let .lightning(
        description: _,
        invoice: invoiceValue,
        destinationPubkey: destinationPubkeyValue,
        htlcDetails: htlcDetails,
        lnurlPayInfo: _,
        lnurlWithdrawInfo: _,
        lnurlReceiveMetadata: _
    ):
        let invoice = normalizedRewardProofField(invoiceValue)
        let invoiceMetadata = invoice.flatMap { NWCBolt11MetadataDecoder.decode($0) }

        return RewardClaimProof(
            destinationPubkey: normalizedRewardProofField(destinationPubkeyValue)
                ?? normalizedRewardProofField(invoiceMetadata?.destinationPubkey),
            invoice: invoice,
            paymentHash: normalizedRewardProofField(htlcDetails.paymentHash)
                ?? normalizedRewardProofField(invoiceMetadata?.paymentHash),
            preimage: normalizedRewardProofField(htlcDetails.preimage)
        )

    case let .spark(invoiceDetails, htlcDetails, _):
        let invoice = normalizedRewardProofField(invoiceDetails?.invoice)
        let invoiceMetadata = invoice.flatMap { NWCBolt11MetadataDecoder.decode($0) }

        return RewardClaimProof(
            destinationPubkey: normalizedRewardProofField(invoiceMetadata?.destinationPubkey),
            invoice: invoice,
            paymentHash: normalizedRewardProofField(htlcDetails?.paymentHash)
                ?? normalizedRewardProofField(invoiceMetadata?.paymentHash),
            preimage: normalizedRewardProofField(htlcDetails?.preimage)
        )

    default:
        return nil
    }
}

func normalizedRewardProofField(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
