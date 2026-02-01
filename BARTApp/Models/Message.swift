import Foundation

// MARK: - Message Delivery Status

enum MessageDeliveryStatus: String, Codable {
    case pending    // Message created locally, not yet sent
    case sending    // RPC call in progress
    case delivered  // Server ACK received
    case failed     // RPC failed or timed out
}

// MARK: - Message

struct Message: Codable, Identifiable, Equatable {
    let id: String
    let conversationId: String
    let role: MessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    var toolCalls: [ToolCall]?
    var location: LocationShare?
    var deliveryStatus: MessageDeliveryStatus

    // Attachment fields
    var attachmentData: Data?
    var attachmentFilename: String?
    var attachmentMimeType: String?

    var hasAttachment: Bool {
        attachmentData != nil
    }

    var isImageAttachment: Bool {
        guard let mimeType = attachmentMimeType else { return false }
        return mimeType.hasPrefix("image/")
    }

    init(
        id: String,
        conversationId: String,
        role: MessageRole,
        content: String,
        timestamp: Date,
        isStreaming: Bool,
        toolCalls: [ToolCall]? = nil,
        location: LocationShare? = nil,
        deliveryStatus: MessageDeliveryStatus = .delivered,
        attachmentData: Data? = nil,
        attachmentFilename: String? = nil,
        attachmentMimeType: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.toolCalls = toolCalls
        self.location = location
        self.deliveryStatus = deliveryStatus
        self.attachmentData = attachmentData
        self.attachmentFilename = attachmentFilename
        self.attachmentMimeType = attachmentMimeType
    }

    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id &&
        lhs.content == rhs.content &&
        lhs.isStreaming == rhs.isStreaming &&
        lhs.deliveryStatus == rhs.deliveryStatus &&
        lhs.attachmentFilename == rhs.attachmentFilename
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
