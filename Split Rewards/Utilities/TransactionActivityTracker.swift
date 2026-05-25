//
//  TransactionActivityTracker.swift
//  Split Rewards
//
//  Created by TeeVee on 3/30/26.
//

import Foundation

@MainActor
final class TransactionActivityTracker: ObservableObject {
    static let shared = TransactionActivityTracker()

    @Published private(set) var unseenTransactionIDs: Set<String> = []

    private let seenTransactionIDsKey = "split.seenTransactionIDs"
    private let hasSeededSeenTransactionsKey = "split.hasSeededSeenTransactions"

    private init() {
        unseenTransactionIDs = []
    }

    var unseenCount: Int {
        unseenTransactionIDs.count
    }

    func refreshIfPossible(walletManager: WalletManager) async {
        guard case .ready = walletManager.state else {
            unseenTransactionIDs = []
            return
        }

        do {
            let rows = try await walletManager.fetchTransactionRowsFromBreez()
            reconcile(with: rows, scope: "spark")
        } catch {
            // Leave the current badge state alone if refresh fails.
        }
    }

    func refreshIfPossible(lndWalletManager: LNDWalletManager) async {
        guard lndWalletManager.isConnected,
              let nodeId = lndWalletManager.activeNodeIdentifier() else {
            unseenTransactionIDs = []
            return
        }

        do {
            let rows = try await lndWalletManager.fetchTransactionRows()
            reconcile(with: rows, scope: "lnd:\(nodeId)")
        } catch {
            // Leave the current badge state alone if refresh fails.
        }
    }

    func refreshIfPossible(nwcWalletManager: NWCWalletManager) async {
        guard nwcWalletManager.isConnected,
              let walletId = nwcWalletManager.activeWalletIdentifier() else {
            unseenTransactionIDs = []
            return
        }

        do {
            let rows = try await nwcWalletManager.fetchTransactionRows()
            reconcile(with: rows, scope: "nwc:\(walletId)")
        } catch {
            // Leave the current badge state alone if refresh fails.
        }
    }

    func refreshIfPossible(coreLightningWalletManager: CoreLightningWalletManager) async {
        guard coreLightningWalletManager.isConnected,
              let nodeId = coreLightningWalletManager.activeNodeIdentifier() else {
            unseenTransactionIDs = []
            return
        }

        do {
            let rows = try await coreLightningWalletManager.fetchTransactionRows()
            reconcile(with: rows, scope: "core-lightning:\(nodeId)")
        } catch {
            // Leave the current badge state alone if refresh fails.
        }
    }

    func refreshIfPossible(eclairWalletManager: EclairWalletManager) async {
        guard eclairWalletManager.isConnected,
              let nodeId = eclairWalletManager.activeNodeIdentifier() else {
            unseenTransactionIDs = []
            return
        }

        do {
            let rows = try await eclairWalletManager.fetchTransactionRows()
            reconcile(with: rows, scope: "eclair:\(nodeId)")
        } catch {
            // Leave the current badge state alone if refresh fails.
        }
    }

    func refreshSparkSubwalletIfPossible(
        sparkSubwalletManager: SparkSubwalletManager,
        walletManager: WalletManager
    ) async {
        guard sparkSubwalletManager.isConnected,
              let walletId = sparkSubwalletManager.connectedWallet?.id else {
            unseenTransactionIDs = []
            return
        }

        do {
            let rows = try await sparkSubwalletManager.fetchTransactionRows(mapper: walletManager)
            reconcile(with: rows, scope: "spark-subwallet:\(walletId)")
        } catch {
            // Leave the current badge state alone if refresh fails.
        }
    }

    func reconcile(with rows: [WalletManager.TransactionRow], scope: String = "spark") {
        let currentIDs = badgeEligibleTransactionIDs(from: rows)

        if !hasSeededSeenTransactions(scope: scope) {
            persistSeenTransactionIDs(currentIDs, scope: scope)
            setHasSeededSeenTransactions(true, scope: scope)
            unseenTransactionIDs = []
            return
        }

        let persistedSeenIDs = loadSeenTransactionIDs(scope: scope)
        let prunedSeenIDs = persistedSeenIDs.intersection(currentIDs)

        if prunedSeenIDs != persistedSeenIDs {
            persistSeenTransactionIDs(prunedSeenIDs, scope: scope)
        }

        unseenTransactionIDs = currentIDs.subtracting(prunedSeenIDs)
    }

    func captureVisibleUnseenAndMarkSeen(
        _ rows: [WalletManager.TransactionRow],
        scope: String = "spark"
    ) -> Set<String> {
        let currentIDs = badgeEligibleTransactionIDs(from: rows)
        let visibleUnseenIDs = unseenTransactionIDs.intersection(currentIDs)

        markSeen(currentIDs, scope: scope)

        return visibleUnseenIDs
    }

    func markSeen(_ ids: Set<String>, scope: String = "spark") {
        guard !ids.isEmpty else { return }

        var seenIDs = loadSeenTransactionIDs(scope: scope)
        seenIDs.formUnion(ids)
        persistSeenTransactionIDs(seenIDs, scope: scope)
        unseenTransactionIDs.subtract(ids)
    }

    private func hasSeededSeenTransactions(scope: String) -> Bool {
        UserDefaults.standard.bool(forKey: hasSeededSeenTransactionsKey(for: scope))
    }

    private func badgeEligibleTransactionIDs(
        from rows: [WalletManager.TransactionRow]
    ) -> Set<String> {
        Set(
            rows
                .filter(\.isBadgeEligibleTransactionActivity)
                .map(\.id)
        )
    }

    private func setHasSeededSeenTransactions(_ value: Bool, scope: String) {
        UserDefaults.standard.set(value, forKey: hasSeededSeenTransactionsKey(for: scope))
    }

    private func loadSeenTransactionIDs(scope: String) -> Set<String> {
        let storedIDs = UserDefaults.standard.stringArray(forKey: seenTransactionIDsKey(for: scope)) ?? []
        return Set(storedIDs)
    }

    private func persistSeenTransactionIDs(_ ids: Set<String>, scope: String) {
        UserDefaults.standard.set(Array(ids), forKey: seenTransactionIDsKey(for: scope))
    }

    private func seenTransactionIDsKey(for scope: String) -> String {
        scope == "spark" ? seenTransactionIDsKey : "\(seenTransactionIDsKey).\(scope)"
    }

    private func hasSeededSeenTransactionsKey(for scope: String) -> String {
        scope == "spark" ? hasSeededSeenTransactionsKey : "\(hasSeededSeenTransactionsKey).\(scope)"
    }
}

extension Notification.Name {
    static let walletTransactionsDidChange = Notification.Name("walletTransactionsDidChange")
}

private extension WalletManager.TransactionRow {
    var isBadgeEligibleTransactionActivity: Bool {
        let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedStatus.isEmpty else { return false }

        return normalizedStatus.localizedCaseInsensitiveContains("complete") ||
            normalizedStatus.localizedCaseInsensitiveContains("succeed") ||
            normalizedStatus.localizedCaseInsensitiveContains("fail")
    }
}
