//
//  KeychainHelper.swift
//  Split Rewards
//
//  Created by TeeVee on 6/3/25.
//

import Foundation
import Security

struct KeychainHelper {
    /// Single-wallet-per-device seed storage key.
    static let walletSeedKey = "split.wallet.seed"

    /// A stable service namespace for all Keychain entries from this app.
    private static let service = AppConfig.keychainService
    private static let sharedAccessGroup = AppConfig.sharedKeychainAccessGroup

    static func save(_ value: String, forKey key: String) {
        delete(forKey: key)

        if !replaceValue(value, forKey: key, accessGroup: sharedAccessGroup) {
            _ = replaceValue(value, forKey: key, accessGroup: nil)
        }
    }

    static func read(forKey key: String) -> String? {
        if let value = readValue(forKey: key, accessGroup: sharedAccessGroup) {
            return value
        }

        if let legacyValue = readValue(forKey: key, accessGroup: nil) {
            let migratedToSharedGroup = replaceValue(
                legacyValue,
                forKey: key,
                accessGroup: sharedAccessGroup
            )

            if migratedToSharedGroup,
               readValue(forKey: key, accessGroup: sharedAccessGroup) == legacyValue {
                deleteLegacyOnly(forKey: key)
            }

            return legacyValue
        }

        return nil
    }

    static func delete(forKey key: String) {
        SecItemDelete(query(forKey: key, accessGroup: sharedAccessGroup) as CFDictionary)
        SecItemDelete(query(forKey: key, accessGroup: nil) as CFDictionary)
    }

    private static func deleteLegacyOnly(forKey key: String) {
        SecItemDelete(query(forKey: key, accessGroup: nil) as CFDictionary)
    }

    private static func readValue(forKey key: String, accessGroup: String?) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching(
            readQuery(forKey: key, accessGroup: accessGroup) as CFDictionary,
            &result
        )

        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }

        return str
    }

    @discardableResult
    private static func replaceValue(forKey key: String, data: Data, accessGroup: String?) -> Bool {
        SecItemDelete(query(forKey: key, accessGroup: accessGroup) as CFDictionary)

        let status = SecItemAdd(
            addQuery(forKey: key, data: data, accessGroup: accessGroup) as CFDictionary,
            nil
        )

        return status == errSecSuccess
    }

    @discardableResult
    private static func replaceValue(_ value: String, forKey key: String, accessGroup: String?) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return replaceValue(forKey: key, data: data, accessGroup: accessGroup)
    }

    private static func query(forKey key: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private static func readQuery(forKey key: String, accessGroup: String?) -> [String: Any] {
        var query = query(forKey: key, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private static func addQuery(forKey key: String, data: Data, accessGroup: String?) -> [String: Any] {
        var query = query(forKey: key, accessGroup: accessGroup)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return query
    }
}
