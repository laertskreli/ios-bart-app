import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var gateway: GatewayConnection
    @State private var showNewSessionSheet = false
    @State private var showCloseConfirmation = false
    @State private var sessionToClose: SessionInfo?
    @State private var deletingSessionKeys: Set<String> = []  // Track sessions being deleted
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    
    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Channel Mode Indicator
                    HStack {
                        Text("Current Mode:")
                            .foregroundStyle(.secondary)
                        Text(gateway.channelMode == .telegram ? "📨 Telegram" : "📱 iPhone")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    
                    // Telegram Session (always first)
                    SessionCard(
                        session: .telegramSession(),
                        isActive: gateway.channelMode == .telegram,
                        isDeleting: false,
                        onTap: { selectTelegramSession() },
                        onClose: nil
                    )
                    
                    // iPhone Direct Session
                    SessionCard(
                        session: .iphoneSession(nodeId: gateway.deviceIdentity.nodeId),
                        isActive: gateway.channelMode == .webchat && gateway.activeSessionKey == nil,
                        isDeleting: false,
                        onTap: { selectIPhoneSession() },
                        onClose: nil
                    )
                    
                    // Divider
                    if !filteredSessions.isEmpty {
                        HStack {
                            Text("Sub-Agent Sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    
                    // Active sessions from gateway
                    ForEach(filteredSessions) { session in
                        SessionCard(
                            session: sessionEntryFrom(session),
                            isActive: gateway.activeSessionKey == session.sessionKey,
                            isDeleting: deletingSessionKeys.contains(session.sessionKey),
                            onTap: { selectSession(session) },
                            onClose: {
                                deleteSession(session)
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .move(edge: .trailing))
                        ))
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewSessionSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewSessionSheet) {
            NewSessionSheet()
                .environmentObject(gateway)
        }
        .alert("Failed to Close Session", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage)
        }
        .onAppear {
            gateway.fetchSessionsList()
        }
    }
    
    private var filteredSessions: [SessionInfo] {
        gateway.activeSessions.filter { session in
            !session.sessionKey.contains(":dm:") &&
            session.sessionKey != SessionEntry.telegramSessionKey &&
            !session.sessionKey.hasSuffix(":main") &&
            !deletingSessionKeys.contains(session.sessionKey)
        }
    }
    
    private func sessionEntryFrom(_ info: SessionInfo) -> SessionEntry {
        let agentId = extractAgentId(from: info.sessionKey)
        
        return SessionEntry(
            id: info.id,
            sessionKey: info.sessionKey,
            agentId: agentId,
            label: info.label,
            description: info.topic,
            channel: .webchat,
            mode: .dedicated,
            tokenCount: info.totalTokens ?? 0,
            lastActivity: info.lastActivity,
            spawnedAgents: [],
            isActive: info.isActive
        )
    }
    
    private func extractAgentId(from sessionKey: String) -> String {
        let parts = sessionKey.components(separatedBy: ":")
        if parts.count >= 2 { return parts[1] }
        return "main"
    }
    
    private func selectTelegramSession() {
        gateway.setChannelMode(.telegram)
    }
    
    private func selectIPhoneSession() {
        gateway.setChannelMode(.webchat)
    }
    
    private func selectSession(_ session: SessionInfo) {
        gateway.setActiveSession(sessionKey: session.sessionKey)
    }
    
    /// Delete a session with proper animation and feedback
    private func deleteSession(_ session: SessionInfo) {
        // Haptic feedback - immediate response
        let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
        impactGenerator.impactOccurred()
        
        // Mark as deleting (will hide from list with animation)
        withAnimation(.easeInOut(duration: 0.3)) {
            deletingSessionKeys.insert(session.sessionKey)
        }
        
        // Call the gateway to actually delete
        gateway.closeSession(sessionKey: session.sessionKey) { success in
            if success {
                // Success haptic
                let successGenerator = UINotificationFeedbackGenerator()
                successGenerator.notificationOccurred(.success)
                
                // Remove from deleting set (session is already removed from gateway.activeSessions)
                withAnimation(.easeOut(duration: 0.2)) {
                    deletingSessionKeys.remove(session.sessionKey)
                }
            } else {
                // Failure - restore the session in the list
                let errorGenerator = UINotificationFeedbackGenerator()
                errorGenerator.notificationOccurred(.error)
                
                withAnimation(.spring()) {
                    deletingSessionKeys.remove(session.sessionKey)
                }
                
                // Show error message
                deleteErrorMessage = "Could not close session. Please try again."
                showDeleteError = true
            }
        }
    }
}

struct SessionCard: View {
    let session: SessionEntry
    var isActive: Bool = false
    var isDeleting: Bool = false
    let onTap: () -> Void
    let onClose: (() -> Void)?
    
    @State private var offset: CGFloat = 0
    @State private var showActions = false
    
    var body: some View {
        ZStack(alignment: .trailing) {
            if onClose != nil {
                HStack(spacing: 0) {
                    Spacer()
                    Button {
                        withAnimation(.spring()) { offset = 0; showActions = false }
                        onClose?()
                    } label: {
                        VStack {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                            Text("Close").font(.caption2)
                        }
                        .frame(width: 80, height: 80)
                        .background(Color.red)
                    }
                    .foregroundStyle(.white)
                }
            }
            
            GlassCard(padding: 16, cornerRadius: 16) {
                HStack(spacing: 12) {
                    Text(agentEmoji)
                        .font(.system(size: 32))
                        .frame(width: 48, height: 48)
                        .background(isActive ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(session.label).font(.headline)
                            if session.channel == .telegram {
                                Image(systemName: "paperplane.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            if isActive {
                                Text("ACTIVE")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                        if let desc = session.description {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        HStack {
                            Text(tokenCountText).font(.caption2).foregroundStyle(.tertiary)
                            Text("•").foregroundStyle(.tertiary)
                            Text(timeAgoText).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .opacity(isDeleting ? 0.5 : 1)
            .offset(x: offset)
            .gesture(
                onClose != nil && !isDeleting ?
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 { offset = max(value.translation.width, -80) }
                    }
                    .onEnded { value in
                        withAnimation(.spring()) {
                            if value.translation.width < -40 {
                                offset = -80
                                showActions = true
                            } else {
                                offset = 0
                                showActions = false
                            }
                        }
                    }
                : nil
            )
            .onTapGesture {
                if showActions {
                    withAnimation(.spring()) { offset = 0; showActions = false }
                } else if !isDeleting {
                    onTap()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var agentEmoji: String {
        SubAgentDefinition.find(id: session.agentId)?.emoji ?? "🤖"
    }
    
    private var tokenCountText: String {
        session.tokenCount >= 1000 ? "\(session.tokenCount / 1000)k tokens" : "\(session.tokenCount) tokens"
    }
    
    private var timeAgoText: String {
        let interval = Date().timeIntervalSince(session.lastActivity)
        if interval < 60 { return "active" }
        else if interval < 3600 { return "\(Int(interval / 60))m ago" }
        else if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        else { return "\(Int(interval / 86400))d ago" }
    }
}

#Preview {
    NavigationStack {
        SessionListView()
            .environmentObject(GatewayConnection(gatewayHost: "localhost"))
    }
}
