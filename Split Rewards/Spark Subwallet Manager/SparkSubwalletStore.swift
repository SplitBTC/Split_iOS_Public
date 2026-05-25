//
//  SparkSubwalletStore.swift
//  Split Rewards
//
//  Created by TeeVee on 5/12/26.
//

import Foundation

final class SparkSubwalletStore {
    static let shared = SparkSubwalletStore()

    private let seedKeyPrefix = "split.sparkSubwallet.seed."

    private init() {}

    func seedKey(for id: String) -> String {
        "\(seedKeyPrefix)\(id)"
    }

    func temporaryStorageDirectoryName() -> String {
        "pending-\(UUID().uuidString)"
    }

    func readSeed(for wallet: SparkSubwalletCredentials) -> String? {
        KeychainHelper.read(forKey: wallet.seedKeychainKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }

    func saveSeed(_ seed: String, for wallet: SparkSubwalletCredentials) {
        KeychainHelper.save(seed, forKey: wallet.seedKeychainKey)
    }

    func deleteSeed(for wallet: SparkSubwalletCredentials) {
        KeychainHelper.delete(forKey: wallet.seedKeychainKey)
    }

    func storageDirectoryURL(for wallet: SparkSubwalletCredentials) throws -> URL {
        try storageDirectoryURL(named: wallet.storageDirectoryName)
    }

    func storageDirectoryURL(named name: String) throws -> URL {
        let base = try baseStorageDirectoryURL()
        return base.appendingPathComponent(name, isDirectory: true)
    }

    func createStorageDirectory(named name: String) throws -> URL {
        let url = try storageDirectoryURL(named: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func deleteStorageDirectory(for wallet: SparkSubwalletCredentials) {
        do {
            let url = try storageDirectoryURL(for: wallet)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("⚠️ Failed to delete Spark sub-wallet storage: \(error.localizedDescription)")
        }
    }

    private func baseStorageDirectoryURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let base = appSupport.appendingPathComponent("breez-spark-subwallets", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
