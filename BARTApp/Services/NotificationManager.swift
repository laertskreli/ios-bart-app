import Foundation
import UserNotifications
import UIKit

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    // MARK: - Published State

    @MainActor @Published var isAuthorized = false
    @MainActor @Published var settings = NotificationSettings.default

    // MARK: - Notification Categories

    enum Category: String {
        case message = "MESSAGE"
        case reminder = "REMINDER"
        case calendar = "CALENDAR"
        case emergency = "EMERGENCY"
        case subagent = "SUBAGENT"

        var identifier: String { rawValue }
    }

    // MARK: - Init

    override init() {
        super.init()
        Task { @MainActor in
            self.loadSettings()
        }
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge, .criticalAlert]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            await MainActor.run {
                self.isAuthorized = granted
            }
            if granted {
                registerCategories()
            }
            return granted
        } catch {
            print("❌ Notification authorization error: \(error)")
            return false
        }
    }

    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Categories & Actions

    private func registerCategories() {
        // Message actions
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type a message..."
        )

        let viewAction = UNNotificationAction(
            identifier: "VIEW",
            title: "View",
            options: .foreground
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: .destructive
        )

        // Emergency actions
        let acknowledgeAction = UNNotificationAction(
            identifier: "ACKNOWLEDGE",
            title: "Acknowledge",
            options: .foreground
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "Snooze 5 min",
            options: []
        )

        // Categories
        let messageCategory = UNNotificationCategory(
            identifier: Category.message.identifier,
            actions: [replyAction, viewAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        let reminderCategory = UNNotificationCategory(
            identifier: Category.reminder.identifier,
            actions: [viewAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        let calendarCategory = UNNotificationCategory(
            identifier: Category.calendar.identifier,
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        let emergencyCategory = UNNotificationCategory(
            identifier: Category.emergency.identifier,
            actions: [acknowledgeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let subagentCategory = UNNotificationCategory(
            identifier: Category.subagent.identifier,
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            messageCategory,
            reminderCategory,
            calendarCategory,
            emergencyCategory,
            subagentCategory
        ])
    }

    // MARK: - Send Notifications

    func sendMessageNotification(from sender: String, content: String, sessionKey: String) {
        guard settings.messagesEnabled else { return }

        let notification = UNMutableNotificationContent()
        notification.title = sender
        notification.body = content
        notification.sound = .default
        notification.categoryIdentifier = Category.message.identifier
        notification.userInfo = ["sessionKey": sessionKey]
        notification.threadIdentifier = sessionKey

        scheduleNotification(notification, identifier: "msg-\(UUID().uuidString)")
    }

    func sendReminderNotification(title: String, body: String, at date: Date? = nil) {
        guard settings.remindersEnabled else { return }

        let notification = UNMutableNotificationContent()
        notification.title = title
        notification.body = body
        notification.sound = .default
        notification.categoryIdentifier = Category.reminder.identifier

        if let date = date {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            scheduleNotification(notification, identifier: "reminder-\(UUID().uuidString)", trigger: trigger)
        } else {
            scheduleNotification(notification, identifier: "reminder-\(UUID().uuidString)")
        }
    }

    func sendCalendarNotification(event: String, time: String) {
        guard settings.calendarEnabled else { return }

        let notification = UNMutableNotificationContent()
        notification.title = "Upcoming Event"
        notification.body = "\(event) at \(time)"
        notification.sound = .default
        notification.categoryIdentifier = Category.calendar.identifier

        scheduleNotification(notification, identifier: "cal-\(UUID().uuidString)")
    }

    func sendEmergencyNotification(title: String, body: String) {
        guard settings.emergencyEnabled else { return }

        let notification = UNMutableNotificationContent()
        notification.title = "ALERT: \(title)"
        notification.body = body
        notification.categoryIdentifier = Category.emergency.identifier

        // Use critical alert for emergency (loud, bypasses DND)
        if settings.emergencyUseCritical {
            notification.sound = .defaultCritical
            notification.interruptionLevel = .critical
        } else {
            notification.sound = .default
            notification.interruptionLevel = .timeSensitive
        }

        scheduleNotification(notification, identifier: "emergency-\(UUID().uuidString)")
    }

    func sendSubagentNotification(label: String, status: String, sessionKey: String) {
        guard settings.subagentEnabled else { return }

        let notification = UNMutableNotificationContent()
        notification.title = "Subagent: \(label)"
        notification.body = "Status: \(status)"
        notification.sound = .default
        notification.categoryIdentifier = Category.subagent.identifier
        notification.userInfo = ["sessionKey": sessionKey]

        scheduleNotification(notification, identifier: "subagent-\(UUID().uuidString)")
    }

    private func scheduleNotification(
        _ content: UNMutableNotificationContent,
        identifier: String,
        trigger: UNNotificationTrigger? = nil
    ) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger ?? UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification: \(error)")
            }
        }
    }

    // MARK: - Settings Persistence

    private let settingsKey = "openclaw-notification-settings"

    @MainActor
    func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(NotificationSettings.self, from: data) else {
            return
        }
        self.settings = decoded
    }

    @MainActor
    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    @MainActor
    func updateSettings(_ newSettings: NotificationSettings) {
        self.settings = newSettings
        saveSettings()
    }
}

// MARK: - Notification Settings

struct NotificationSettings: Codable, Equatable {
    var messagesEnabled: Bool
    var remindersEnabled: Bool
    var calendarEnabled: Bool
    var emergencyEnabled: Bool
    var subagentEnabled: Bool
    var emergencyUseCritical: Bool  // Use critical alerts (loud, bypasses DND)

    static let `default` = NotificationSettings(
        messagesEnabled: true,
        remindersEnabled: true,
        calendarEnabled: true,
        emergencyEnabled: true,
        subagentEnabled: true,
        emergencyUseCritical: true
    )
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier

        Task { @MainActor in
            switch actionId {
            case "REPLY":
                if let textResponse = response as? UNTextInputNotificationResponse,
                   let sessionKey = userInfo["sessionKey"] as? String {
                    // Handle reply - could post to gateway
                    print("📝 Reply to \(sessionKey): \(textResponse.userText)")
                    NotificationCenter.default.post(
                        name: .openClawReply,
                        object: nil,
                        userInfo: ["sessionKey": sessionKey, "text": textResponse.userText]
                    )
                }

            case "VIEW":
                if let sessionKey = userInfo["sessionKey"] as? String {
                    NotificationCenter.default.post(
                        name: .openClawOpenSession,
                        object: nil,
                        userInfo: ["sessionKey": sessionKey]
                    )
                }

            case "ACKNOWLEDGE":
                print("✅ Emergency acknowledged")

            case "SNOOZE":
                // Re-schedule notification for 5 minutes later
                let content = response.notification.request.content.mutableCopy() as! UNMutableNotificationContent
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "snoozed-\(UUID().uuidString)",
                    content: content,
                    trigger: trigger
                )
                try? await UNUserNotificationCenter.current().add(request)

            default:
                break
            }
        }

        completionHandler()
    }
}

// MARK: - Notification Names
// Note: These are defined in BARTApp.swift as .openClawOpenSession and .openClawReply
