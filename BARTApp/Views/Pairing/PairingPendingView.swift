import SwiftUI

struct PairingPendingView: View {
    let code: String
    var requestId: String = ""

    @State private var copied = false
    @State private var showSuccess = true
    @State private var pulseAnimation = false

    private var approvalCommand: String {
        if requestId.isEmpty {
            return "openclaw devices approve"
        }
        return "openclaw devices approve \(requestId)"
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 28) {
                Spacer()

                // Success checkmark with animation
                ZStack {
                    // Pulse rings
                    Circle()
                        .stroke(Color.green.opacity(0.3), lineWidth: 2)
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulseAnimation ? 1.3 : 1)
                        .opacity(pulseAnimation ? 0 : 0.5)

                    Circle()
                        .stroke(Color.green.opacity(0.4), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseAnimation ? 1.2 : 1)
                        .opacity(pulseAnimation ? 0 : 0.7)

                    GlassCard(padding: 24, cornerRadius: 60) {
                        Image(systemName: showSuccess ? "qrcode.viewfinder" : "checkmark.shield.fill")
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
                .onAppear {
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: false)) {
                        pulseAnimation = true
                    }
                    // Transition to shield after 1 second
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        withAnimation(.spring(response: 0.4)) {
                            showSuccess = false
                        }
                    }
                }

                VStack(spacing: 8) {
                    Text("QR Code Scanned!")
                        .font(.title.bold())
                        .foregroundColor(.green)

                    Text("Now approve on your Mac")
                        .foregroundStyle(.secondary)
                }

                // Approval command card
                VStack(spacing: 12) {
                    Text("Run this command:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        copyToClipboard()
                    } label: {
                        HStack(spacing: 12) {
                            Text(approvalCommand)
                                .font(.system(.footnote, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            Spacer()

                            ZStack {
                                Image(systemName: "doc.on.doc")
                                    .opacity(copied ? 0 : 1)
                                Image(systemName: "checkmark")
                                    .opacity(copied ? 1 : 0)
                                    .foregroundColor(.green)
                            }
                            .font(.system(size: 16, weight: .medium))
                        }
                        .padding(16)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(UIColor.systemBackground))

                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(
                                        LinearGradient(
                                            colors: copied
                                                ? [Color.green.opacity(0.6), Color.green.opacity(0.3)]
                                                : [.white.opacity(0.5), .white.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: copied ? 2 : 1
                                    )
                            }
                        )
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if copied {
                        Text("Copied to clipboard!")
                            .font(.caption)
                            .foregroundColor(.green)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal)
                .animation(.spring(response: 0.3), value: copied)

                // Verification code display
                if !code.isEmpty {
                    VStack(spacing: 12) {
                        Text("Verification Code")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 8) {
                            ForEach(Array(code.prefix(6).enumerated()), id: \.offset) { _, char in
                                Text(String(char))
                                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                                    .frame(width: 36, height: 44)
                                    .background(GlassBackground(cornerRadius: 10))
                            }
                        }
                    }
                }

                Spacer()

                // Status indicator
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        PulsingDot(color: .orange)
                        Text("Waiting for approval...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("The pairing request will expire in 5 minutes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 40)
            }
            .padding()
        }
        .onAppear {
            // Auto-copy to clipboard on appear
            copyToClipboard()
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = approvalCommand

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        withAnimation(.spring(response: 0.3)) {
            copied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeOut) {
                copied = false
            }
        }
    }
}

#Preview {
    PairingPendingView(code: "143B76", requestId: "abc123def456")
}
