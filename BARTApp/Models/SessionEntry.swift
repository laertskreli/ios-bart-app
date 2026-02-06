import Foundation

/// Channel mode determines how messages are routed
enum ChannelMode: String, Codable, CaseIterable {
    case telegram = "telegram"  // Join main Telegram conversation
    case webchat = "webchat"    // iPhone-specific session
    
    var displayName: String {
        switch self {
        case .telegram: return "Telegram"
        case .webchat: return "iPhone"
        }
    }
    
    var icon: String {
        switch self {
        case .telegram: return "paperplane.fill"
        case .webchat: return "iphone"
        }
    }
}

/// Session mode determines if session is shared or dedicated
enum SessionMode: String, Codable {
    case shared = "shared"       // Joins existing session (e.g., Telegram main)
    case dedicated = "dedicated" // Own isolated session
}

/// Represents a chat session entry
struct SessionEntry: Identifiable, Codable {
    let id: String
    var sessionKey: String
    var agentId: String
    var label: String
    var description: String?
    var channel: ChannelMode
    var mode: SessionMode
    var tokenCount: Int
    var lastActivity: Date
    var spawnedAgents: [String]  // Session keys of spawned sub-agents
    var isActive: Bool
    
    /// The Telegram main session key
    static let telegramSessionKey = "agent:main:main"
    
    /// Generate iPhone direct session key
    static func iphoneSessionKey(nodeId: String) -> String {
        return "agent:main:node:dm:\(nodeId)"
    }
    
    /// Generate sub-agent session key
    static func subAgentSessionKey(agentId: String, sessionId: String) -> String {
        return "agent:\(agentId):iphone-\(sessionId)"
    }
    
    /// Create the default Telegram session entry
    static func telegramSession() -> SessionEntry {
        SessionEntry(
            id: "telegram-main",
            sessionKey: telegramSessionKey,
            agentId: "main",
            label: "Telegram",
            description: "Main conversation",
            channel: .telegram,
            mode: .shared,
            tokenCount: 0,
            lastActivity: Date(),
            spawnedAgents: [],
            isActive: true
        )
    }
    
    /// Create iPhone direct session entry
    static func iphoneSession(nodeId: String) -> SessionEntry {
        SessionEntry(
            id: "iphone-direct",
            sessionKey: iphoneSessionKey(nodeId: nodeId),
            agentId: "main",
            label: "iPhone Tasks",
            description: "Canvas + local",
            channel: .webchat,
            mode: .dedicated,
            tokenCount: 0,
            lastActivity: Date(),
            spawnedAgents: [],
            isActive: true
        )
    }
}

/// Available sub-agents that can be spawned
struct SubAgentDefinition: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let description: String
    
    static let available: [SubAgentDefinition] = [
        SubAgentDefinition(id: "main", name: "Bart V", emoji: "🦞", description: "Main assistant"),
        SubAgentDefinition(id: "cto", name: "CTO", emoji: "🔧", description: "Technical architecture"),
        SubAgentDefinition(id: "cpo", name: "CPO", emoji: "🎯", description: "Product strategy"),
        SubAgentDefinition(id: "ciso", name: "CISO", emoji: "🛡️", description: "Security & compliance"),
        SubAgentDefinition(id: "cfo", name: "CFO", emoji: "💰", description: "Financial analysis"),
        SubAgentDefinition(id: "cmo", name: "CMO", emoji: "📣", description: "Marketing strategy"),
        SubAgentDefinition(id: "coo", name: "COO", emoji: "⚙️", description: "Operations"),
        SubAgentDefinition(id: "cro", name: "CRO", emoji: "📈", description: "Revenue & growth"),
        SubAgentDefinition(id: "cco", name: "CCO", emoji: "🤝", description: "Customer success"),
        SubAgentDefinition(id: "cso", name: "CSO", emoji: "🔬", description: "Strategy & research"),
        SubAgentDefinition(id: "privacy", name: "Privacy", emoji: "🔒", description: "Privacy & data protection"),
    ]
    
    static func find(id: String) -> SubAgentDefinition? {
        available.first { $0.id == id }
    }
}
