//  RewardsView.swift
//  Split Rewards
//
//  Updated for monthly pot + RewardStats endpoint
//
import SwiftUI

struct RewardsView: View {
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var authManager: AuthManager

    // Brand
    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink
    private let indigo = Color.splitIndigo
    private let cardSurface = Color.splitCardSurface
    private let hairline = Color.white.opacity(0.10)

    @State private var isLoading: Bool = false
    @State private var hasAttemptedLoad: Bool = false
    @State private var errorMessage: String?
    @State private var stats: RewardStatsResponse?
    @State private var showHowRewardsWork: Bool = false
    @State private var showMerchantHelp: Bool = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            backgroundAtmosphere

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if !hasAttemptedLoad || isLoading {
                            loadingStateCard

                        } else if let errorMessage {
                            stateMessageCard(
                                title: "Rewards unavailable",
                                message: errorMessage,
                                accentColor: pink,
                                isError: true
                            )

                        } else if stats == nil {
                            stateMessageCard(
                                title: "No rewards data yet",
                                message: "Spend through Split and this screen will start to fill in.",
                                accentColor: blue,
                                isError: false
                            )

                        } else if let stats {
                            rewardsHero(stats: stats)
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 34)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .task {
            await initialLoad()
        }
        .refreshable {
            await refresh()
            walletManager.refreshBtcPriceFromCoinbase()
        }
        .fullScreenCover(isPresented: $showHowRewardsWork) {
            RewardsHowItWorksSheet(pink: pink, blue: blue)
        }
        .sheet(isPresented: $showMerchantHelp) {
            MerchantRewardsHelpSheet()
        }
    }

    private var backgroundAtmosphere: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.045),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 170)

            Spacer()
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rewards")
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(.white)
            }

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                Button {
                    showMerchantHelp = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Circle()
                                    .stroke(blue.opacity(0.35), lineWidth: 1)
                            )

                        Image(systemName: "storefront.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How to report a merchant")

                Button {
                    showHowRewardsWork = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )

                        Image(systemName: "atom")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How rewards work")
            }
        }
    }

    @ViewBuilder
    private func rewardsHero(stats: RewardStatsResponse) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            projectedRewardSummary(stats: stats)

            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Your Stats")

                rewardsDetailRow(
                    title: "Your Share",
                    subtitle: "Of this month's rewards pot",
                    value: shareString(fromBps: stats.stats.shareBps),
                    detail: nil,
                    symbol: "percent",
                    accentColor: pink
                )

                rewardsDetailRow(
                    title: "Your Reward Spend",
                    subtitle: transactionsLabel(stats.user.transactions),
                    value: centsToUSD(stats.user.rewardSpendCents),
                    detail: nil,
                    symbol: "person.crop.circle.fill",
                    accentColor: blue
                )

                rewardsDetailRow(
                    title: "Your Lifetime BTC",
                    subtitle: "Paid rewards",
                    value: btcString(fromSats: stats.stats.lifetimeEarningsSats),
                    detail: nil,
                    symbol: "checkmark.seal.fill",
                    accentColor: pink
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Platform")

                monthlyActivityCard(stats: stats)
            }
        }
    }

    private func projectedRewardSummary(stats: RewardStatsResponse) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Monthly Rewards")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.66))

                    Text("Current projection")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.46))
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Text(stats.monthKey)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.76))

                    Circle()
                        .fill(pink)
                        .frame(width: 7, height: 7)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
            }

            HStack(spacing: 12) {
                heroRewardMetric(
                    title: "Your Rewards",
                    primaryValue: usdString(fromSats: stats.stats.projectedEarningsSats),
                    secondaryValue: btcString(fromSats: stats.stats.projectedEarningsSats),
                    accentColor: pink
                )

                heroRewardMetric(
                    title: "Rewards Pot",
                    primaryValue: usdString(fromSats: stats.monthlyPot.sats),
                    secondaryValue: btcString(fromSats: stats.monthlyPot.sats),
                    accentColor: blue
                )
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.splitAppBlack)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 20, x: 0, y: 12)
    }

    private var loadingStateCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)

            Text("Loading rewards stats...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(hairline, lineWidth: 1)
        )
        .shadow(color: indigo.opacity(0.20), radius: 14, x: 0, y: 8)
    }

    private func stateMessageCard(
        title: String,
        message: String,
        accentColor: Color,
        isError: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            Text(message)
                .font(.subheadline)
                .foregroundColor(
                    isError
                    ? .red.opacity(0.9)
                    : .white.opacity(0.70)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accentColor.opacity(0.28), lineWidth: 1)
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundColor(.white.opacity(0.44))
            .padding(.horizontal, 2)
    }

    private func heroRewardMetric(
        title: String,
        primaryValue: String,
        secondaryValue: String,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(accentColor)
                .frame(width: 30, height: 3)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.58))

            Text(primaryValue)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(secondaryValue)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.58))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func rewardsDetailRow(
        title: String,
        subtitle: String,
        value: String,
        detail: String?,
        symbol: String,
        accentColor: Color
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 46, height: 46)

                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.86))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.48))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)

                if let detail {
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.50))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func monthlyActivityCard(stats: RewardStatsResponse) -> some View {
        VStack(spacing: 0) {
            activityComparisonRow(
                title: "Platform Reward Spend",
                value: centsToUSD(stats.platform.rewardSpendCents),
                detail: transactionsLabel(stats.platform.transactions)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func activityComparisonRow(
        title: String,
        value: String,
        detail: String?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                if let detail {
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.44))
                }
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 13)
    }

    private func btcString(fromSats sats: Int) -> String {
        let btc = Double(sats) / 100_000_000.0
        return String(format: "₿%.8f", btc)
    }

    private func usdString(fromSats sats: Int) -> String {
        guard let rate = walletManager.btcUsdRate else { return "$—" }
        let btc = Double(sats) / 100_000_000.0
        let usd = btc * rate

        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2

        return nf.string(from: NSNumber(value: usd)) ?? "$—"
    }

    private func shareString(fromBps bps: Int) -> String {
        let pct = Double(bps) / 100.0
        return String(format: "%.2f%%", pct)
    }

    private func transactionsLabel(_ count: Int) -> String {
        count == 1 ? "1 transaction" : "\(count) transactions"
    }

    @MainActor
    private func initialLoad() async {
        // First attempt immediately
        await refresh()
        walletManager.refreshBtcPriceFromCoinbase()

        // If we still have neither data nor error, the initial attempt likely happened
        // before the session/cookie was actually usable (or got cancelled). Retry briefly.
        if stats == nil && errorMessage == nil {
            for _ in 0..<2 {
                try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
                await refresh()
                if stats != nil || errorMessage != nil { break }
            }
        }
    }

    @MainActor
    private func refresh() async {
        if isLoading { return }

        hasAttemptedLoad = true
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let resp = try await RewardsStatsAPI.fetchRewardsStats(
                authManager: authManager,
                walletManager: walletManager
            )
            stats = resp
        } catch is CancellationError {
            // don’t show an error for cancellation
        } catch let urlError as URLError where urlError.code == .cancelled {
            // don’t show an error for cancellation
        } catch {
            errorMessage = "Failed to load rewards stats."
        }
    }
}

private struct MerchantRewardsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {

                        Text("Paid a bitcoin-accepting merchant and didn't get rewarded? Submit the business from your transaction details. We'll add them to our rewards program ASAP.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        Text("Just tap the")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.62))

                        Image(systemName: "storefront.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color.white)

                        Text("in your transaction.")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.62))
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle("Merchant Help")
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
        .presentationDetents([.height(260)])
    }
}

// MARK: - Cards

private struct PotCard: View {
    @EnvironmentObject private var walletManager: WalletManager

    let monthKey: String
    let potSats: Int
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("REWARDS POT")
                        .font(.caption.weight(.heavy))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.50))

                    Text("₿ Rewards Pot")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(monthKey)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.64))
                }

                Spacer()

                HeroHaloIcon(symbol: "bitcoinsign.circle.fill", accentColor: accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                statRow(label: "(USD)", value: usdString(fromSats: potSats))
                statRow(label: "(BTC)", value: btcString(fromSats: potSats))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 182, alignment: .topLeading)
        .padding(16)
        .background(rewardPanelBackground(accentColor: accentColor))
    }

    @ViewBuilder
    private func statRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 58, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.90))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func btcString(fromSats sats: Int) -> String {
        let btc = Double(sats) / 100_000_000.0
        return String(format: "₿%.8f", btc)
    }

    private func usdString(fromSats sats: Int) -> String {
        guard let rate = walletManager.btcUsdRate else { return "$—" }
        let btc = Double(sats) / 100_000_000.0
        let usd = btc * rate

        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2

        return nf.string(from: NSNumber(value: usd)) ?? "$—"
    }
}

private struct PlatformTotalsCard: View {
    let rewardSpendCents: Int
    let transactions: Int
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PLATFORM")
                        .font(.caption.weight(.heavy))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.50))

                    Text("Platform Totals")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("All users • this month")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.64))
                }

                Spacer()

                HeroHaloIcon(symbol: "globe.americas.fill", accentColor: accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                statRow(label: "Reward Spend", value: centsToUSD(rewardSpendCents))
                statRow(label: "Transactions", value: "\(transactions)")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 182, alignment: .topLeading)
        .padding(16)
        .background(rewardPanelBackground(accentColor: accentColor))
    }

    @ViewBuilder
    private func statRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 130, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.90))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct UserTotalsCard: View {
    let rewardSpendCents: Int
    let transactions: Int
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOU")
                        .font(.caption.weight(.heavy))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.50))

                    Text("Your Totals")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("This month")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.64))
                }

                Spacer()

                HeroHaloIcon(symbol: "person.crop.circle.fill", accentColor: accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                statRow(label: "Reward Spend", value: centsToUSD(rewardSpendCents))
                statRow(label: "Transactions", value: "\(transactions)")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 182, alignment: .topLeading)
        .padding(16)
        .background(rewardPanelBackground(accentColor: accentColor))
    }

    @ViewBuilder
    private func statRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 130, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.90))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ProjectionCard: View {
    @EnvironmentObject private var walletManager: WalletManager

    let shareBps: Int
    let projectedEarningsSats: Int
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROJECTION")
                        .font(.caption.weight(.heavy))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.50))

                    Text("Projected Rewards")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("If month ended now")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.64))
                }

                Spacer()

                HeroHaloIcon(symbol: "chart.line.uptrend.xyaxis", accentColor: accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                statRow(label: "Your Share", value: shareString(fromBps: shareBps))
                statRow(label: "(USD)", value: usdString(fromSats: projectedEarningsSats))
                statRow(label: "(BTC)", value: btcString(fromSats: projectedEarningsSats))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 182, alignment: .topLeading)
        .padding(16)
        .background(rewardPanelBackground(accentColor: accentColor))
    }

    @ViewBuilder
    private func statRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 78, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.90))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func shareString(fromBps bps: Int) -> String {
        // bps = 1/100 of a percent
        let pct = Double(bps) / 100.0
        return String(format: "%.2f%%", pct)
    }

    private func btcString(fromSats sats: Int) -> String {
        let btc = Double(sats) / 100_000_000.0
        return String(format: "₿%.8f", btc)
    }

    private func usdString(fromSats sats: Int) -> String {
        guard let rate = walletManager.btcUsdRate else { return "$—" }
        let btc = Double(sats) / 100_000_000.0
        let usd = btc * rate

        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2

        return nf.string(from: NSNumber(value: usd)) ?? "$—"
    }
}

private struct TotalRewardsCard: View {
    let lifetimeEarningsSats: Int
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIFETIME")
                        .font(.caption.weight(.heavy))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.50))

                    Text("Total Rewards")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Lifetime earnings")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.64))
                }

                Spacer()

                HeroHaloIcon(symbol: "sparkle.magnifyingglass", accentColor: accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                statRow(label: "(BTC)", value: btcString(fromSats: lifetimeEarningsSats))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(rewardPanelBackground(accentColor: accentColor))
    }

    @ViewBuilder
    private func statRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.90))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func btcString(fromSats sats: Int) -> String {
        let btc = Double(sats) / 100_000_000.0
        return String(format: "₿%.8f", btc)
    }
}

// MARK: - Shared UI Helpers

private func rewardPanelBackground(accentColor: Color) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color(red: 12 / 255, green: 12 / 255, blue: 16 / 255))

        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        accentColor.opacity(0.88),
                        accentColor.opacity(0.40),
                        Color.black.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.10), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            )
    }
    .overlay(
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(Color.white.opacity(0.14), lineWidth: 1)
    )
    .shadow(color: accentColor.opacity(0.18), radius: 16, x: 0, y: 10)
}

private func centsToUSD(_ cents: Int) -> String {
    let dollars = Double(cents) / 100.0
    let nf = NumberFormatter()
    nf.numberStyle = .currency
    nf.currencyCode = "USD"
    nf.maximumFractionDigits = 2
    nf.minimumFractionDigits = 2
    return nf.string(from: NSNumber(value: dollars)) ?? "$—"
}

private struct MiniPill: View {
    let text: String
    let accentColor: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundColor(accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accentColor.opacity(0.16))
            .clipShape(Capsule())
    }
}

private struct HeroHaloIcon: View {
    let symbol: String
    let accentColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.18))
                .frame(width: 42, height: 42)

            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .frame(width: 42, height: 42)

            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
        }
    }
}

#Preview {
    RewardsView()
        .environmentObject(WalletManager())
        .environmentObject(AuthManager())
}
