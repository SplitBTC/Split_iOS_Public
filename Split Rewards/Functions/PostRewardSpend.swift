//
//  PostRewardSpend.swift
//  Split Rewards
//
//  Created by TeeVee on 12/6/25.
//

import Foundation
import CryptoKit

// MARK: - Response Model

struct RewardSpendResponse: Decodable {
    let ok: Bool
    let rewardSpendApplied: Bool
}

struct RewardClaimEncryptionKeyResponse: Decodable {
    let ok: Bool
    let keyId: String
    let algorithm: String
    let publicKey: String
}

private struct EncryptedRewardSpendClaimPayload: Encodable {
    let merchantPubkeyHash: String
    let paymentHash: String
    let preimage: String
    let btcAmountSats: Int
    let usdAmountCents: Int
    let occurredAt: Date
    let invoice: String
}

private struct EncryptedRewardSpendClaimEnvelope: Encodable {
    let keyId: String
    let algorithm: String
    let ephemeralPublicKey: String
    let nonce: String
    let ciphertext: String
    let tag: String
    let clientClaimId: String
}

private enum RewardClaimEncryption {
    static let algorithm = "p256-hkdf-sha256-aes-256-gcm-v1"
    private static let salt = Data("split-reward-claim-v1".utf8)
    private static let sharedInfo = Data("reward-spend-claim-payload".utf8)

    static func encrypt(_ payload: EncryptedRewardSpendClaimPayload, using key: RewardClaimEncryptionKeyResponse) throws -> EncryptedRewardSpendClaimEnvelope {
        guard key.ok,
              key.algorithm == algorithm,
              let publicKeyData = Data(base64Encoded: key.publicKey) else {
            throw RewardSpendClaimError.invalidEncryptionKey
        }

        let serverPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: publicKeyData)
        let ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: sharedInfo,
            outputByteCount: 32
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintext = try encoder.encode(payload)
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey, nonce: nonce)
        let nonceData = nonce.withUnsafeBytes { Data($0) }

        return EncryptedRewardSpendClaimEnvelope(
            keyId: key.keyId,
            algorithm: key.algorithm,
            ephemeralPublicKey: ephemeralPrivateKey.publicKey.x963Representation.base64EncodedString(),
            nonce: nonceData.base64EncodedString(),
            ciphertext: sealedBox.ciphertext.base64EncodedString(),
            tag: sealedBox.tag.base64EncodedString(),
            clientClaimId: UUID().uuidString
        )
    }
}

@MainActor
func postEncryptedRewardSpendClaim(
    walletManager: WalletManager,
    authManager: AuthManager,
    merchantPubkeyHash: String?,
    paymentHash: String?,
    preimage: String?,
    btcAmountSats: Int,
    usdAmountCents: Int,
    invoice: String,
    occurredAt: Date = Date(),
    onSuccess: ((RewardSpendResponse) -> Void)? = nil,
    onError: ((String) -> Void)? = nil
) {
    Task {
        do {
            try await authManager.ensureSession(walletManager: walletManager)

            let invoice = invoice.trimmingCharacters(in: .whitespacesAndNewlines)
            var missingFields: [String] = []
            if merchantPubkeyHash?.nilIfBlank == nil { missingFields.append("merchant match") }
            if paymentHash?.nilIfBlank == nil { missingFields.append("payment hash") }
            if preimage?.nilIfBlank == nil { missingFields.append("preimage") }
            if invoice.isEmpty { missingFields.append("invoice") }

            guard missingFields.isEmpty,
                  let merchantPubkeyHash = merchantPubkeyHash?.nilIfBlank,
                  let paymentHash = paymentHash?.nilIfBlank,
                  let preimage = preimage?.nilIfBlank else {
                throw RewardSpendClaimError.missingPaymentProof(missingFields)
            }

            let key = try await fetchRewardClaimEncryptionKey()
            let payload = EncryptedRewardSpendClaimPayload(
                merchantPubkeyHash: merchantPubkeyHash,
                paymentHash: paymentHash,
                preimage: preimage,
                btcAmountSats: btcAmountSats,
                usdAmountCents: usdAmountCents,
                occurredAt: occurredAt,
                invoice: invoice
            )
            let envelope = try RewardClaimEncryption.encrypt(payload, using: key)

            guard let url = URL(string: "\(AppConfig.baseURL)/v2/reward-spend-claims") else {
                throw RewardSpendClaimError.invalidRequest
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpShouldHandleCookies = true
            request.httpBody = try JSONEncoder().encode(envelope)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RewardSpendClaimError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Server error \(httpResponse.statusCode)"
                throw RewardSpendClaimError.server(message)
            }

            let decoded = try JSONDecoder().decode(RewardSpendResponse.self, from: data)
            onSuccess?(decoded)
        } catch {
            onError?(error.localizedDescription)
        }
    }
}

private func fetchRewardClaimEncryptionKey() async throws -> RewardClaimEncryptionKeyResponse {
    guard let url = URL(string: "\(AppConfig.baseURL)/v1/reward-claim-encryption-key") else {
        throw RewardSpendClaimError.invalidRequest
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.httpShouldHandleCookies = false

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw RewardSpendClaimError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
        throw RewardSpendClaimError.server(String(data: data, encoding: .utf8) ?? "Encryption key request failed")
    }

    return try JSONDecoder().decode(RewardClaimEncryptionKeyResponse.self, from: data)
}

enum RewardSpendClaimError: LocalizedError {
    case invalidRequest
    case missingPaymentProof([String])
    case invalidResponse
    case invalidEncryptionKey
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "This reward claim is missing required payment proof."
        case .missingPaymentProof(let fields):
            let fieldList = fields.isEmpty ? "required payment proof" : fields.joined(separator: ", ")
            return "Missing \(fieldList)."
        case .invalidResponse:
            return "The server returned an invalid reward claim response."
        case .invalidEncryptionKey:
            return "The server returned an invalid reward claim encryption key."
        case .server(let message):
            return message
        }
    }
}






