//
//  LNDCredentialStore.swift
//  Split Rewards
//
//  Created by TeeVee on 4/21/26.
//

import Foundation

final class LNDCredentialStore {
    static let shared = LNDCredentialStore()

    private let externalWalletStore = ExternalWalletStore.shared

    private init() {}

    func loadNodes() -> [LNDNodeCredentials] {
        externalWalletStore.wallets(kind: .lnd).compactMap { record in
            if case let .lnd(node) = record.payload {
                return node.withLabel(record.label)
            }

            return nil
        }
    }

    func activeNode() -> LNDNodeCredentials? {
        let nodes = loadNodes()
        guard case let .external(kind, id) = externalWalletStore.activeSelection,
              kind == .lnd else {
            return nodes.first
        }

        return nodes.first { $0.id == id } ?? nodes.first
    }

    func activeNodeId() -> String? {
        activeNode()?.id
    }

    @discardableResult
    func saveNode(_ node: LNDNodeCredentials, makeActive: Bool = true) -> LNDNodeCredentials {
        externalWalletStore.saveLNDNode(node, makeActive: makeActive)
    }

    func setActiveNode(id: String) {
        externalWalletStore.setActiveSelection(.external(kind: .lnd, id: id))
    }

    func deleteNode(id: String) {
        externalWalletStore.deleteWallet(kind: .lnd, id: id)
    }

    func renameNode(id: String, label: String) {
        externalWalletStore.renameWallet(kind: .lnd, id: id, label: label)
    }

    func clearAll() {
        loadNodes().forEach { node in
            deleteNode(id: node.id)
        }
    }
}
