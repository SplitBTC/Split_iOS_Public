////
//  NavBarView.swift
//  Split Rewards
//
//  Created by TeeVee on 1/20/25.
//

import SwiftUI
import UIKit

struct NavBarView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var messageStore = MessageStore.shared

    @Binding var selectedTab: Tab

    enum Tab {
        case wallet, rewards, promos, messages
    }

    private let pink = Color.splitBrandPink

    init(selectedTab: Binding<Tab>) {
        self._selectedTab = selectedTab
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.10)

        let normalColor = UIColor.white
        let selectedColor = UIColor(Color.splitBrandPink)

        appearance.stackedLayoutAppearance.normal.iconColor = normalColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: normalColor
        ]
        appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: selectedColor
        ]

        appearance.inlineLayoutAppearance.normal.iconColor = normalColor
        appearance.inlineLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: normalColor
        ]
        appearance.inlineLayoutAppearance.selected.iconColor = selectedColor
        appearance.inlineLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: selectedColor
        ]

        appearance.compactInlineLayoutAppearance.normal.iconColor = normalColor
        appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: normalColor
        ]
        appearance.compactInlineLayoutAppearance.selected.iconColor = selectedColor
        appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: selectedColor
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = normalColor
        UITabBar.appearance().tintColor = selectedColor
        UITabBar.appearance().isTranslucent = true
    }

    private var hasWallet: Bool {
        if case .ready = walletManager.state { return true }
        return false
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            CustomerIndexView()
                .tabItem {
                    Label("Wallet", systemImage: "bitcoinsign.circle")
                }
                .tag(Tab.wallet)
            
            RewardsView()
                .tabItem {
                    Label("Rewards", systemImage: "atom")
                }
                .tag(Tab.rewards)
                .disabled(!hasWallet)
                .opacity(hasWallet ? 1 : 0.35)

            NearbyCouponsView()
                .tabItem {
                    Label("Promos", systemImage: "tag.fill")
                }
                .tag(Tab.promos)

            MessageView()
                .tabItem {
                    Label("Messages", systemImage: "bubble.circle")
                }
                .tag(Tab.messages)
                .badge(messageStore.unreadMessageCount > 0 ? messageStore.unreadMessageCount : 0)
                .disabled(!hasWallet)
                .opacity(hasWallet ? 1 : 0.35)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accentColor(pink)
        .toolbarBackground(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .onChange(of: walletManager.state) { _, newState in
            if case .noWallet = newState {
                selectedTab = .wallet
            }
        }
    }
}
