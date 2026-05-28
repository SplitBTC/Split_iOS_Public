//
//  handledSdkEvent.swift
//  Split Rewards
//
//  Created by TeeVee on 12/8/25.
//
import Foundation
import BreezSdkSpark

@MainActor
extension WalletManager {

    // MARK: - Event listener wiring

    /// Attach Breez SDK event listener.
    /// The caller MUST provide AuthManager so wallet events can safely
    /// trigger authenticated backend calls.
    func attachEventListener(
        to sdk: BreezSdk,
        authManager: AuthManager
    ) async {
        print("🔌 [WalletManager \(instanceId)] attachEventListener() – start")

        // If we already have a listener, detach it first just to be safe.
        await detachEventListener()

        let listener = WalletEventListener { [weak self] event in
            guard let self else { return }
            await self.handleSdkEvent(event, authManager: authManager)
        }

        let id = await sdk.addEventListener(listener: listener)
        self.eventListener = listener
        self.eventListenerId = id

        print("🔌 [WalletManager \(instanceId)] attachEventListener() – attached id=\(id)")
    }

    /// Detach the current Breez event listener, if any.
    func detachEventListener() async {
        guard let sdk, let id = eventListenerId else {
            if eventListener != nil {
                print("🔌 [WalletManager \(instanceId)] detachEventListener() – clearing local listener without id")
            }
            eventListener = nil
            eventListenerId = nil
            return
        }

        print("🔌 [WalletManager \(instanceId)] detachEventListener() – detaching id=\(id)")
        _ = await sdk.removeEventListener(id: id)
        eventListener = nil
        eventListenerId = nil
    }

    // MARK: - Helpers

    /// Determine whether this payment is outgoing (send) vs incoming (receive).
    func isOutgoingPayment(_ payment: Payment) -> Bool {
        switch payment.paymentType {
        case .send:
            return true
        case .receive:
            return false
        @unknown default:
            // Safer to default to outgoing than misclassify inbound
            return true
        }
    }

    // MARK: - Top-level event handler

    /// Top-level handler for Breez `SdkEvent`s.
    /// Requires AuthManager to safely call authenticated backend endpoints.
    func handleSdkEvent(
        _ event: SdkEvent,
        authManager: AuthManager
    ) async {
        let shouldNotifyTransactionActivity: Bool = {
            switch event {
            case .synced,
                 .paymentSucceeded,
                 .paymentPending,
                 .paymentFailed,
                 .claimedDeposits,
                 .unclaimedDeposits:
                return true
            default:
                return false
            }
        }()

        // 1) Toasts / UI feedback
        if let toastManager {
            switch event {
            case .paymentSucceeded(let payment):
                let isOutgoing = isOutgoingPayment(payment)
                if !(isOutgoing && consumeSuppressedOutgoingSuccessToastIfNeeded(paymentId: payment.id)) {
                    toastManager.showPaymentSuccess(
                        direction: isOutgoing ? .sent : .received
                    )
                }

            case .paymentFailed(let payment):
                let isOutgoing = isOutgoingPayment(payment)
                if !(isOutgoing && consumeSuppressedOutgoingFailureToastIfNeeded(paymentId: payment.id)) {
                    toastManager.showPaymentFailure(
                        direction: isOutgoing ? .sent : .received
                    )
                }

            default:
                break
            }
        }

        // 2) Payment handling + backend logging
        switch event {
        case .paymentSucceeded(let payment):
            await persistUsdSnapshotIfNeeded(for: payment)

            // NEW: keep BTC amount in sats (no float conversion)
            let btcAmountSats = Int(payment.amount)

            // sats -> USD cents (via btcUsdRate, if available)
            var usdAmountCents: Int = 0
            if let rate = btcUsdRate {
                // rate is USD per BTC
                // USD = (sats / 1e8) * rate
                let usd = (Double(btcAmountSats) / 100_000_000.0) * rate
                usdAmountCents = Int((usd * 100).rounded())
            }

            let rewardProof = rewardClaimProof(from: payment)

            let dedupeKey = payment.id
            guard !processedPaymentIds.contains(dedupeKey) else {
                print("🔁 [WalletManager \(instanceId)] Duplicate payment ignored: \(dedupeKey)")
                return
            }

            processedPaymentIds.insert(dedupeKey)

            await PaymentRequestStatusManager.shared.handleSucceededPaymentEvent(
                payment,
                authManager: authManager,
                walletManager: self
            )

            let direction = isOutgoingPayment(payment) ? "sent" : "received"

            let methodDescription = String(describing: payment.method).lowercased()
            let network: String
            if methodDescription.contains("lightning") {
                network = "lightning"
            } else if methodDescription.contains("onchain") || methodDescription.contains("bitcoin") {
                network = "onchain"
            } else if methodDescription.contains("swap") {
                network = "swap"
            } else {
                network = "lightning"
            }

            if direction == "sent",
               network == "lightning",
               let destinationPubkey = rewardProof?.destinationPubkey {
                let rewardsCheck = try? await localRewardsCheck(destinationPubkey: destinationPubkey)
                if rewardsCheck?.rewardEligible == true {
                    postEncryptedRewardSpendClaim(
                        walletManager: self,
                        authManager: authManager,
                        merchantPubkeyHash: rewardsCheck?.merchantPubkeyHash,
                        paymentHash: rewardProof?.paymentHash,
                        preimage: rewardProof?.preimage,
                        btcAmountSats: btcAmountSats,
                        usdAmountCents: usdAmountCents,
                        invoice: rewardProof?.invoice ?? "",
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
            }

        default:
            break
        }

        // 3) Sync behavior (coalesced)
        switch event {
        case .synced:
            scheduleRefresh()

        case .paymentSucceeded,
             .paymentPending,
             .paymentFailed,
             .claimedDeposits,
             .unclaimedDeposits:
            scheduleRefresh()

        default:
            break
        }

        if shouldNotifyTransactionActivity {
            NotificationCenter.default.post(name: .walletTransactionsDidChange, object: nil)
        }
    }

    /// Backwards-compatible helper — now coalesces refreshes instead of refreshing immediately.
    func handleSyncedEvent() async {
        scheduleRefresh()
    }
}
