import SwiftUI

@main
struct BARTApp: App {
    @StateObject private var gateway: GatewayConnection

    init() {
        _gateway = StateObject(wrappedValue: GatewayConnection(
            gatewayHost: Configuration.gatewayHost,
            port: Configuration.gatewayPort
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
