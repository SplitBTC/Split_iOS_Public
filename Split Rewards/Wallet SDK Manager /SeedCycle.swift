//
//  SeedCycle.swift
//  Split Rewards
//
//  Created by TeeVee on 12/8/25.
//

import Foundation
import Bip39

@MainActor
extension WalletManager {

    // MARK: - Create new wallet (generate seed)

    func createWallet() async {
        lastErrorMessage = nil

        do {
            // 128-bit entropy => 12-word mnemonic by default.
            let mnemonicObj = try Mnemonic()
            let words = mnemonicObj.mnemonic()
            let phrase = words.joined(separator: " ")

            pendingSeedWords = words
            pendingSeedPhrase = phrase

            // We only connect after explicit confirmation. Leave the current
            // wallet state alone so recovery-mode users can back out cleanly.
        } catch {
            let message = "Failed to generate seed phrase: \(error.localizedDescription)"
            state = .error(message)
            lastErrorMessage = message
        }
    }

    // MARK: - Confirm / cancel creation

    func confirmPendingWalletCreation(authManager: AuthManager) async {
        guard let phrase = pendingSeedPhrase.nilIfBlank else {
            lastErrorMessage = "No pending seed phrase to confirm."
            return
        }

        clearStoredWalletRecoveryFlow()
        saveLocalSeed(phrase)

        pendingSeedPhrase = nil
        pendingSeedWords = []

        await connectWithSeed(phrase, authManager: authManager)
    }

    func cancelPendingWalletCreation() {
        pendingSeedPhrase = nil
        pendingSeedWords = []
    }

    // MARK: - Restore from existing seed

    func restoreWallet(fromMnemonic phrase: String, authManager: AuthManager) async {
        lastErrorMessage = nil

        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        guard words.count >= 12 else {
            let message = "Seed phrase too short. Expected at least 12 words."
            state = .noWallet
            lastErrorMessage = message
            return
        }

        await connectWithSeed(
            trimmed,
            authManager: authManager,
            persistSeedOnSuccess: true
        )
    }
}

