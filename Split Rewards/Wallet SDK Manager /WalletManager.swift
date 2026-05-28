//  WalletManager.swift
//  Split Rewards
//
//  Created by TeeVee on 12/8/25.
//
import Foundation
import Combine
import BreezSdkSpark
import Bip39          // BIP39 seed phrase
import BigNumber      // BInt used by Breez Spark for some amounts

/// High-level state for the BTC/Spark wallet UI.
@MainActor
final class WalletManager: ObservableObject {
    
    // MARK: - Types
    
    enum WalletState: Equatable {
        case loading
        case noWallet           // No wallet configured on this device
        case ready              // Connected and usable
        case error(String)      // Fatal-ish error to show in the UI
    }
    
    enum WalletError: Error, LocalizedError {
        case sdkNotInitialized
        case invalidSeedPhrase
        case invalidAmount

        var errorDescription: String? {
            switch self {
            case .sdkNotInitialized:
                return "Wallet not initialized."
            case .invalidSeedPhrase:
                return "Invalid seed phrase."
            case .invalidAmount:
                return "Enter an amount in sats."
            }
        }
    }

    /// Lightweight data model for the "review & confirm" send screen.
    struct PaymentPreview: Identifiable, Equatable {
        enum Backend: Equatable {
            case spark
            case lnd
            case nwc
            case coreLightning
            case eclair
            case sparkSubwallet
        }

        let id: UUID

        let backend: Backend
        
        /// The raw invoice / address / Spark address string.
        let paymentRequest: String
        
        /// Amount to send in sats. For amountless invoices this can be 0.
        let amountSats: UInt64
        
        /// Optional USD equivalent for the amount, if we have a BTC/USD rate.
        let amountFiatUSD: Double?
        
        /// Estimated routing / network fee in sats (if known).
        /// Populated from the Breez `PrepareSendPaymentResponse.paymentMethod`.
        let routingFeeSats: UInt64?

        /// True when Breez will deduct the fee from the requested amount.
        let feesIncluded: Bool
        
        /// Optional human-readable recipient label (if available).
        let recipientName: String?

        /// Optional LND-specific amount override for amountless BOLT11 invoices.
        let lndAmountOverrideSats: Int64?

        /// Lightning destination pubkey, when the active wallet can expose it before send.
        let destinationPubkey: String?

        /// Lightning payment hash, when the active wallet can expose it before send.
        let paymentHash: String?

        /// Hash of the matched merchant pubkey from the public rewards merchant list.
        let merchantPubkeyHash: String?

        /// Whether the Lightning destination pubkey matched the local rewards merchant hash list.
        let rewardEligible: Bool?

        init(
            id: UUID,
            backend: Backend = .spark,
            paymentRequest: String,
            amountSats: UInt64,
            amountFiatUSD: Double?,
            routingFeeSats: UInt64?,
            feesIncluded: Bool,
            recipientName: String?,
            lndAmountOverrideSats: Int64? = nil,
            destinationPubkey: String? = nil,
            paymentHash: String? = nil,
            merchantPubkeyHash: String? = nil,
            rewardEligible: Bool? = nil
        ) {
            self.id = id
            self.backend = backend
            self.paymentRequest = paymentRequest
            self.amountSats = amountSats
            self.amountFiatUSD = amountFiatUSD
            self.routingFeeSats = routingFeeSats
            self.feesIncluded = feesIncluded
            self.recipientName = recipientName
            self.lndAmountOverrideSats = lndAmountOverrideSats
            self.destinationPubkey = destinationPubkey
            self.paymentHash = paymentHash
            self.merchantPubkeyHash = merchantPubkeyHash
            self.rewardEligible = rewardEligible
        }
    }
    
    // MARK: - Published properties used by SwiftUI
    
    @Published var state: WalletState = .loading
    @Published var balanceSats: UInt64 = 0
    @Published var fiatBalanceUSD: Double? = nil
    @Published var isSyncing: Bool = false
    @Published var lastErrorMessage: String?
    @Published private(set) var isStoredWalletRecoveryFlowActive: Bool = false
    
    /// When the user taps “Create Wallet”, we generate a mnemonic and store it here.
    /// The UI can show a SeedPhraseBackupView while this is non-nil.
    @Published var pendingSeedPhrase: String?
    @Published var pendingSeedWords: [String] = []
    
    // MARK: - External collaborators
    
    /// Optional global toast manager, injected from the app root.
    /// Used to show payment-related toasts on Breez events.
    var toastManager: ToastManager?
    
    // MARK: - Private-ish state (internal so extensions can mutate)
    
    /// Live Breez SDK instance (Spark)
    var sdk: BreezSdk?
    
    /// Key for wallet seed in Keychain (single wallet per device).
    let walletSeedKey = KeychainHelper.walletSeedKey
    
    /// In-memory cache of prepared payments, keyed by preview ID.
    ///
    /// We cache both the standard prepare response (BOLT11 / BTC address / Spark)
    /// and LNURL-pay prepares (including Lightning Addresses).
    enum PreparedPayment {
        case send(PrepareSendPaymentResponse)
        case lnurl(PrepareLnurlPayResponse)
    }

    var preparedPayments: [UUID: PreparedPayment] = [:]
    
    /// Cached BTC→USD rate from Breez fiat rates.
    /// Used to compute USD equivalents for amounts and fees.
    @Published var btcUsdRate: Double?

    /// Current Breez event listener and its registration ID.
    var eventListener: WalletEventListener?
    var eventListenerId: String?
    
    /// Guard to prevent overlapping configure()/connect cycles that can stack listeners.
    var isConfiguring: Bool = false
    
    /// Simple instance counter to help debug multiple instances (if they ever occur).
    static var instanceCounter: Int = 0
    let instanceId: Int
    
    /// Set of payment identifiers we've already sent to the backend (per app lifetime).
    /// Key is `paymentHash` if available, otherwise `payment.id`.
    var processedPaymentIds = Set<String>()
    private var suppressedOutgoingSuccessPaymentIds = Set<String>()
    private var suppressedOutgoingFailurePaymentIds = Set<String>()
    var didAttemptSilentWalletRepairInCurrentStartupFlow = false
    
    // MARK: - Refresh coalescing (debounce)
    /// Coalesce multiple Breez events into a single refresh.
    private var refreshTask: Task<Void, Never>?
    private let refreshDebounceNanos: UInt64 = 300_000_000 // 300ms
    var usdSnapshotSyncTask: Task<Void, Never>?
    
    /// Schedule a single refresh soon; multiple calls within the debounce window collapse into one.
    func scheduleRefresh() {
        // If a refresh is already scheduled/running, do nothing.
        if refreshTask != nil { return }
        
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            
            // Small debounce to collapse event storms (pending->succeeded->synced etc.)
            try? await Task.sleep(nanoseconds: self.refreshDebounceNanos)
            
            self.isSyncing = true
            defer {
                self.isSyncing = false
                self.refreshTask = nil
            }
            
            do {
                try await self.loadRemoteState()
                self.updateFiatBalance()
            } catch {
                let msg = "Failed to sync wallet: \(error.localizedDescription)"
                self.lastErrorMessage = msg
                // Do not hard-fail wallet state to .error just because a refresh failed;
                // let the UI keep functioning and retry on next event / manual refresh.
                print("⚠️ [WalletManager \(self.instanceId)] scheduleRefresh failed: \(msg)")
            }
        }
    }

    func suppressOutgoingSuccessToast(for paymentId: String) {
        suppressedOutgoingSuccessPaymentIds.insert(paymentId)
    }

    func consumeSuppressedOutgoingSuccessToastIfNeeded(paymentId: String) -> Bool {
        suppressedOutgoingSuccessPaymentIds.remove(paymentId) != nil
    }

    func suppressOutgoingFailureToast(for paymentId: String) {
        suppressedOutgoingFailurePaymentIds.insert(paymentId)
    }

    func consumeSuppressedOutgoingFailureToastIfNeeded(paymentId: String) -> Bool {
        suppressedOutgoingFailurePaymentIds.remove(paymentId) != nil
    }
    
    // MARK: - Init
    
    init() {
        WalletManager.instanceCounter += 1
        instanceId = WalletManager.instanceCounter
        print("🧠 WalletManager init – instanceId=\(instanceId)")
        state = .loading
    }
    
    deinit {
        print("🧠 WalletManager deinit – instanceId=\(instanceId)")
    }
    
    // MARK: - Convenience accessors
    
    /// Human-readable sats balance for display.
    var formattedSatsBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: balanceSats)) ?? "\(balanceSats)"
    }
    
    /// BTC balance (from sats) as a fixed 8-decimal string.
    // Define this as a static constant so it's only created once
    private static let btcFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 8
        f.maximumFractionDigits = 8
        return f
    }()

    var formattedBTCBalance: String {
        let btc = Double(balanceSats) / 100_000_000.0
        return Self.btcFormatter.string(from: NSNumber(value: btc)) ?? "0.00000000"
    }
}

@MainActor
extension WalletManager {
    func activateStoredWalletRecoveryFlow() {
        isStoredWalletRecoveryFlowActive = true
    }

    func clearStoredWalletRecoveryFlow() {
        isStoredWalletRecoveryFlowActive = false
    }
}

// MARK: - Helpers

extension Optional where Wrapped == String {
    /// Treat nil, empty, or all-whitespace strings as nil.
    var nilIfBlank: String? {
        guard let self = self else { return nil }
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension WalletManager {
    
    /// "Market" BTC price in USD from Breez fiat rates.
    var formattedBtcUsdPrice: String {
        guard let rate = btcUsdRate else { return "$—" }
        
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        nf.maximumFractionDigits = 2
        
        return nf.string(from: NSNumber(value: rate)) ?? "$—"
    }
    
    func refreshBtcPriceFromCoinbase() {
        fetchBitcoinPriceUSD(
            onSuccess: { [weak self] price in
                guard let self else { return }
                self.btcUsdRate = price
                self.updateFiatBalance()
            },
            onError: { error in
                print("⚠️ Coinbase BTC price fetch failed:", error)
            }
        )
    }
}
