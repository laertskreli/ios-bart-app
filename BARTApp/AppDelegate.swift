import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {

    // Reference to gateway connection (set by BARTApp)
    weak var gateway: GatewayConnection?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared

        // Register for remote notifications
        registerForPushNotifications()

        return true
    }

    // MARK: - Push Notification Registration

    func registerForPushNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                print("❌ Push authorization error: \(error)")
                return
            }

            print("📱 Push notification permission: \(granted ? "granted" : "denied")")

            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    // MARK: - APNs Token Callbacks

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Convert token to hex string
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 APNs device token: \(tokenString)")

        // Store token for later use
        UserDefaults.standard.set(tokenString, forKey: "apnsDeviceToken")

        // Send token to gateway if connected
        Task { @MainActor in
            gateway?.registerPushToken(tokenString)
        }

        // Post notification so other parts of app can react
        NotificationCenter.default.post(
            name: .didReceiveAPNsToken,
            object: nil,
            userInfo: ["token": tokenString]
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for APNs: \(error)")

        // Common errors:
        // - Simulator doesn't support push notifications
        // - Missing push notification capability in provisioning profile
        // - App ID not configured for push in Apple Developer Portal
    }

    // MARK: - Remote Notification Received (Background/Terminated)

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("📬 Received remote notification: \(userInfo)")

        // Handle silent push notification
        if let aps = userInfo["aps"] as? [String: Any],
           aps["content-available"] as? Int == 1 {
            // Silent push - fetch new data
            handleSilentPush(userInfo: userInfo, completionHandler: completionHandler)
            return
        }

        // Handle regular push with content
        handlePushNotification(userInfo: userInfo)
        completionHandler(.newData)
    }

    private func handleSilentPush(
        userInfo: [AnyHashable: Any],
        completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("🔇 Processing silent push...")

        Task { @MainActor in
            // If gateway is connected, fetch new messages
            if let gateway = gateway, gateway.connectionState.isConnected {
                gateway.fetchSessionsList()
                completionHandler(.newData)
            } else {
                // Try to reconnect briefly to fetch messages
                gateway?.connect()

                // Give it a few seconds then complete
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                gateway?.fetchSessionsList()
                completionHandler(.newData)
            }
        }
    }

    private func handlePushNotification(userInfo: [AnyHashable: Any]) {
        // Extract message info from push payload
        guard let sessionKey = userInfo["sessionKey"] as? String else {
            print("⚠️ Push missing sessionKey")
            return
        }

        let sender = userInfo["sender"] as? String ?? "BART"
        let message = userInfo["message"] as? String ?? "New message"

        // Show local notification if app is in background
        if UIApplication.shared.applicationState != .active {
            Task { @MainActor in
                NotificationManager.shared.sendMessageNotification(
                    from: sender,
                    content: message,
                    sessionKey: sessionKey
                )
            }
        }

        // Post notification to open the session
        NotificationCenter.default.post(
            name: .openClawOpenSession,
            object: nil,
            userInfo: ["sessionKey": sessionKey]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let didReceiveAPNsToken = Notification.Name("didReceiveAPNsToken")
}
