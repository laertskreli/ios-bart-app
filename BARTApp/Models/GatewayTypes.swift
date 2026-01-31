import Foundation

struct AgentInfo: Codable, Equatable {
    let id: String
    let name: String?
    let workspace: String?
}

struct RPCRequest: Codable {
    let id: String
    let method: String
    let params: [String: AnyCodable]?
}

struct RPCResponse: Codable {
    let id: String
    let result: AnyCodable?
    let error: RPCError?
}

struct RPCError: Codable {
    let code: Int
    let message: String
}

enum GatewayEvent {
    case assistantDelta(sessionId: String, messageId: String, text: String)
    case toolStart(sessionId: String, toolId: String, toolName: String)
    case toolEnd(sessionId: String, toolId: String, result: String?)
    case streamStart(sessionId: String)
    case streamEnd(sessionId: String)
    case pairingApproved(token: String)
    case subAgentAnnounce(sessionKey: String, result: AnnounceResult)
    case error(code: String, message: String)
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
