//
//  NWCCredentialStore.swift
//  Split Rewards
//
//  Created by TeeVee on 5/1/26.
//

import Foundation

final class NWCCredentialStore {
    static let shared = NWCCredentialStore()

    private let externalWalletStore = ExternalWalletStore.shared

    private init() {}

    func loadWallets() -> [NWCWalletCredentials] {
        externalWalletStore.wallets(kind: .nwc).compactMap { record in
            if case let .nwc(wallet) = record.payload {
                return wallet.withLabel(record.label)
            }

            return nil
        }
    }

    func activeWallet() -> NWCWalletCredentials? {
        let wallets = loadWallets()
        guard case let .external(kind, id) = externalWalletStore.activeSelection,
              kind == .nwc else {
            return wallets.first
        }

        return wallets.first { $0.id == id } ?? wallets.first
    }

    func activeWalletId() -> String? {
        activeWallet()?.id
    }

    @discardableResult
    func saveWallet(_ wallet: NWCWalletCredentials, makeActive: Bool = true) -> NWCWalletCredentials {
        externalWalletStore.saveNWCWallet(wallet, makeActive: makeActive)
    }

    func setActiveWallet(id: String) {
        externalWalletStore.setActiveSelection(.external(kind: .nwc, id: id))
    }

    func deleteWallet(id: String) {
        externalWalletStore.deleteWallet(kind: .nwc, id: id)
    }

    func renameWallet(id: String, label: String) {
        externalWalletStore.renameWallet(kind: .nwc, id: id, label: label)
    }

    func clearAll() {
        loadWallets().forEach { wallet in
            deleteWallet(id: wallet.id)
        }
    }
}
