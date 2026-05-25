//  CustomerIndexView.swift
//  Split
//
//  Created by TeeVee on 1/5/25.
//
import SwiftUI
import UIKit

struct CustomerIndexView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var authManager: AuthManager

    let blue = Color.splitBrandBlue
    let pink = Color.splitBrandPink
    
    private let berry = Color.splitBerry
    private let indigo = Color.splitIndigo
    private let appBlack = Color.splitAppBlack
    private let cardSurface = Color.splitCardSurface
    private let hairline = Color.white.opacity(0.10)
    private let strongHairline = Color.white.opacity(0.16)

    @State private var isShowingRestoreSheet = false
    @State private var isShowingSeedBackup = false
    @State private var isShowingCreateWalletConfirmation = false

    @State private var btcPriceUSD: Double? = nil
    @State private var isRefreshingBTCPrice: Bool = false

    @State private var isStartingOnRamp: Bool = false
    @State private var isShowingCashAppAmountSheet: Bool = false

    @State private var alertMessage: String? = nil

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                walletStateSection

                if !isWalletReady {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .onChange(of: walletManager.state) { _, newState in
            guard case .ready = newState else { return }
            Task { try? await authManager.ensureSession(walletManager: walletManager) }
            refreshBTCPrice()
        }
        .onAppear {
            if case .ready = walletManager.state {
                refreshBTCPrice()
            }
        }
        .sheet(isPresented: $isShowingRestoreSheet) {
            RestoreWalletView(isPresented: $isShowingRestoreSheet, pink: pink)
                .environmentObject(walletManager)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $isShowingSeedBackup) {
            if !walletManager.pendingSeedWords.isEmpty {
                SeedPhraseBackupView(
                    words: walletManager.pendingSeedWords,
                    onConfirm: {
                        Task {
                            await walletManager.confirmPendingWalletCreation(authManager: authManager)
                            await MainActor.run { isShowingSeedBackup = false }

                            if case .ready = walletManager.state {
                                try? await authManager.ensureSession(walletManager: walletManager)
                            }
                            refreshBTCPrice()
                        }
                    },
                    onCancel: {
                        walletManager.cancelPendingWalletCreation()
                        isShowingSeedBackup = false
                    }
                )
            } else {
                VStack {
                    Text("No seed phrase available.")
                        .foregroundColor(.white)
                        .padding()

                    Button("Close") {
                        isShowingSeedBackup = false
                    }
                    .padding()
                }
                .background(appBlack.ignoresSafeArea())
            }
        }
        .fullScreenCover(isPresented: $isShowingCashAppAmountSheet) {
            CashAppAmountSheet(
                btcUsdRate: btcPriceUSD ?? walletManager.btcUsdRate,
                isStarting: isStartingOnRamp,
                onStart: { amountSats in
                    startCashAppOnRamp(amountSats: amountSats)
                },
                onCancel: {
                    isShowingCashAppAmountSheet = false
                }
            )
        }
        .alert(
            "Notice",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { newValue in
                    if !newValue { alertMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .alert(
            "Replace Saved Wallet?",
            isPresented: $isShowingCreateWalletConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Create New Wallet", role: .destructive) {
                Task {
                    await walletManager.createWallet()
                    await MainActor.run {
                        if !walletManager.pendingSeedWords.isEmpty {
                            isShowingSeedBackup = true
                        }
                    }
                }
            }
        } message: {
            Text("Creating a new wallet will wipe the seedphrase currently saved on this device making recovery without your own backup impossible. Only continue if you want a brand-new wallet on this device.")
        }
    }

    @ViewBuilder
    private var walletStateSection: some View {
        switch walletManager.state {

        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)

                Text("Loading wallet...")
                    .foregroundColor(.white.opacity(0.74))
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(hairline, lineWidth: 1)
            )
            .shadow(color: indigo.opacity(0.30), radius: 16, x: 0, y: 10)

        case .noWallet:
            VStack(alignment: .leading, spacing: 16) {
                Text("Set Up Your Wallet")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("You can link an existing wallet with a seed phrase, or create a brand-new non-custodial wallet on this device.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.72))

                Button {
                    isShowingRestoreSheet = true
                } label: {
                    Text("Link Existing Wallet (Restore)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [indigo, blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(strongHairline, lineWidth: 1)
                        )
                }

                Button {
                    Task {
                        await walletManager.createWallet()
                        await MainActor.run {
                            if !walletManager.pendingSeedWords.isEmpty {
                                isShowingSeedBackup = true
                            }
                        }
                    }
                } label: {
                    Text("Create New Wallet")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [berry, pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(strongHairline, lineWidth: 1)
                        )
                }

                if let error = walletManager.lastErrorMessage {
                    ErrorBox(message: error)
                }
            }
            .padding()
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(hairline, lineWidth: 1)
            )
            .shadow(color: indigo.opacity(0.30), radius: 16, x: 0, y: 10)

        case .ready:
            let fiatText: String = {
                if let fiat = walletManager.fiatBalanceUSD {
                    return String(format: "$%.2f", fiat)
                } else {
                    return "$0.00"
                }
            }()

            let btcText = "₿ \(walletManager.formattedBTCBalance)"

            let (authText, isAuthError): (String?, Bool) = {
                switch authManager.state {
                case .authenticating:
                    return ("Verifying with server…", false)
                case .failed(let msg):
                    return ("Server auth failed: \(msg)", true)
                default:
                    return (nil, false)
                }
            }()

            let priceText: String = {
                guard let btcPriceUSD else { return "—" }
                return formatUSD(btcPriceUSD)
            }()

            ScrollView(showsIndicators: false) {
                UnifiedWalletSurface(
                    blue: blue,
                    pink: pink,
                    fiatBalanceText: fiatText,
                    btcBalanceText: btcText,
                    isSyncing: walletManager.isSyncing,
                    authStatusText: authText,
                    authStatusIsError: isAuthError,
                    btcUsdRate: btcPriceUSD ?? walletManager.btcUsdRate,
                    btcPriceText: priceText,
                    onRefreshBTCPrice: { refreshBTCPrice() },
                    onBuy: { isShowingCashAppAmountSheet = true }
                )
                .padding(.bottom, 10)
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 12) {
                Text(walletManager.isStoredWalletRecoveryFlowActive ? "Wallet Couldn't Open" : "Wallet Error")
                    .font(.headline)
                    .foregroundColor(.white)

                if walletManager.isStoredWalletRecoveryFlowActive {
                    Text("We found a wallet seed on this device, but Split couldn’t reopen the wallet automatically. Try restoring the existing wallet first. If you create a new wallet instead, the saved recovery phrase on this device will be replaced.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.72))
                }

                Text(message)
                    .font(.footnote)
                    .foregroundColor(.red)

                Button {
                    Task {
                        await walletManager.configure(authManager: authManager)
                    }
                } label: {
                    Text("Retry")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [indigo, blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(strongHairline, lineWidth: 1)
                        )
                }

                if walletManager.isStoredWalletRecoveryFlowActive {
                    Button {
                        isShowingRestoreSheet = true
                    } label: {
                        Text("Restore Wallet")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [berry, pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(strongHairline, lineWidth: 1)
                            )
                    }

                    Button {
                        isShowingCreateWalletConfirmation = true
                    } label: {
                        Text("Create New Wallet")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(hairline, lineWidth: 1)
                            )
                    }
                }
            }
            .padding()
            .background(cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(hairline, lineWidth: 1)
            )
            .shadow(color: indigo.opacity(0.30), radius: 16, x: 0, y: 10)
        }
    }

    private var isWalletReady: Bool {
        if case .ready = walletManager.state {
            return true
        }

        return false
    }

    private func refreshBTCPrice() {
        guard !isRefreshingBTCPrice else { return }
        isRefreshingBTCPrice = true

        fetchBitcoinPriceUSD { price in
            btcPriceUSD = price
            isRefreshingBTCPrice = false
        } onError: { msg in
            isRefreshingBTCPrice = false
            print("BTC price fetch failed: \(msg)")
        }
    }

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private func startCashAppOnRamp(amountSats: UInt64) {
        guard !isStartingOnRamp else { return }
        isStartingOnRamp = true

        Task {
            do {
                let url = try await walletManager.createCashAppBuyURL(amountSats: amountSats)

                await MainActor.run {
                    UIApplication.shared.open(url, options: [:]) { accepted in
                        if !accepted {
                            alertMessage = "Unable to open Cash App for this purchase."
                        }

                        isShowingCashAppAmountSheet = false
                        isStartingOnRamp = false
                    }
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Failed to start Cash App: \(error.localizedDescription)"
                    isStartingOnRamp = false
                }
            }
        }
    }
}
