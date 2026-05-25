//
//  RewardsSheet.swift
//  Split Rewards
//
//  Created by TeeVee on 2/7/26.
//
import SwiftUI

struct RewardsHowItWorksSheet: View {
@Environment(\.dismiss) private var dismiss

    let pink: Color
    let blue: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.97)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack(alignment: .center) {
                    Text("How Rewards Work")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.80))
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.top, 6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Each month, Split sets aside Bitcoin in a rewards pool that’s paid out at the end of the month.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)

                        Text("You earn a share of the Bitcoin pool based on the Bitcoin you spend with verified merchants.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("Your Bitcoin reward is determined by your percentage of spend relative to the platform. If you account for 5% of the platform's reward eligible spending, you receive 5% of the Bitcoin rewards pot.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)

                        Text("As reward eligible spend grows, we will grow the size of the Bitcoin rewards pool. Our goal is simple: Drive real world Bitcoin transactions.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)

                        Text("If you have any questions, comments, suggestions, or concerns please reach out to support@example.com")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)

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
                                    .foregroundColor(.white.opacity(0.65))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .background(cardBackground(accentColor: blue))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .padding(.vertical, 6)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Got it")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [pink.opacity(0.85), blue.opacity(0.70)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Shared background helper (keep here OR move to a shared helpers file)

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
    RewardsHowItWorksSheet(
        pink: .splitBrandPink,
        blue: .splitBrandBlue
    )
}
