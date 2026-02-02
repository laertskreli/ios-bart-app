import SwiftUI

// Notification names for inter-component communication
extension Notification.Name {
    static let openClawOpenSession = Notification.Name("OpenClawNotificationOpenSession")
    static let openClawReply = Notification.Name("OpenClawNotificationReply")
}

@main
struct BARTApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var gateway: GatewayConnection

    init() {
        _gateway = StateObject(wrappedValue: GatewayConnection(
            gatewayHost: AppConfig.gatewayHost,
            port: AppConfig.gatewayPort,
            useSSL: AppConfig.useSSL
        ))
    }

    var body: some Scene {
        WindowGroup {
            AppContentView(appDelegate: appDelegate)
                .environmentObject(gateway)
        }
    }
}

// MARK: - App Content View (handles lifecycle)

struct AppContentView: View {
    @EnvironmentObject var gateway: GatewayConnection
    @Environment(\.scenePhase) private var scenePhase
    let appDelegate: AppDelegate

    var body: some View {
        RootView()
            .preferredColorScheme(.dark)
            .onAppear {
                // ONE-TIME FORCE RESET (remove after successful pairing)
                let resetKey = "force_reset_feb02_2026"
                if !UserDefaults.standard.bool(forKey: resetKey) {
                    print("🔄 Performing one-time auth reset...")
                    gateway.resetPairing()
                    UserDefaults.standard.set(true, forKey: resetKey)
                }
                
                // Give AppDelegate access to gateway for push token registration
                appDelegate.gateway = gateway

                // If we already have a stored APNs token, send it to gateway
                if let storedToken = UserDefaults.standard.string(forKey: "apnsDeviceToken") {
                    gateway.registerPushToken(storedToken)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openClawOpenSession)) { notification in
                if let sessionKey = notification.userInfo?["sessionKey"] as? String {
                    // Handle opening the session from notification
                    print("📲 Open session from notification: \(sessionKey)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openClawReply)) { notification in
                if let sessionKey = notification.userInfo?["sessionKey"] as? String,
                   let text = notification.userInfo?["text"] as? String {
                    // Handle reply from notification
                    print("📝 Sending reply from notification to \(sessionKey)")
                    Task {
                        try? await gateway.sendMessage(text, sessionKey: sessionKey)
                    }
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(from: oldPhase, to: newPhase)
            }
    }

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            print("📱 App became active")
            // Delay slightly to ensure view is fully loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                gateway.handleAppDidBecomeActive()
            }
        case .inactive:
            print("📱 App became inactive")
        case .background:
            print("📱 App entered background")
            gateway.handleAppWillBackground()
        @unknown default:
            break
        }
    }
}
