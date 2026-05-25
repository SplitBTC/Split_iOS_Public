//
//  CoreLightningTransactionStores.swift
//  Split Rewards
//
//  Created by TeeVee on 5/9/26.
//

import Foundation

enum CoreLightningTransactionStore {
    static func rows(forNodeId nodeId: String) async -> [WalletManager.TransactionRow] {
        await LNDTransactionStore.shared.rows(forNodeId: storageNodeId(nodeId))
    }

    static func merge(_ rows: [WalletManager.TransactionRow], forNodeId nodeId: String) async {
        await LNDTransactionStore.shared.merge(rows, forNodeId: storageNodeId(nodeId))
    }

    static func clear(nodeId: String) async {
        await LNDTransactionStore.shared.clear(nodeId: storageNodeId(nodeId))
    }

    static func storageNodeId(_ nodeId: String) -> String {
        "core-lightning:\(nodeId)"
    }
}

enum CoreLightningTransactionMetadataStore {
    static func metadata(nodeId: String, transactionIds: [String]) async -> [String: LNDTransactionMetadata] {
        await LNDTransactionMetadataStore.shared.metadata(
            nodeId: CoreLightningTransactionStore.storageNodeId(nodeId),
            transactionIds: transactionIds
        )
    }

    static func reportableStates(nodeId: String, transactionIds: [String]) async -> [String: Bool] {
        await LNDTransactionMetadataStore.shared.reportableStates(
            nodeId: CoreLightningTransactionStore.storageNodeId(nodeId),
            transactionIds: transactionIds
        )
    }

    static func userLogs(nodeId: String, transactionIds: [String]) async -> [String: String] {
        await LNDTransactionMetadataStore.shared.userLogs(
            nodeId: CoreLightningTransactionStore.storageNodeId(nodeId),
            transactionIds: transactionIds
        )
    }

    static func setReportable(
        nodeId: String,
        transactionId: String,
        transactionType: LNDTransactionMetadata.TransactionType,
        isReportable: Bool
    ) async {
        await LNDTransactionMetadataStore.shared.setReportable(
            nodeId: CoreLightningTransactionStore.storageNodeId(nodeId),
            transactionId: transactionId,
            transactionType: transactionType,
            isReportable: isReportable
        )
    }

    static func setUserLog(
        nodeId: String,
        transactionId: String,
        transactionType: LNDTransactionMetadata.TransactionType,
        userLog: String?
    ) async {
        await LNDTransactionMetadataStore.shared.setUserLog(
            nodeId: CoreLightningTransactionStore.storageNodeId(nodeId),
            transactionId: transactionId,
            transactionType: transactionType,
            userLog: userLog
        )
    }

    static func setDestinationMetadata(
        nodeId: String,
        transactionId: String,
        transactionType: LNDTransactionMetadata.TransactionType,
        destinationPubkey: String?,
        paymentHash: String?
    ) async {
        await LNDTransactionMetadataStore.shared.setDestinationMetadata(
            nodeId: CoreLightningTransactionStore.storageNodeId(nodeId),
            transactionId: transactionId,
            transactionType: transactionType,
            destinationPubkey: destinationPubkey,
            paymentHash: paymentHash
        )
    }

    static func ensureUsdSnapshots(
        for rows: [WalletManager.TransactionRow],
        nodeId: String,
        currentBtcUsdRate: Double?
    ) async {
        await LNDTransactionMetadataStore.shared.ensureUsdSnapshots(
            for: rows,
            nodeId: CoreLightningTransactionStore.storageNodeId(nodeId),
            currentBtcUsdRate: currentBtcUsdRate
        )
    }

    static func clear(nodeId: String) async {
        await LNDTransactionMetadataStore.shared.clear(nodeId: CoreLightningTransactionStore.storageNodeId(nodeId))
    }
}
