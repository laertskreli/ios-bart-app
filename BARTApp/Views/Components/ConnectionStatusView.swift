import SwiftUI

struct ConnectionStatusView: View {
    let state: ConnectionState
    var activeSessions: [SessionInfo] = []
    var onSessionSelect: ((SessionInfo) -> Void)?
    var onRefresh: (() -> Void)?

    @State private var showSessionPicker = false

    var body: some View {
        Button {
            if !activeSessions.isEmpty {
                showSessionPicker = true
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    // Show badge if there are active subagents
                    if activeSubagentCount > 0 {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Text("\(activeSubagentCount)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 8, y: -6)
                    }
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !activeSessions.isEmpty && state.isConnected {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(UIColor.systemBackground)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showSessionPicker) {
            SessionPickerView(
                sessions: activeSessions,
                onSelect: { session in
                    showSessionPicker = false
                    onSessionSelect?(session)
                },
                onRefresh: {
                    onRefresh?()
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var activeSubagentCount: Int {
        activeSessions.filter { !$0.isMain && $0.isActive }.count
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

// MARK: - Session Picker

struct SessionPickerView: View {
    let sessions: [SessionInfo]
    let onSelect: (SessionInfo) -> Void
    var onRefresh: (() -> Void)?

    private var mainSessions: [SessionInfo] {
        sessions.filter { $0.isMain || !$0.isSubagent }
    }

    private var subagentSessions: [SessionInfo] {
        sessions.filter { $0.isSubagent }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sessions")
                    .font(.headline)

                Spacer()

                Button {
                    onRefresh?()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Main sessions
                    if !mainSessions.isEmpty {
                        ForEach(mainSessions) { session in
                            SessionRowView(session: session) {
                                onSelect(session)
                            }
                        }
                    }

                    // Subagents section
                    if !subagentSessions.isEmpty {
                        HStack {
                            Text("Subagents")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Text("(\(subagentSessions.count))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                        ForEach(subagentSessions) { session in
                            SessionRowView(session: session) {
                                onSelect(session)
                            }
                        }
                    }

                    if sessions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text("No sessions")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 300)
    }
}

struct SessionRowView: View {
    let session: SessionInfo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Status indicator
                Circle()
                    .fill(session.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.friendlyName)
                            .font(.subheadline)
                            .fontWeight(session.isMain ? .semibold : .regular)
                            .lineLimit(1)

                        if session.isMain {
                            Text("MAIN")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor))
                        }

                        if session.isSubagent {
                            Image(systemName: "person.2")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 6) {
                        if let model = session.model {
                            Text(formatModel(model))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let tokens = session.totalTokens {
                            Text("• \(formatTokens(tokens))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Text("• \(session.lastActivity, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if session.unreadCount > 0 {
                    Text("\(session.unreadCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.red))
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatModel(_ model: String) -> String {
        // Shorten model names
        if model.contains("opus") {
            return "Opus"
        } else if model.contains("sonnet") {
            return "Sonnet"
        } else if model.contains("haiku") {
            return "Haiku"
        }
        return model.prefix(10).description
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1000 {
            return String(format: "%.1fK", Double(tokens) / 1000)
        }
        return "\(tokens)"
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
            .background(Color(UIColor.systemBackground))
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

        // With sessions
        ConnectionStatusView(
            state: .connected,
            activeSessions: [
                SessionInfo.main(sessionKey: "ios-chat"),
                SessionInfo(
                    id: "sub1",
                    sessionKey: "agent:main:subagent:research",
                    label: "Research Task",
                    isMain: false,
                    isActive: true,
                    lastActivity: Date(),
                    unreadCount: 2,
                    model: nil,
                    totalTokens: nil,
                    category: .subagent,
                    topic: "Researching topic",
                    messageCount: 5,
                    participantName: nil
                )
            ]
        )

        ConnectionStatusBanner(state: .reconnecting(attempt: 1))
    }
    .padding()
}
