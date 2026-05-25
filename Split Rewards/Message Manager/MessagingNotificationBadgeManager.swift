//
//  MessagingNotificationBadgeManager.swift
//  Split Rewards
//
//  Created by TeeVee on 3/28/26.
//

import UIKit
import UserNotifications

@MainActor
final class MessagingNotificationBadgeManager {
    static let shared = MessagingNotificationBadgeManager()
    private let cachedBadgeCountKey = "split.messaging.cachedBadgeCount"

    private init() {}

    func syncUnreadMessageCount(_ unreadCount: Int) {
        let badgeCount = max(0, unreadCount)
        let application = UIApplication.shared
        let currentBadgeCount = cachedBadgeCount

        let resolvedBadgeCount: Int
        if application.applicationState == .active {
            resolvedBadgeCount = badgeCount
        } else {
            // While the app is backgrounded, never lower the visible badge count from a
            // transient stale read of local state. We can still raise it immediately.
            resolvedBadgeCount = max(currentBadgeCount, badgeCount)
        }

        applyBadgeCount(resolvedBadgeCount)
    }

    func ensureMinimumUnreadBadgeCount(_ minimumCount: Int = 1) {
        let currentBadgeCount = cachedBadgeCount
        applyBadgeCount(max(currentBadgeCount, max(0, minimumCount)))
    }

    private func applyBadgeCount(_ badgeCount: Int) {
        cachedBadgeCount = badgeCount
        UNUserNotificationCenter.current().setBadgeCount(badgeCount, withCompletionHandler: nil)
    }

    private var cachedBadgeCount: Int {
        get {
            max(0, UserDefaults.standard.integer(forKey: cachedBadgeCountKey))
        }
        set {
            UserDefaults.standard.set(max(0, newValue), forKey: cachedBadgeCountKey)
        }
    }
}
