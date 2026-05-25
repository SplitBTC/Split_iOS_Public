//
//  ActiveSpendWalletStore.swift
//  Split Rewards
//
//  Created by TeeVee on 4/21/26.
//

import Foundation

@MainActor
final class ActiveSpendWalletStore: ObservableObject {
    @Published private(set) var activeWallet: SpendWalletSelection

    init() {
        ExternalWalletStore.shared.clearLegacyExternalWalletStorageIfNeeded()
        activeWallet = ExternalWalletStore.shared.reconcileActiveSelection()
    }

    var isSparkActive: Bool {
        activeWallet == .spark
    }

    var isLndActive: Bool {
        if case let .external(kind, _) = activeWallet {
            return kind == .lnd
        }

        return false
    }

    var isNWCActive: Bool {
        if case let .external(kind, _) = activeWallet {
            return kind == .nwc
        }

        return false
    }

    var isCoreLightningActive: Bool {
        if case let .external(kind, _) = activeWallet {
            return kind == .coreLightning
        }

        return false
    }

    var isEclairActive: Bool {
        if case let .external(kind, _) = activeWallet {
            return kind == .eclair
        }

        return false
    }

    var isSparkSubwalletActive: Bool {
        if case let .external(kind, _) = activeWallet {
            return kind == .sparkSubwallet
        }

        return false
    }

    var activeExternalWalletId: String? {
        if case let .external(_, id) = activeWallet {
            return id
        }

        return nil
    }

    var activeWalletLabel: String {
        switch activeWallet {
        case .spark:
            return "Split"
        case let .external(kind, id):
            return ExternalWalletStore.shared.loadWallet(kind: kind, id: id)?.label ?? kind.displayName
        }
    }

    func setSparkActive() {
        setActiveWallet(.spark)
    }

    func setLndActiveIfAvailable() -> Bool {
        guard let node = LNDCredentialStore.shared.activeNode() else {
            setSparkActive()
            return false
        }

        setActiveWallet(.external(kind: .lnd, id: node.id))
        return true
    }

    func setNWCActiveIfAvailable() -> Bool {
        guard let wallet = NWCCredentialStore.shared.activeWallet() else {
            setSparkActive()
            return false
        }

        setActiveWallet(.external(kind: .nwc, id: wallet.id))
        return true
    }

    func setCoreLightningActiveIfAvailable() -> Bool {
        guard let node = CoreLightningCredentialStore.shared.activeNode() else {
            setSparkActive()
            return false
        }

        setActiveWallet(.external(kind: .coreLightning, id: node.id))
        return true
    }

    func setEclairActiveIfAvailable() -> Bool {
        guard let node = EclairCredentialStore.shared.activeNode() else {
            setSparkActive()
            return false
        }

        setActiveWallet(.external(kind: .eclair, id: node.id))
        return true
    }

    func setSparkSubwalletActiveIfAvailable() -> Bool {
        guard let wallet = SparkSubwalletCredentialStore.shared.activeWallet() else {
            setSparkActive()
            return false
        }

        setActiveWallet(.external(kind: .sparkSubwallet, id: wallet.id))
        return true
    }

    func setExternalWalletActive(kind: ExternalWalletKind, id: String) -> Bool {
        guard ExternalWalletStore.shared.loadWallet(kind: kind, id: id) != nil else {
            setSparkActive()
            return false
        }

        setActiveWallet(.external(kind: kind, id: id))
        return true
    }

    @discardableResult
    func toggle() -> SpendWalletSelection {
        switch activeWallet {
        case .spark:
            _ = setLndActiveIfAvailable()
        case .external:
            setSparkActive()
        }

        return activeWallet
    }

    func reconcileWithStoredNode() {
        if case let .external(kind, id) = activeWallet,
           ExternalWalletStore.shared.loadWallet(kind: kind, id: id) == nil {
            setSparkActive()
        }
    }

    func reconcileWithStoredWallets() {
        setActiveWallet(ExternalWalletStore.shared.reconcileActiveSelection())
    }

    private func setActiveWallet(_ wallet: SpendWalletSelection) {
        guard activeWallet != wallet else { return }
        activeWallet = wallet
        ExternalWalletStore.shared.setActiveSelection(wallet)
    }
}
