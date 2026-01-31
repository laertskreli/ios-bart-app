import SwiftUI

struct PairingView: View {
    @EnvironmentObject var gateway: GatewayConnection

    @State private var showPulse = false

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 32) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 2)
                        .frame(width: 160, height: 160)
                        .scaleEffect(showPulse ? 1.3 : 1)
                        .opacity(showPulse ? 0 : 0.5)

                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 140, height: 140)
                        .scaleEffect(showPulse ? 1.2 : 1)
                        .opacity(showPulse ? 0 : 0.7)

                    GlassCard(padding: 24, cornerRadius: 60) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.accentColor, .accentColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: false)) {
                        showPulse = true
                    }
                }

                VStack(spacing: 12) {
                    Text("Connecting to BART")
                        .font(.title.bold())

                    Text("Establishing secure connection...")
                        .foregroundStyle(.secondary)
                }

                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.accentColor)

                Spacer()

                VStack(spacing: 8) {
                    Text("Make sure you're connected to Tailscale")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ConnectionStatusView(state: gateway.connectionState)
                }
                .padding(.bottom, 40)
            }
            .padding()
        }
    }
}

struct AnimatedGradientBackground: View {
    @State private var animateGradient = false

    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color.accentColor.opacity(0.1),
                Color.purple.opacity(0.05)
            ],
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
        }
    }
}

#Preview {
    PairingView()
        .environmentObject(GatewayConnection(gatewayHost: "localhost"))
}
