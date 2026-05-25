//
//  ShareExtensionDataCleanup.swift
//  Split Rewards
//
//  Created by TeeVee on 5/13/26.
//

import Foundation

enum ShareExtensionDataCleanup {
    private static let appGroupIdentifier = AppConfig.sharedAppGroupIdentifier
    private static let cleanupCompletedKey = "split.shareExtensionDataCleanup.completed.v1"
    private static let draftsDirectoryName = "SharedMessageDrafts"
    private static let sharedDefaultsKeys = [
        "sharedMessageRecipientRecords",
        "shareExtensionOutgoingMessageRelayRecords",
    ]

    static func runIfNeeded() {
        let appDefaults = UserDefaults.standard
        guard !appDefaults.bool(forKey: cleanupCompletedKey) else {
            return
        }

        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }

        for key in sharedDefaultsKeys {
            sharedDefaults.removeObject(forKey: key)
        }

        var didRemoveDrafts = true
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            let draftsURL = containerURL.appendingPathComponent(draftsDirectoryName, isDirectory: true)
            if FileManager.default.fileExists(atPath: draftsURL.path) {
                do {
                    try FileManager.default.removeItem(at: draftsURL)
                } catch {
                    didRemoveDrafts = false
                }
            }
        }

        if didRemoveDrafts {
            appDefaults.set(true, forKey: cleanupCompletedKey)
        }
    }
}
