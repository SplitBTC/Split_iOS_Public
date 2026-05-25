//
//  SparkSubwalletCredentialStore.swift
//  Split Rewards
//
//  Created by TeeVee on 5/12/26.
//

import Foundation

final class SparkSubwalletCredentialStore {
    static let shared = SparkSubwalletCredentialStore()

    private init() {}

    func loadWallets() -> [SparkSubwalletCredentials] {
        ExternalWalletStore.shared.wallets(kind: .sparkSubwallet).compactMap { record in
            if case let .sparkSubwallet(wallet) = record.payload {
                return wallet.withLabel(record.label)
            }

            return nil
        }
    }

    func loadWallet(id: String) -> SparkSubwalletCredentials? {
        loadWallets().first { $0.id == id }
    }

    func activeWallet() -> SparkSubwalletCredentials? {
        let wallets = loadWallets()
        guard case let .external(kind, id) = ExternalWalletStore.shared.activeSelection,
              kind == .sparkSubwallet else {
            return wallets.first
        }

        return wallets.first { $0.id == id } ?? wallets.first
    }

    @discardableResult
    func saveWallet(_ wallet: SparkSubwalletCredentials, makeActive: Bool = true) -> SparkSubwalletCredentials {
        ExternalWalletStore.shared.saveSparkSubwallet(wallet, makeActive: makeActive)
    }

    func deleteWallet(id: String) {
        ExternalWalletStore.shared.deleteWallet(kind: .sparkSubwallet, id: id)
    }

    func renameWallet(id: String, label: String) {
        ExternalWalletStore.shared.renameWallet(kind: .sparkSubwallet, id: id, label: label)
    }
}
