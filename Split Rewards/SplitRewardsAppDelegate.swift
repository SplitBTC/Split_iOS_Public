//
//  SplitRewardsAppDelegate.swift
//  Split Rewards
//
//  Created by TeeVee on 3/21/26.
//

import UIKit
import UserNotifications

final class SplitRewardsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        Task { @MainActor in
            MessagingDeviceTokenManager.shared.registerForRemoteNotifications()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            MessagingDeviceTokenManager.shared.updateAPNsDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let pushType = extractMessagingPushType(from: userInfo) else {
            completionHandler(.noData)
            return
        }

        Task { @MainActor in
            if pushType == "messaging.new_message",
               application.applicationState != .active {
                MessagingNotificationBadgeManager.shared.ensureMinimumUnreadBadgeCount()
            }
            let didSync: Bool
            if pushType == "messaging.rekey_required" || pushType == "messaging.outgoing_status" {
                didSync = await MessagingPushSyncCoordinator.shared.handleOutgoingStatusPush()
            } else {
                didSync = await MessagingPushSyncCoordinator.shared.handleIncomingMessagePush()
            }
            completionHandler(didSync ? .newData : .noData)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        guard isMessagingNotification(userInfo) else {
            completionHandler([])
            return
        }

        Task { @MainActor in
            _ = await MessagingPushSyncCoordinator.shared.handleIncomingMessagePush()
        }

        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        guard isMessagingNotification(userInfo) else {
            completionHandler()
            return
        }

        Task { @MainActor in
            if let conversationId = extractConversationId(from: userInfo) {
                MessagingNotificationRouter.shared.queueConversationRoute(conversationId)
            }
            _ = await MessagingPushSyncCoordinator.shared.handleIncomingMessagePush()
            completionHandler()
        }
    }

    private func isMessagingNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        extractMessagingPushType(from: userInfo) == "messaging.new_message"
    }

    private func extractMessagingPushType(from userInfo: [AnyHashable: Any]) -> String? {
        guard let pushType = userInfo["type"] as? String else {
            return nil
        }

        switch pushType {
        case "messaging.new_message", "messaging.rekey_required", "messaging.outgoing_status":
            return pushType
        default:
            return nil
        }
    }

    private func extractConversationId(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo["conversationId"] as? String
    }
}
