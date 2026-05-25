//
//  EclairCredentialStore.swift
//  Split Rewards
//
//  Created by TeeVee on 5/19/26.
//

import Foundation

final class EclairCredentialStore {
    static let shared = EclairCredentialStore()

    private let externalWalletStore = ExternalWalletStore.shared

    private init() {}

    func loadNodes() -> [EclairNodeCredentials] {
        externalWalletStore.wallets(kind: .eclair).compactMap { record in
            if case let .eclair(node) = record.payload {
                return node.withLabel(record.label)
            }

            return nil
        }
    }

    func activeNode() -> EclairNodeCredentials? {
        let nodes = loadNodes()
        guard case let .external(kind, id) = externalWalletStore.activeSelection,
              kind == .eclair else {
            return nodes.first
        }

        return nodes.first { $0.id == id } ?? nodes.first
    }

    func activeNodeId() -> String? {
        activeNode()?.id
    }

    @discardableResult
    func saveNode(_ node: EclairNodeCredentials, makeActive: Bool = true) -> EclairNodeCredentials {
        externalWalletStore.saveEclairNode(node, makeActive: makeActive)
    }

    func setActiveNode(id: String) {
        externalWalletStore.setActiveSelection(.external(kind: .eclair, id: id))
    }

    func deleteNode(id: String) {
        externalWalletStore.deleteWallet(kind: .eclair, id: id)
    }

    func renameNode(id: String, label: String) {
        externalWalletStore.renameWallet(kind: .eclair, id: id, label: label)
    }

    func clearAll() {
        loadNodes().forEach { node in
            deleteNode(id: node.id)
        }
    }
}

