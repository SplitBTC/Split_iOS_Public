//
//  NearbyCouponsView.swift
//  Split Rewards
//
//  Created by OpenAI on 4/14/26.
//

import SwiftUI

struct NearbyCouponsView: View {
    private let background = Color.splitAppBlack
    private let cardSurface = Color.splitCardSurface
    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 32)

                Image(systemName: "tag.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [blue, pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 82, height: 82)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )

                VStack(spacing: 14) {
                    Text("Promo feature coming soon.")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Here we will bring you exclusive special offers from top quality brands.")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(cardSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 16)

                Spacer(minLength: 48)
            }
        }
        .navigationTitle("Promos")
        .navigationBarTitleDisplayMode(.inline)
    }
}
