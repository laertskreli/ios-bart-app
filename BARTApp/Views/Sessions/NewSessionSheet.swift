import SwiftUI

struct NewSessionSheet: View {
    @EnvironmentObject var gateway: GatewayConnection
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedAgent: SubAgentDefinition = SubAgentDefinition.available[0]
    @State private var sessionLabel = ""
    @State private var sessionDescription = ""
    @State private var isCreating = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Agent Selector
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Select Agent")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                                ForEach(SubAgentDefinition.available) { agent in
                                    AgentButton(
                                        agent: agent,
                                        isSelected: selectedAgent.id == agent.id
                                    ) {
                                        selectedAgent = agent
                                    }
                                }
                            }
                        }
                        
                        // Session Details
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Session Details")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            
                            GlassCard(padding: 16, cornerRadius: 16) {
                                VStack(spacing: 16) {
                                    TextField("Session Label", text: $sessionLabel)
                                        .textFieldStyle(.plain)
                                        .padding(12)
                                        .background(Color.white.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    TextField("Description (optional)", text: $sessionDescription)
                                        .textFieldStyle(.plain)
                                        .padding(12)
                                        .background(Color.white.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        
                        // Action Buttons
                        VStack(spacing: 12) {
                            // Create Fresh Session
                            Button {
                                createFreshSession()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Create Fresh Session")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(isCreating || sessionLabel.isEmpty)
                            
                            // Join Telegram (only for main agent)
                            if selectedAgent.id == "main" {
                                Button {
                                    joinTelegramSession()
                                } label: {
                                    HStack {
                                        Image(systemName: "paperplane.fill")
                                        Text("Join Telegram Session")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue.opacity(0.3))
                                    .foregroundStyle(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .padding(.top)
                    }
                    .padding()
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func createFreshSession() {
        isCreating = true
        gateway.createSession(
            agentId: selectedAgent.id,
            label: sessionLabel,
            description: sessionDescription.isEmpty ? nil : sessionDescription
        ) { success in
            isCreating = false
            if success {
                dismiss()
            }
        }
    }
    
    private func joinTelegramSession() {
        gateway.setChannelMode(.telegram)
        dismiss()
    }
}

struct AgentButton: View {
    let agent: SubAgentDefinition
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(agent.emoji)
                    .font(.system(size: 28))
                
                Text(agent.name)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(width: 72, height: 72)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NewSessionSheet()
        .environmentObject(GatewayConnection(gatewayHost: "localhost"))
}
