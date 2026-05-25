//
//  Split_RewardsApp.swift
//  Split Rewards
//
//  Created by TeeVee on 1/11/25.
//

import SwiftUI

@main
struct Split_RewardsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(SplitRewardsAppDelegate.self) private var appDelegate

    @StateObject private var walletManager = WalletManager()
    @StateObject private var authManager = AuthManager()   // ✅ ADD THIS
    @StateObject private var lndWalletManager = LNDWalletManager()
    @StateObject private var nwcWalletManager = NWCWalletManager()
    @StateObject private var coreLightningWalletManager = CoreLightningWalletManager()
    @StateObject private var eclairWalletManager = EclairWalletManager()
    @StateObject private var sparkSubwalletManager = SparkSubwalletManager()
    @StateObject private var activeSpendWalletStore = ActiveSpendWalletStore()
    @StateObject private var toastManager = ToastManager()
    @StateObject private var appState = AppState()
    @StateObject private var appLockManager = AppLockManager()

    @State private var isLoading = true
    @State private var isVersionValid = true

    // MARK: - App version check (unchanged)

    private func checkAppVersion() {
        guard let url = URL(string: "\(AppConfig.baseURL)/rewards-version-check") else {
            print("Invalid version check URL")
            isVersionValid = true
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Version check error: \(error.localizedDescription)")
                    isVersionValid = true
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let minimumVersion = json["minimumVersion"] as? String else {
                    print("Invalid version check response")
                    isVersionValid = true
                    return
                }

                let currentVersion =
                    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"

                isVersionValid = compareVersions(currentVersion, minimumVersion)
            }
        }.resume()
    }

    private func compareVersions(_ current: String, _ required: String) -> Bool {
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }
        let requiredComponents = required.split(separator: ".").compactMap { Int($0) }

        for (c, r) in zip(currentComponents, requiredComponents) {
            if c < r { return false }
            if c > r { return true }
        }
        return currentComponents.count >= requiredComponents.count
    }

    @MainActor
    private func warmTorForActiveWalletIfNeeded() {
        guard selectedSpendWalletUsesTor() else { return }

        Task {
            _ = try? await RemoteNodeTorManager.shared.bootstrapIfNeeded()
        }
    }

    @MainActor
    private func selectedSpendWalletUsesTor() -> Bool {
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

    // MARK: - App body

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                NavigationStack {
                    if isLoading {
                        ProgressView()
                    } else if !isVersionValid {
                        ForcedUpdateView()
                    } else {
                        MainTemplateView()
                    }
                }
                .task {
                    ShareExtensionDataCleanup.runIfNeeded()
                    checkAppVersion()
                    walletManager.toastManager = toastManager
                    lndWalletManager.toastManager = toastManager
                    sparkSubwalletManager.toastManager = toastManager

                    // ✅ FIX: authManager now exists in this scope
                    await walletManager.configure(authManager: authManager)
                    activeSpendWalletStore.reconcileWithStoredWallets()
                    warmTorForActiveWalletIfNeeded()

                    isLoading = false

                    Task {
                        try? await lndWalletManager.restoreActiveNode()
                        await lndWalletManager.startInvoiceEventListenerIfPossible()
                    }

                    Task {
                        try? await nwcWalletManager.restoreActiveWallet()
                        if activeSpendWalletStore.isNWCActive {
                            _ = try? await nwcWalletManager.refreshBalance()
                            await nwcWalletManager.startNotificationListenerIfPossible()
                        }
                    }

                    Task {
                        try? await coreLightningWalletManager.restoreActiveNode()
                        if activeSpendWalletStore.isCoreLightningActive {
                            _ = try? await coreLightningWalletManager.refreshBalance()
                        }
                    }

                    Task {
                        try? await eclairWalletManager.restoreActiveNode()
                        if activeSpendWalletStore.isEclairActive {
                            _ = try? await eclairWalletManager.refreshBalance()
                        }
                    }

                    Task {
                        if activeSpendWalletStore.isSparkSubwalletActive {
                            try? await sparkSubwalletManager.restoreWalletIfNeeded()
                        }
                    }
                }

                ToastView()
                    .padding(.top, 0)

                if appLockManager.isLocked {
                    AppLockOverlay(
                        isAuthenticating: appLockManager.isAuthenticating,
                        errorMessage: appLockManager.errorMessage,
                        onUnlock: {
                            appLockManager.requestUnlock()
                        }
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .onAppear {
                walletManager.toastManager = toastManager
                lndWalletManager.toastManager = toastManager
                sparkSubwalletManager.toastManager = toastManager
                MessagingDeviceTokenManager.shared.configure(
                    authManager: authManager,
                    walletManager: walletManager
                )
                MessagingPushSyncCoordinator.shared.configure(
                    authManager: authManager,
                    walletManager: walletManager
                )
                Task { @MainActor in
                    _ = await MessagingPushSyncCoordinator.shared.processPendingPushIfPossible()
                }
                appLockManager.handleScenePhaseChange(scenePhase)
                if scenePhase == .active {
                    warmTorForActiveWalletIfNeeded()
                    Task {
                        await lndWalletManager.startInvoiceEventListenerIfPossible()
                        await nwcWalletManager.startNotificationListenerIfPossible()
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                appLockManager.handleScenePhaseChange(newPhase)

                switch newPhase {
                case .active:
                    warmTorForActiveWalletIfNeeded()
                    Task {
                        await lndWalletManager.startInvoiceEventListenerIfPossible()
                        await nwcWalletManager.startNotificationListenerIfPossible()
                    }
                case .inactive, .background:
                    lndWalletManager.stopInvoiceEventListener()
                    nwcWalletManager.stopNotificationListener()
                @unknown default:
                    lndWalletManager.stopInvoiceEventListener()
                    nwcWalletManager.stopNotificationListener()
                }
            }
            .onChange(of: activeSpendWalletStore.activeWallet) { _, _ in
                if scenePhase == .active {
                    warmTorForActiveWalletIfNeeded()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .paymentRequestInvoiceSettled)) { notification in
                guard let invoice = notification.userInfo?["invoice"] as? String else {
                    return
                }

                Task {
                    await PaymentRequestStatusManager.shared.handleSettledInvoice(
                        invoice,
                        authManager: authManager,
                        walletManager: walletManager
                    )
                }
            }
            .environmentObject(walletManager)
            .environmentObject(authManager)   // ✅ OPTIONAL but recommended
            .environmentObject(lndWalletManager)
            .environmentObject(nwcWalletManager)
            .environmentObject(coreLightningWalletManager)
            .environmentObject(eclairWalletManager)
            .environmentObject(sparkSubwalletManager)
            .environmentObject(activeSpendWalletStore)
            .environmentObject(toastManager)
            .environmentObject(appState)
        }
    }
}
