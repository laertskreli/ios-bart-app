import Foundation

struct Conversation: Codable, Identifiable {
    let id: String
    let sessionKey: String
    let agentId: String
    let label: String?
    let isSubAgent: Bool
    let parentSessionKey: String?
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date
    var status: ConversationStatus
}

enum ConversationStatus: String, Codable {
    case active
    case streaming
    case completed
    case error
}
