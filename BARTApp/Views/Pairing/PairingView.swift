import SwiftUI

struct PairingView: View {
    @EnvironmentObject var gateway: GatewayConnection

    @State private var showPulse = false
    @State private var showingQRScanner = false
    @State private var showingManualEntry = false

    private var isConnecting: Bool {
        if case .connecting = gateway.connectionState { return true }
        return false
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            // Main content
            if isConnecting {
                connectingView
            } else {
                pairingOptionsView
            }
        }
        .animation(.spring(response: 0.4), value: isConnecting)
        .sheet(isPresented: $showingQRScanner) {
            QRScannerView { payload in
                gateway.connectWithQRPayload(payload)
            }
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualPairingView()
        }
    }

    // MARK: - Connecting View

    private var connectingView: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                // Animated rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.green.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                        .frame(width: CGFloat(120 + i * 30), height: CGFloat(120 + i * 30))
                        .scaleEffect(showPulse ? 1.2 : 1)
                        .opacity(showPulse ? 0 : 0.7)
                        .animation(
                            .easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.3),
                            value: showPulse
                        )
                }

                GlassCard(padding: 24, cornerRadius: 60) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }

            VStack(spacing: 12) {
                Text("QR Code Scanned!")
                    .font(.title2.bold())
                    .foregroundColor(.green)

                Text("Connecting to gateway...")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.top, 8)
            }

            Spacer()

            ConnectionStatusView(state: gateway.connectionState)
                .padding(.bottom, 40)
        }
        .padding()
        .onAppear {
            showPulse = true
        }
    }

    // MARK: - Pairing Options View

    private var pairingOptionsView: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon/logo
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
                    Image(systemName: "brain.head.profile")
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

            VStack(spacing: 8) {
                Text("Connect to BART")
                    .font(.title.bold())

                Text("Choose how to pair with your AI assistant")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Pairing options with liquid glass effects
            VStack(spacing: 16) {
                LiquidGlassButton(
                    icon: "qrcode.viewfinder",
                    iconColor: .cyan,
                    title: "Scan QR Code",
                    subtitle: "Quick setup in seconds"
                ) {
                    showingQRScanner = true
                }

                LiquidGlassButton(
                    icon: "keyboard",
                    iconColor: .orange,
                    title: "Manual Entry",
                    subtitle: "Enter URL and token"
                ) {
                    showingManualEntry = true
                }
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 8) {
                Text("On your Mac, run:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("openclaw devices pair --qr")
                    .font(.system(.footnote, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6).opacity(0.5))
                    .cornerRadius(8)

                ConnectionStatusView(state: gateway.connectionState)
                    .padding(.top, 8)
            }
            .padding(.bottom, 40)
        }
        .padding()
    }
}

// MARK: - Animated Gradient Background

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
