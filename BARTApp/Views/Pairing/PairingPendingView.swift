import SwiftUI

struct PairingPendingView: View {
    let code: String

    @State private var copied = false
    @State private var showCheckmark = false

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 32) {
                Spacer()

                GlassCard(padding: 24, cornerRadius: 60) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 12) {
                    Text("Approve on Mac")
                        .font(.title.bold())

                    Text("Run this command on your Mac Mini")
                        .foregroundStyle(.secondary)
                }

                GlassCard(padding: 20, cornerRadius: 16) {
                    HStack {
                        Text("openclaw nodes approve")
                            .font(.system(.body, design: .monospaced))

                        Spacer()

                        Button {
                            UIPasteboard.general.string = "openclaw nodes approve"
                            withAnimation(.spring(response: 0.3)) {
                                copied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { copied = false }
                            }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(copied ? .green : .secondary)
                        }
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 16) {
                    Text("Pairing Code")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(Array(code.enumerated()), id: \.offset) { _, char in
                            Text(String(char))
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .frame(width: 44, height: 56)
                                .background(GlassBackground(cornerRadius: 12))
                        }
                    }
                }

                Spacer()

                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Waiting for approval...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("The code will expire in 5 minutes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 40)
            }
            .padding()
        }
    }
}

#Preview {
    PairingPendingView(code: "ABC123")
}
