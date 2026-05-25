//
//  WalletManagementView.swift
//  Split Rewards
//
//  Created by TeeVee on 12/17/25.
//
import SwiftUI

struct WalletManagementView: View {
    let blue = Color.splitBrandBlue
    let pink = Color.splitBrandPink

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    Text("Wallet")
                        .font(.largeTitle)
                        .fontWeight(.heavy)
                        .foregroundColor(blue)
                        .padding(.top, 8)

                    Text("This is a self-custodial Bitcoin wallet app. The wallet is designed to facilate Bitcoin transactions via Spark and the Lightning Network. Your wallet functions as your Split account. It is extremely important that you maintain possession of your wallet seedphrase. Split cannot help recover your seedphrase or your account.")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(blue)

                    Divider()
                        .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink {
                            RemoveWalletConfirmView()
                        } label: {
                            Text("Remove Wallet From This Device")
                                .font(.headline)
                                .fontWeight(.heavy)
                                .foregroundColor(pink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        }

                        Text("You can only restore your wallet using your seed phrase. Split cannot recover wallets or funds.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }

                    Spacer(minLength: 30)
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
