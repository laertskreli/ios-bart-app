import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var gateway: GatewayConnection
    @State private var showResetConfirmation = false

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            ScrollView {
                VStack(spacing: 20) {
                    connectionSection
                    deviceSection
                    agentSection
                    subAgentsSection
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
