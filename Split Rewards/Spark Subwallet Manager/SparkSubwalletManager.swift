//
//  SparkSubwalletManager.swift
//  Split Rewards
//
//  Created by TeeVee on 5/12/26.
//

import BigNumber
import Bip39
import BreezSdkSpark
import Foundation

@MainActor
final class SparkSubwalletManager: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case ready
        case error(String)
    }

    struct BalanceSummary: Equatable {
        let spendableSats: UInt64
    }

    enum PreparedPayment {
        case send(PrepareSendPaymentResponse)
        case lnurl(PrepareLnurlPayResponse)
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var connectedWallet: SparkSubwalletCredentials?
    @Published private(set) var balanceSummary: BalanceSummary?
    @Published var lastErrorMessage: String?
    @Published var pendingSeedPhrase: String?
    @Published var pendingSeedWords: [String] = []

    var toastManager: ToastManager?
    weak var walletManager: WalletManager?
    weak var authManager: AuthManager?

    private let store: SparkSubwalletStore
    private var sdk: BreezSdk?
    private var eventListener: SparkSubwalletEventListener?
    private var eventListenerId: String?
    private var eventListenerWalletId: String?
    private var preparedPayments: [UUID: PreparedPayment] = [:]
    private var processedRewardPaymentIds: Set<String> = []
    private var refreshTask: Task<Void, Never>?
    private let refreshDebounceNanos: UInt64 = 300_000_000

    init(store: SparkSubwalletStore = .shared) {
        self.store = store
    }

    func configure(walletManager: WalletManager, authManager: AuthManager) {
        self.walletManager = walletManager
        self.authManager = authManager
    }

    var isConnected: Bool {
        if case .ready = state {
            return true
        }

        return false
    }

    func createPendingWalletSeed() throws {
        let mnemonic = try Mnemonic()
        let words = mnemonic.mnemonic()
        pendingSeedWords = words
        pendingSeedPhrase = words.joined(separator: " ")
    }

    func cancelPendingWalletSeed() {
        pendingSeedWords = []
        pendingSeedPhrase = nil
    }

    func createWallet(label: String) async throws -> SparkSubwalletCredentials {
        guard let phrase = pendingSeedPhrase?.nilIfBlank else {
            throw SparkSubwalletError.invalidSeedPhrase
        }

        let wallet = try await connectAndSave(seedPhrase: phrase, label: label)
        pendingSeedWords = []
        pendingSeedPhrase = nil
        return wallet
    }

    func restoreWallet(seedPhrase: String, label: String) async throws -> SparkSubwalletCredentials {
        try await connectAndSave(seedPhrase: normalizedSeedPhrase(seedPhrase), label: label)
    }

    func restoreWalletIfNeeded(id: String? = nil) async throws {
        let wallet: SparkSubwalletCredentials?
        if let id {
            wallet = SparkSubwalletCredentialStore.shared.loadWallet(id: id)
        } else {
            wallet = SparkSubwalletCredentialStore.shared.activeWallet()
        }

        guard let wallet else {
            state = .disconnected
            connectedWallet = nil
            sdk = nil
            balanceSummary = nil
            throw SparkSubwalletError.noStoredWallet
        }

        try await connectStoredWallet(wallet)
    }

    func disconnectActiveWallet() async {
        await detachEventListener()

        if let sdk {
            do {
                try await sdk.disconnect()
            } catch {
                print("⚠️ Spark sub-wallet disconnect failed: \(error.localizedDescription)")
            }
        }

        sdk = nil
        connectedWallet = nil
        balanceSummary = nil
        preparedPayments.removeAll()
        refreshTask?.cancel()
        refreshTask = nil
        state = .disconnected
    }

    func forgetWallet(id: String) {
        let wallet = SparkSubwalletCredentialStore.shared.loadWallet(id: id)

        if connectedWallet?.id == id {
            SparkSubwalletCredentialStore.shared.deleteWallet(id: id)
            Task {
                await PaymentUsdSnapshotStore.shared.clear(walletPubkey: id)
            }

            Task {
                await disconnectActiveWallet()
                if let wallet {
                    store.deleteSeed(for: wallet)
                    store.deleteStorageDirectory(for: wallet)
                }
            }
            return
        }

        removeStoredWallet(id: id, wallet: wallet)
    }

    private func removeStoredWallet(id: String, wallet: SparkSubwalletCredentials?) {
        if let wallet {
            store.deleteSeed(for: wallet)
            store.deleteStorageDirectory(for: wallet)
        }

        SparkSubwalletCredentialStore.shared.deleteWallet(id: id)
        Task {
            await PaymentUsdSnapshotStore.shared.clear(walletPubkey: id)
        }
    }

    func storedWallets() -> [SparkSubwalletCredentials] {
        SparkSubwalletCredentialStore.shared.loadWallets()
    }

    func setActiveStoredWallet(id: String) async throws {
        guard let wallet = SparkSubwalletCredentialStore.shared.loadWallet(id: id) else {
            throw SparkSubwalletError.noStoredWallet
        }

        try await connectStoredWallet(wallet)
        ExternalWalletStore.shared.setActiveSelection(.external(kind: .sparkSubwallet, id: id))
    }

    func renameWallet(id: String, label: String) {
        SparkSubwalletCredentialStore.shared.renameWallet(id: id, label: label)
        if connectedWallet?.id == id,
           let updated = SparkSubwalletCredentialStore.shared.loadWallet(id: id) {
            connectedWallet = updated
        }
    }

    @discardableResult
    func refreshBalance() async throws -> BalanceSummary {
        let sdk = try requireSdk()
        let info = try await sdk.getInfo(request: GetInfoRequest(ensureSynced: false))
        let summary = BalanceSummary(spendableSats: info.balanceSats)
        balanceSummary = summary
        state = .ready
        return summary
    }

    func generateBolt11Invoice(description: String, amountSats: UInt64?, expirySecs: UInt32 = 3600) async throws -> String {
        let response = try await requireSdk().receivePayment(
            request: ReceivePaymentRequest(
                paymentMethod: .bolt11Invoice(
                    description: description,
                    amountSats: amountSats,
                    expirySecs: expirySecs,
                    paymentHash: nil
                )
            )
        )

        return response.paymentRequest
    }

    func decodeBolt11InvoiceMetadata(_ paymentRequest: String) async -> (
        destinationPubkey: String?,
        paymentHash: String?,
        description: String?
    )? {
        let localMetadata = NWCBolt11MetadataDecoder.decode(paymentRequest)

        do {
            let parsed = try await requireSdk().parse(input: paymentRequest)
            guard case .bolt11Invoice(v1: let invoice) = parsed else {
                guard let localMetadata else { return nil }
                return (
                    localMetadata.destinationPubkey?.nilIfBlank,
                    localMetadata.paymentHash?.nilIfBlank,
                    localMetadata.description?.nilIfBlank
                )
            }

            return (
                invoice.payeePubkey.nilIfBlank ?? localMetadata?.destinationPubkey?.nilIfBlank,
                invoice.paymentHash.nilIfBlank ?? localMetadata?.paymentHash?.nilIfBlank,
                invoice.description?.nilIfBlank ?? localMetadata?.description?.nilIfBlank
            )
        } catch {
            guard let localMetadata else { return nil }
            return (
                localMetadata.destinationPubkey?.nilIfBlank,
                localMetadata.paymentHash?.nilIfBlank,
                localMetadata.description?.nilIfBlank
            )
        }
    }

    func preparePayment(
        paymentRequest: String,
        amountSatsOverride: UInt64? = nil,
        feesIncluded: Bool = false,
        lnurlComment: String? = nil,
        btcUsdRate: Double?
    ) async -> WalletManager.PaymentPreview? {
        lastErrorMessage = nil

        do {
            let sdk = try requireSdk()
            let normalizedLnurlComment = lnurlComment?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
            let feePolicy: FeePolicy? = feesIncluded ? .feesIncluded : nil
            let inputType = try await sdk.parse(input: paymentRequest)

            if case .lightningAddress(v1: let details) = inputType {
                return try await prepareLnurlPayment(
                    sdk: sdk,
                    paymentRequest: paymentRequest,
                    payRequest: details.payRequest,
                    amountSatsOverride: amountSatsOverride,
                    feePolicy: feePolicy,
                    lnurlComment: normalizedLnurlComment,
                    btcUsdRate: btcUsdRate
                )
            }

            if case .lnurlPay(v1: let details) = inputType {
                return try await prepareLnurlPayment(
                    sdk: sdk,
                    paymentRequest: paymentRequest,
                    payRequest: details,
                    amountSatsOverride: amountSatsOverride,
                    feePolicy: feePolicy,
                    lnurlComment: normalizedLnurlComment,
                    btcUsdRate: btcUsdRate
                )
            }

            let prepareResponse = try await sdk.prepareSendPayment(
                request: PrepareSendPaymentRequest(
                    paymentRequest: paymentRequest,
                    amount: amountSatsOverride.map { BInt($0) },
                    feePolicy: feePolicy
                )
            )

            let routingFeeSats = routingFeeSats(for: prepareResponse)
            let requestedSats: UInt64
            if let amountSatsOverride {
                requestedSats = amountSatsOverride
            } else if case .bolt11Invoice(v1: let invoice) = inputType,
                      let msat = invoice.amountMsat {
                requestedSats = UInt64(msat / 1_000)
            } else {
                requestedSats = UInt64(prepareResponse.amount.description) ?? 0
            }

            let feesIncludedResponse = prepareResponse.feePolicy == .feesIncluded
            let sats = previewAmountSats(
                requestedAmountSats: requestedSats,
                routingFeeSats: routingFeeSats,
                feesIncluded: feesIncludedResponse
            )
            let previewId = UUID()
            preparedPayments[previewId] = .send(prepareResponse)
            let bolt11Metadata = bolt11PreviewMetadata(from: inputType, paymentRequest: paymentRequest)

            return WalletManager.PaymentPreview(
                id: previewId,
                backend: .sparkSubwallet,
                paymentRequest: paymentRequest,
                amountSats: sats,
                amountFiatUSD: fiatUSD(for: sats, btcUsdRate: btcUsdRate),
                routingFeeSats: routingFeeSats,
                feesIncluded: feesIncludedResponse,
                recipientName: bolt11Metadata.recipientName,
                destinationPubkey: bolt11Metadata.destinationPubkey,
                paymentHash: bolt11Metadata.paymentHash
            )
        } catch {
            lastErrorMessage = "Unable to send payment.\n\nDetails:\n\(error.localizedDescription)"
            return nil
        }
    }

    func confirmPreparedPayment(preview: WalletManager.PaymentPreview) async -> WalletManager.PreparedPaymentConfirmationResult {
        lastErrorMessage = nil

        guard let prepared = preparedPayments.removeValue(forKey: preview.id) else {
            lastErrorMessage = "Payment details expired. Please try again."
            return .failed
        }

        do {
            let payment: Payment
            switch prepared {
            case .send(let prepareResponse):
                payment = try await requireSdk().sendPayment(
                    request: SendPaymentRequest(
                        prepareResponse: prepareResponse,
                        idempotencyKey: UUID().uuidString
                    )
                ).payment
            case .lnurl(let prepareResponse):
                payment = try await requireSdk().lnurlPay(
                    request: LnurlPayRequest(
                        prepareResponse: prepareResponse,
                        idempotencyKey: UUID().uuidString
                    )
                ).payment
            }

            scheduleRefresh()
            if payment.status == .completed {
                return .completed(paymentId: payment.id)
            }

            if payment.status == .pending {
                return .pending
            }

            return .failed
        } catch {
            lastErrorMessage = "Payment failed: \(error.localizedDescription)"
            return .failed
        }
    }

    func handleSdkEvent(_ event: SdkEvent) async {
        switch event {
        case .paymentSucceeded(let payment):
            await handleSucceededPaymentEvent(payment)
            scheduleRefresh()

        case .paymentPending,
             .paymentFailed,
             .claimedDeposits,
             .unclaimedDeposits,
             .synced:
            scheduleRefresh()

        default:
            break
        }
    }

    private func handleSucceededPaymentEvent(_ payment: Payment) async {
        guard payment.paymentType == .send else { return }

        let dedupeKey = payment.id
        guard !processedRewardPaymentIds.contains(dedupeKey) else { return }
        processedRewardPaymentIds.insert(dedupeKey)

        let methodDescription = String(describing: payment.method).lowercased()
        guard methodDescription.contains("lightning") else { return }

        let btcAmountSats = Int(payment.amount)
        var usdAmountCents = 0
        if let rate = walletManager?.btcUsdRate {
            let usd = (Double(btcAmountSats) / 100_000_000.0) * rate
            usdAmountCents = Int((usd * 100).rounded())
        }

        let proof = rewardClaimProof(from: payment)

        guard let destinationPubkey = proof?.destinationPubkey,
              let walletManager,
              let authManager else {
            return
        }

        let rewardsCheck = try? await localRewardsCheck(destinationPubkey: destinationPubkey)
        guard rewardsCheck?.rewardEligible == true else { return }

        postEncryptedRewardSpendClaim(
            walletManager: walletManager,
            authManager: authManager,
            merchantPubkeyHash: rewardsCheck?.merchantPubkeyHash,
            paymentHash: proof?.paymentHash,
            preimage: proof?.preimage,
            btcAmountSats: btcAmountSats,
            usdAmountCents: usdAmountCents,
            invoice: proof?.invoice ?? "",
            onSuccess: { _ in },
            onError: { [weak self] message in
                self?.lastErrorMessage = message
                self?.toastManager?.showInfo(
                    title: "Payment sent",
                    subtitle: "Reward could not be credited. \(message)",
                    duration: 5.0
                )
            }
        )
    }

    func fetchTransactionRows(mapper: WalletManager, maxCount: UInt32 = 100) async throws -> [WalletManager.TransactionRow] {
        let response = try await requireSdk().listPayments(
            request: ListPaymentsRequest(offset: nil, limit: maxCount)
        )

        return response.payments
            .map { mapper.transactionRow(from: $0) }
            .sorted { $0.transactionDate > $1.transactionDate }
    }

    func scheduleRefresh() {
        guard refreshTask == nil else { return }

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.refreshDebounceNanos)
            defer { self.refreshTask = nil }
            _ = try? await self.refreshBalance()
            NotificationCenter.default.post(name: .walletTransactionsDidChange, object: nil)
        }
    }

    private func connectAndSave(seedPhrase: String, label: String) async throws -> SparkSubwalletCredentials {
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLabel.isEmpty else {
            throw SparkSubwalletError.noStoredWallet
        }

        let normalizedSeed = normalizedSeedPhrase(seedPhrase)
        let storageDirectoryName = store.temporaryStorageDirectoryName()
        let sdk = try await connectSdk(seedPhrase: normalizedSeed, storageDirectoryName: storageDirectoryName)
        let info = try await sdk.getInfo(request: GetInfoRequest(ensureSynced: false))
        let identityPubkey = info.identityPubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let seedKey = store.seedKey(for: identityPubkey)
        let sparkAddress = try? await sparkAddress(sdk: sdk)
        let existing = SparkSubwalletCredentialStore.shared.loadWallet(id: identityPubkey)

        let wallet = SparkSubwalletCredentials(
            id: identityPubkey,
            label: normalizedLabel,
            seedKeychainKey: seedKey,
            storageDirectoryName: existing?.storageDirectoryName ?? storageDirectoryName,
            sparkAddress: sparkAddress,
            connectedAt: existing?.connectedAt ?? Date(),
            lastVerifiedAt: Date()
        )

        if let existing, existing.storageDirectoryName != storageDirectoryName {
            try? await sdk.disconnect()
            store.deleteStorageDirectory(
                for: SparkSubwalletCredentials(
                    id: identityPubkey,
                    label: normalizedLabel,
                    seedKeychainKey: seedKey,
                    storageDirectoryName: storageDirectoryName,
                    sparkAddress: sparkAddress,
                    connectedAt: Date(),
                    lastVerifiedAt: Date()
                )
            )
            try await connectStoredWallet(wallet.withLabel(normalizedLabel))
        } else {
            await disconnectActiveWallet()
            self.sdk = sdk
            self.connectedWallet = wallet
            self.balanceSummary = BalanceSummary(spendableSats: info.balanceSats)
            self.state = .ready
            await attachEventListener(to: sdk, walletId: wallet.id)
        }

        store.saveSeed(normalizedSeed, for: wallet)
        SparkSubwalletCredentialStore.shared.saveWallet(wallet, makeActive: true)
        return wallet
    }

    private func connectStoredWallet(_ wallet: SparkSubwalletCredentials) async throws {
        guard let seed = store.readSeed(for: wallet) else {
            state = .error(SparkSubwalletError.missingSeed.localizedDescription)
            throw SparkSubwalletError.missingSeed
        }

        if connectedWallet?.id == wallet.id, sdk != nil {
            _ = try await refreshBalance()
            return
        }

        await disconnectActiveWallet()
        state = .connecting

        do {
            let sdk = try await connectSdk(seedPhrase: seed, storageDirectoryName: wallet.storageDirectoryName)
            let info = try await sdk.getInfo(request: GetInfoRequest(ensureSynced: false))
            let sparkAddress = try? await sparkAddress(sdk: sdk)
            let verified = wallet.verified(sparkAddress: sparkAddress)

            self.sdk = sdk
            connectedWallet = verified
            balanceSummary = BalanceSummary(spendableSats: info.balanceSats)
            state = .ready
            SparkSubwalletCredentialStore.shared.saveWallet(verified, makeActive: false)
            await attachEventListener(to: sdk, walletId: verified.id)
        } catch {
            state = .error(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func connectSdk(seedPhrase: String, storageDirectoryName: String) async throws -> BreezSdk {
        let apiKey = try await getBreezApiKey()
        var config = defaultConfig(network: .mainnet)
        config.apiKey = apiKey
        config.lnurlDomain = "example.com"
        config.privateEnabledDefault = true

        let storageDir = try store.createStorageDirectory(named: storageDirectoryName).path
        return try await connect(
            request: ConnectRequest(
                config: config,
                seed: .mnemonic(mnemonic: seedPhrase, passphrase: nil),
                storageDir: storageDir
            )
        )
    }

    private func attachEventListener(to sdk: BreezSdk, walletId: String) async {
        await detachEventListener()
        let listener = SparkSubwalletEventListener(manager: self, walletId: walletId)
        eventListener = listener
        eventListenerWalletId = walletId
        eventListenerId = await sdk.addEventListener(listener: listener)
    }

    private func detachEventListener() async {
        guard let id = eventListenerId, let sdk else {
            eventListener = nil
            eventListenerId = nil
            eventListenerWalletId = nil
            return
        }

        _ = await sdk.removeEventListener(id: id)
        eventListener = nil
        eventListenerId = nil
        eventListenerWalletId = nil
    }

    private func sparkAddress(sdk: BreezSdk) async throws -> String {
        try await sdk.receivePayment(
            request: ReceivePaymentRequest(paymentMethod: .sparkAddress)
        ).paymentRequest
    }

    private func requireSdk() throws -> BreezSdk {
        guard let sdk else {
            throw SparkSubwalletError.walletNotConnected
        }

        return sdk
    }

    private func normalizedSeedPhrase(_ phrase: String) -> String {
        phrase
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
    }

    private func previewAmountSats(requestedAmountSats: UInt64, routingFeeSats: UInt64?, feesIncluded: Bool) -> UInt64 {
        guard feesIncluded, let routingFeeSats else {
            return requestedAmountSats
        }

        return requestedAmountSats > routingFeeSats ? requestedAmountSats - routingFeeSats : 0
    }

    private func fiatUSD(for sats: UInt64, btcUsdRate: Double?) -> Double? {
        guard let btcUsdRate, sats > 0 else { return nil }
        return (Double(sats) / 100_000_000.0) * btcUsdRate
    }

    private func routingFeeSats(for prepareResponse: PrepareSendPaymentResponse) -> UInt64? {
        switch prepareResponse.paymentMethod {
        case .bolt11Invoice(invoiceDetails: _, sparkTransferFeeSats: _, lightningFeeSats: let lightningFeeSats):
            return lightningFeeSats
        case .bitcoinAddress(address: _, feeQuote: let feeQuote):
            let mediumFee = feeQuote.speedMedium.userFeeSat + feeQuote.speedMedium.l1BroadcastFeeSat
            return UInt64(mediumFee)
        case .sparkAddress(address: _, fee: let fee, tokenIdentifier: _):
            return UInt64(fee.description)
        case .sparkInvoice(sparkInvoiceDetails: _, fee: let fee, tokenIdentifier: _):
            return UInt64(fee.description)
        }
    }

    private func bolt11PreviewMetadata(from inputType: InputType, paymentRequest: String) -> (
        recipientName: String?,
        destinationPubkey: String?,
        paymentHash: String?
    ) {
        let localMetadata = NWCBolt11MetadataDecoder.decode(paymentRequest)
        guard case .bolt11Invoice(v1: let invoice) = inputType else {
            return (
                localMetadata?.description?.nilIfBlank,
                localMetadata?.destinationPubkey?.nilIfBlank,
                localMetadata?.paymentHash?.nilIfBlank
            )
        }

        return (
            invoice.description?.nilIfBlank ?? localMetadata?.description?.nilIfBlank,
            invoice.payeePubkey.nilIfBlank ?? localMetadata?.destinationPubkey?.nilIfBlank,
            invoice.paymentHash.nilIfBlank ?? localMetadata?.paymentHash?.nilIfBlank
        )
    }

    private func prepareLnurlPayment(
        sdk: BreezSdk,
        paymentRequest: String,
        payRequest: LnurlPayRequestDetails,
        amountSatsOverride: UInt64?,
        feePolicy: FeePolicy?,
        lnurlComment: String?,
        btcUsdRate: Double?
    ) async throws -> WalletManager.PaymentPreview? {
        guard let amountSatsOverride, amountSatsOverride > 0 else {
            lastErrorMessage = "Enter an amount in sats."
            return nil
        }

        let prepareResponse = try await sdk.prepareLnurlPay(
            request: PrepareLnurlPayRequest(
                amount: BInt(amountSatsOverride),
                payRequest: payRequest,
                comment: lnurlComment,
                validateSuccessActionUrl: true,
                feePolicy: feePolicy
            )
        )

        let feesIncludedResponse = prepareResponse.feePolicy == .feesIncluded
        let sats = previewAmountSats(
            requestedAmountSats: amountSatsOverride,
            routingFeeSats: prepareResponse.feeSats,
            feesIncluded: feesIncludedResponse
        )
        let previewId = UUID()
        preparedPayments[previewId] = .lnurl(prepareResponse)

        return WalletManager.PaymentPreview(
            id: previewId,
            backend: .sparkSubwallet,
            paymentRequest: paymentRequest,
            amountSats: sats,
            amountFiatUSD: fiatUSD(for: sats, btcUsdRate: btcUsdRate),
            routingFeeSats: prepareResponse.feeSats,
            feesIncluded: feesIncludedResponse,
            recipientName: nil
        )
    }
}
