import SwiftUI

struct SimpleChatView: View {
    @EnvironmentObject var gateway: GatewayConnection

    var body: some View {
        NavigationStack {
            ChatThreadView(sessionKey: "main", title: "BART")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ConnectionStatusView(state: gateway.connectionState)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gear")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
        }
    }
}

#Preview {
    SimpleChatView()
        .environmentObject(GatewayConnection(gatewayHost: "localhost"))
}
