//
//  CoreLightningCredentialStore.swift
//  Split Rewards
//
//  Created by TeeVee on 5/9/26.
//

import Foundation

final class CoreLightningCredentialStore {
    static let shared = CoreLightningCredentialStore()

    private let externalWalletStore = ExternalWalletStore.shared

    private init() {}

    func loadNodes() -> [CoreLightningNodeCredentials] {
        externalWalletStore.wallets(kind: .coreLightning).compactMap { record in
            if case let .coreLightning(node) = record.payload {
                return node.withLabel(record.label)
            }

            return nil
        }
    }

    func activeNode() -> CoreLightningNodeCredentials? {
        let nodes = loadNodes()
        guard case let .external(kind, id) = externalWalletStore.activeSelection,
              kind == .coreLightning else {
            return nodes.first
        }

        return nodes.first { $0.id == id } ?? nodes.first
    }

    func activeNodeId() -> String? {
        activeNode()?.id
    }

    @discardableResult
    func saveNode(_ node: CoreLightningNodeCredentials, makeActive: Bool = true) -> CoreLightningNodeCredentials {
        externalWalletStore.saveCoreLightningNode(node, makeActive: makeActive)
    }

    func setActiveNode(id: String) {
        externalWalletStore.setActiveSelection(.external(kind: .coreLightning, id: id))
    }

    func deleteNode(id: String) {
        externalWalletStore.deleteWallet(kind: .coreLightning, id: id)
    }

    func renameNode(id: String, label: String) {
        externalWalletStore.renameWallet(kind: .coreLightning, id: id, label: label)
    }

    func clearAll() {
        loadNodes().forEach { node in
            deleteNode(id: node.id)
        }
    }
}
