//  RewardsInfo.swift
//  Split Rewards
//
//  Created by TeeVee on 2/10/26.
//
import SwiftUI

struct RewardsInfo: View {
    let blue = Color.splitBrandBlue
    let pink = Color.splitBrandPink

    var body: some View {
        ZStack {
            Color.black.opacity(0.97)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    Text("How Rewards Work")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, 8)

                    Text("Each month, Split sets aside Bitcoin in a rewards pool that’s paid out at the end of the month.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("You earn a share of the Bitcoin pool based on the Bitcoin you spend with verified merchants.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("You get credited for all of the Bitcoin you spend with verified merchants.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Your Bitcoin reward is determined by your percentage of spend relative to the platform. If you account for 5% of the platform's reward eligible spending, you receive 5% of the Bitcoin rewards pot.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("As reward eligible spend grows, we will grow the size of the Bitcoin rewards pool. Our goal is simple: Drive real world Bitcoin transactions.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("If you have any questions, comments, suggestions, or concerns please reach out to support@example.com")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    // Reward eligible spend card
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(pink)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Reward Eligible Spend")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.85))

                            Text("Rewards are based on Bitcoin spent with verified merchants listed in the app.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.70))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .background(cardBackground(accentColor: blue))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                    // Disclaimer card (kept exactly as it was)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Disclaimer")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.85))

                        Text("Rewards are discretionary and can change over time. Lightning payments are generally final. Bitcoin value is volatile, The rewards pool is a set Bitcoin amount. The fiat value (USD) will shift up or down throughout the month.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.70))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .navigationTitle("Rewards")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Background helper

private func cardBackground(accentColor: Color) -> some View {
    ZStack {
        Color.white.opacity(0.06)

        LinearGradient(
            colors: [
                accentColor.opacity(0.10),
                Color.white.opacity(0.02),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .opacity(0.55)
    }
}

#Preview {
    NavigationStack {
        RewardsInfo()
    }
}
