import SwiftUI

struct RootView: View {
    @EnvironmentObject var gateway: GatewayConnection

    var body: some View {
        Group {
            switch gateway.pairingState {
            case .unpaired:
                PairingView()

            case .pendingApproval(let code, _):
                PairingPendingView(code: code)

            case .paired:
                MainView()

            case .failed(let error):
                PairingFailedView(error: error)
            }
        }
        .animation(.spring(response: 0.4), value: pairingStateId)
        .onAppear {
            gateway.connect()
        }
    }

    private var pairingStateId: String {
        switch gateway.pairingState {
        case .unpaired:
            return "unpaired"
        case .pendingApproval:
            return "pending"
        case .paired:
            return "paired"
        case .failed:
            return "failed"
        }
    }
}

#Preview {
    RootView()
        .environmentObject(GatewayConnection(gatewayHost: "localhost"))
}
