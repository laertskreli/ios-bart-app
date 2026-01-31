import SwiftUI

struct ConnectionStatusView: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    private var statusColor: Color {
        switch state {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .disconnected, .failed:
            return .red
        }
    }

    private var statusText: String {
        switch state {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .reconnecting(let attempt):
            return "Reconnecting (\(attempt))..."
        case .disconnected:
            return "Disconnected"
        case .failed(let message):
            return message.prefix(20) + (message.count > 20 ? "..." : "")
        }
    }
}

struct ConnectionStatusBanner: View {
    let state: ConnectionState

    var body: some View {
        if !state.isConnected {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)

                Text(bannerText)
                    .font(.subheadline)

                Spacer()

                if case .reconnecting = state {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var iconName: String {
        switch state {
        case .connecting, .reconnecting:
            return "wifi.exclamationmark"
        case .disconnected, .failed:
            return "wifi.slash"
        default:
            return "wifi"
        }
    }

    private var iconColor: Color {
        switch state {
        case .connecting, .reconnecting:
            return .orange
        case .disconnected, .failed:
            return .red
        default:
            return .green
        }
    }

    private var bannerText: String {
        switch state {
        case .connecting:
            return "Connecting to BART..."
        case .reconnecting(let attempt):
            return "Reconnecting (attempt \(attempt))..."
        case .disconnected:
            return "Disconnected from BART"
        case .failed(let message):
            return "Connection failed: \(message)"
        default:
            return ""
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ConnectionStatusView(state: .connected)
        ConnectionStatusView(state: .connecting)
        ConnectionStatusView(state: .reconnecting(attempt: 2))
        ConnectionStatusView(state: .failed("Network error"))

        ConnectionStatusBanner(state: .reconnecting(attempt: 1))
    }
    .padding()
}
