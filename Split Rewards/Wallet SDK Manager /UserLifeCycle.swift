//
//  UserLifeCycle.swift
//  Split Rewards
//
//  Created by TeeVee on 12/8/25.
//
import Foundation
import BreezSdkSpark

@MainActor
extension WalletManager {
    private enum WalletBootstrapFailure: Error {
        case preConnect(Error)
        case connect(error: Error, hadExistingStorage: Bool)
        case postConnect(Error)
    }

    // MARK: - Public API (called from the app)

    /// Main entry point: connect to Breez if a local seed exists.
    /// Caller must supply AuthManager so wallet events can trigger
    /// authenticated backend calls.
    func configure(authManager: AuthManager) async {
        if isConfiguring {
            print("⚠️ [WalletManager \(instanceId)] configure() already running – skipping re-entry")
            return
        }

        isConfiguring = true
        defer { isConfiguring = false }

        lastErrorMessage = nil
        didAttemptSilentWalletRepairInCurrentStartupFlow = false

        if let seed = readLocalSeed() {
            print("ℹ️ [WalletManager \(instanceId)] configure(): found local seed, connecting with seed")
            await connectWithSeed(
                seed,
                authManager: authManager,
                allowSilentRepair: true,
                showRecoveryOptionsOnConnectFailure: true
            )
        } else {
            print("ℹ️ [WalletManager \(instanceId)] configure(): no local seed → disconnecting, state = .noWallet")
            await disconnectCurrentWallet()
            clearStoredWalletRecoveryFlow()
            state = .noWallet
        }
    }

    /// Force a re-fetch of wallet info from Breez.
    func refreshWalletState() async {
        lastErrorMessage = nil

        do {
            try await loadRemoteState()
            await refreshBtcUsdRate()
            updateFiatBalance()
        } catch {
            let msg = "Failed to refresh wallet: \(error.localizedDescription)"
            state = .error(msg)
            lastErrorMessage = msg
        }
    }

    // MARK: - Connection & state loading

    func connectWithSeed(
        _ mnemonic: String,
        authManager: AuthManager,
        persistSeedOnSuccess: Bool = false,
        allowSilentRepair: Bool = false,
        showRecoveryOptionsOnConnectFailure: Bool = false
    ) async {
        lastErrorMessage = nil

        do {
            try await bootstrapWallet(
                withMnemonic: mnemonic,
                authManager: authManager,
                persistSeedOnSuccess: persistSeedOnSuccess
            )
            clearStoredWalletRecoveryFlow()
        } catch let failure as WalletBootstrapFailure {
            switch failure {
            case .preConnect(let error), .postConnect(let error):
                let msg = "Failed to connect wallet: \(error.localizedDescription)"
                state = .error(msg)
                lastErrorMessage = msg
            case .connect(let error, let hadExistingStorage):
                if showRecoveryOptionsOnConnectFailure {
                    let shouldAttemptRepair =
                        allowSilentRepair &&
                        !didAttemptSilentWalletRepairInCurrentStartupFlow &&
                        shouldAttemptSilentWalletRepair(
                            for: error,
                            hadExistingStorage: hadExistingStorage
                        )

                    if shouldAttemptRepair {
                        didAttemptSilentWalletRepairInCurrentStartupFlow = true
                        let repairSucceeded = await repairLocalWallet(
                            using: mnemonic,
                            authManager: authManager,
                            persistSeedOnSuccess: persistSeedOnSuccess
                        )

                        if repairSucceeded {
                            clearStoredWalletRecoveryFlow()
                            return
                        }
                    }

                    activateStoredWalletRecoveryFlow()
                }

                let msg = "Failed to connect wallet: \(error.localizedDescription)"
                state = .error(msg)
                lastErrorMessage = msg
            }
        } catch {
            let msg = "Failed to connect wallet: \(error.localizedDescription)"
            state = .error(msg)
            lastErrorMessage = msg
        }
    }

    func loadRemoteState() async throws {
        guard let sdk else { throw WalletError.sdkNotInitialized }

        let info = try await sdk.getInfo(
            request: GetInfoRequest(ensureSynced: false)
        )

        await MainActor.run {
            self.balanceSats = info.balanceSats
            self.updateFiatBalance()
            self.state = .ready
        }
    }

    // MARK: - Wallet removal

    /// Remove the wallet from this device.
    /// This deletes the locally stored seed, clears Breez local storage,
    /// and disconnects from Breez.
    /// Restoration is only possible using the recovery phrase.
    func removeWalletFromThisDevice() async {
        // 1) Stop Breez + clear in-memory state
        await disconnectCurrentWallet()

        // 2) Delete seed from Keychain (irreversible without phrase)
        clearLocalSeed()

        // 3) Delete messaging identity + local messages so device-scoped chat state is wiped
        MessageKeyManager.shared.clearStoredMessagingKey()
        SecureMessagingStorage.shared.clearStoredKey()
        MessagingDeviceTokenManager.shared.clearCachedDeviceTokenState()
        MessageRecipientTrustStore.clearAll()
        clearCachedLightningAddress()
        MessageStore.shared.clearAll()
        MessageAttachmentManager.shared.clearAll()
        await PaymentUsdSnapshotStore.shared.clearAll()

        // 4) Delete Breez local storage so stale SDK state cannot survive
        clearBreezStorage()

        // 5) Reset UI state
        clearStoredWalletRecoveryFlow()
        state = .noWallet
        lastErrorMessage = nil
    }

    // MARK: - Internal teardown

    private func disconnectCurrentWallet() async {
        await detachEventListener()

        if let existing = sdk {
            do {
                try await existing.disconnect()
            } catch {
                print("⚠️ [WalletManager \(instanceId)] Breez disconnect failed: \(error)")
            }
        }

        sdk = nil
        balanceSats = 0
        fiatBalanceUSD = nil
        btcUsdRate = nil
        processedPaymentIds.removeAll()
        usdSnapshotSyncTask?.cancel()
        usdSnapshotSyncTask = nil
    }

    // MARK: - Seed storage helpers

    func readLocalSeed() -> String? {
        let trimmedSeed = KeychainHelper.read(forKey: walletSeedKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let trimmedSeed, !trimmedSeed.isEmpty else {
            return nil
        }

        return trimmedSeed
    }

    private func bootstrapWallet(
        withMnemonic mnemonic: String,
        authManager: AuthManager,
        persistSeedOnSuccess: Bool
    ) async throws {
        if let existing = sdk {
            do {
                await detachEventListener()
                try await existing.disconnect()
            } catch {
                print("⚠️ [WalletManager \(instanceId)] Breez disconnect failed: \(error)")
            }
        }

        let seed = Seed.mnemonic(mnemonic: mnemonic, passphrase: nil)

        let apiKey: String
        do {
            apiKey = try await getBreezApiKey()
        } catch {
            throw WalletBootstrapFailure.preConnect(error)
        }

        var config = defaultConfig(network: .mainnet)
        config.apiKey = apiKey
        config.lnurlDomain = AppConfig.lightningAddressDomain
        config.privateEnabledDefault = true

        let hadExistingStorage = hasExistingBreezStorageDirectory()

        let storageDir: String
        do {
            storageDir = try makeStorageDir()
        } catch {
            throw WalletBootstrapFailure.preConnect(error)
        }

        let newSdk: BreezSdk
        do {
            newSdk = try await connect(
                request: ConnectRequest(
                    config: config,
                    seed: seed,
                    storageDir: storageDir
                )
            )
        } catch {
            throw WalletBootstrapFailure.connect(
                error: error,
                hadExistingStorage: hadExistingStorage
            )
        }

        sdk = newSdk

        if persistSeedOnSuccess {
            saveLocalSeed(mnemonic)
        }

        await attachEventListener(
            to: newSdk,
            authManager: authManager
        )

        do {
            try await loadRemoteState()
        } catch {
            throw WalletBootstrapFailure.postConnect(error)
        }
        do {
            _ = try await MessageKeyManager.shared.ensureRegistered(
                authManager: authManager,
                walletManager: self
            )
            await MessagingDeviceTokenManager.shared.syncDeviceTokenIfPossible(
                authManager: authManager,
                walletManager: self,
                force: true
            )
            await MessageSyncManager.shared.syncInboxIfPossible(
                authManager: authManager,
                walletManager: self,
                force: true
            )
            _ = await MessagingPushSyncCoordinator.shared.processPendingPushIfPossible()
        } catch {
            if MessageKeyManager.shared.shouldSilentlyDeferActivation(for: error) {
                print("ℹ️ [WalletManager \(instanceId)] Messaging activation deferred: \(error.localizedDescription)")
            } else {
                print("⚠️ [WalletManager \(instanceId)] Messaging key ensure failed: \(error.localizedDescription)")
            }
        }

        await refreshBtcUsdRate()
        updateFiatBalance()
    }

    private func shouldAttemptSilentWalletRepair(
        for error: Error,
        hadExistingStorage: Bool
    ) -> Bool {
        guard hadExistingStorage else {
            return false
        }

        guard let sdkError = error as? SdkError else {
            return false
        }

        if case .StorageError = sdkError {
            return true
        }

        return false
    }

    private func repairLocalWallet(
        using mnemonic: String,
        authManager: AuthManager,
        persistSeedOnSuccess: Bool
    ) async -> Bool {
        print("ℹ️ [WalletManager \(instanceId)] Attempting silent wallet repair")
        await disconnectCurrentWallet()
        clearBreezStorage()

        do {
            try await bootstrapWallet(
                withMnemonic: mnemonic,
                authManager: authManager,
                persistSeedOnSuccess: persistSeedOnSuccess
            )
            print("ℹ️ [WalletManager \(instanceId)] Silent wallet repair succeeded")
            return true
        } catch {
            print("⚠️ [WalletManager \(instanceId)] Silent wallet repair failed: \(error.localizedDescription)")
            return false
        }
    }

    func saveLocalSeed(_ seed: String) {
        KeychainHelper.save(seed, forKey: walletSeedKey)
    }

    private func clearLocalSeed() {
        KeychainHelper.delete(forKey: walletSeedKey)
    }

    // MARK: - Storage dir & fiat balance

    private func breezStorageDirectoryURL() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return appSupport.appendingPathComponent("breez-spark", isDirectory: true)
    }

    private func hasExistingBreezStorageDirectory() -> Bool {
        do {
            let dir = try breezStorageDirectoryURL()
            return FileManager.default.fileExists(atPath: dir.path)
        } catch {
            return false
        }
    }

    private func makeStorageDir() throws -> String {
        let fm = FileManager.default
        let dir = try breezStorageDirectoryURL()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private func clearBreezStorage() {
        do {
            let fm = FileManager.default
            let dir = try breezStorageDirectoryURL()

            if fm.fileExists(atPath: dir.path) {
                try fm.removeItem(at: dir)
                print("🧹 [WalletManager \(instanceId)] Cleared Breez storage: \(dir.path)")
            } else {
                print("ℹ️ [WalletManager \(instanceId)] No Breez storage found to clear at: \(dir.path)")
            }
        } catch {
            print("⚠️ [WalletManager \(instanceId)] Failed to clear Breez storage: \(error)")
        }
    }

    func updateFiatBalance() {
        Task { @MainActor in
            guard sdk != nil else { return }
            guard let rate = btcUsdRate else {
                fiatBalanceUSD = nil
                return
            }

            let btc = Double(balanceSats) / 100_000_000.0
            fiatBalanceUSD = btc * rate
        }
    }
}
