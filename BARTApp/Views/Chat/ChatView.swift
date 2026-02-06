import SwiftUI
import Combine

// MARK: - Channel Types

enum ChatChannel: String, CaseIterable {
    case telegram = "Telegram"
    case signal = "Signal"
    case direct = "Direct"
    
    var icon: String {
        switch self {
        case .telegram: return "paperplane.fill"
        case .signal: return "lock.shield.fill"
        case .direct: return "bubble.left.and.bubble.right.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .telegram: return Color(red: 0.0, green: 0.53, blue: 0.87)
        case .signal: return Color(red: 0.23, green: 0.47, blue: 0.87)
        case .direct: return .purple
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    @EnvironmentObject var gateway: GatewayConnection
    @State private var selectedChannel: ChatChannel = .telegram
    @State private var showChannelPicker = false
    @State private var scrollOffset: CGFloat = 0
    
    // Current session tracking
    @State private var displaySessionKey: String = ""
    @State private var displayTitle: String = "Chat"
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Liquid glass animated background
                LiquidGlassBackground(
                    primaryColor: .purple,
                    secondaryColor: .blue,
                    tertiaryColor: .indigo
                )
                
                ChatThreadView(
                    initialSessionKey: displaySessionKey,
                    initialTitle: displayTitle
                )
                .id(displaySessionKey)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionIndicator(state: gateway.connectionState)
                }
                
                ToolbarItem(placement: .principal) {
                    channelPickerButton
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        LiquidGlassButton(icon: "gearshape.fill")
                    }
                }
            }
        }
        .onAppear {
            syncSession()
        }
        .onChange(of: gateway.channelMode) { _, _ in
            syncSession()
        }
        .onChange(of: gateway.activeSessionKey) { _, _ in
            syncSession()
        }
        .onChange(of: selectedChannel) { _, newChannel in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                switch newChannel {
                case .telegram:
                    gateway.setChannelMode(.telegram)
                case .signal, .direct:
                    gateway.setChannelMode(.webchat)
                }
                syncSession()
            }
        }
    }
    
    // MARK: - Channel Picker Button
    
    private var channelPickerButton: some View {
        Button {
            showChannelPicker = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedChannel.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selectedChannel.color)
                
                Text(selectedChannel.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        }
        .sheet(isPresented: $showChannelPicker) {
            ChannelPickerSheet(
                selectedChannel: $selectedChannel,
                sessions: gateway.activeSessions,
                onSessionSelect: { session in
                    switchToSession(session)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }
    
    // MARK: - Session Management
    
    private func syncSession() {
        let newKey = gateway.getCurrentSessionKey()
        
        let newTitle: String
        switch gateway.channelMode {
        case .telegram:
            newTitle = "📨 Telegram"
            selectedChannel = .telegram
        case .webchat:
            if let activeKey = gateway.activeSessionKey,
               activeKey != SessionEntry.iphoneSessionKey(nodeId: gateway.deviceIdentity.nodeId),
               let session = gateway.activeSessions.first(where: { $0.sessionKey == activeKey }) {
                newTitle = session.label
            } else {
                newTitle = "📱 iPhone"
            }
            selectedChannel = .direct
        }
        
        if newKey != displaySessionKey || newTitle != displayTitle {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                displaySessionKey = newKey
                displayTitle = newTitle
            }
        }
    }
    
    private func switchToSession(_ session: SessionInfo) {
        gateway.setActiveSession(sessionKey: session.sessionKey)
        syncSession()
    }
}

// MARK: - Channel Picker Sheet

struct ChannelPickerSheet: View {
    @Binding var selectedChannel: ChatChannel
    let sessions: [SessionInfo]
    let onSessionSelect: (SessionInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Channel buttons
                    VStack(spacing: 12) {
                        Text("CHANNELS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        
                        HStack(spacing: 12) {
                            ForEach(ChatChannel.allCases, id: \.self) { channel in
                                channelButton(channel)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal)
                    
                    // Sessions list
                    VStack(spacing: 12) {
                        Text("SESSIONS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        
                        if sessions.isEmpty {
                            Text("No active sessions")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(sessions) { session in
                                sessionRow(session)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(.ultraThinMaterial)
            .navigationTitle("Select Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func channelButton(_ channel: ChatChannel) -> some View {
        Button {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                selectedChannel = channel
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(channel.color.opacity(selectedChannel == channel ? 0.3 : 0.1))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: channel.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(channel.color)
                }
                .overlay(
                    Circle()
                        .stroke(selectedChannel == channel ? channel.color : .clear, lineWidth: 2)
                        .frame(width: 56, height: 56)
                )
                
                Text(channel.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(selectedChannel == channel ? .white : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
    
    private func sessionRow(_ session: SessionInfo) -> some View {
        Button {
            onSessionSelect(session)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: session.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(colorFromName(session.colorName))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(colorFromName(session.colorName).opacity(0.15))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.friendlyName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    
                    if let topic = session.topic, !topic.isEmpty {
                        Text(topic)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if session.unreadCount > 0 {
                    Text("\(session.unreadCount)")
                        .font(.caption2.weight(.bold))
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
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
    
    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "orange": return .orange
        case "cyan": return .cyan
        case "green": return .green
        case "indigo": return .indigo
        case "purple": return .purple
        case "red": return .red
        case "mint": return .mint
        case "teal": return .teal
        case "gray": return .gray
        case "yellow": return .yellow
        case "pink": return .pink
        default: return .blue
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(GatewayConnection(gatewayHost: "localhost"))
}
