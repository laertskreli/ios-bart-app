import SwiftUI

struct MainView: View {
    @EnvironmentObject var gateway: GatewayConnection

    private var isPowerUser: Bool {
        gateway.currentAgent?.id == "bart"
    }

    var body: some View {
        Group {
            if isPowerUser {
                TabbedChatView()
            } else {
                SimpleChatView()
            }
        }
    }
}

#Preview {
    MainView()
        .environmentObject(GatewayConnection(gatewayHost: "localhost"))
}
