//  TransactionsView.swift
//  Split Rewards
//
//  Created by TeeVee on 12/17/25.
//
import SwiftUI
import UIKit

private enum TransactionWalletSource: Equatable {
    case spark
    case external(kind: ExternalWalletKind, id: String)

    var emptyMessage: String {
        switch self {
        case .spark:
            return "No Spark transactions yet."
        case let .external(kind, _):
            return "No \(kind.displayName) transactions yet."
        }
    }

    var title: String {
        switch self {
        case .spark:
            return "Split"
        case let .external(kind, id):
            return ExternalWalletStore.shared.loadWallet(kind: kind, id: id)?.label ?? kind.displayName
        }
    }

    var subtitle: String {
        switch self {
        case .spark:
            return "Root Spark wallet"
        case let .external(kind, _):
            return kind.displayName
        }
    }

    var isLND: Bool {
        if case let .external(kind, _) = self {
            return kind == .lnd
        }

        return false
    }

    var isNWC: Bool {
        if case let .external(kind, _) = self {
            return kind == .nwc
        }

        return false
    }

    var isCoreLightning: Bool {
        if case let .external(kind, _) = self {
            return kind == .coreLightning
        }

        return false
    }

    var isEclair: Bool {
        if case let .external(kind, _) = self {
            return kind == .eclair
        }

        return false
    }

    var isSparkSubwallet: Bool {
        if case let .external(kind, _) = self {
            return kind == .sparkSubwallet
        }

        return false
    }

    var lndWalletId: String? {
        if case let .external(kind, id) = self, kind == .lnd {
            return id
        }

        return nil
    }

    var nwcWalletId: String? {
        if case let .external(kind, id) = self, kind == .nwc {
            return id
        }

        return nil
    }

    var coreLightningWalletId: String? {
        if case let .external(kind, id) = self, kind == .coreLightning {
            return id
        }

        return nil
    }

    var eclairWalletId: String? {
        if case let .external(kind, id) = self, kind == .eclair {
            return id
        }

        return nil
    }

    var sparkSubwalletId: String? {
        if case let .external(kind, id) = self, kind == .sparkSubwallet {
            return id
        }

        return nil
    }
}

private struct TransactionDestinationMetadata {
    let destinationPubkey: String?
    let paymentHash: String?
}

private enum MerchantPubkeyResolutionError: Error {
    case unavailable
}

struct TransactionsView: View {
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var lndWalletManager: LNDWalletManager
    @EnvironmentObject private var nwcWalletManager: NWCWalletManager
    @EnvironmentObject private var coreLightningWalletManager: CoreLightningWalletManager
    @EnvironmentObject private var eclairWalletManager: EclairWalletManager
    @EnvironmentObject private var sparkSubwalletManager: SparkSubwalletManager
    @EnvironmentObject private var activeSpendWalletStore: ActiveSpendWalletStore
    @EnvironmentObject private var authManager: AuthManager

    // Brand
    let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var transactions: [WalletManager.TransactionRow] = []
    @State private var highlightedTransactionIDs: Set<String> = []
    @State private var reportableTransactionIDs: Set<String> = []
    @State private var selectedTransaction: WalletManager.TransactionRow?
    @State private var merchantReportTransaction: WalletManager.TransactionRow?
    @State private var merchantReportErrorMessage: String?
    @State private var reportableTransaction: WalletManager.TransactionRow?
    @State private var reportableTransactionWallet: TransactionWalletSource = .spark
    @State private var selectedTransactionWallet: TransactionWalletSource = .spark
    @State private var displayedTransactionWallet: TransactionWalletSource = .spark
    @State private var hasSeededInitialTransactionWallet = false
    @State private var showTransactionWalletPicker = false
    @State private var refreshGeneration = 0
    @StateObject private var transactionActivityTracker = TransactionActivityTracker.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                header

                transactionWalletSelector

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)

                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.top, 8)

                } else if transactions.isEmpty {
                    Text(selectedTransactionWallet.emptyMessage)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.70))
                        .padding(.top, 8)

                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(transactions) { tx in
                                let transactionWallet = displayedTransactionWallet

                                TransactionCard(
                                    tx: tx,
                                    accentColor: pink,
                                    showsNewActivity: highlightedTransactionIDs.contains(tx.id),
                                    isReportable: reportableTransactionIDs.contains(tx.id),
                                    onOpenDetails: {
                                        selectedTransaction = tx
                                    },
                                    onReportMerchant: {
                                        reportMerchantTapped(tx, walletSource: transactionWallet)
                                    },
                                    onManageReportability: {
                                        reportableTransactionWallet = transactionWallet
                                        reportableTransaction = tx
                                    },
                                    onSaveUserLog: { userLog in
                                        try await saveUserLog(
                                            for: tx,
                                            userLog: userLog,
                                            walletSource: transactionWallet
                                        )
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
        }
        .task {
            seedInitialTransactionWalletIfNeeded()
            await refresh()
        }
        .refreshable { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .walletTransactionsDidChange)) { _ in
            Task {
                await refresh()
            }
        }
        .onDisappear {
            Task {
                await refreshActiveWalletActivity()
            }
        }
        .sheet(item: $selectedTransaction) { tx in
            TransactionDetailView(tx: tx)
        }
        .sheet(item: $merchantReportTransaction) { tx in
            MerchantPubkeyReportSheet(tx: tx)
                .environmentObject(walletManager)
                .environmentObject(authManager)
        }
        .alert("Unable to determine destination pubkey.", isPresented: Binding(
            get: { merchantReportErrorMessage != nil },
            set: { if !$0 { merchantReportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                merchantReportErrorMessage = nil
            }
        } message: {
            Text(merchantReportErrorMessage ?? "")
        }
        .sheet(item: $reportableTransaction) { tx in
            TransactionReportableSheet(
                tx: tx,
                isInitiallyReportable: reportableTransactionIDs.contains(tx.id),
                onStatusChanged: { isReportable in
                    updateReportableStatus(for: tx.id, isReportable: isReportable)
                },
                onPersistStatus: { isReportable in
                    try await saveReportableStatus(
                        for: tx,
                        isReportable: isReportable,
                        walletSource: reportableTransactionWallet
                    )
                }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Transactions")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Spacer(minLength: 0)

            TransactionExportButton(
                transactions: transactions,
                walletManager: walletManager,
                isLndTransactionList: displayedTransactionWallet.isLND,
                isNWCTransactionList: displayedTransactionWallet.isNWC,
                lndWalletId: displayedTransactionWallet.lndWalletId,
                nwcWalletId: displayedTransactionWallet.nwcWalletId,
                isCoreLightningTransactionList: displayedTransactionWallet.isCoreLightning,
                coreLightningWalletId: displayedTransactionWallet.coreLightningWalletId,
                isEclairTransactionList: displayedTransactionWallet.isEclair,
                eclairWalletId: displayedTransactionWallet.eclairWalletId,
                accentColor: pink
            )
        }
    }

    private var transactionWalletSelector: some View {
        Button {
            showTransactionWalletPicker = true
        } label: {
            HStack(spacing: 12) {
                transactionWalletIcon(for: selectedTransactionWallet)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedTransactionWallet.title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(selectedTransactionWallet.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white.opacity(0.68))
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .sheet(isPresented: $showTransactionWalletPicker) {
            TransactionWalletPickerSheet(
                selectedWallet: selectedTransactionWallet,
                wallets: ExternalWalletStore.shared.loadWallets(),
                onSelect: selectTransactionWallet
            )
            .presentationDetents([.fraction(0.74)])
            .presentationDragIndicator(.visible)
        }
    }

    private var hasStoredNode: Bool {
        !LNDCredentialStore.shared.loadNodes().isEmpty
    }

    private var hasStoredNWCWallet: Bool {
        !NWCCredentialStore.shared.loadWallets().isEmpty
    }

    private var hasStoredCoreLightningNode: Bool {
        !CoreLightningCredentialStore.shared.loadNodes().isEmpty
    }

    private var hasStoredSparkSubwallet: Bool {
        !SparkSubwalletCredentialStore.shared.loadWallets().isEmpty
    }

    private var hasExternalTransactionWallet: Bool {
        hasStoredNode || hasStoredNWCWallet || hasStoredCoreLightningNode || hasStoredSparkSubwallet
    }

    private func isTransactionWalletAvailable(_ walletSource: TransactionWalletSource) -> Bool {
        switch walletSource {
        case .spark:
            return true
        case let .external(kind, id):
            return ExternalWalletStore.shared.loadWallet(kind: kind, id: id) != nil
        }
    }

    @ViewBuilder
    private func transactionWalletIcon(for walletSource: TransactionWalletSource) -> some View {
        switch walletSource {
        case .spark:
            Image("SplitLogo")
                .resizable()
                .scaledToFit()
                .padding(7)
        case let .external(kind, _):
            switch kind {
            case .lnd:
                Image(systemName: "bolt.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(blue)
            case .nwc:
                NWCSymbol()
                    .frame(width: 30, height: 30)
            case .coreLightning, .eclair:
                Image(systemName: "bolt.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(blue)
            case .sparkSubwallet:
                Image(systemName: "bolt.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(blue)
            }
        }
    }

    @MainActor
    private func seedInitialTransactionWalletIfNeeded() {
        guard !hasSeededInitialTransactionWallet else { return }

        hasSeededInitialTransactionWallet = true
        if case let .external(kind, id) = activeSpendWalletStore.activeWallet,
           ExternalWalletStore.shared.loadWallet(kind: kind, id: id) != nil {
            selectedTransactionWallet = .external(kind: kind, id: id)
        } else {
            selectedTransactionWallet = .spark
        }
        displayedTransactionWallet = selectedTransactionWallet
    }

    @MainActor
    private func selectTransactionWallet(_ walletSource: TransactionWalletSource) {
        guard isTransactionWalletAvailable(walletSource) else { return }
        guard selectedTransactionWallet != walletSource else { return }

        showTransactionWalletPicker = false
        selectedTransactionWallet = walletSource
        transactions = []
        highlightedTransactionIDs = []
        reportableTransactionIDs = []
        errorMessage = nil

        Task {
            await refresh()
        }
    }

    @MainActor
    private func refreshActiveWalletActivity() async {
        if activeSpendWalletStore.isNWCActive {
            await transactionActivityTracker.refreshIfPossible(nwcWalletManager: nwcWalletManager)
        } else if activeSpendWalletStore.isLndActive {
            await transactionActivityTracker.refreshIfPossible(lndWalletManager: lndWalletManager)
        } else if activeSpendWalletStore.isCoreLightningActive {
            await transactionActivityTracker.refreshIfPossible(coreLightningWalletManager: coreLightningWalletManager)
        } else if activeSpendWalletStore.isEclairActive {
            await transactionActivityTracker.refreshIfPossible(eclairWalletManager: eclairWalletManager)
        } else if activeSpendWalletStore.isSparkSubwalletActive {
            await transactionActivityTracker.refreshSparkSubwalletIfPossible(
                sparkSubwalletManager: sparkSubwalletManager,
                walletManager: walletManager
            )
        } else {
            await transactionActivityTracker.refreshIfPossible(walletManager: walletManager)
        }
    }

    @MainActor
    private func refresh() async {
        if !isTransactionWalletAvailable(selectedTransactionWallet) {
            selectedTransactionWallet = .spark
            displayedTransactionWallet = .spark
        }

        refreshGeneration += 1
        let currentRefreshGeneration = refreshGeneration
        let requestedWalletSource = selectedTransactionWallet

        isLoading = true
        errorMessage = nil

        do {
            let rows: [WalletManager.TransactionRow]
            let userLogs: [String: String]
            let reportableIDs: Set<String>
            let destinationMetadata: [String: TransactionDestinationMetadata]
            let activityScope: String

            if let nodeId = requestedWalletSource.lndWalletId {
                guard let node = LNDCredentialStore.shared.loadNodes().first(where: { $0.id == nodeId }) else {
                    throw LNDWalletError.noStoredNode
                }

                rows = try await lndWalletManager.fetchTransactionRows(for: node)
                let paymentIds = rows.map(\.id)

                await LNDTransactionMetadataStore.shared.ensureUsdSnapshots(
                    for: rows,
                    nodeId: nodeId,
                    currentBtcUsdRate: walletManager.btcUsdRate
                )

                userLogs = await LNDTransactionMetadataStore.shared.userLogs(
                    nodeId: nodeId,
                    transactionIds: paymentIds
                )
                reportableIDs = await loadLNDReportableTransactionIDs(
                    for: rows,
                    nodeId: nodeId
                )
                await captureLNDDestinationMetadata(for: rows, nodeId: nodeId)
                destinationMetadata = await loadLNDDestinationMetadata(for: rows, nodeId: nodeId)
                activityScope = "lnd:\(nodeId)"
            } else if let walletId = requestedWalletSource.nwcWalletId {
                guard let wallet = NWCCredentialStore.shared.loadWallets().first(where: { $0.id == walletId }) else {
                    throw NWCWalletError.noStoredConnection
                }

                rows = try await nwcWalletManager.fetchTransactionRows(for: wallet)
                let paymentIds = rows.map(\.id)

                await NWCTransactionMetadataStore.shared.ensureUsdSnapshots(
                    for: rows,
                    walletId: walletId,
                    currentBtcUsdRate: walletManager.btcUsdRate
                )

                userLogs = await NWCTransactionMetadataStore.shared.userLogs(
                    walletId: walletId,
                    transactionIds: paymentIds
                )
                reportableIDs = await loadNWCReportableTransactionIDs(
                    for: rows,
                    walletId: walletId
                )
                await captureNWCDestinationMetadata(for: rows, walletId: walletId)
                destinationMetadata = await loadNWCDestinationMetadata(for: rows, walletId: walletId)
                activityScope = "nwc:\(walletId)"
            } else if let nodeId = requestedWalletSource.coreLightningWalletId {
                guard let node = CoreLightningCredentialStore.shared.loadNodes().first(where: { $0.id == nodeId }) else {
                    throw CoreLightningWalletError.noStoredNode
                }

                rows = try await coreLightningWalletManager.fetchTransactionRows(for: node)
                let paymentIds = rows.map(\.id)

                await CoreLightningTransactionMetadataStore.ensureUsdSnapshots(
                    for: rows,
                    nodeId: nodeId,
                    currentBtcUsdRate: walletManager.btcUsdRate
                )

                userLogs = await CoreLightningTransactionMetadataStore.userLogs(
                    nodeId: nodeId,
                    transactionIds: paymentIds
                )
                reportableIDs = await loadCoreLightningReportableTransactionIDs(
                    for: rows,
                    nodeId: nodeId
                )
                await captureCoreLightningDestinationMetadata(for: rows, nodeId: nodeId)
                destinationMetadata = await loadCoreLightningDestinationMetadata(for: rows, nodeId: nodeId)
                activityScope = "core-lightning:\(nodeId)"
            } else if let nodeId = requestedWalletSource.eclairWalletId {
                guard let node = EclairCredentialStore.shared.loadNodes().first(where: { $0.id == nodeId }) else {
                    throw EclairWalletError.noStoredNode
                }

                rows = try await eclairWalletManager.fetchTransactionRows(for: node)
                let paymentIds = rows.map(\.id)

                await EclairTransactionMetadataStore.ensureUsdSnapshots(
                    for: rows,
                    nodeId: nodeId,
                    currentBtcUsdRate: walletManager.btcUsdRate
                )

                userLogs = await EclairTransactionMetadataStore.userLogs(
                    nodeId: nodeId,
                    transactionIds: paymentIds
                )
                reportableIDs = await loadEclairReportableTransactionIDs(
                    for: rows,
                    nodeId: nodeId
                )
                await captureEclairDestinationMetadata(for: rows, nodeId: nodeId)
                destinationMetadata = await loadEclairDestinationMetadata(for: rows, nodeId: nodeId)
                activityScope = "eclair:\(nodeId)"
            } else if let walletId = requestedWalletSource.sparkSubwalletId {
                guard SparkSubwalletCredentialStore.shared.loadWallet(id: walletId) != nil else {
                    throw SparkSubwalletError.noStoredWallet
                }

                if sparkSubwalletManager.connectedWallet?.id != walletId || !sparkSubwalletManager.isConnected {
                    try await sparkSubwalletManager.restoreWalletIfNeeded(id: walletId)
                }

                rows = try await sparkSubwalletManager.fetchTransactionRows(mapper: walletManager)
                let paymentIds = rows.map(\.id)

                userLogs = await PaymentUsdSnapshotStore.shared.userLogs(
                    walletPubkey: walletId,
                    paymentIds: paymentIds
                )
                reportableIDs = await loadSparkReportableTransactionIDs(
                    for: rows,
                    walletPubkey: walletId
                )
                await captureSparkDestinationMetadata(for: rows, walletPubkey: walletId)
                destinationMetadata = await loadSparkDestinationMetadata(for: rows, walletPubkey: walletId)
                activityScope = "spark-subwallet:\(walletId)"
            } else {
                rows = try await walletManager.fetchTransactionRowsFromBreez()
                let walletPubkey = try? await MessageKeyManager.shared.currentWalletPubkey(walletManager: walletManager)
                let paymentIds = rows.map(\.id)

                if let walletPubkey {
                    userLogs = await PaymentUsdSnapshotStore.shared.userLogs(
                        walletPubkey: walletPubkey,
                        paymentIds: paymentIds
                    )
                } else {
                    userLogs = [:]
                }

                reportableIDs = await loadSparkReportableTransactionIDs(
                    for: rows,
                    walletPubkey: walletPubkey
                )
                if let walletPubkey {
                    await captureSparkDestinationMetadata(for: rows, walletPubkey: walletPubkey)
                    destinationMetadata = await loadSparkDestinationMetadata(for: rows, walletPubkey: walletPubkey)
                } else {
                    destinationMetadata = [:]
                }
                activityScope = "spark"
            }

            guard currentRefreshGeneration == refreshGeneration,
                  selectedTransactionWallet == requestedWalletSource else {
                return
            }

            transactions = rows.map { row in
                let metadata = destinationMetadata[row.id]
                return row
                    .withUserLog(userLogs[row.id])
                    .withDestinationMetadata(
                        destinationPubkey: metadata?.destinationPubkey,
                        paymentHash: metadata?.paymentHash
                    )
            }
            displayedTransactionWallet = requestedWalletSource
            transactionActivityTracker.reconcile(with: rows, scope: activityScope)
            highlightedTransactionIDs.formUnion(
                transactionActivityTracker.captureVisibleUnseenAndMarkSeen(rows, scope: activityScope)
            )
            reportableTransactionIDs = reportableIDs
        } catch {
            guard currentRefreshGeneration == refreshGeneration,
                  selectedTransactionWallet == requestedWalletSource else {
                return
            }

            errorMessage = failedTransactionLoadMessage(for: requestedWalletSource, error: error)
        }

        isLoading = false
    }

    @MainActor
    private func loadSparkReportableTransactionIDs(
        for rows: [WalletManager.TransactionRow],
        walletPubkey: String?
    ) async -> Set<String> {
        guard let walletPubkey else {
            return []
        }

        let reportableStates = await PaymentUsdSnapshotStore.shared.reportableStates(
            walletPubkey: walletPubkey,
            paymentIds: rows.map(\.id)
        )

        return Set(
            reportableStates.compactMap { paymentId, isReportable in
                isReportable ? paymentId : nil
            }
        )
    }

    @MainActor
    private func captureSparkDestinationMetadata(
        for rows: [WalletManager.TransactionRow],
        walletPubkey: String
    ) async {
        for row in rows where row.direction.lowercased() == "sent" {
            await PaymentUsdSnapshotStore.shared.setDestinationMetadata(
                walletPubkey: walletPubkey,
                paymentId: row.id,
                paymentType: .sent,
                destinationPubkey: row.destinationPubkey,
                paymentHash: row.paymentHash
            )
        }
    }

    @MainActor
    private func loadSparkDestinationMetadata(
        for rows: [WalletManager.TransactionRow],
        walletPubkey: String
    ) async -> [String: TransactionDestinationMetadata] {
        let snapshots = await PaymentUsdSnapshotStore.shared.snapshots(
            walletPubkey: walletPubkey,
            paymentIds: rows.map(\.id)
        )

        return snapshots.reduce(into: [String: TransactionDestinationMetadata]()) { partialResult, entry in
            partialResult[entry.key] = TransactionDestinationMetadata(
                destinationPubkey: entry.value.destinationPubkey,
                paymentHash: entry.value.paymentHash
            )
        }
    }

    @MainActor
    private func loadLNDReportableTransactionIDs(
        for rows: [WalletManager.TransactionRow],
        nodeId: String
    ) async -> Set<String> {
        let reportableStates = await LNDTransactionMetadataStore.shared.reportableStates(
            nodeId: nodeId,
            transactionIds: rows.map(\.id)
        )

        return Set(
            reportableStates.compactMap { transactionId, isReportable in
                isReportable ? transactionId : nil
            }
        )
    }

    @MainActor
    private func captureLNDDestinationMetadata(
        for rows: [WalletManager.TransactionRow],
        nodeId: String
    ) async {
        for row in rows where row.direction.lowercased() == "sent" {
            await LNDTransactionMetadataStore.shared.setDestinationMetadata(
                nodeId: nodeId,
                transactionId: row.id,
                transactionType: .sent,
                destinationPubkey: row.destinationPubkey,
                paymentHash: row.paymentHash
            )
        }
    }

    @MainActor
    private func loadLNDDestinationMetadata(
        for rows: [WalletManager.TransactionRow],
        nodeId: String
    ) async -> [String: TransactionDestinationMetadata] {
        let metadata = await LNDTransactionMetadataStore.shared.metadata(
            nodeId: nodeId,
            transactionIds: rows.map(\.id)
        )

        return metadata.reduce(into: [String: TransactionDestinationMetadata]()) { partialResult, entry in
            partialResult[entry.key] = TransactionDestinationMetadata(
                destinationPubkey: entry.value.destinationPubkey,
                paymentHash: entry.value.paymentHash
            )
        }
    }

    @MainActor
    private func loadNWCReportableTransactionIDs(
        for rows: [WalletManager.TransactionRow],
        walletId: String
    ) async -> Set<String> {
        let reportableStates = await NWCTransactionMetadataStore.shared.reportableStates(
            walletId: walletId,
            transactionIds: rows.map(\.id)
        )

        return Set(
            reportableStates.compactMap { transactionId, isReportable in
                isReportable ? transactionId : nil
            }
        )
    }

    @MainActor
    private func captureNWCDestinationMetadata(
        for rows: [WalletManager.TransactionRow],
        walletId: String
    ) async {
        for row in rows where row.direction.lowercased() == "sent" {
            await NWCTransactionMetadataStore.shared.setDestinationMetadata(
                walletId: walletId,
                transactionId: row.id,
                transactionType: .sent,
                destinationPubkey: row.destinationPubkey,
                paymentHash: row.paymentHash
            )
        }
    }

    @MainActor
    private func loadNWCDestinationMetadata(
        for rows: [WalletManager.TransactionRow],
        walletId: String
    ) async -> [String: TransactionDestinationMetadata] {
        let metadata = await NWCTransactionMetadataStore.shared.metadata(
            walletId: walletId,
            transactionIds: rows.map(\.id)
        )

        return metadata.reduce(into: [String: TransactionDestinationMetadata]()) { partialResult, entry in
            partialResult[entry.key] = TransactionDestinationMetadata(
                destinationPubkey: entry.value.destinationPubkey,
                paymentHash: entry.value.paymentHash
            )
        }
    }

    @MainActor
    private func loadCoreLightningReportableTransactionIDs(
        for rows: [WalletManager.TransactionRow],
        nodeId: String
    ) async -> Set<String> {
        let reportableStates = await CoreLightningTransactionMetadataStore.reportableStates(
            nodeId: nodeId,
            transactionIds: rows.map(\.id)
        )

        return Set(
            reportableStates.compactMap { transactionId, isReportable in
                isReportable ? transactionId : nil
            }
        )
    }

    @MainActor
    private func captureCoreLightningDestinationMetadata(
        for rows: [WalletManager.TransactionRow],
        nodeId: String
    ) async {
        for row in rows where row.direction.lowercased() == "sent" {
            await CoreLightningTransactionMetadataStore.setDestinationMetadata(
                nodeId: nodeId,
                transactionId: row.id,
                transactionType: .sent,
                destinationPubkey: row.destinationPubkey,
                paymentHash: row.paymentHash
            )
        }
    }

    @MainActor
    private func loadCoreLightningDestinationMetadata(
        for rows: [WalletManager.TransactionRow],
        nodeId: String
    ) async -> [String: TransactionDestinationMetadata] {
        let metadata = await CoreLightningTransactionMetadataStore.metadata(
            nodeId: nodeId,
            transactionIds: rows.map(\.id)
        )

        return metadata.reduce(into: [String: TransactionDestinationMetadata]()) { partialResult, entry in
            partialResult[entry.key] = TransactionDestinationMetadata(
                destinationPubkey: entry.value.destinationPubkey,
                paymentHash: entry.value.paymentHash
            )
        }
    }

    @MainActor
    private func loadEclairReportableTransactionIDs(
        for rows: [WalletManager.TransactionRow],
        nodeId: String
    ) async -> Set<String> {
        let reportableStates = await EclairTransactionMetadataStore.reportableStates(
            nodeId: nodeId,
            transactionIds: rows.map(\.id)
        )

        return Set(
            reportableStates.compactMap { transactionId, isReportable in
                isReportable ? transactionId : nil
            }
        )
    }

    @MainActor
    private func captureEclairDestinationMetadata(
        for rows: [WalletManager.TransactionRow],
        nodeId: String
    ) async {
        for row in rows where row.direction.lowercased() == "sent" {
            await EclairTransactionMetadataStore.setDestinationMetadata(
                nodeId: nodeId,
                transactionId: row.id,
                transactionType: .sent,
                destinationPubkey: row.destinationPubkey,
                paymentHash: row.paymentHash
            )
        }
    }

    @MainActor
    private func loadEclairDestinationMetadata(
        for rows: [WalletManager.TransactionRow],
        nodeId: String
    ) async -> [String: TransactionDestinationMetadata] {
        let metadata = await EclairTransactionMetadataStore.metadata(
            nodeId: nodeId,
            transactionIds: rows.map(\.id)
        )

        return metadata.reduce(into: [String: TransactionDestinationMetadata]()) { partialResult, entry in
            partialResult[entry.key] = TransactionDestinationMetadata(
                destinationPubkey: entry.value.destinationPubkey,
                paymentHash: entry.value.paymentHash
            )
        }
    }

    @MainActor
    private func updateReportableStatus(for paymentId: String, isReportable: Bool) {
        if isReportable {
            reportableTransactionIDs.insert(paymentId)
        } else {
            reportableTransactionIDs.remove(paymentId)
        }
    }

    @MainActor
    private func updateUserLog(for paymentId: String, userLog: String?) {
        transactions = transactions.map { row in
            row.id == paymentId ? row.withUserLog(userLog) : row
        }

        if let selectedTransaction, selectedTransaction.id == paymentId {
            self.selectedTransaction = selectedTransaction.withUserLog(userLog)
        }
    }

    @MainActor
    private func reportMerchantTapped(_ tx: WalletManager.TransactionRow, walletSource: TransactionWalletSource) {
        Task {
            do {
                let destinationPubkey = try await resolveDestinationPubkey(for: tx, walletSource: walletSource)
                let enrichedTransaction = tx.withDestinationMetadata(
                    destinationPubkey: destinationPubkey,
                    paymentHash: tx.paymentHash
                )
                await persistDestinationMetadata(for: enrichedTransaction, walletSource: walletSource)
                merchantReportTransaction = enrichedTransaction
            } catch {
                merchantReportErrorMessage = "Unable to determine destination pubkey."
            }
        }
    }

    @MainActor
    private func resolveDestinationPubkey(
        for tx: WalletManager.TransactionRow,
        walletSource: TransactionWalletSource
    ) async throws -> String {
        if let destinationPubkey = tx.destinationPubkey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            return destinationPubkey
        }

        if let metadata = await storedDestinationMetadata(for: tx, walletSource: walletSource),
           let destinationPubkey = metadata.destinationPubkey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            return destinationPubkey
        }

        if let invoicePubkey = tx.invoice.flatMap({ NWCBolt11MetadataDecoder.decode($0)?.destinationPubkey?.nilIfBlank }) {
            return invoicePubkey
        }

        if let resolved = try await resolveDestinationPubkeyFromWallet(for: tx, walletSource: walletSource) {
            return resolved
        }

        throw MerchantPubkeyResolutionError.unavailable
    }

    @MainActor
    private func storedDestinationMetadata(
        for tx: WalletManager.TransactionRow,
        walletSource: TransactionWalletSource
    ) async -> TransactionDestinationMetadata? {
        if let nodeId = walletSource.lndWalletId {
            return await loadLNDDestinationMetadata(for: [tx], nodeId: nodeId)[tx.id]
        }

        if let walletId = walletSource.nwcWalletId {
            return await loadNWCDestinationMetadata(for: [tx], walletId: walletId)[tx.id]
        }

        if let nodeId = walletSource.coreLightningWalletId {
            return await loadCoreLightningDestinationMetadata(for: [tx], nodeId: nodeId)[tx.id]
        }

        if let nodeId = walletSource.eclairWalletId {
            return await loadEclairDestinationMetadata(for: [tx], nodeId: nodeId)[tx.id]
        }

        if let walletId = walletSource.sparkSubwalletId {
            return await loadSparkDestinationMetadata(for: [tx], walletPubkey: walletId)[tx.id]
        }

        guard let walletPubkey = try? await MessageKeyManager.shared.currentWalletPubkey(walletManager: walletManager) else {
            return nil
        }

        return await loadSparkDestinationMetadata(for: [tx], walletPubkey: walletPubkey)[tx.id]
    }

    @MainActor
    private func resolveDestinationPubkeyFromWallet(
        for tx: WalletManager.TransactionRow,
        walletSource: TransactionWalletSource
    ) async throws -> String? {
        if let nodeId = walletSource.lndWalletId,
           let node = LNDCredentialStore.shared.loadNodes().first(where: { $0.id == nodeId }) {
            let rows = try await lndWalletManager.fetchTransactionRows(for: node)
            return matchingTransaction(in: rows, for: tx)?.destinationPubkey?.nilIfBlank
        }

        if let walletId = walletSource.nwcWalletId,
           let wallet = NWCCredentialStore.shared.loadWallets().first(where: { $0.id == walletId }) {
            let rows = try await nwcWalletManager.fetchTransactionRows(for: wallet)
            if let destinationPubkey = matchingTransaction(in: rows, for: tx)?.destinationPubkey?.nilIfBlank {
                return destinationPubkey
            }

            if let paymentHash = tx.paymentHash?.nilIfBlank ?? tx.txReference?.nilIfBlank {
                let invoice = try await NWCCommandClient(wallet: wallet).lookupInvoice(paymentHash: paymentHash)
                return invoice.invoice.flatMap { NWCBolt11MetadataDecoder.decode($0)?.destinationPubkey?.nilIfBlank }
            }
        }

        if let nodeId = walletSource.coreLightningWalletId,
           let node = CoreLightningCredentialStore.shared.loadNodes().first(where: { $0.id == nodeId }) {
            let rows = try await coreLightningWalletManager.fetchTransactionRows(for: node)
            return matchingTransaction(in: rows, for: tx)?.destinationPubkey?.nilIfBlank
        }

        if let nodeId = walletSource.eclairWalletId,
           let node = EclairCredentialStore.shared.loadNodes().first(where: { $0.id == nodeId }) {
            let rows = try await eclairWalletManager.fetchTransactionRows(for: node)
            if let destinationPubkey = matchingTransaction(in: rows, for: tx)?.destinationPubkey?.nilIfBlank {
                return destinationPubkey
            }

            if let paymentHash = tx.paymentHash?.nilIfBlank ?? tx.txReference?.nilIfBlank {
                let sentPayments = try await EclairRestClient(credentials: node).getSentInfo(paymentHash: paymentHash)
                for payment in sentPayments {
                    if let invoice = payment.payment?.serialized,
                       let destinationPubkey = try? await EclairRestClient(credentials: node).parseInvoice(invoice).nodeId?.nilIfBlank {
                        return destinationPubkey
                    }
                }
            }
        }

        return nil
    }

    private func matchingTransaction(
        in rows: [WalletManager.TransactionRow],
        for tx: WalletManager.TransactionRow
    ) -> WalletManager.TransactionRow? {
        rows.first { row in
            row.id == tx.id
                || (row.paymentHash?.nilIfBlank != nil && row.paymentHash?.nilIfBlank == tx.paymentHash?.nilIfBlank)
                || (row.txReference?.nilIfBlank != nil && row.txReference?.nilIfBlank == tx.txReference?.nilIfBlank)
        }
    }

    @MainActor
    private func persistDestinationMetadata(
        for tx: WalletManager.TransactionRow,
        walletSource: TransactionWalletSource
    ) async {
        if let nodeId = walletSource.lndWalletId {
            await LNDTransactionMetadataStore.shared.setDestinationMetadata(
                nodeId: nodeId,
                transactionId: tx.id,
                transactionType: .sent,
                destinationPubkey: tx.destinationPubkey,
                paymentHash: tx.paymentHash
            )
            return
        }

        if let walletId = walletSource.nwcWalletId {
            await NWCTransactionMetadataStore.shared.setDestinationMetadata(
                walletId: walletId,
                transactionId: tx.id,
                transactionType: .sent,
                destinationPubkey: tx.destinationPubkey,
                paymentHash: tx.paymentHash
            )
            return
        }

        if let nodeId = walletSource.coreLightningWalletId {
            await CoreLightningTransactionMetadataStore.setDestinationMetadata(
                nodeId: nodeId,
                transactionId: tx.id,
                transactionType: .sent,
                destinationPubkey: tx.destinationPubkey,
                paymentHash: tx.paymentHash
            )
            return
        }

        if let nodeId = walletSource.eclairWalletId {
            await EclairTransactionMetadataStore.setDestinationMetadata(
                nodeId: nodeId,
                transactionId: tx.id,
                transactionType: .sent,
                destinationPubkey: tx.destinationPubkey,
                paymentHash: tx.paymentHash
            )
            return
        }

        if let walletId = walletSource.sparkSubwalletId {
            await PaymentUsdSnapshotStore.shared.setDestinationMetadata(
                walletPubkey: walletId,
                paymentId: tx.id,
                paymentType: .sent,
                destinationPubkey: tx.destinationPubkey,
                paymentHash: tx.paymentHash
            )
            return
        }

        guard let walletPubkey = try? await MessageKeyManager.shared.currentWalletPubkey(walletManager: walletManager) else {
            return
        }

        await PaymentUsdSnapshotStore.shared.setDestinationMetadata(
            walletPubkey: walletPubkey,
            paymentId: tx.id,
            paymentType: .sent,
            destinationPubkey: tx.destinationPubkey,
            paymentHash: tx.paymentHash
        )
    }

    @MainActor
    private func saveUserLog(
        for tx: WalletManager.TransactionRow,
        userLog: String?,
        walletSource: TransactionWalletSource
    ) async throws {
        let normalizedUserLog = TransactionUserLogNormalizer.normalized(userLog)

        if let nodeId = walletSource.lndWalletId {
            guard LNDCredentialStore.shared.loadNodes().contains(where: { $0.id == nodeId }) else {
                throw LNDWalletError.noStoredNode
            }

            await LNDTransactionMetadataStore.shared.setUserLog(
                nodeId: nodeId,
                transactionId: tx.id,
                transactionType: tx.direction.lowercased() == "received" ? .received : .sent,
                userLog: normalizedUserLog
            )

            updateUserLog(for: tx.id, userLog: normalizedUserLog)
            return
        }

        if let walletId = walletSource.nwcWalletId {
            guard NWCCredentialStore.shared.loadWallets().contains(where: { $0.id == walletId }) else {
                throw NWCWalletError.noStoredConnection
            }

            await NWCTransactionMetadataStore.shared.setUserLog(
                walletId: walletId,
                transactionId: tx.id,
                transactionType: tx.direction.lowercased() == "received" ? .received : .sent,
                userLog: normalizedUserLog
            )

            updateUserLog(for: tx.id, userLog: normalizedUserLog)
            return
        }

        if let nodeId = walletSource.coreLightningWalletId {
            guard CoreLightningCredentialStore.shared.loadNodes().contains(where: { $0.id == nodeId }) else {
                throw CoreLightningWalletError.noStoredNode
            }

            await CoreLightningTransactionMetadataStore.setUserLog(
                nodeId: nodeId,
                transactionId: tx.id,
                transactionType: tx.direction.lowercased() == "received" ? .received : .sent,
                userLog: normalizedUserLog
            )

            updateUserLog(for: tx.id, userLog: normalizedUserLog)
            return
        }

        if let nodeId = walletSource.eclairWalletId {
            guard EclairCredentialStore.shared.loadNodes().contains(where: { $0.id == nodeId }) else {
                throw EclairWalletError.noStoredNode
            }

            await EclairTransactionMetadataStore.setUserLog(
                nodeId: nodeId,
                transactionId: tx.id,
                transactionType: tx.direction.lowercased() == "received" ? .received : .sent,
                userLog: normalizedUserLog
            )

            updateUserLog(for: tx.id, userLog: normalizedUserLog)
            return
        }

        if let walletId = walletSource.sparkSubwalletId {
            guard SparkSubwalletCredentialStore.shared.loadWallet(id: walletId) != nil else {
                throw SparkSubwalletError.noStoredWallet
            }

            await PaymentUsdSnapshotStore.shared.setUserLog(
                walletPubkey: walletId,
                paymentId: tx.id,
                paymentType: tx.direction.lowercased() == "received" ? .received : .sent,
                userLog: normalizedUserLog
            )

            updateUserLog(for: tx.id, userLog: normalizedUserLog)
            return
        }

        let walletPubkey = try await MessageKeyManager.shared.currentWalletPubkey(walletManager: walletManager)
        await PaymentUsdSnapshotStore.shared.setUserLog(
            walletPubkey: walletPubkey,
            paymentId: tx.id,
            paymentType: tx.direction.lowercased() == "received" ? .received : .sent,
            userLog: normalizedUserLog
        )

        updateUserLog(for: tx.id, userLog: normalizedUserLog)
    }

    @MainActor
    private func saveReportableStatus(
        for tx: WalletManager.TransactionRow,
        isReportable: Bool,
        walletSource: TransactionWalletSource
    ) async throws {
        if let nodeId = walletSource.lndWalletId {
            guard LNDCredentialStore.shared.loadNodes().contains(where: { $0.id == nodeId }) else {
                throw LNDWalletError.noStoredNode
            }

            await LNDTransactionMetadataStore.shared.setReportable(
                nodeId: nodeId,
                transactionId: tx.id,
                transactionType: tx.direction.lowercased() == "received" ? .received : .sent,
                isReportable: isReportable
            )
            return
        }

        if let walletId = walletSource.nwcWalletId {
            guard NWCCredentialStore.shared.loadWallets().contains(where: { $0.id == walletId }) else {
                throw NWCWalletError.noStoredConnection
            }

            await NWCTransactionMetadataStore.shared.setReportable(
                walletId: walletId,
                transactionId: tx.id,
                transactionType: tx.direction.lowercased() == "received" ? .received : .sent,
                isReportable: isReportable
            )
            return
        }

        if let nodeId = walletSource.coreLightningWalletId {
            guard CoreLightningCredentialStore.shared.loadNodes().contains(where: { $0.id == nodeId }) else {
                throw CoreLightningWalletError.noStoredNode
            }

            await CoreLightningTransactionMetadataStore.setReportable(
                nodeId: nodeId,
                transactionId: tx.id,
                transactionType: tx.direction.lowercased() == "received" ? .received : .sent,
                isReportable: isReportable
            )
            return
        }

        if let nodeId = walletSource.eclairWalletId {
            guard EclairCredentialStore.shared.loadNodes().contains(where: { $0.id == nodeId }) else {
                throw EclairWalletError.noStoredNode
            }

            await EclairTransactionMetadataStore.setReportable(
                nodeId: nodeId,
                transactionId: tx.id,
                transactionType: tx.direction.lowercased() == "received" ? .received : .sent,
                isReportable: isReportable
            )
            return
        }

        if let walletId = walletSource.sparkSubwalletId {
            guard SparkSubwalletCredentialStore.shared.loadWallet(id: walletId) != nil else {
                throw SparkSubwalletError.noStoredWallet
            }

            await PaymentUsdSnapshotStore.shared.setReportable(
                walletPubkey: walletId,
                paymentId: tx.id,
                paymentType: tx.direction.lowercased() == "received" ? .received : .sent,
                isReportable: isReportable
            )
            return
        }

        let walletPubkey = try await MessageKeyManager.shared.currentWalletPubkey(walletManager: walletManager)
        await PaymentUsdSnapshotStore.shared.setReportable(
            walletPubkey: walletPubkey,
            paymentId: tx.id,
            paymentType: tx.direction.lowercased() == "received" ? .received : .sent,
            isReportable: isReportable
        )
    }

    private func failedTransactionLoadMessage(for walletSource: TransactionWalletSource, error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        switch walletSource {
        case .spark:
            return "Failed to load Spark transactions."
        case let .external(kind, _):
            return "Failed to load \(kind.displayName) transactions."
        }
    }
}

private struct TransactionWalletPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedWallet: TransactionWalletSource
    let wallets: [ExternalWalletRecord]
    let onSelect: (TransactionWalletSource) -> Void

    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    var body: some View {
        ZStack {
            Color.splitSoftBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transaction Wallet")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Choose which wallet's history you want to view.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.62))
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        walletRow(
                            title: "Split",
                            subtitle: "Root Spark wallet",
                            icon: {
                                Image("SplitLogo")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(8)
                            },
                            isSelected: selectedWallet == .spark,
                            action: {
                                onSelect(.spark)
                                dismiss()
                            }
                        )

                        ForEach(wallets) { wallet in
                            let source = TransactionWalletSource.external(kind: wallet.kind, id: wallet.id)

                            walletRow(
                                title: wallet.label,
                                subtitle: wallet.kind.displayName,
                                icon: {
                                    walletIcon(for: wallet.kind)
                                },
                                isSelected: selectedWallet == source,
                                action: {
                                    onSelect(source)
                                    dismiss()
                                }
                            )
                        }
                    }
                    .padding(.bottom, 28)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
        }
    }

    private func walletRow<Icon: View>(
        title: String,
        subtitle: String,
        @ViewBuilder icon: () -> Icon,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)

                    icon()
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.bold))
                    .foregroundColor(isSelected ? pink : .white.opacity(0.30))
            }
            .padding(14)
            .background(Color.splitInputSurfaceTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? pink.opacity(0.80) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func walletIcon(for kind: ExternalWalletKind) -> some View {
        switch kind {
        case .lnd:
            Image(systemName: "bolt.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(blue)
        case .nwc:
            NWCSymbol()
                .frame(width: 32, height: 32)
        case .coreLightning, .eclair:
            Image(systemName: "bolt.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(blue)
        case .sparkSubwallet:
            Image(systemName: "bolt.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(blue)
        }
    }
}

private struct TransactionCard: View {
    let tx: WalletManager.TransactionRow
    let accentColor: Color
    let showsNewActivity: Bool
    let isReportable: Bool
    let onOpenDetails: () -> Void
    let onReportMerchant: () -> Void
    let onManageReportability: () -> Void
    let onSaveUserLog: (String?) async throws -> Void

    @State private var userLogText: String
    @State private var savedUserLog: String?
    @State private var userLogSaveError: String?
    @State private var isSavingUserLog = false
    @FocusState private var isUserLogFocused: Bool

    init(
        tx: WalletManager.TransactionRow,
        accentColor: Color,
        showsNewActivity: Bool,
        isReportable: Bool,
        onOpenDetails: @escaping () -> Void,
        onReportMerchant: @escaping () -> Void,
        onManageReportability: @escaping () -> Void,
        onSaveUserLog: @escaping (String?) async throws -> Void
    ) {
        self.tx = tx
        self.accentColor = accentColor
        self.showsNewActivity = showsNewActivity
        self.isReportable = isReportable
        self.onOpenDetails = onOpenDetails
        self.onReportMerchant = onReportMerchant
        self.onManageReportability = onManageReportability
        self.onSaveUserLog = onSaveUserLog

        let normalizedUserLog = TransactionUserLogNormalizer.normalized(tx.userLog)
        _userLogText = State(initialValue: normalizedUserLog ?? "")
        _savedUserLog = State(initialValue: normalizedUserLog)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                topLine

                Divider()
                    .background(Color.white.opacity(0.10))
                    .opacity(0.35)

                VStack(alignment: .leading, spacing: 8) {
                    infoRow(label: "Status", value: tx.status)
                    infoRow(label: "Network", value: tx.network.capitalized)
                    infoRow(label: "Date", value: tx.dateString)

                    if !cardNoteText.isEmpty {
                        infoRow(label: "Memo", value: cardNoteText)
                    }

                    if tx.feeSats > 0 {
                        infoRow(label: "Fee (BTC)", value: tx.feeBtcAmount)
                    }

                    HStack {
                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .padding(.top, 4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenDetails)

            compactUserLogField
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    showsNewActivity
                        ? Color.splitBrandBlue.opacity(0.78)
                        : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
        .shadow(
            color: showsNewActivity
                ? Color.splitBrandBlue.opacity(0.14)
                : .clear,
            radius: 10,
            x: 0,
            y: 4
        )
        .onChange(of: userLogText) { _, _ in
            userLogSaveError = nil
        }
        .onChange(of: isUserLogFocused) { _, isFocused in
            if !isFocused {
                saveUserLog()
            }
        }
        .onChange(of: tx.userLog) { _, newValue in
            syncUserLog(with: newValue)
        }
    }

    private var cardBackground: some View {
        ZStack {
            Color.white.opacity(0.06)

            LinearGradient(
                colors: [
                    (showsNewActivity ? Color.splitBrandBlue : accentColor).opacity(0.12),
                    Color.white.opacity(0.02),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.55)
        }
    }

    private var topLine: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tx.direction.capitalized)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                if let sentLightningAddressLine {
                    Text(sentLightningAddressLine)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                }

                Text(signedAmountText)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if canReportMerchant {
                    Button(action: onReportMerchant) {
                        Image(systemName: "storefront.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color.white)
                            .padding(7)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add merchant for rewards")
                }

                if canManageReportableStatus {
                    Button(action: onManageReportability) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isReportable ? accentColor : Color.white.opacity(0.88))
                            .padding(8)
                            .background(isReportable ? accentColor.opacity(0.18) : Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isReportable ? "Edit reportable status" : "Mark transaction as reportable")
                }
            }
        }
    }

    private var isSent: Bool {
        tx.direction.lowercased() == "sent"
    }

    private var canManageReportableStatus: Bool {
        isSent && tx.status == "Completed"
    }

    private var cardNoteText: String {
        if !isSent,
           let senderComment = tx.senderComment?.trimmingCharacters(in: .whitespacesAndNewlines),
           !senderComment.isEmpty {
            return senderComment
        }

        return tx.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var signedAmountText: String {
        let sign = isSent ? "−" : "+"
        return "\(sign)\(tx.btcAmount) BTC"
    }

    private var sentLightningAddressLine: String? {
        guard isSent else { return nil }
        guard let lnAddress = tx.lnAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lnAddress.isEmpty else {
            return nil
        }

        return "to \(lnAddress)"
    }

    private var canReportMerchant: Bool {
        guard isSent && tx.status == "Completed" else { return false }
        let network = tx.network.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let method = tx.method.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return network == "lightning" || network == "spark" || method.contains("spark")
    }

    private var compactUserLogField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                TextField(
                    "",
                    text: $userLogText,
                    prompt: Text(isUserLogFocused ? "" : "Logs are only stored on device.")
                        .foregroundColor(.white.opacity(0.35)),
                    axis: .vertical
                )
                .focused($isUserLogFocused)
                .lineLimit(1...3)
                .submitLabel(.done)
                .onSubmit(saveUserLog)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                Button(action: saveUserLogAndDismissField) {
                    Group {
                        if isSavingUserLog {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(canTapUserLogButton ? accentColor : Color.white.opacity(0.08))
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(!canTapUserLogButton)
                .opacity(canTapUserLogButton || isSavingUserLog ? 1 : 0.42)
                .accessibilityLabel("Save payment log")
            }

            if let userLogSaveError {
                Text(userLogSaveError)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.red.opacity(0.92))
            }
        }
        .padding(.top, 4)
    }

    private var normalizedUserLogText: String? {
        TransactionUserLogNormalizer.normalized(userLogText)
    }

    private var canSaveUserLog: Bool {
        !isSavingUserLog && normalizedUserLogText != savedUserLog
    }

    private var canTapUserLogButton: Bool {
        !isSavingUserLog && (canSaveUserLog || isUserLogFocused)
    }

    private func saveUserLog() {
        guard canSaveUserLog else { return }

        let normalizedUserLog = normalizedUserLogText
        isSavingUserLog = true
        userLogSaveError = nil

        Task {
            do {
                try await onSaveUserLog(normalizedUserLog)

                await MainActor.run {
                    savedUserLog = normalizedUserLog
                    userLogText = normalizedUserLog ?? ""
                    isSavingUserLog = false
                }
            } catch {
                await MainActor.run {
                    userLogSaveError = "Unable to save this log on device."
                    isSavingUserLog = false
                }
            }
        }
    }

    private func saveUserLogAndDismissField() {
        saveUserLog()
        isUserLogFocused = false
    }

    private func syncUserLog(with userLog: String?) {
        let normalizedUserLog = TransactionUserLogNormalizer.normalized(userLog)
        savedUserLog = normalizedUserLog

        if !isUserLogFocused {
            userLogText = normalizedUserLog ?? ""
        }
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.86))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TransactionReportableSheet: View {
    @Environment(\.dismiss) private var dismiss

    let tx: WalletManager.TransactionRow
    let onStatusChanged: (Bool) -> Void
    let onPersistStatus: (Bool) async throws -> Void

    @State private var isReportable: Bool
    @State private var errorMessage: String?
    @State private var isRevertingState = false
    @State private var persistenceTask: Task<Void, Never>?

    init(
        tx: WalletManager.TransactionRow,
        isInitiallyReportable: Bool,
        onStatusChanged: @escaping (Bool) -> Void,
        onPersistStatus: @escaping (Bool) async throws -> Void
    ) {
        self.tx = tx
        self.onStatusChanged = onStatusChanged
        self.onPersistStatus = onPersistStatus
        _isReportable = State(initialValue: isInitiallyReportable)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reportable Status")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("Use this to decide whether this send should export as reportable in your CSV. Transactions stay non-reportable unless you turn this on.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.70))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(isOn: $isReportable) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(isReportable ? "Reportable" : "Non-reportable")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)

                                    Text(toggleDetailText)
                                        .font(.footnote)
                                        .foregroundColor(.white.opacity(0.66))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(Color.splitBrandPink)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.splitInputSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("This payment")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            reportSummaryRow(label: "Amount", value: "\(tx.btcAmount) BTC")
                            reportSummaryRow(label: "Date", value: tx.dateString)
                            reportSummaryRow(label: "Status", value: tx.status)

                            if !tx.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                reportSummaryRow(label: "Memo", value: tx.note)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.splitInputSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.medium))
                                .foregroundColor(.red.opacity(0.92))
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Reportable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onChange(of: isReportable) { oldValue, newValue in
            persistReportableStatus(from: oldValue, to: newValue)
        }
        .onDisappear {
            persistenceTask?.cancel()
        }
    }

    private var toggleDetailText: String {
        isReportable
            ? "This transaction will export as Reportable."
            : "This transaction will export as Non-reportable."
    }

    private func persistReportableStatus(from oldValue: Bool, to newValue: Bool) {
        guard !isRevertingState else { return }
        guard oldValue != newValue else { return }

        errorMessage = nil
        onStatusChanged(newValue)
        persistenceTask?.cancel()

        persistenceTask = Task {
            do {
                try await onPersistStatus(newValue)
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    isRevertingState = true
                    isReportable = oldValue
                    onStatusChanged(oldValue)
                    errorMessage = "Unable to update the reportable setting on this device."
                    isRevertingState = false
                }
            }
        }
    }

    @ViewBuilder
    private func reportSummaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 68, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MerchantPubkeyReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var authManager: AuthManager

    let tx: WalletManager.TransactionRow

    @State private var merchantName = ""
    @State private var merchantAddress = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add Merchant")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("Share the merchant name and address. We’ll review the business and add them to rewards as quickly as possible.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.70))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            inputField(
                                title: "Merchant Name",
                                text: $merchantName,
                                prompt: "Enter the business name"
                            )

                            inputField(
                                title: "Merchant Address",
                                text: $merchantAddress,
                                prompt: "Enter the business address"
                            )
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.splitInputSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("This payment")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            reportSummaryRow(label: "Amount", value: "\(tx.btcAmount) BTC")
                            reportSummaryRow(label: "Date", value: tx.dateString)

                            if !tx.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                reportSummaryRow(label: "Memo", value: tx.note)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.splitInputSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.medium))
                                .foregroundColor(.red.opacity(0.92))
                        }

                        Button {
                            submit()
                        } label: {
                            Group {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Add Merchant")
                                        .font(.system(size: 17, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(canSubmit ? Color.splitBrandPink : Color.white.opacity(0.08))
                            )
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit || isSubmitting)
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Add Merchant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private var canSubmit: Bool {
        !merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !merchantAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func inputField(title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.65))

            TextField("", text: text, prompt: Text(prompt).foregroundColor(.white.opacity(0.35)))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.splitInputSurfaceSecondary)
                )
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private func reportSummaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 68, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submit() {
        guard !isSubmitting else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                try await postMerchantPubkeyReport(
                    walletManager: walletManager,
                    authManager: authManager,
                    transaction: tx,
                    merchantName: merchantName,
                    merchantAddress: merchantAddress
                )
                await MainActor.run {
                    isSubmitting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let tx: WalletManager.TransactionRow

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        summaryCard

                        if showsCounterpartySection {
                            TransactionDetailSection(title: "Counterparty") {
                                if tx.direction.lowercased() == "sent",
                                   let destinationPubkey = tx.destinationPubkey {
                                    TransactionCopyRow(
                                        label: "Destination Pubkey",
                                        value: destinationPubkey
                                    )
                                }

                                if let lnAddress = tx.lnAddress {
                                    TransactionCopyRow(
                                        label: "Lightning Address",
                                        value: lnAddress,
                                        useMonospacedFont: false
                                    )
                                }

                                if let domain = tx.lnurlDomain {
                                    TransactionValueRow(label: "LNURL Domain", value: domain)
                                }
                            }
                        }

                        if showsReferenceSection {
                            TransactionDetailSection(title: "Reference") {
                                if let label = tx.txReferenceLabel,
                                   let reference = tx.txReference {
                                    TransactionCopyRow(label: label, value: reference)
                                }

                                if let paymentHash = tx.paymentHash {
                                    TransactionCopyRow(label: "Payment Hash", value: paymentHash)
                                }

                                if let preimage = tx.preimage {
                                    TransactionCopyRow(label: "Preimage", value: preimage)
                                }

                                if let invoice = tx.invoice {
                                    TransactionCopyRow(label: "Invoice", value: invoice)
                                }

                                if let expiryDateString = tx.expiryDateString {
                                    TransactionValueRow(label: "HTLC Expiry", value: expiryDateString)
                                }
                            }
                        }

                        if showsNotesSection {
                            TransactionDetailSection(title: "Payment Memo") {
                                if !tx.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    TransactionValueRow(label: "Memo", value: tx.note)
                                }

                                if let lnurlComment = tx.lnurlComment, lnurlComment != tx.note {
                                    TransactionValueRow(label: "LNURL Comment", value: lnurlComment)
                                }

                                if let senderComment = tx.senderComment {
                                    TransactionValueRow(label: "Sender Comment", value: senderComment)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tx.direction.capitalized)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.70))

                if let sentLightningAddressLine {
                    Text(sentLightningAddressLine)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(signedAmountText)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                if !tx.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(tx.note)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.90))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                TransactionValueRow(label: "Status", value: tx.status)
                TransactionValueRow(label: "Method", value: tx.method)
                TransactionValueRow(label: "Network", value: tx.network.capitalized)
                TransactionValueRow(label: "Date", value: tx.dateString)
                TransactionValueRow(label: "Fee (BTC)", value: tx.feeBtcAmount)

                if tx.hasConversion {
                    TransactionValueRow(label: "Conversion", value: "Yes")
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.splitInputSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var signedAmountText: String {
        let sign = tx.direction.lowercased() == "sent" ? "−" : "+"
        return "\(sign)\(tx.btcAmount) BTC"
    }

    private var sentLightningAddressLine: String? {
        guard tx.direction.lowercased() == "sent" else { return nil }
        guard let lnAddress = tx.lnAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lnAddress.isEmpty else {
            return nil
        }

        return "to \(lnAddress)"
    }

    private var showsCounterpartySection: Bool {
        (tx.direction.lowercased() == "sent" && tx.destinationPubkey != nil)
            || tx.lnAddress != nil
            || tx.lnurlDomain != nil
    }

    private var showsReferenceSection: Bool {
        tx.txReference != nil
            || tx.paymentHash != nil
            || tx.preimage != nil
            || tx.invoice != nil
            || tx.expiryDateString != nil
    }

    private var showsNotesSection: Bool {
        !tx.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || tx.lnurlComment != nil
            || tx.senderComment != nil
    }
}

private struct TransactionDetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.splitInputSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }
}

private struct TransactionValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TransactionCopyRow: View {
    let label: String
    let value: String
    var useMonospacedFont: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(
                    useMonospacedFont
                    ? .system(size: 13, weight: .medium, design: .monospaced)
                    : .system(size: 14, weight: .medium)
                )
                .foregroundColor(.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Button {
                UIPasteboard.general.string = value
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.splitBrandPink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy \(label)")
        }
    }
}

private enum TransactionUserLogNormalizer {
    static func normalized(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }

        return normalized
    }
}

#Preview {
    TransactionsView()
        .environmentObject(WalletManager())
        .environmentObject(LNDWalletManager())
        .environmentObject(ActiveSpendWalletStore())
        .environmentObject(AuthManager())
}
