//
//  ExternalWalletStore.swift
//  Split Rewards
//
//  Created by TeeVee on 5/6/26.
//

import Foundation
import Security

enum ExternalWalletKind: String, Codable, CaseIterable, Equatable {
    case lnd
    case nwc
    case coreLightning
    case eclair
    case sparkSubwallet

    var displayName: String {
        switch self {
        case .lnd:
            return "LND Node"
        case .nwc:
            return "NWC Wallet"
        case .coreLightning:
            return "Core Lightning Node"
        case .eclair:
            return "Eclair Node"
        case .sparkSubwallet:
            return "Spark Wallet"
        }
    }
}

enum SpendWalletSelection: Codable, Equatable {
    case spark
    case external(kind: ExternalWalletKind, id: String)

    var storageValue: String {
        switch self {
        case .spark:
            return "spark"
        case let .external(kind, id):
            return "external:\(kind.rawValue):\(id)"
        }
    }

    init(storageValue: String?) {
        guard let storageValue = storageValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !storageValue.isEmpty,
              storageValue != "spark" else {
            self = .spark
            return
        }

        let parts = storageValue.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3,
              parts[0] == "external",
              let kind = ExternalWalletKind(rawValue: parts[1]),
              !parts[2].isEmpty else {
            self = .spark
            return
        }

        self = .external(kind: kind, id: parts[2])
    }
}

enum ExternalWalletPayload: Codable, Equatable {
    case lnd(LNDNodeCredentials)
    case nwc(NWCWalletCredentials)
    case coreLightning(CoreLightningNodeCredentials)
    case eclair(EclairNodeCredentials)
    case sparkSubwallet(SparkSubwalletCredentials)

    private enum CodingKeys: String, CodingKey {
        case kind
        case lnd
        case nwc
        case coreLightning
        case eclair
        case sparkSubwallet
    }

    var kind: ExternalWalletKind {
        switch self {
        case .lnd:
            return .lnd
        case .nwc:
            return .nwc
        case .coreLightning:
            return .coreLightning
        case .eclair:
            return .eclair
        case .sparkSubwallet:
            return .sparkSubwallet
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ExternalWalletKind.self, forKey: .kind)

        switch kind {
        case .lnd:
            self = .lnd(try container.decode(LNDNodeCredentials.self, forKey: .lnd))
        case .nwc:
            self = .nwc(try container.decode(NWCWalletCredentials.self, forKey: .nwc))
        case .coreLightning:
            self = .coreLightning(try container.decode(CoreLightningNodeCredentials.self, forKey: .coreLightning))
        case .eclair:
            self = .eclair(try container.decode(EclairNodeCredentials.self, forKey: .eclair))
        case .sparkSubwallet:
            self = .sparkSubwallet(try container.decode(SparkSubwalletCredentials.self, forKey: .sparkSubwallet))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case let .lnd(credentials):
            try container.encode(credentials, forKey: .lnd)
        case let .nwc(credentials):
            try container.encode(credentials, forKey: .nwc)
        case let .coreLightning(credentials):
            try container.encode(credentials, forKey: .coreLightning)
        case let .eclair(credentials):
            try container.encode(credentials, forKey: .eclair)
        case let .sparkSubwallet(credentials):
            try container.encode(credentials, forKey: .sparkSubwallet)
        }
    }
}

struct ExternalWalletRecord: Codable, Equatable, Identifiable {
    let id: String
    let kind: ExternalWalletKind
    var label: String
    let createdAt: Date
    var updatedAt: Date
    var lastVerifiedAt: Date?
    var payload: ExternalWalletPayload

    var storageAccount: String {
        Self.storageAccount(kind: kind, id: id)
    }

    static func storageAccount(kind: ExternalWalletKind, id: String) -> String {
        "external:\(kind.rawValue):\(id)"
    }
}

final class ExternalWalletStore {
    static let shared = ExternalWalletStore()

    private let walletService = "com.split.rewards.external-wallets"
    private let activeService = "com.split.rewards.active-spend-wallet"
    private let activeAccount = "active"
    private let defaultWalletCounterKey = "split.externalWallet.defaultLabelCounter.v1"
    private let legacyCleanupKey = "split.externalWallet.legacyCleanupCompleted.v1"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadWallets() -> [ExternalWalletRecord] {
        keychainAccounts(service: walletService)
            .compactMap { readRecord(account: $0) }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }

                return lhs.createdAt < rhs.createdAt
            }
    }

    func loadWallet(kind: ExternalWalletKind, id: String) -> ExternalWalletRecord? {
        readRecord(account: ExternalWalletRecord.storageAccount(kind: kind, id: id))
    }

    func wallets(kind: ExternalWalletKind) -> [ExternalWalletRecord] {
        loadWallets().filter { $0.kind == kind }
    }

    func saveLNDNode(_ node: LNDNodeCredentials, makeActive: Bool = true) -> LNDNodeCredentials {
        let existing = loadWallet(kind: .lnd, id: node.id)
        let label = existing?.label ?? node.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? nextDefaultWalletLabel()
        let now = Date()
        let labeledNode = node.withLabel(label)
        let record = ExternalWalletRecord(
            id: labeledNode.id,
            kind: .lnd,
            label: label,
            createdAt: existing?.createdAt ?? labeledNode.connectedAt,
            updatedAt: now,
            lastVerifiedAt: labeledNode.lastVerifiedAt,
            payload: .lnd(labeledNode)
        )

        saveRecord(record)

        if makeActive {
            setActiveSelection(.external(kind: .lnd, id: labeledNode.id))
        }

        return labeledNode
    }

    func saveNWCWallet(_ wallet: NWCWalletCredentials, makeActive: Bool = true) -> NWCWalletCredentials {
        let existing = loadWallet(kind: .nwc, id: wallet.id)
        let label = existing?.label ?? wallet.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? nextDefaultWalletLabel()
        let now = Date()
        let labeledWallet = wallet.withLabel(label)
        let record = ExternalWalletRecord(
            id: labeledWallet.id,
            kind: .nwc,
            label: label,
            createdAt: existing?.createdAt ?? labeledWallet.connectedAt,
            updatedAt: now,
            lastVerifiedAt: labeledWallet.lastVerifiedAt,
            payload: .nwc(labeledWallet)
        )

        saveRecord(record)

        if makeActive {
            setActiveSelection(.external(kind: .nwc, id: labeledWallet.id))
        }

        return labeledWallet
    }

    func saveCoreLightningNode(
        _ node: CoreLightningNodeCredentials,
        makeActive: Bool = true
    ) -> CoreLightningNodeCredentials {
        let existing = loadWallet(kind: .coreLightning, id: node.id)
        let label = existing?.label ?? node.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? nextDefaultWalletLabel()
        let now = Date()
        let labeledNode = node.withLabel(label)
        let record = ExternalWalletRecord(
            id: labeledNode.id,
            kind: .coreLightning,
            label: label,
            createdAt: existing?.createdAt ?? labeledNode.connectedAt,
            updatedAt: now,
            lastVerifiedAt: labeledNode.lastVerifiedAt,
            payload: .coreLightning(labeledNode)
        )

        saveRecord(record)

        if makeActive {
            setActiveSelection(.external(kind: .coreLightning, id: labeledNode.id))
        }

        return labeledNode
    }

    func saveEclairNode(
        _ node: EclairNodeCredentials,
        makeActive: Bool = true
    ) -> EclairNodeCredentials {
        let existing = loadWallet(kind: .eclair, id: node.id)
        let label = existing?.label ?? node.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? nextDefaultWalletLabel()
        let now = Date()
        let labeledNode = node.withLabel(label)
        let record = ExternalWalletRecord(
            id: labeledNode.id,
            kind: .eclair,
            label: label,
            createdAt: existing?.createdAt ?? labeledNode.connectedAt,
            updatedAt: now,
            lastVerifiedAt: labeledNode.lastVerifiedAt,
            payload: .eclair(labeledNode)
        )

        saveRecord(record)

        if makeActive {
            setActiveSelection(.external(kind: .eclair, id: labeledNode.id))
        }

        return labeledNode
    }

    func saveSparkSubwallet(
        _ wallet: SparkSubwalletCredentials,
        makeActive: Bool = true
    ) -> SparkSubwalletCredentials {
        let existing = loadWallet(kind: .sparkSubwallet, id: wallet.id)
        let label = wallet.displayName
        let now = Date()
        let labeledWallet = wallet.withLabel(label)
        let record = ExternalWalletRecord(
            id: labeledWallet.id,
            kind: .sparkSubwallet,
            label: label,
            createdAt: existing?.createdAt ?? labeledWallet.connectedAt,
            updatedAt: now,
            lastVerifiedAt: labeledWallet.lastVerifiedAt,
            payload: .sparkSubwallet(labeledWallet)
        )

        saveRecord(record)

        if makeActive {
            setActiveSelection(.external(kind: .sparkSubwallet, id: labeledWallet.id))
        }

        return labeledWallet
    }

    func renameWallet(kind: ExternalWalletKind, id: String, label rawLabel: String) {
        guard var record = loadWallet(kind: kind, id: id) else { return }

        let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }

        record.label = label
        record.updatedAt = Date()

        switch record.payload {
        case let .lnd(node):
            record.payload = .lnd(node.withLabel(label))
        case let .nwc(wallet):
            record.payload = .nwc(wallet.withLabel(label))
        case let .coreLightning(node):
            record.payload = .coreLightning(node.withLabel(label))
        case let .eclair(node):
            record.payload = .eclair(node.withLabel(label))
        case let .sparkSubwallet(wallet):
            record.payload = .sparkSubwallet(wallet.withLabel(label))
        }

        saveRecord(record)
    }

    func deleteWallet(kind: ExternalWalletKind, id: String) {
        deleteValue(service: walletService, account: ExternalWalletRecord.storageAccount(kind: kind, id: id))

        if activeSelection == .external(kind: kind, id: id) {
            setActiveSelection(.spark)
        }
    }

    var activeSelection: SpendWalletSelection {
        SpendWalletSelection(storageValue: readValue(service: activeService, account: activeAccount))
    }

    func setActiveSelection(_ selection: SpendWalletSelection) {
        saveValue(selection.storageValue, service: activeService, account: activeAccount)
    }

    func reconcileActiveSelection() -> SpendWalletSelection {
        switch activeSelection {
        case .spark:
            return .spark
        case let .external(kind, id):
            if loadWallet(kind: kind, id: id) != nil {
                return activeSelection
            }

            setActiveSelection(.spark)
            return .spark
        }
    }

    func clearLegacyExternalWalletStorageIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: legacyCleanupKey) else { return }

        deleteValue(service: "com.split.rewards.lnd", account: "split.lnd.nodes.v1")
        deleteValue(service: "com.split.rewards.lnd", account: "split.lnd.activeNodeId.v1")
        deleteValue(service: "com.split.rewards.nwc", account: "split.nwc.wallets.v1")
        deleteValue(service: "com.split.rewards.nwc", account: "split.nwc.activeWalletId.v1")
        UserDefaults.standard.removeObject(forKey: "split.activeSpendWallet.v1")
        UserDefaults.standard.set(true, forKey: legacyCleanupKey)
    }

    private func readRecord(account: String) -> ExternalWalletRecord? {
        guard let value = readValue(service: walletService, account: account),
              let data = value.data(using: .utf8) else {
            return nil
        }

        return try? decoder.decode(ExternalWalletRecord.self, from: data)
    }

    private func saveRecord(_ record: ExternalWalletRecord) {
        guard let data = try? encoder.encode(record),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        saveValue(json, service: walletService, account: record.storageAccount)
    }

    private func nextDefaultWalletLabel() -> String {
        let next = UserDefaults.standard.integer(forKey: defaultWalletCounterKey) + 1
        UserDefaults.standard.set(next, forKey: defaultWalletCounterKey)
        return "Wallet #\(next)"
    }

    private func saveValue(_ value: String, service: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }

        deleteValue(service: service, account: account)

        var query = baseQuery(service: service, account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemAdd(query as CFDictionary, nil)
    }

    private func readValue(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func deleteValue(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }

    private func keychainAccounts(service: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return [] }

        if let items = result as? [[String: Any]] {
            return items.compactMap { $0[kSecAttrAccount as String] as? String }
        }

        if let item = result as? [String: Any],
           let account = item[kSecAttrAccount as String] as? String {
            return [account]
        }

        return []
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
