import SwiftUI

struct PairingFailedView: View {
    let error: String
    @EnvironmentObject var gateway: GatewayConnection

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 32) {
                Spacer()

                GlassCard(padding: 24, cornerRadius: 60) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.red, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 12) {
                    Text("Pairing Failed")
                        .font(.title.bold())

                    Text(error)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 16) {
                    Button("Try Again") {
                        gateway.connect()
                    }
                    .buttonStyle(GlassButton(isProminent: true))

                    Button("Reset & Retry") {
                        gateway.resetPairing()
                        gateway.connect()
                    }
                    .buttonStyle(GlassButton())
                }

                Spacer()

                VStack(spacing: 8) {
                    Text("Troubleshooting")
                        .font(.footnote.bold())
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        TroubleshootingItem(text: "Check Tailscale is connected")
                        TroubleshootingItem(text: "Verify Mac Mini is running OpenClaw")
                        TroubleshootingItem(text: "Ensure you're on the same network")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 40)
            }
            .padding()
        }
    }
}

struct TroubleshootingItem: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
            Text(text)
        }
    }
}

#Preview {
    PairingFailedView(error: "Connection timed out")
        .environmentObject(GatewayConnection(gatewayHost: "localhost"))
}
