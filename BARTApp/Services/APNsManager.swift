import Foundation
import UIKit
import UserNotifications

/// Manages APNs (Apple Push Notification service) registration and token handling.
/// Sends device tokens to the gateway via HTTP POST for push notification delivery.
class APNsManager: NSObject, ObservableObject {
    static let shared = APNsManager()

    // MARK: - Published State

    @Published var deviceToken: String?
    @Published var registrationState: RegistrationState = .unregistered

    enum RegistrationState: Equatable {
        case unregistered
        case registering
        case registered
        case failed(String)
    }

    // MARK: - Private Properties

    private var lastRegisteredToken: String?
    private let session: URLSession

    // MARK: - Init

    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        super.init()
    }

    // MARK: - Permission Request

    /// Request notification permissions from the user
    func requestPermissions() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)

            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                print("[APNs] Permission granted, registering for remote notifications")
            } else {
                print("[APNs] Permission denied by user")
            }

            return granted
        } catch {
            print("[APNs] Permission request failed: \(error)")
            return false
        }
    }

    // MARK: - Token Handling

    /// Called when APNs returns a device token
    func handleDeviceToken(_ tokenData: Data) {
        let tokenString = tokenData.map { String(format: "%02.2hhx", $0) }.joined()

        Task { @MainActor in
            self.deviceToken = tokenString
        }

        // Store token in UserDefaults
        UserDefaults.standard.set(tokenString, forKey: "apnsDeviceToken")

        // Log redacted token
        let redacted = String(tokenString.prefix(8)) + "..." + String(tokenString.suffix(4))
        print("[APNs] Received device token: \(redacted)")

        // Send to gateway
        Task {
            await sendTokenToGateway(tokenString)
        }
    }

    /// Called when APNs registration fails
    func handleRegistrationError(_ error: Error) {
        print("[APNs] Registration failed: \(error.localizedDescription)")

        Task { @MainActor in
            self.registrationState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Gateway Registration

    /// Send the device token to the gateway server via HTTP POST
    func sendTokenToGateway(_ token: String) async {
        // Don't re-register the same token
        guard token != lastRegisteredToken else {
            print("[APNs] Token already registered with gateway")
            return
        }

        // Get gateway URL from UserDefaults
        guard let gatewayURLString = UserDefaults.standard.string(forKey: "gatewayURL"),
              let gatewayURL = URL(string: gatewayURLString) else {
            print("[APNs] No gateway URL configured in UserDefaults")
            await MainActor.run {
                self.registrationState = .failed("No gateway URL configured")
            }
            return
        }

        // Get device ID from UserDefaults
        guard let deviceId = UserDefaults.standard.string(forKey: "deviceId") else {
            print("[APNs] No device ID configured in UserDefaults")
            await MainActor.run {
                self.registrationState = .failed("No device ID configured")
            }
            return
        }

        // Build registration endpoint URL
        let registerURL = gatewayURL.appendingPathComponent("/api/push/register")

        // Build request body
        let body: [String: Any] = [
            "deviceToken": token,
            "deviceId": deviceId
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            print("[APNs] Failed to serialize registration body")
            return
        }

        // Create request
        var request = URLRequest(url: registerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        await MainActor.run {
            self.registrationState = .registering
        }

        let redactedToken = String(token.prefix(8)) + "..." + String(token.suffix(4))
        print("[APNs] Registering token \(redactedToken) with gateway at \(registerURL)")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APNsError.invalidResponse
            }

            if (200...299).contains(httpResponse.statusCode) {
                print("[APNs] Token registered successfully")
                lastRegisteredToken = token

                await MainActor.run {
                    self.registrationState = .registered
                }
            } else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("[APNs] Registration failed with status \(httpResponse.statusCode): \(message)")

                await MainActor.run {
                    self.registrationState = .failed("HTTP \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("[APNs] Registration request failed: \(error)")

            await MainActor.run {
                self.registrationState = .failed(error.localizedDescription)
            }
        }
    }

    /// Re-register a stored token (e.g., after app restart or reconnection)
    func reregisterStoredToken() async {
        guard let storedToken = UserDefaults.standard.string(forKey: "apnsDeviceToken") else {
            print("[APNs] No stored token to re-register")
            return
        }

        // Force re-registration by clearing last registered
        lastRegisteredToken = nil
        await sendTokenToGateway(storedToken)
    }

    // MARK: - Notification Handling

    /// Handle a push notification payload when app is in foreground
    func handleForegroundNotification(_ userInfo: [AnyHashable: Any]) {
        print("[APNs] Foreground notification received: \(userInfo)")

        // Extract session key if present
        if let sessionKey = userInfo["sessionKey"] as? String {
            NotificationCenter.default.post(
                name: .apnsNotificationReceived,
                object: nil,
                userInfo: ["sessionKey": sessionKey, "foreground": true]
            )
        }
    }

    /// Handle a push notification payload when app is in background
    func handleBackgroundNotification(
        _ userInfo: [AnyHashable: Any],
        completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("[APNs] Background notification received: \(userInfo)")

        // Check for silent push (content-available)
        if let aps = userInfo["aps"] as? [String: Any],
           aps["content-available"] as? Int == 1 {
            // Silent push - notify app to fetch new data
            NotificationCenter.default.post(
                name: .apnsSilentPushReceived,
                object: nil,
                userInfo: userInfo as? [String: Any]
            )
            completionHandler(.newData)
            return
        }

        // Regular push notification
        if let sessionKey = userInfo["sessionKey"] as? String {
            NotificationCenter.default.post(
                name: .apnsNotificationReceived,
                object: nil,
                userInfo: ["sessionKey": sessionKey, "foreground": false]
            )
        }

        completionHandler(.newData)
    }

    /// Handle notification tap action
    func handleNotificationTap(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo

        print("[APNs] Notification tapped: \(response.actionIdentifier)")

        // Extract session key and navigate to it
        if let sessionKey = userInfo["sessionKey"] as? String {
            NotificationCenter.default.post(
                name: .apnsNotificationTapped,
                object: nil,
                userInfo: ["sessionKey": sessionKey, "action": response.actionIdentifier]
            )
        }
    }
}

// MARK: - Errors

enum APNsError: LocalizedError {
    case invalidResponse
    case noGatewayURL
    case noDeviceId

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .noGatewayURL:
            return "No gateway URL configured"
        case .noDeviceId:
            return "No device ID configured"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let apnsNotificationReceived = Notification.Name("APNsNotificationReceived")
    static let apnsSilentPushReceived = Notification.Name("APNsSilentPushReceived")
    static let apnsNotificationTapped = Notification.Name("APNsNotificationTapped")
}
