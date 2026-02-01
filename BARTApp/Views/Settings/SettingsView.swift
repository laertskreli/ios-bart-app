import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var gateway: GatewayConnection
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var showResetConfirmation = false
    @State private var showClearHistoryConfirmation = false
    @State private var showClearAllDataConfirmation = false
    @State private var showDebugInfo = false

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            ScrollView {
                VStack(spacing: 20) {
                    connectionSection
                    deviceSection
                    notificationsSection
                    agentSection
                    subAgentsSection
                    chatSection
                    debugSection
                    dangerZoneSection
                }
                .padding()
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert("Reset Pairing", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                gateway.resetPairing()
            }
        } message: {
            Text("This will unpair your device from BART. You'll need to approve the device again from your Mac.")
        }
        .alert("Clear Chat History", isPresented: $showClearHistoryConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                gateway.clearConversationHistory()
            }
        } message: {
            Text("This will delete all chat messages from this device. This cannot be undone.")
        }
        .alert("Clear All App Data", isPresented: $showClearAllDataConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                clearAllAppData()
            }
        } message: {
            Text("This will clear all cached data including conversations, tokens, and settings. The app will restart in a fresh state.")
        }
        .sheet(isPresented: $showDebugInfo) {
            DebugInfoSheet(gateway: gateway)
        }
    }

    private func clearAllAppData() {
        // Clear conversations
        gateway.clearConversationHistory()

        // Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        // Disconnect
        gateway.disconnect()

        // Force reconnect after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            gateway.connect()
        }
    }

    private var connectionSection: some View {
        SettingsSection(title: "Connection", icon: "wifi") {
            SettingsRow(label: "Status") {
                ConnectionStatusView(state: gateway.connectionState)
            }

            if gateway.connectionState.isConnected {
                SettingsRow(label: "Latency") {
                    Text("< 50ms")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var deviceSection: some View {
        SettingsSection(title: "Device", icon: "iphone") {
            SettingsRow(label: "Node ID") {
                Text(gateway.deviceIdentity.nodeId)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            SettingsRow(label: "Name") {
                Text(gateway.deviceIdentity.displayName)
                    .foregroundStyle(.secondary)
            }

            if case .paired = gateway.pairingState,
               let pairedAt = gateway.deviceIdentity.pairedAt {
                SettingsRow(label: "Paired") {
                    Text(pairedAt, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var agentSection: some View {
        if let agent = gateway.currentAgent {
            SettingsSection(title: "Agent", icon: "brain.head.profile") {
                SettingsRow(label: "ID") {
                    Text(agent.id)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let name = agent.name {
                    SettingsRow(label: "Name") {
                        Text(name)
                            .foregroundStyle(.secondary)
                    }
                }

                if let workspace = agent.workspace {
                    SettingsRow(label: "Workspace") {
                        Text(workspace)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    private var subAgentsSection: some View {
        SettingsSection(title: "Sub-Agents", icon: "bubble.left.and.bubble.right") {
            if gateway.subAgents.isEmpty {
                HStack {
                    Text("No active sub-agents")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                ForEach(gateway.subAgents) { subAgent in
                    SubAgentRow(subAgent: subAgent)
                }
            }
        }
    }

    private var notificationsSection: some View {
        SettingsSection(title: "Notifications", icon: "bell.fill") {
            if !notificationManager.isAuthorized {
                Button {
                    Task {
                        await notificationManager.requestAuthorization()
                    }
                } label: {
                    HStack {
                        Text("Enable Notifications")
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                NotificationToggleRow(
                    label: "Messages",
                    icon: "message.fill",
                    isOn: Binding(
                        get: { notificationManager.settings.messagesEnabled },
                        set: { updateNotificationSetting(\.messagesEnabled, $0) }
                    )
                )

                NotificationToggleRow(
                    label: "Reminders",
                    icon: "bell.badge.fill",
                    isOn: Binding(
                        get: { notificationManager.settings.remindersEnabled },
                        set: { updateNotificationSetting(\.remindersEnabled, $0) }
                    )
                )

                NotificationToggleRow(
                    label: "Calendar",
                    icon: "calendar",
                    isOn: Binding(
                        get: { notificationManager.settings.calendarEnabled },
                        set: { updateNotificationSetting(\.calendarEnabled, $0) }
                    )
                )

                NotificationToggleRow(
                    label: "Subagent Updates",
                    icon: "bubble.left.and.bubble.right.fill",
                    isOn: Binding(
                        get: { notificationManager.settings.subagentEnabled },
                        set: { updateNotificationSetting(\.subagentEnabled, $0) }
                    )
                )

                Divider()

                NotificationToggleRow(
                    label: "Emergency Alerts",
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .red,
                    isOn: Binding(
                        get: { notificationManager.settings.emergencyEnabled },
                        set: { updateNotificationSetting(\.emergencyEnabled, $0) }
                    )
                )

                if notificationManager.settings.emergencyEnabled {
                    NotificationToggleRow(
                        label: "Critical Sound",
                        subtitle: "Bypasses Do Not Disturb",
                        icon: "speaker.wave.3.fill",
                        iconColor: .orange,
                        isOn: Binding(
                            get: { notificationManager.settings.emergencyUseCritical },
                            set: { updateNotificationSetting(\.emergencyUseCritical, $0) }
                        )
                    )
                }
            }
        }
    }

    private func updateNotificationSetting<T>(_ keyPath: WritableKeyPath<NotificationSettings, T>, _ value: T) {
        var newSettings = notificationManager.settings
        newSettings[keyPath: keyPath] = value
        notificationManager.updateSettings(newSettings)
    }

    private var chatSection: some View {
        SettingsSection(title: "Chat", icon: "bubble.left.and.bubble.right") {
            SettingsRow(label: "Messages") {
                let count = gateway.conversations.values.reduce(0) { $0 + $1.messages.count }
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }

            SettingsRow(label: "Conversations") {
                Text("\(gateway.conversations.count)")
                    .foregroundStyle(.secondary)
            }

            Button {
                showClearHistoryConfirmation = true
            } label: {
                HStack {
                    Text("Clear History")
                        .foregroundStyle(.red)
                    Spacer()
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var debugSection: some View {
        SettingsSection(title: "Debug", icon: "ladybug.fill", iconColor: .orange) {
            Button {
                showDebugInfo = true
            } label: {
                HStack {
                    Text("View Debug Info")
                    Spacer()
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                gateway.disconnect()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    gateway.connect()
                }
            } label: {
                HStack {
                    Text("Force Reconnect")
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                showClearAllDataConfirmation = true
            } label: {
                HStack {
                    Text("Clear All App Data")
                        .foregroundStyle(.orange)
                    Spacer()
                    Image(systemName: "trash.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var dangerZoneSection: some View {
        SettingsSection(title: "Danger Zone", icon: "exclamationmark.triangle.fill", iconColor: .red) {
            Button {
                showResetConfirmation = true
            } label: {
                HStack {
                    Text("Reset Pairing")
                        .foregroundStyle(.red)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Debug Info Sheet

struct DebugInfoSheet: View {
    let gateway: GatewayConnection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    LabeledContent("State", value: connectionStateText)
                    LabeledContent("Gateway", value: gatewayHost)
                }

                Section("Device") {
                    LabeledContent("Node ID", value: gateway.deviceIdentity.nodeId)
                    LabeledContent("Display Name", value: gateway.deviceIdentity.displayName)
                }

                Section("Push Notifications") {
                    LabeledContent("APNs Token") {
                        if let token = UserDefaults.standard.string(forKey: "apnsDeviceToken") {
                            Text(String(token.prefix(20)) + "...")
                                .font(.system(.caption, design: .monospaced))
                        } else {
                            Text("Not registered")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Cache") {
                    LabeledContent("Conversations", value: "\(gateway.conversations.count)")
                    LabeledContent("Messages") {
                        let count = gateway.conversations.values.reduce(0) { $0 + $1.messages.count }
                        Text("\(count)")
                    }
                    LabeledContent("Active Sessions", value: "\(gateway.activeSessions.count)")
                }

                Section("App Info") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")
                    LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "?")
                }
            }
            .navigationTitle("Debug Info")
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

    private var connectionStateText: String {
        switch gateway.connectionState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reconnecting(let attempt): return "Reconnecting (\(attempt))..."
        case .failed(let error): return "Failed: \(error)"
        }
    }

    private var gatewayHost: String {
        // Try to get from UserDefaults config
        if let data = UserDefaults.standard.data(forKey: "openclaw-gateway-config"),
           let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let host = config["host"] as? String,
           let port = config["port"] as? Int {
            return "\(host):\(port)"
        }
        return "Unknown"
    }
}

// MARK: - Notification Toggle Row

struct NotificationToggleRow: View {
    let label: String
    var subtitle: String? = nil
    let icon: String
    var iconColor: Color = .accentColor
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    var iconColor: Color = .accentColor
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)

                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }

            GlassCard(padding: 16, cornerRadius: 16) {
                VStack(spacing: 16) {
                    content
                }
            }
        }
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            content
        }
    }
}

struct SubAgentRow: View {
    let subAgent: SubAgentInfo

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(subAgent.label)
                    .font(.subheadline.bold())

                Text(subAgent.task)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(subAgent.status.rawValue.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.ultraThinMaterial))
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch subAgent.status {
        case .running:
            return .green
        case .completed:
            return .blue
        case .failed:
            return .red
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(GatewayConnection(gatewayHost: "localhost"))
    }
}
