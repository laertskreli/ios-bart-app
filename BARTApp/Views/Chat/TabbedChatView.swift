import SwiftUI

/// Clean chat view - direct conversation with Bart
/// No floating tabs, just a standard messaging interface
struct TabbedChatView: View {
    @EnvironmentObject var gateway: GatewayConnection

    var body: some View {
        NavigationStack {
            // ChatThreadView handles its own background and toolbar items
            // Don't add extra ZStack/background - it causes layering issues with keyboard
            ChatThreadView(initialSessionKey: "main", initialTitle: "Bart")
        }
    }
}

#Preview {
    TabbedChatView()
        .environmentObject(GatewayConnection(gatewayHost: "localhost"))
}
