import SwiftUI

struct RootView: View {
    @EnvironmentObject var gateway: GatewayConnection

    var body: some View {
        ZStack {
            // Solid black background to prevent any transparency
            Color.black.ignoresSafeArea()
            
            Group {
                switch gateway.pairingState {
                case .unpaired:
                    PairingView()
                        .onAppear { print("📱 RootView: Showing PairingView (unpaired)") }

                case .pendingApproval(let code, let requestId):
                    PairingPendingView(code: code, requestId: requestId)
                        .onAppear { print("📱 RootView: Showing PairingPendingView") }

                case .paired:
                    MainView()
                        .onAppear { print("📱 RootView: Showing MainView (paired)") }

                case .failed(let error):
                    PairingFailedView(error: error)
                        .onAppear { print("📱 RootView: Showing PairingFailedView: \(error)") }
                }
            }
        }
        .animation(.spring(response: 0.4), value: pairingStateId)
        .onChange(of: pairingStateId) { oldValue, newValue in
            print("📱 RootView: pairingState changed from \(oldValue) to \(newValue)")
        }
        .onAppear {
            print("📱 RootView: onAppear - pairingState: \(pairingStateId)")
            if case .paired = gateway.pairingState {
                gateway.connect()
            }
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
