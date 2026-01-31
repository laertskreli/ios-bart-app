import Foundation

struct Message: Codable, Identifiable, Equatable {
    let id: String
    let conversationId: String
    let role: MessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    var toolCalls: [ToolCall]?
    var location: LocationShare?

    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id &&
        lhs.content == rhs.content &&
        lhs.isStreaming == rhs.isStreaming
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct ToolCall: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    var status: ToolCallStatus
    var result: String?
    var spawnedSessionKey: String?
    var spawnedLabel: String?
}

enum ToolCallStatus: String, Codable {
    case running
    case completed
    case failed
}
