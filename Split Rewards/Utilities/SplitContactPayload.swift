//
//  SplitContactPayload.swift
//  Split Rewards
//
//  Created by TeeVee on 3/23/26.
//

import Foundation

enum SplitContactPayloadError: LocalizedError {
    case incompleteSignedIdentity
    case mismatchedSignedIdentity
    case invalidSignedIdentity

    var errorDescription: String? {
        switch self {
        case .incompleteSignedIdentity:
            return "This Split contact card includes incomplete wallet verification data."
        case .mismatchedSignedIdentity:
            return "This Split contact card has mismatched wallet verification data."
        case .invalidSignedIdentity:
            return "This Split contact card failed wallet signature verification."
        }
    }
}

struct SplitContactPayload: Codable, Hashable, Identifiable {
    static let prefix = "split-contact:"

    let type: String
    let version: Int
    let lightningAddress: String
    let suggestedName: String
    let profilePicUrl: String?
    let walletPubkey: String?
    let messagingPubkey: String?
    let messagingIdentitySignature: String?
    let messagingIdentitySignatureVersion: Int?
    let messagingIdentitySignedAt: Int?

    var id: String { lightningAddress }

    var normalizedLightningAddress: String {
        lightningAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var hasSignedIdentityBindingFields: Bool {
        [walletPubkey, messagingPubkey, messagingIdentitySignature]
            .contains { value in
                guard let value else { return false }
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ||
        messagingIdentitySignatureVersion != nil ||
        messagingIdentitySignedAt != nil
    }

    func verifiedIdentityBindingPayload() throws -> MessagingIdentityBindingPayload? {
        guard hasSignedIdentityBindingFields else {
            return nil
        }

        guard let walletPubkey = walletPubkey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !walletPubkey.isEmpty,
              let messagingPubkey = messagingPubkey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !messagingPubkey.isEmpty,
              let messagingIdentitySignature = messagingIdentitySignature?.trimmingCharacters(in: .whitespacesAndNewlines),
              !messagingIdentitySignature.isEmpty,
              let messagingIdentitySignatureVersion,
              let messagingIdentitySignedAt
        else {
            throw SplitContactPayloadError.incompleteSignedIdentity
        }

        let binding = MessagingIdentityBindingPayload(
            walletPubkey: walletPubkey,
            lightningAddress: normalizedLightningAddress,
            messagingPubkey: messagingPubkey,
            messagingIdentitySignature: messagingIdentitySignature,
            messagingIdentitySignatureVersion: messagingIdentitySignatureVersion,
            messagingIdentitySignedAt: messagingIdentitySignedAt
        )

        guard binding.lightningAddress == normalizedLightningAddress else {
            throw SplitContactPayloadError.mismatchedSignedIdentity
        }

        do {
            try MessageKeyBindingVerifier.verifyBinding(binding)
            return binding
        } catch {
            throw SplitContactPayloadError.invalidSignedIdentity
        }
    }

    static func parse(from raw: String) -> SplitContactPayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let direct = decodePayload(from: trimmed) {
            return direct
        }

        for line in trimmed.components(separatedBy: .newlines) {
            if let parsed = decodePayload(from: line.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parsed
            }
        }

        if let range = trimmed.range(of: prefix) {
            let candidate = String(trimmed[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return decodePayload(from: candidate)
        }

        return nil
    }

    private static func decodePayload(from candidate: String) -> SplitContactPayload? {
        guard candidate.lowercased().hasPrefix(prefix) else { return nil }

        let jsonString = String(candidate.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = jsonString.data(using: .utf8),
              let payload = try? JSONDecoder().decode(SplitContactPayload.self, from: jsonData) else {
            return nil
        }

        guard payload.type == "split_contact",
              payload.version == 1,
              payload.normalizedLightningAddress.contains("@") else {
            return nil
        }

        return payload
    }
}
