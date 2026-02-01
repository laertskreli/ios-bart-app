import Foundation

struct SubAgentInfo: Codable, Identifiable, Equatable {
    let id: String
    let sessionKey: String
    let parentSessionKey: String
    let label: String
    let task: String
    let spawnedAt: Date
    var status: SubAgentStatus
    var announceResult: AnnounceResult?
}

enum SubAgentStatus: String, Codable {
    case running
    case completed
    case failed
}

struct AnnounceResult: Codable, Equatable {
    let status: String
    let result: String?
    let notes: String?
    let runtime: TimeInterval?
    let tokens: Int?
    let cost: Double?
}

// MARK: - Session Category (Channel Types)

enum SessionCategory: String, Codable, CaseIterable {
    case agent = "agent"           // Main BART agent
    case subagent = "subagent"     // Spawned subagents
    case ios = "ios"               // iOS app sessions
    case telegram = "telegram"
    case whatsapp = "whatsapp"
    case discord = "discord"
    case slack = "slack"
    case email = "email"
    case sms = "sms"
    case web = "web"
    case api = "api"
    case node = "node"             // Generic node/device connections

    var icon: String {
        switch self {
        case .agent: return "brain.head.profile"
        case .subagent: return "arrow.triangle.branch"
        case .ios: return "iphone"
        case .telegram: return "paperplane.fill"
        case .whatsapp: return "phone.bubble.fill"
        case .discord: return "gamecontroller.fill"
        case .slack: return "number.square.fill"
        case .email: return "envelope.fill"
        case .sms: return "message.fill"
        case .web: return "globe"
        case .api: return "terminal.fill"
        case .node: return "desktopcomputer"
        }
    }

    var color: String {
        switch self {
        case .agent: return "blue"
        case .subagent: return "orange"
        case .ios: return "blue"
        case .telegram: return "cyan"
        case .whatsapp: return "green"
        case .discord: return "indigo"
        case .slack: return "purple"
        case .email: return "red"
        case .sms: return "mint"
        case .web: return "teal"
        case .api: return "gray"
        case .node: return "gray"
        }
    }

    var displayName: String {
        switch self {
        case .agent: return "Agent"
        case .subagent: return "Subagent"
        case .ios: return "iOS"
        case .telegram: return "Telegram"
        case .whatsapp: return "WhatsApp"
        case .discord: return "Discord"
        case .slack: return "Slack"
        case .email: return "Email"
        case .sms: return "SMS"
        case .web: return "Web"
        case .api: return "API"
        case .node: return "Device"
        }
    }
}

// MARK: - Session Info (for session switcher)

struct SessionInfo: Codable, Identifiable, Equatable {
    let id: String
    let sessionKey: String
    let label: String
    let isMain: Bool
    var isActive: Bool
    var lastActivity: Date
    var unreadCount: Int
    var model: String?
    var totalTokens: Int?

    // Channel/Category support
    var category: SessionCategory
    var topic: String?           // Channel topic or last message preview
    var messageCount: Int        // Total messages in session
    var participantName: String? // For DMs: the other participant's name

    var isSubagent: Bool {
        category == .subagent || sessionKey.contains(":subagent:")
    }

    var friendlyName: String {
        if !label.isEmpty {
            return label
        }
        if let participant = participantName {
            return participant
        }
        if isSubagent {
            return String(sessionKey.components(separatedBy: ":subagent:").last?.prefix(8) ?? "Subagent")
        }
        return isMain ? "Main Chat" : String(sessionKey.prefix(12))
    }

    var icon: String {
        category.icon
    }

    var colorName: String {
        category.color
    }

    /// Short name for compact display in toolbar (e.g., "TG", "iPhone", "Main")
    var shortName: String {
        // Use participant name if available (truncated)
        if let participant = participantName, !participant.isEmpty {
            let parts = participant.split(separator: " ")
            if parts.count > 1 {
                // First name only
                return String(parts[0])
            }
            return String(participant.prefix(10))
        }

        // Use label if short enough
        if !label.isEmpty && label.count <= 12 {
            return label
        }

        // Generate short name based on category and session key
        switch category {
        case .telegram:
            // Extract chat identifier or use "TG"
            if let dmPart = sessionKey.components(separatedBy: ":dm:").last {
                return "TG · \(String(dmPart.prefix(6)))"
            }
            return "Telegram"
        case .whatsapp:
            return "WhatsApp"
        case .discord:
            return "Discord"
        case .slack:
            return "Slack"
        case .ios:
            // Extract device identifier
            if sessionKey.contains("iphone-") {
                if let devicePart = sessionKey.components(separatedBy: "iphone-").last {
                    return "iPhone · \(String(devicePart.prefix(4)))"
                }
            }
            return "iOS"
        case .node:
            return "Device"
        case .agent:
            if sessionKey.contains(":main") || isMain {
                return "Main"
            }
            return "Agent"
        case .subagent:
            if !label.isEmpty {
                return String(label.prefix(10))
            }
            return "Subagent"
        case .email:
            return "Email"
        case .sms:
            return "SMS"
        case .web:
            return "Web"
        case .api:
            return "API"
        }
    }

    static func main(sessionKey: String) -> SessionInfo {
        SessionInfo(
            id: "main",
            sessionKey: sessionKey,
            label: "Main Chat",
            isMain: true,
            isActive: true,
            lastActivity: Date(),
            unreadCount: 0,
            model: nil,
            totalTokens: nil,
            category: .agent,
            topic: nil,
            messageCount: 0,
            participantName: nil
        )
    }

    static func fromSubAgent(_ subAgent: SubAgentInfo) -> SessionInfo {
        SessionInfo(
            id: subAgent.id,
            sessionKey: subAgent.sessionKey,
            label: subAgent.label,
            isMain: false,
            isActive: subAgent.status == .running,
            lastActivity: subAgent.spawnedAt,
            unreadCount: 0,
            model: nil,
            totalTokens: nil,
            category: .subagent,
            topic: subAgent.task,
            messageCount: 0,
            participantName: nil
        )
    }

    /// Parse category from session key or metadata
    /// Session key patterns:
    /// - agent:main:telegram:dm:* → telegram
    /// - agent:main:node:dm:iphone-* → ios
    /// - agent:main:ios-chat → ios
    /// - agent:main:subagent:* → subagent
    /// - agent:main:main → agent
    static func parseCategory(from sessionKey: String, metadata: [String: Any]? = nil) -> SessionCategory {
        // Check metadata first
        if let categoryStr = metadata?["category"] as? String,
           let category = SessionCategory(rawValue: categoryStr) {
            return category
        }

        let key = sessionKey.lowercased()

        // Parse from session key patterns (order matters - more specific first)
        if key.contains(":subagent:") {
            return .subagent
        } else if key.contains(":telegram:") || key.hasPrefix("tg:") {
            return .telegram
        } else if key.contains(":whatsapp:") || key.hasPrefix("wa:") {
            return .whatsapp
        } else if key.contains(":discord:") || key.hasPrefix("dc:") {
            return .discord
        } else if key.contains(":slack:") || key.hasPrefix("slack:") {
            return .slack
        } else if key.contains(":email:") || key.hasPrefix("email:") {
            return .email
        } else if key.contains(":sms:") || key.hasPrefix("sms:") {
            return .sms
        } else if key.contains("ios-chat") || key.contains(":iphone") || key.contains("iphone-") {
            return .ios
        } else if key.contains(":node:") {
            return .node
        } else if key.contains(":web:") || key.hasPrefix("web:") {
            return .web
        } else if key.contains(":api:") || key.hasPrefix("api:") {
            return .api
        }

        return .agent
    }
}
