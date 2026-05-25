//
//  EclairTransactionStores.swift
//  Split Rewards
//
//  Created by TeeVee on 5/19/26.
//

import Foundation

enum EclairTransactionStore {
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
        "eclair:\(nodeId)"
    }
}

enum EclairTransactionMetadataStore {
    static func metadata(nodeId: String, transactionIds: [String]) async -> [String: LNDTransactionMetadata] {
        await LNDTransactionMetadataStore.shared.metadata(
            nodeId: EclairTransactionStore.storageNodeId(nodeId),
            transactionIds: transactionIds
        )
    }

    static func reportableStates(nodeId: String, transactionIds: [String]) async -> [String: Bool] {
        await LNDTransactionMetadataStore.shared.reportableStates(
            nodeId: EclairTransactionStore.storageNodeId(nodeId),
            transactionIds: transactionIds
        )
    }

    static func userLogs(nodeId: String, transactionIds: [String]) async -> [String: String] {
        await LNDTransactionMetadataStore.shared.userLogs(
            nodeId: EclairTransactionStore.storageNodeId(nodeId),
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
            nodeId: EclairTransactionStore.storageNodeId(nodeId),
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
            nodeId: EclairTransactionStore.storageNodeId(nodeId),
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
            nodeId: EclairTransactionStore.storageNodeId(nodeId),
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
            nodeId: EclairTransactionStore.storageNodeId(nodeId),
            currentBtcUsdRate: currentBtcUsdRate
        )
    }

    static func clear(nodeId: String) async {
        await LNDTransactionMetadataStore.shared.clear(nodeId: EclairTransactionStore.storageNodeId(nodeId))
    }
}
