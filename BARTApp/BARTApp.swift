import SwiftUI

@main
struct BARTApp: App {
    @StateObject private var gateway: GatewayConnection

    init() {
        _gateway = StateObject(wrappedValue: GatewayConnection(
            gatewayHost: AppConfig.gatewayHost,
            port: AppConfig.gatewayPort
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(gateway)
                .preferredColorScheme(.dark)
        }
    }
}
