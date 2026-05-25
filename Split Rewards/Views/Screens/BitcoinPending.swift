//  BitcoinPending.swift
//  Split Rewards
//
//  Created by TeeVee on 2/15/26.
//
import SwiftUI

struct BitcoinPending: View {

    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var authManager: AuthManager

    // Brand colors (matching CustomerIndexView)
    let blue = Color.splitBrandBlue
    let pink = Color.splitBrandPink

    // BTC Price (same pattern as CustomerIndexView)
    @State private var btcPriceUSD: Double? = nil
    @State private var isRefreshingBTCPrice: Bool = false

    // Deposits
    @State private var deposits: [WalletManager.UnclaimedBitcoinDepositUI] = []
    @State private var isLoadingDeposits: Bool = false

    // Sheet state
    @State private var selectedDeposit: WalletManager.UnclaimedBitcoinDepositUI? = nil
    @State private var isClaiming: Bool = false

    // Alerts
    @State private var alertMessage: String? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {

                headerCard

                if isLoadingDeposits {
                    loadingCard
                } else if deposits.isEmpty {
                    emptyCard
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(deposits) { deposit in
                                depositCard(deposit)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Bitcoin Claims")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshBTCPrice()
            Task { await loadDeposits() }
        }
        .refreshable {
            refreshBTCPrice()
            await loadDeposits()
        }
        .sheet(item: $selectedDeposit) { deposit in
            claimSheet(deposit: deposit)
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
    }
}

// MARK: - Header

private extension BitcoinPending {

    var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bitcoin Deposits")
                .font(.headline)
                .foregroundColor(.white)

            Text("""
            Network fees rise and fall based on Bitcoin network congestion. We let you choose when you want to claim the deposit to give you maximum control over costs.
            """)
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color.splitInputSurface)
        .cornerRadius(16)
    }

    var loadingCard: some View {
        VStack(spacing: 10) {
            ProgressView().tint(.white)
            Text("Loading deposits…")
                .foregroundColor(.gray)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.splitInputSurface)
        .cornerRadius(16)
    }

    var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundColor(blue)

            Text("No deposits to claim.")
                .foregroundColor(.white)
                .font(.headline)

            Text("Bitcoin deposits coming to your onchain wallet address will appear here.")
                .foregroundColor(.gray)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.splitInputSurface)
        .cornerRadius(16)
    }
}

// MARK: - Deposit Cards

private extension BitcoinPending {

    func depositCard(_ deposit: WalletManager.UnclaimedBitcoinDepositUI) -> some View {
        Button {
            selectedDeposit = deposit
        } label: {
            VStack(alignment: .leading, spacing: 12) {

                // Amount line: sats • USD (inline)
                HStack {
                    Text("\(deposit.amountSats.formatted()) sats")
                        .foregroundColor(.white)
                        .font(.headline)

                    if let usd = usdString(fromSats: deposit.amountSats) {
                        Text("• \(usd)")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                    }

                    Spacer()
                }

                if let feeSats = deposit.requiredFeeSats {

                    Text("Network Fee")
                        .foregroundColor(.gray)
                        .font(.footnote)

                    // Fee line: sats • USD (inline)
                    HStack {
                        Text("\(feeSats.formatted()) sats")
                            .foregroundColor(.white)
                            .font(.subheadline)

                        if let feeUSD = usdString(fromSats: feeSats) {
                            Text("• \(feeUSD)")
                                .foregroundColor(.gray)
                                .font(.subheadline)
                        }

                        Spacer()
                    }
                } else if let failure = deposit.failureReason {
                    Text(failure)
                        .foregroundColor(.gray)
                        .font(.footnote)
                } else {
                    Text("Fee details unavailable.")
                        .foregroundColor(.gray)
                        .font(.footnote)
                }

                // Visual CTA (card remains the only tap target)
                HStack {
                    Spacer()
                    Text("Claim")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(pink)
                        )
                }
            }
            .padding()
            .background(Color.splitInputSurface)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Claim Sheet (clean + simple)

private extension BitcoinPending {

    func claimSheet(deposit: WalletManager.UnclaimedBitcoinDepositUI) -> some View {

        let bg = Color.black.opacity(0.95)
        let surface = Color.white.opacity(0.06)
        let surfaceStroke = Color.white.opacity(0.10)

        return ZStack {
            bg.ignoresSafeArea()

            VStack(spacing: 18) {

                // Top bar
                HStack {
                    Text("Deposit")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Button {
                        selectedDeposit = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.65))
                            .padding(10)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 4)

                // Hero amount
                VStack(spacing: 10) {
                    Text("\(deposit.amountSats.formatted()) sats")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let usd = usdString(fromSats: deposit.amountSats) {
                        Text(usd)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.white.opacity(0.60))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(surfaceStroke, lineWidth: 1)
                        )
                )

                // Fee row (only if needed)
                if let feeSats = deposit.requiredFeeSats {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Network fee")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundColor(.white.opacity(0.55))

                            if let feeUSD = usdString(fromSats: feeSats) {
                                Text(feeUSD)
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundColor(.white.opacity(0.40))
                            }
                        }

                        Spacer()

                        Text("\(feeSats.formatted()) sats")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(.white)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }

                Spacer()

                // Primary CTA pinned to bottom
                Button {
                    Task { await claimNow(deposit: deposit) }
                } label: {
                    HStack(spacing: 10) {
                        if isClaiming {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isClaiming ? "Claiming…" : "Claim Now")
                            .font(.system(.headline, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(pink)
                    )
                    .foregroundColor(.white)
                }
                .disabled(isClaiming)
                .opacity(isClaiming ? 0.75 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
    }
}

// MARK: - Actions / Helpers

private extension BitcoinPending {

    func loadDeposits() async {
        guard !isLoadingDeposits else { return }
        isLoadingDeposits = true

        do {
            deposits = try await walletManager.getUnclaimedBitcoinDeposits()
        } catch {
            alertMessage = error.localizedDescription
        }

        isLoadingDeposits = false
    }

    func claimNow(deposit: WalletManager.UnclaimedBitcoinDepositUI) async {

        guard let feeRate = deposit.requiredFeeRateSatPerVbyte else { return }

        isClaiming = true

        do {
            try await walletManager.claimDepositWithRate(
                txid: deposit.txid,
                vout: deposit.vout,
                satPerVbyte: feeRate
            )

            selectedDeposit = nil
            await loadDeposits()

        } catch {
            alertMessage = error.localizedDescription
        }

        isClaiming = false
    }

    // Same as CustomerIndexView
    func refreshBTCPrice() {
        guard !isRefreshingBTCPrice else { return }
        isRefreshingBTCPrice = true

        fetchBitcoinPriceUSD { price in
            btcPriceUSD = price
            isRefreshingBTCPrice = false
        } onError: { _ in
            isRefreshingBTCPrice = false
        }
    }

    func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    func usdString(fromSats sats: UInt64) -> String? {
        guard let btcPriceUSD else { return nil }
        let btc = Double(sats) / 100_000_000
        let usd = btc * btcPriceUSD
        return formatUSD(usd)
    }
}
