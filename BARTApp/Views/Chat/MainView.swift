import SwiftUI

struct MainView: View {
    @EnvironmentObject var gateway: GatewayConnection

    var body: some View {
        MainTabView()
    }
}

#Preview {
    MainView()
        .environmentObject(GatewayConnection(gatewayHost: "localhost"))
}
