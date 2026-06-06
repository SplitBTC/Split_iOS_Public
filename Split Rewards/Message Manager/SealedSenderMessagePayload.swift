//
//  SealedSenderMessagePayload.swift
//  Split Rewards
//
//  Created by TeeVee on 4/2/26.
//

import Foundation

struct SealedSenderMessagePayload: Codable {
    let body: String
    let sender: MessagingIdentityBindingPayload
    let messagingSigningPubkey: String
    let messagingSigningPubkeySignature: String
    let messagingSigningPubkeySignatureVersion: Int
    let messagingSigningPubkeySignedAt: Int
    let messageSignature: String
    let messageSignatureVersion: Int
}

struct SealedSenderMessagePayloadV4: Codable {
    let body: String
    let sender: MessagingIdentityBindingPayloadV4
    let senderLightningAddress: String
    let messagingSigningPubkey: String
    let messagingSigningPubkeySignature: String
    let messagingSigningPubkeySignatureVersion: Int
    let messagingSigningPubkeySignedAt: Int
    let messageSignature: String
    let messageSignatureVersion: Int
}
