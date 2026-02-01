import SwiftUI

struct SimpleChatView: View {
    @EnvironmentObject var gateway: GatewayConnection
    @State private var currentSessionKey = ""  // Will be set from server
    @State private var currentTitle = "BART"

    // Get the main/default session from active sessions
    private var defaultSessionKey: String {
        // Prefer session containing our device node ID
        if let mySession = gateway.activeSessions.first(where: { $0.sessionKey.contains(gateway.deviceIdentity.nodeId) }) {
            return mySession.sessionKey
        }
        // Then prefer main DM session
        if let mainSession = gateway.activeSessions.first(where: { $0.isMain }) {
            return mainSession.sessionKey
        }
        // Then any session that's not a subagent
        if let firstSession = gateway.activeSessions.first(where: { !$0.isSubagent }) {
            return firstSession.sessionKey
        }
        // Fallback to generated session key
        return "agent:main:node:dm:\(gateway.deviceIdentity.nodeId)"
    }

    var body: some View {
        NavigationStack {
            ChatThreadView(initialSessionKey: effectiveSessionKey, initialTitle: currentTitle)
                .onAppear {
                    // Fetch sessions list when view appears
                    if gateway.connectionState.isConnected {
                        gateway.fetchSessionsList()
                    }
                }
                .onChange(of: gateway.connectionState) { _, newState in
                    // Fetch sessions when connection is established
                    if newState.isConnected {
                        gateway.fetchSessionsList()
                    }
                }
                .onChange(of: gateway.activeSessions) { _, sessions in
                    // Auto-select first session if we don't have one
                    if currentSessionKey.isEmpty, let first = sessions.first {
                        print("🔄 Auto-selecting session: \(first.sessionKey)")
                        switchToSession(first)
                    }
                }
        }
    }

    private var effectiveSessionKey: String {
        currentSessionKey.isEmpty ? defaultSessionKey : currentSessionKey
    }

    private func buildSessionList() -> [SessionInfo] {
        // Use activeSessions from gateway if available
        if !gateway.activeSessions.isEmpty {
            return gateway.activeSessions
        }

        // Fallback to building from subAgents
        var sessions: [SessionInfo] = []

        // Add main session
        sessions.append(SessionInfo.main(sessionKey: "ios-chat"))

        // Add subagent sessions
        for subAgent in gateway.subAgents {
            sessions.append(SessionInfo.fromSubAgent(subAgent))
        }

        return sessions
    }

    private func switchToSession(_ session: SessionInfo) {
        currentSessionKey = session.sessionKey
        currentTitle = session.isMain ? "BART" : session.friendlyName

        // Fetch history for this session if we don't have messages yet
        if gateway.conversations[session.sessionKey]?.messages.isEmpty ?? true {
            gateway.fetchSessionHistory(sessionKey: session.sessionKey) { _ in }
        }
    }
}

#Preview {
    SimpleChatView()
        .environmentObject(GatewayConnection(gatewayHost: "localhost"))
}
