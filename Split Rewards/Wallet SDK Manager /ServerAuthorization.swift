//
//  ServerAuthorization.swift
//  Split Rewards
//
//  Created by TeeVee on 12/17/25.
//

import Foundation
import BreezSdkSpark

@MainActor
extension WalletManager {

    /// Signs an auth message using the wallet's identity key.
    ///
    /// IMPORTANT:
    /// - With the updated backend flow, the message should come from the server
    ///   (e.g. `messageToSign` returned by `/auth/nonce`) and must be signed
    ///   byte-for-byte as provided.
    ///
    /// Returns the full response so callers can access both `signature` and `pubkey`.
    func signAuthMessage(_ message: String) async throws -> SignMessageResponse {
        guard let sdk else {
            throw AuthManager.AuthError.missingSigningProvider
        }

        return try await sdk.signMessage(
            request: SignMessageRequest(message: message, compact: true)
        )
    }
}




