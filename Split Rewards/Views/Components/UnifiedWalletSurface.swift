//
//  UnifiedWalletSurface.swift
//  Split Rewards
//
//  Created by TeeVee on 1/15/26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct UnifiedWalletSurface: View {
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var lndWalletManager: LNDWalletManager
    @EnvironmentObject private var nwcWalletManager: NWCWalletManager
    @EnvironmentObject private var coreLightningWalletManager: CoreLightningWalletManager
    @EnvironmentObject private var eclairWalletManager: EclairWalletManager
    @EnvironmentObject private var sparkSubwalletManager: SparkSubwalletManager
    @EnvironmentObject private var activeSpendWalletStore: ActiveSpendWalletStore
    @EnvironmentObject private var toastManager: ToastManager
    @ObservedObject private var torManager = RemoteNodeTorManager.shared

    let blue: Color
    let pink: Color

    let fiatBalanceText: String
    let btcBalanceText: String

    let isSyncing: Bool
    let authStatusText: String?
    let authStatusIsError: Bool

    let btcUsdRate: Double?
    let btcPriceText: String
    let onRefreshBTCPrice: () -> Void
    let onBuy: () -> Void

    @State private var showScanToPayFlow = false
    @State private var isScanFlowLaunching = false
    @State private var showSendFlow = false
    @State private var showReceiveFlow = false
    @State private var showBuyBitcoinInfo = false
    @State private var showWalletPicker = false
    @State private var showAddLightningWallet = false
    @StateObject private var transactionActivityTracker = TransactionActivityTracker.shared
    @State private var displayedUnseenTransactionCount = 0
    @AppStorage("split.walletBalanceHidden.v1") private var isWalletBalanceHidden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                balanceHero
                actionRow
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.splitAppBlack)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)

            WalletIdentitySection(
                blue: blue,
                pink: pink,
                onBuy: onBuy,
                onShowBuyInfo: { showBuyBitcoinInfo = true }
            )

            RampPriceCard(
                priceText: btcPriceText,
                onRefreshPrice: onRefreshBTCPrice
            )
        }
        .sheet(isPresented: $showBuyBitcoinInfo) {
            BuyBitcoinInfoSheet(pink: pink)
                .presentationDetents([.fraction(0.4)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWalletPicker) {
            ActiveWalletPickerSheet(
                activeSelection: activeSpendWalletStore.activeWallet,
                wallets: ExternalWalletStore.shared.loadWallets(),
                onSelectSpark: selectSparkWallet,
                onSelectExternal: selectExternalWallet,
                onAddWallet: {
                    showWalletPicker = false
                    showAddLightningWallet = true
                }
            )
            .presentationDetents([.fraction(0.74)])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showScanToPayFlow, onDismiss: {
            isScanFlowLaunching = false
        }) {
            NavigationStack {
                SendBTCView()
            }
        }
        .fullScreenCover(isPresented: $showSendFlow) {
            NavigationStack {
                SendToView()
            }
        }
        .fullScreenCover(isPresented: $showReceiveFlow) {
            NavigationStack {
                ReceiveAmountView()
            }
        }
        .fullScreenCover(isPresented: $showAddLightningWallet) {
            NavigationStack {
                AddLightningWalletView(onWalletAdded: {
                    showAddLightningWallet = false
                })
            }
        }
        .task {
            displayedUnseenTransactionCount = transactionActivityTracker.unseenCount
            await refreshTransactionActivity()
        }
        .onAppear {
            displayedUnseenTransactionCount = transactionActivityTracker.unseenCount
        }
        .onReceive(NotificationCenter.default.publisher(for: .walletTransactionsDidChange)) { _ in
            Task {
                await refreshTransactionActivity()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await refreshTransactionActivity()
            }
        }
        .onChange(of: transactionActivityTracker.unseenCount) { _, newCount in
            guard !toastManager.isTransactionBadgeHeld else { return }
            displayedUnseenTransactionCount = newCount
        }
        .onChange(of: toastManager.isTransactionBadgeHeld) { _, isHeld in
            guard !isHeld else { return }
            displayedUnseenTransactionCount = transactionActivityTracker.unseenCount
        }
    }

    private var balanceHero: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                if hasExternalSpendWallet || showsRootOnlyAddWalletButton {
                    Color.clear
                        .frame(height: 20)
                }

                HStack(alignment: .top, spacing: 10) {
                    Text(visibleFiatBalanceText)
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)

                    Button {
                        isWalletBalanceHidden.toggle()
                    } label: {
                        Image(systemName: isWalletBalanceHidden ? "shield.fill" : "shield")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white.opacity(0.82))
                            .frame(width: 34, height: 34)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isWalletBalanceHidden ? "Show balance" : "Hide balance")
                    .padding(.top, 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(visibleBTCBalanceText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.84))
                    .monospacedDigit()

                if isSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)

                        Text("Syncing…")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.82))
                    }
                }

                if let authStatusText {
                    Text(authStatusText)
                        .font(.caption)
                        .foregroundColor(authStatusIsError ? .red.opacity(0.95) : .white.opacity(0.82))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasExternalSpendWallet {
                HStack(spacing: 8) {
                    if activeSelectedWalletUsesTor && torManager.bootstrapState.isStarting {
                        torStartupStatus
                    }

                    activeWalletButton
                }
                    .padding(.top, -4)
                    .padding(.trailing, -4)
            } else if showsRootOnlyAddWalletButton {
                rootOnlyAddWalletButton
                    .padding(.top, -4)
                    .padding(.trailing, -4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .background(
            Color.splitAppBlack
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 22, x: 0, y: 12)
    }

    private var visibleFiatBalanceText: String {
        isWalletBalanceHidden ? "******" : displayedFiatBalanceText
    }

    private var visibleBTCBalanceText: String {
        isWalletBalanceHidden ? "******" : displayedBTCBalanceText
    }

    private var displayedFiatBalanceText: String {
        guard !activeSpendWalletStore.isSparkActive else {
            return fiatBalanceText
        }

        if activeSpendWalletStore.isNWCActive {
            guard let sats = nwcWalletManager.balanceSummary?.spendableSats,
                  let rate = btcUsdRate ?? walletManager.btcUsdRate,
                  rate > 0 else {
                return "$—"
            }

            let usdValue = (Double(max(sats, 0)) / 100_000_000.0) * rate
            return formatUSDBalance(usdValue)
        }

        if activeSpendWalletStore.isCoreLightningActive {
            guard let sats = coreLightningWalletManager.balanceSummary?.spendableSats,
                  let rate = btcUsdRate ?? walletManager.btcUsdRate,
                  rate > 0 else {
                return "$—"
            }

            let usdValue = (Double(max(sats, 0)) / 100_000_000.0) * rate
            return formatUSDBalance(usdValue)
        }

        if activeSpendWalletStore.isEclairActive {
            guard let sats = eclairWalletManager.balanceSummary?.spendableSats,
                  let rate = btcUsdRate ?? walletManager.btcUsdRate,
                  rate > 0 else {
                return "$—"
            }

            let usdValue = (Double(max(sats, 0)) / 100_000_000.0) * rate
            return formatUSDBalance(usdValue)
        }

        if activeSpendWalletStore.isSparkSubwalletActive {
            guard let sats = sparkSubwalletManager.balanceSummary?.spendableSats,
                  let rate = btcUsdRate ?? walletManager.btcUsdRate,
                  rate > 0 else {
                return "$—"
            }

            let usdValue = (Double(sats) / 100_000_000.0) * rate
            return formatUSDBalance(usdValue)
        }

        guard let sats = lndWalletManager.balanceSummary?.spendableSats,
              let rate = btcUsdRate ?? walletManager.btcUsdRate,
              rate > 0 else {
            return "$—"
        }

        let usdValue = (Double(max(sats, 0)) / 100_000_000.0) * rate
        return formatUSDBalance(usdValue)
    }

    private var displayedBTCBalanceText: String {
        guard !activeSpendWalletStore.isSparkActive else {
            return btcBalanceText
        }

        if activeSpendWalletStore.isNWCActive {
            let sats = nwcWalletManager.balanceSummary?.spendableSats ?? 0
            return "₿ \(formatBTCBalance(sats: sats))"
        }

        if activeSpendWalletStore.isCoreLightningActive {
            let sats = coreLightningWalletManager.balanceSummary?.spendableSats ?? 0
            return "₿ \(formatBTCBalance(sats: sats))"
        }

        if activeSpendWalletStore.isEclairActive {
            let sats = eclairWalletManager.balanceSummary?.spendableSats ?? 0
            return "₿ \(formatBTCBalance(sats: sats))"
        }

        if activeSpendWalletStore.isSparkSubwalletActive {
            let sats = sparkSubwalletManager.balanceSummary?.spendableSats ?? 0
            return "₿ \(formatBTCBalance(sats: Int64(min(sats, UInt64(Int64.max)))))"
        }

        let sats = lndWalletManager.balanceSummary?.spendableSats ?? 0
        return "₿ \(formatBTCBalance(sats: sats))"
    }

    private var hasStoredNode: Bool {
        lndWalletManager.connectedNode != nil || LNDCredentialStore.shared.activeNode() != nil
    }

    private var hasStoredNWCWallet: Bool {
        nwcWalletManager.connectedWallet != nil || NWCCredentialStore.shared.activeWallet() != nil
    }

    private var hasStoredCoreLightningNode: Bool {
        coreLightningWalletManager.connectedNode != nil || CoreLightningCredentialStore.shared.activeNode() != nil
    }

    private var hasStoredEclairNode: Bool {
        eclairWalletManager.connectedNode != nil || EclairCredentialStore.shared.activeNode() != nil
    }

    private var hasStoredSparkSubwallet: Bool {
        sparkSubwalletManager.connectedWallet != nil || SparkSubwalletCredentialStore.shared.activeWallet() != nil
    }

    private var hasExternalSpendWallet: Bool {
        hasStoredNode || hasStoredNWCWallet || hasStoredCoreLightningNode || hasStoredEclairNode || hasStoredSparkSubwallet
    }

    private var showsRootOnlyAddWalletButton: Bool {
        !hasExternalSpendWallet && ExternalWalletStore.shared.loadWallets().isEmpty
    }

    private var activeSelectedWalletUsesTor: Bool {
        switch activeSpendWalletStore.activeWallet {
        case .spark:
            return false
        case let .external(kind, id):
            switch kind {
            case .lnd:
                return LNDCredentialStore.shared.loadNodes().first(where: { $0.id == id })?.usesTor == true
            case .nwc:
                return NWCCredentialStore.shared.loadWallets().first(where: { $0.id == id })?.usesTor == true
            case .coreLightning:
                return CoreLightningCredentialStore.shared.loadNodes().first(where: { $0.id == id })?.usesTor == true
            case .eclair:
                return EclairCredentialStore.shared.loadNodes().first(where: { $0.id == id })?.usesTor == true
            case .sparkSubwallet:
                return false
            }
        }
    }

    private var activeWalletButton: some View {
        Button {
            showWalletPicker = true
        } label: {
            activeWalletBadge
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Active wallet")
    }

    private var rootOnlyAddWalletButton: some View {
        Button {
            showAddLightningWallet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add wallet")
    }

    private var torStartupStatus: some View {
        HStack(spacing: 5) {
            Text("Starting Tor")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.white)

            ProgressView()
                .scaleEffect(0.52)
                .tint(.white)
                .frame(width: 12, height: 12)
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 20)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.14))
        )
    }

    @ViewBuilder
    private var activeWalletBadge: some View {
        HStack(spacing: 6) {
            if activeSpendWalletStore.isLndActive {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .black))

                Text(activeSpendWalletStore.activeWalletLabel)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if activeSpendWalletStore.isNWCActive {
                NWCSymbol()
                    .frame(width: 12, height: 12)

                Text(activeSpendWalletStore.activeWalletLabel)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if activeSpendWalletStore.isCoreLightningActive {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .black))

                Text(activeSpendWalletStore.activeWalletLabel)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if activeSpendWalletStore.isEclairActive {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .black))

                Text(activeSpendWalletStore.activeWalletLabel)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if activeSpendWalletStore.isSparkSubwalletActive {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .black))

                Text(activeSpendWalletStore.activeWalletLabel)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("Split")
                    .font(.system(size: 10, weight: .black, design: .rounded))
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .heavy))
                .opacity(0.70)
        }
        .foregroundColor(Color.splitAppBlack)
        .lineLimit(1)
        .frame(minWidth: 42, maxWidth: 78, minHeight: 20)
        .padding(.horizontal, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
        )
        .contentShape(Capsule(style: .continuous))
    }

    @MainActor
    private func selectSparkWallet() {
        activeSpendWalletStore.setSparkActive()
        showWalletPicker = false

        Task {
            await refreshTransactionActivity()
        }
    }

    @MainActor
    private func selectNodeWallet() {
        guard activeSpendWalletStore.setLndActiveIfAvailable() else {
            return
        }
        showWalletPicker = false

        Task {
            if !lndWalletManager.isConnected {
                try? await lndWalletManager.restoreActiveNode()
            }

            _ = try? await lndWalletManager.refreshBalance()
            await refreshTransactionActivity()
        }
    }

    @MainActor
    private func selectNWCWallet() {
        guard activeSpendWalletStore.setNWCActiveIfAvailable() else {
            return
        }
        showWalletPicker = false

        Task {
            if !nwcWalletManager.isConnected {
                try? await nwcWalletManager.restoreActiveWallet()
            }

            _ = try? await nwcWalletManager.refreshBalance()
            await refreshTransactionActivity()
        }
    }

    @MainActor
    private func selectExternalWallet(_ record: ExternalWalletRecord) {
        showWalletPicker = false

        Task {
            switch record.payload {
            case .lnd:
                guard activeSpendWalletStore.setExternalWalletActive(kind: .lnd, id: record.id) else {
                    return
                }

                try? await lndWalletManager.setActiveStoredNode(id: record.id)
                _ = try? await lndWalletManager.refreshBalance()
            case .nwc:
                guard activeSpendWalletStore.setExternalWalletActive(kind: .nwc, id: record.id) else {
                    return
                }

                try? await nwcWalletManager.setActiveStoredWallet(id: record.id)
                _ = try? await nwcWalletManager.refreshBalance()
            case .coreLightning:
                guard activeSpendWalletStore.setExternalWalletActive(kind: .coreLightning, id: record.id) else {
                    return
                }

                try? await coreLightningWalletManager.setActiveStoredNode(id: record.id)
                _ = try? await coreLightningWalletManager.refreshBalance()
            case .eclair:
                guard activeSpendWalletStore.setExternalWalletActive(kind: .eclair, id: record.id) else {
                    return
                }

                try? await eclairWalletManager.setActiveStoredNode(id: record.id)
                _ = try? await eclairWalletManager.refreshBalance()
            case .sparkSubwallet:
                guard activeSpendWalletStore.setExternalWalletActive(kind: .sparkSubwallet, id: record.id) else {
                    return
                }

                try? await sparkSubwalletManager.setActiveStoredWallet(id: record.id)
            }

            await refreshTransactionActivity()
        }
    }

    private func formatBTCBalance(sats: Int64) -> String {
        let btc = Double(max(sats, 0)) / 100_000_000.0
        return String(format: "%.8f", btc)
    }

    private func formatUSDBalance(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            Button {
                guard !isScanFlowLaunching, !showScanToPayFlow else { return }
                isScanFlowLaunching = true
                showScanToPayFlow = true
            } label: {
                WalletActionPill(
                    icon: "qrcode.viewfinder",
                    title: nil,
                    iconSize: 22,
                    background: pink,
                    tint: Color.white,
                    highlightColor: nil,
                    badgeCount: 0
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .disabled(isScanFlowLaunching || showScanToPayFlow)
            .accessibilityLabel("Scan QR")

            Button {
                showSendFlow = true
            } label: {
                WalletActionPill(
                    icon: "arrow.up.right",
                    title: "Send",
                    background: blue,
                    tint: Color.white,
                    highlightColor: nil,
                    badgeCount: 0
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button {
                showReceiveFlow = true
            } label: {
                WalletActionPill(
                    icon: "arrow.down.left",
                    title: "Receive",
                    background: blue,
                    tint: Color.white,
                    highlightColor: nil,
                    badgeCount: 0
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            NavigationLink {
                TransactionsView()
            } label: {
                WalletActionPill(
                    icon: "clock",
                    title: "activity",
                    background: Color.white,
                    tint: Color.splitAppBlack,
                    highlightColor: pink,
                    badgeCount: displayedUnseenTransactionCount
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @MainActor
    private func refreshTransactionActivity() async {
        if activeSpendWalletStore.isLndActive {
            await transactionActivityTracker.refreshIfPossible(lndWalletManager: lndWalletManager)
        } else if activeSpendWalletStore.isNWCActive {
            await transactionActivityTracker.refreshIfPossible(nwcWalletManager: nwcWalletManager)
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

    private struct WalletActionPill: View {
        let icon: String
        let title: String?
        let iconSize: CGFloat
        let background: Color
        let tint: Color
        let highlightColor: Color?
        let badgeCount: Int

        init(
            icon: String,
            title: String?,
            iconSize: CGFloat = 14,
            background: Color,
            tint: Color,
            highlightColor: Color?,
            badgeCount: Int
        ) {
            self.icon = icon
            self.title = title
            self.iconSize = iconSize
            self.background = background
            self.tint = tint
            self.highlightColor = highlightColor
            self.badgeCount = badgeCount
        }

        private var isHighlighted: Bool {
            badgeCount > 0
        }

        private var badgeText: String {
            badgeCount > 9 ? "9+" : "\(badgeCount)"
        }

        var body: some View {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(tint)

                    if let title {
                        Text(title)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 6)
                .padding(.vertical, 7)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isHighlighted
                                ? (highlightColor ?? tint).opacity(0.80)
                                : Color.white.opacity(0.10),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isHighlighted
                        ? (highlightColor ?? tint).opacity(0.18)
                        : .clear,
                    radius: 10,
                    x: 0,
                    y: 4
                )

                if badgeCount > 0 {
                    Text(badgeText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill((highlightColor ?? tint).opacity(0.92))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.20), lineWidth: 1)
                        )
                        .offset(x: 8, y: -8)
                }
            }
        }
    }
}

private struct WalletIdentitySection: View {
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var authManager: AuthManager

    let blue: Color
    let pink: Color
    let onBuy: () -> Void
    let onShowBuyInfo: () -> Void

    @State private var lightningAddress: WalletManager.LightningAddressInfo?
    @State private var messagingRegistration: MessageKeyManager.RegistrationResponse?
    @State private var profilePicUrl: String?
    @State private var selectedProfileImage: UIImage?
    @State private var pickedPhotoImage: UIImage?
    @State private var isLoadingAddress = true
    @State private var isUploadingProfilePic = false
    @State private var addressLoadError: String?
    @State private var profilePicUploadError: String?

    @State private var showingCreateSheet = false
    @State private var showingQRSheet = false
    @State private var showingPhotoSourceDialog = false
    @State private var showingImagePicker = false
    @State private var showingFileImporter = false

    var body: some View {
        configuredBody(content: identityContent)
    }

    private var identityContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                profilePhotoSection
                lightningAddressSection
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, lightningAddress == nil ? 0 : 34)
            }

            if let profilePicUploadError {
                Text(profilePicUploadError)
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.95))
                    .multilineTextAlignment(.leading)
            }

            if lightningAddress != nil {
                lightningAddressControls
            }
        }
    }

    private func configuredBody<Content: View>(content: Content) -> some View {
        content
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.splitAppBlack)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 9)
        .overlay(alignment: .topTrailing) {
            if lightningAddress != nil {
                buyInfoCornerButton
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
        }
        .task {
            await loadProfileContent()
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateLightningAddressSheet { createdAddress, registration in
                lightningAddress = createdAddress
                messagingRegistration = registration
            }
            .environmentObject(walletManager)
            .environmentObject(authManager)
        }
        .sheet(isPresented: $showingQRSheet) {
            if let lightningAddress {
                IdentityShareSheet(
                    lightningAddress: lightningAddress.lightningAddress,
                    suggestedContactName: suggestedContactName(for: lightningAddress),
                    paymentQRString: qrPayload(for: lightningAddress),
                    contactQRString: contactPayload(for: lightningAddress)
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
        .confirmationDialog(
            "Update Profile Photo",
            isPresented: $showingPhotoSourceDialog,
            titleVisibility: .visible
        ) {
            Button("Choose Photo") {
                showingImagePicker = true
            }

            Button("Choose File") {
                showingFileImporter = true
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose an image from your photo library or Files.")
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $pickedPhotoImage)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleProfileFileSelection(result)
        }
        .onChange(of: pickedPhotoImage) { _, newImage in
            guard let newImage else { return }

            Task {
                await handleSelectedPhoto(newImage)
            }
        }
    }

    private var resolvedProfilePicURL: URL? {
        guard let profilePicUrl else { return nil }

        let trimmedProfilePicURL = profilePicUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProfilePicURL.isEmpty else { return nil }

        return URL(string: trimmedProfilePicURL)
    }

    private var buyInfoCornerButton: some View {
        Button(action: onShowBuyInfo) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.06))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Buying Bitcoin info")
    }

    private var profilePhotoSection: some View {
        Button {
            showingPhotoSourceDialog = true
        } label: {
            Group {
                if let selectedProfileImage {
                    Image(uiImage: selectedProfileImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                } else if let resolvedProfilePicURL {
                    AsyncImage(url: resolvedProfilePicURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        case .failure:
                            profilePhotoPlaceholder
                        @unknown default:
                            profilePhotoPlaceholder
                        }
                    }
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                } else {
                    profilePhotoPlaceholder
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isUploadingProfilePic {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.72)
                        .tint(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.black.opacity(0.72)))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isUploadingProfilePic)
        .accessibilityLabel("Update profile photo")
    }

    private var lightningAddressQRButton: some View {
        Button(action: {
            showingQRSheet = true
        }) {
            Image(systemName: "qrcode")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(blue)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show Lightning Address QR code")
    }

    private var buyBitcoinControls: some View {
        HStack(alignment: .center, spacing: 6) {
            Button(action: onBuy) {
                (
                    Text("Buy ")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(.white) +
                    Text("₿")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(pink) +
                    Text("itcoin")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(.white)
                )
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .padding(.horizontal, 6)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(minWidth: 110, idealWidth: 132, maxWidth: 148)
            .accessibilityLabel("Buy Bitcoin")
        }
    }

    private var lightningAddressControls: some View {
        HStack(alignment: .center, spacing: 18) {
            buyBitcoinControls
            lightningAddressQRButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var profilePhotoPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))

            Text("+ photo")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .frame(width: 72, height: 72)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var lightningAddressSection: some View {
        if isLoadingAddress {
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))

                Text("Loading Lightning Address...")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        } else if let addressLoadError {
            VStack(alignment: .leading, spacing: 10) {
                Text(addressLoadError)
                    .font(.subheadline)
                    .foregroundColor(.red.opacity(0.95))
                    .multilineTextAlignment(.leading)

                Button(action: {
                    Task { await loadLightningAddress() }
                }) {
                    Text("Retry")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(blue)
                        )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        } else if let lightningAddress {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Lightning Address")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.56))

                    Text(lightningAddress.lightningAddress)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Setup a Lightning Address for this wallet.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.68))
                    .multilineTextAlignment(.leading)

                Button(action: {
                    showingCreateSheet = true
                }) {
                    Text("Create Lightning Address")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(blue)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadProfileContent() async {
        await loadProfilePic()
        await loadLightningAddress()
    }

    private func loadProfilePic() async {
        do {
            let response = try await ProfilePicAPI.fetchProfilePic(
                authManager: authManager,
                walletManager: walletManager
            )
            profilePicUrl = response.profilePicUrl
        } catch {
            print("Failed to load profile picture: \(error.localizedDescription)")
            profilePicUrl = nil
        }
    }

    private func handleSelectedPhoto(_ image: UIImage) async {
        guard let fileData = image.jpegData(compressionQuality: 0.9) else {
            profilePicUploadError = "Failed to prepare selected photo."
            pickedPhotoImage = nil
            return
        }

        await uploadProfilePic(
            fileData: fileData,
            fileName: "profile-photo.jpg",
            mimeType: "image/jpeg",
            previewImage: image
        )

        pickedPhotoImage = nil
    }

    private func handleProfileFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                guard let image = UIImage(data: data) else {
                    profilePicUploadError = "Selected file could not be used as a profile picture."
                    return
                }

                let fileName = url.lastPathComponent.isEmpty ? "profile-file" : url.lastPathComponent
                let mimeType = mimeTypeForProfileFile(at: url)

                Task {
                    await uploadProfilePic(
                        fileData: data,
                        fileName: fileName,
                        mimeType: mimeType,
                        previewImage: image
                    )
                }
            } catch {
                profilePicUploadError = "Failed to read selected file."
                print("Failed to read selected profile file: \(error.localizedDescription)")
            }
        case .failure(let error):
            print("Profile file import cancelled or failed: \(error.localizedDescription)")
        }
    }

    private func uploadProfilePic(
        fileData: Data,
        fileName: String,
        mimeType: String,
        previewImage: UIImage
    ) async {
        isUploadingProfilePic = true
        profilePicUploadError = nil

        do {
            let response = try await ProfilePicUploadAPI.postProfilePic(
                fileData: fileData,
                fileName: fileName,
                mimeType: mimeType,
                authManager: authManager,
                walletManager: walletManager
            )

            selectedProfileImage = previewImage
            profilePicUrl = response.profilePicUrl ?? profilePicUrl
        } catch {
            profilePicUploadError = error.localizedDescription
            print("Failed to upload profile picture: \(error.localizedDescription)")
        }

        isUploadingProfilePic = false
    }

    private func mimeTypeForProfileFile(at url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = values.contentType,
           let mimeType = contentType.preferredMIMEType {
            return mimeType
        }

        return "application/octet-stream"
    }

    private func loadLightningAddress() async {
        isLoadingAddress = true
        addressLoadError = nil

        do {
            let fetched = try await walletManager.fetchLightningAddress()
            lightningAddress = fetched

            if fetched != nil {
                do {
                    messagingRegistration = try await MessageKeyManager.shared.ensureRegistered(
                        authManager: authManager,
                        walletManager: walletManager
                    )
                } catch {
                    messagingRegistration = nil
                    print("Failed to sync messaging identity: \(error.localizedDescription)")
                }
            } else {
                messagingRegistration = nil
            }
        } catch {
            addressLoadError = error.localizedDescription
            lightningAddress = nil
            messagingRegistration = nil
        }

        isLoadingAddress = false
    }

    private func qrPayload(for info: WalletManager.LightningAddressInfo) -> String {
        if !info.lnurlBech32.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return info.lnurlBech32
        }

        return "lightning:\(info.lightningAddress)"
    }

    private func suggestedContactName(for info: WalletManager.LightningAddressInfo) -> String {
        let address = info.lightningAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let username = address.split(separator: "@").first, !username.isEmpty else {
            return "Split User"
        }

        return String(username)
    }

    private func contactPayload(for info: WalletManager.LightningAddressInfo) -> String {
        struct SplitContactPayload: Encodable {
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
        }

        let normalizedLightningAddress = info.lightningAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let signedBinding = messagingRegistration?.identityBindingPayload
        let shouldEmbedSignedBinding = signedBinding?.lightningAddress == normalizedLightningAddress

        let payload = SplitContactPayload(
            type: "split_contact",
            version: 1,
            lightningAddress: normalizedLightningAddress,
            suggestedName: suggestedContactName(for: info),
            profilePicUrl: profilePicUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? profilePicUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            walletPubkey: shouldEmbedSignedBinding ? signedBinding?.walletPubkey : nil,
            messagingPubkey: shouldEmbedSignedBinding ? signedBinding?.messagingPubkey : nil,
            messagingIdentitySignature: shouldEmbedSignedBinding ? signedBinding?.messagingIdentitySignature : nil,
            messagingIdentitySignatureVersion: shouldEmbedSignedBinding ? signedBinding?.messagingIdentitySignatureVersion : nil,
            messagingIdentitySignedAt: shouldEmbedSignedBinding ? signedBinding?.messagingIdentitySignedAt : nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "split-contact:{\"lightningAddress\":\"\(info.lightningAddress.lowercased())\",\"suggestedName\":\"\(suggestedContactName(for: info))\",\"type\":\"split_contact\",\"version\":1}"
        }

        return "split-contact:\(jsonString)"
    }
}

private struct BuyBitcoinInfoSheet: View {
    let pink: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.splitAppBlack,
                    Color.splitSurface
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    (
                        Text("₿")
                            .foregroundColor(pink) +
                        Text("uying Bitcoin")
                            .foregroundColor(.white)
                    )
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .padding(.top, 24)
                    .padding(.bottom, 10)

                    Text("Split has integrated with Cash App to provide a seamless buying experience deposited over the Lightning Network. Cash App is responsible for pricing, fees, execution, and any related liabilities. Your Bitcoin is sent directly to your Split wallet, and Split does not charge any fees for these purchases.")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ActiveWalletPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let activeSelection: SpendWalletSelection
    let wallets: [ExternalWalletRecord]
    let onSelectSpark: () -> Void
    let onSelectExternal: (ExternalWalletRecord) -> Void
    let onAddWallet: () -> Void

    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    var body: some View {
        ZStack {
            Color.splitSoftBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header

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
                            isSelected: activeSelection == .spark,
                            action: {
                                onSelectSpark()
                                dismiss()
                            }
                        )

                        ForEach(wallets) { wallet in
                            walletRow(
                                title: wallet.label,
                                subtitle: wallet.kind.displayName,
                                icon: {
                                    walletIcon(for: wallet.kind)
                                },
                                isSelected: activeSelection == .external(kind: wallet.kind, id: wallet.id),
                                action: {
                                    onSelectExternal(wallet)
                                    dismiss()
                                }
                            )
                        }

                    }
                    .padding(.bottom, 12)
                }

                addWalletAction
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 18)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Select Wallet")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private var addWalletAction: some View {
        Button(action: onAddWallet) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.headline.weight(.bold))
                    .frame(width: 22, height: 22)

                Text("Add Wallet")
                    .font(.headline.weight(.semibold))

                Spacer()
            }
            .foregroundColor(.white)
            .padding(14)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
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
