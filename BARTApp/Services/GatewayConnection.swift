import Foundation
import Combine
import UIKit

@MainActor
class GatewayConnection: ObservableObject {

    // MARK: - Published State

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var pairingState: PairingState = .unpaired
    @Published private(set) var currentAgent: AgentInfo?
    @Published private(set) var conversations: [String: Conversation] = [:]
    @Published private(set) var subAgents: [SubAgentInfo] = []
    @Published private(set) var deviceIdentity: DeviceIdentity

    // MARK: - Configuration

    private let gatewayHost: String
    private let port: Int
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var pendingRequests: [String: CheckedContinuation<RPCResponse, Error>] = [:]
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 5
    private var isReceiving = false

    private let keychainService = "com.bart.gateway"
    private let keychainAccount = "pairingToken"

    // MARK: - Init

    init(gatewayHost: String, port: Int = 18789) {
        self.gatewayHost = gatewayHost
        self.port = port

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        self.deviceIdentity = Self.loadOrCreateDeviceIdentity()

        if let token = KeychainHelper.loadString(service: keychainService, account: keychainAccount) {
            self.pairingState = .paired(token: token)
            self.deviceIdentity.pairingToken = token
        }
    }

    // MARK: - Device Identity

    private static func loadOrCreateDeviceIdentity() -> DeviceIdentity {
        if let data = UserDefaults.standard.data(forKey: DeviceIdentity.storageKey),
           let identity = try? JSONDecoder().decode(DeviceIdentity.self, from: data) {
            return identity
        }

        let newIdentity = DeviceIdentity(
            nodeId: "iphone-\(UUID().uuidString.prefix(8).lowercased())",
            displayName: UIDevice.current.name,
            pairingToken: nil,
            pairedAt: nil
        )

        if let data = try? JSONEncoder().encode(newIdentity) {
            UserDefaults.standard.set(data, forKey: DeviceIdentity.storageKey)
        }

        return newIdentity
    }

    private func saveDeviceIdentity() {
        if let data = try? JSONEncoder().encode(deviceIdentity) {
            UserDefaults.standard.set(data, forKey: DeviceIdentity.storageKey)
        }
    }

    // MARK: - Connection

    func connect() {
        guard connectionState == .disconnected ||
              (connectionState != .connecting && connectionState != .connected) else { return }

        connectionState = .connecting

        var urlComponents = URLComponents()
        urlComponents.scheme = "ws"
        urlComponents.host = gatewayHost
        urlComponents.port = port

        guard let url = urlComponents.url else {
            connectionState = .failed("Invalid gateway URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("ios-node", forHTTPHeaderField: "X-Client-Type")
        request.setValue(deviceIdentity.nodeId, forHTTPHeaderField: "X-Node-Id")

        if case .paired(let token) = pairingState {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        connectionState = .connected
        reconnectAttempt = 0
        isReceiving = false

        receiveMessages()

        Task {
            if case .paired(let token) = pairingState {
                await verifyPairing(token: token)
            } else {
                await requestPairing()
            }
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        isReceiving = false
    }

    // MARK: - Pairing

    private func requestPairing() async {
        do {
            let response = try await rpc(
                method: "node.pair.request",
                params: [
                    "nodeId": AnyCodable(deviceIdentity.nodeId),
                    "name": AnyCodable(deviceIdentity.displayName),
                    "capabilities": AnyCodable(["chat", "location"])
                ]
            )

            if let result = response.result?.value as? [String: Any],
               let requestId = result["requestId"] as? String,
               let code = result["code"] as? String {
                pairingState = .pendingApproval(code: code, requestId: requestId)
                await pollForPairingApproval(requestId: requestId)
            }
        } catch {
            pairingState = .failed("Pairing request failed: \(error.localizedDescription)")
        }
    }

    private func pollForPairingApproval(requestId: String) async {
        for _ in 0..<150 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            guard case .pendingApproval = pairingState else { return }

            do {
                let response = try await rpc(
                    method: "node.pair.status",
                    params: ["requestId": AnyCodable(requestId)]
                )

                if let result = response.result?.value as? [String: Any],
                   let status = result["status"] as? String {

                    if status == "approved", let token = result["token"] as? String {
                        deviceIdentity.pairingToken = token
                        deviceIdentity.pairedAt = Date()
                        saveDeviceIdentity()

                        _ = KeychainHelper.saveString(token, service: keychainService, account: keychainAccount)

                        pairingState = .paired(token: token)

                        disconnect()
                        connect()
                        return
                    } else if status == "rejected" {
                        pairingState = .failed("Pairing rejected")
                        return
                    } else if status == "expired" {
                        pairingState = .failed("Pairing request expired")
                        return
                    }
                }
            } catch {
                // Continue polling
            }
        }

        pairingState = .failed("Pairing timed out")
    }

    private func verifyPairing(token: String) async {
        do {
            let response = try await rpc(
                method: "node.pair.verify",
                params: [
                    "nodeId": AnyCodable(deviceIdentity.nodeId),
                    "token": AnyCodable(token)
                ]
            )

            if let result = response.result?.value as? [String: Any],
               let valid = result["valid"] as? Bool, valid {
                await fetchAgentInfo()
            } else {
                KeychainHelper.delete(service: keychainService, account: keychainAccount)
                deviceIdentity.pairingToken = nil
                saveDeviceIdentity()
                pairingState = .unpaired
                await requestPairing()
            }
        } catch {
            connectionState = .failed("Verification failed: \(error.localizedDescription)")
        }
    }

    private func fetchAgentInfo() async {
        do {
            let response = try await rpc(method: "agents.current", params: nil)

            if let result = response.result?.value as? [String: Any],
               let agentId = result["id"] as? String {
                currentAgent = AgentInfo(
                    id: agentId,
                    name: result["name"] as? String,
                    workspace: result["workspace"] as? String
                )
            }
        } catch {
            // Non-fatal
        }
    }

    func resetPairing() {
        KeychainHelper.delete(service: keychainService, account: keychainAccount)
        deviceIdentity.pairingToken = nil
        deviceIdentity.pairedAt = nil
        saveDeviceIdentity()
        pairingState = .unpaired
        disconnect()
    }

    // MARK: - RPC

    private func rpc(method: String, params: [String: AnyCodable]?) async throws -> RPCResponse {
        let requestId = UUID().uuidString
        let request = RPCRequest(id: requestId, method: method, params: params)

        let data = try JSONEncoder().encode(request)
        let message = URLSessionWebSocketTask.Message.data(data)

        try await webSocketTask?.send(message)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation

            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if let cont = pendingRequests.removeValue(forKey: requestId) {
                    cont.resume(throwing: NSError(
                        domain: "Gateway",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Request timed out"]
                    ))
                }
            }
        }
    }

    // MARK: - Chat

    func sendMessage(_ text: String, sessionKey: String? = nil) async throws {
        let key = sessionKey ?? "main"

        let userMessage = Message(
            id: UUID().uuidString,
            conversationId: key,
            role: .user,
            content: text,
            timestamp: Date(),
            isStreaming: false,
            toolCalls: nil,
            location: nil
        )

        addMessageToConversation(userMessage, sessionKey: key)

        let response = try await rpc(
            method: "chat.send",
            params: [
                "message": AnyCodable(text),
                "sessionKey": AnyCodable(key)
            ]
        )

        if let error = response.error {
            throw NSError(
                domain: "Gateway",
                code: error.code,
                userInfo: [NSLocalizedDescriptionKey: error.message]
            )
        }
    }

    func sendLocation(_ location: LocationShare, sessionKey: String? = nil) async throws {
        let key = sessionKey ?? "main"

        let response = try await rpc(
            method: "chat.send",
            params: [
                "message": AnyCodable("Shared location"),
                "sessionKey": AnyCodable(key),
                "attachments": AnyCodable([
                    [
                        "type": "location",
                        "latitude": location.latitude,
                        "longitude": location.longitude,
                        "accuracy": location.accuracy ?? 0,
                        "ttl": location.ttl
                    ]
                ])
            ]
        )

        if let error = response.error {
            throw NSError(
                domain: "Gateway",
                code: error.code,
                userInfo: [NSLocalizedDescriptionKey: error.message]
            )
        }
    }

    func fetchHistory(sessionKey: String, limit: Int = 50) async throws -> [Message] {
        let response = try await rpc(
            method: "chat.history",
            params: [
                "sessionKey": AnyCodable(sessionKey),
                "limit": AnyCodable(limit)
            ]
        )

        guard let result = response.result?.value as? [[String: Any]] else {
            return []
        }

        return result.compactMap { dict -> Message? in
            guard let id = dict["id"] as? String,
                  let roleStr = dict["role"] as? String,
                  let content = dict["content"] as? String else { return nil }

            return Message(
                id: id,
                conversationId: sessionKey,
                role: roleStr == "user" ? .user : .assistant,
                content: content,
                timestamp: Date(),
                isStreaming: false,
                toolCalls: nil,
                location: nil
            )
        }
    }

    // MARK: - Receive & Parse

    private func receiveMessages() {
        guard !isReceiving else { return }
        isReceiving = true

        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                self.isReceiving = false

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveMessages()

                case .failure(let error):
                    self.handleConnectionError(error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = s.data(using: .utf8) ?? Data()
        @unknown default: return
        }

        if let response = try? JSONDecoder().decode(RPCResponse.self, from: data),
           let continuation = pendingRequests.removeValue(forKey: response.id) {
            continuation.resume(returning: response)
            return
        }

        if let event = parseEvent(data) {
            handleEvent(event)
        }
    }

    private func parseEvent(_ data: Data) -> GatewayEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = json["event"] as? String else {
            return nil
        }

        let sessionId = json["sessionId"] as? String ?? ""
        let eventData = json["data"] as? [String: Any] ?? [:]

        switch eventType {
        case "assistant:delta", "assistant":
            guard let text = eventData["text"] as? String,
                  let messageId = eventData["messageId"] as? String else { return nil }
            return .assistantDelta(sessionId: sessionId, messageId: messageId, text: text)

        case "tool:start":
            guard let toolId = eventData["toolCallId"] as? String,
                  let toolName = eventData["toolName"] as? String else { return nil }
            return .toolStart(sessionId: sessionId, toolId: toolId, toolName: toolName)

        case "tool:end":
            guard let toolId = eventData["toolCallId"] as? String else { return nil }
            return .toolEnd(sessionId: sessionId, toolId: toolId, result: eventData["result"] as? String)

        case "stream:start":
            return .streamStart(sessionId: sessionId)

        case "stream:end":
            return .streamEnd(sessionId: sessionId)

        case "subagent:announce":
            guard let sessionKey = eventData["sessionKey"] as? String else { return nil }
            let result = AnnounceResult(
                status: eventData["status"] as? String ?? "",
                result: eventData["result"] as? String,
                notes: eventData["notes"] as? String,
                runtime: eventData["runtime"] as? TimeInterval,
                tokens: eventData["tokens"] as? Int,
                cost: eventData["cost"] as? Double
            )
            return .subAgentAnnounce(sessionKey: sessionKey, result: result)

        case "error":
            return .error(
                code: eventData["code"] as? String ?? "unknown",
                message: eventData["message"] as? String ?? "Unknown error"
            )

        default:
            return nil
        }
    }

    private func handleEvent(_ event: GatewayEvent) {
        switch event {
        case .assistantDelta(let sessionId, let messageId, let text):
            updateMessageWithDelta(sessionId: sessionId, messageId: messageId, delta: text)

        case .toolStart(let sessionId, let toolId, let toolName):
            addToolCall(sessionId: sessionId, toolId: toolId, toolName: toolName)

            if toolName == "sessions_spawn" {
                // Sub-agent spawning, handled in tool:end
            }

        case .toolEnd(let sessionId, let toolId, let result):
            updateToolCall(sessionId: sessionId, toolId: toolId, result: result)

            if let result = result,
               let resultData = result.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
               let childSessionKey = json["childSessionKey"] as? String {

                let parts = childSessionKey.split(separator: ":")
                if parts.count >= 4, parts[2] == "subagent" {
                    let subAgentId = String(parts[3])
                    let subAgent = SubAgentInfo(
                        id: subAgentId,
                        sessionKey: childSessionKey,
                        parentSessionKey: sessionId,
                        label: json["label"] as? String ?? "Sub-agent",
                        task: json["task"] as? String ?? "",
                        spawnedAt: Date(),
                        status: .running,
                        announceResult: nil
                    )
                    subAgents.append(subAgent)
                }
            }

        case .streamStart(let sessionId):
            if var conversation = conversations[sessionId] {
                conversation.status = .streaming
                conversations[sessionId] = conversation
            }

        case .streamEnd(let sessionId):
            if var conversation = conversations[sessionId] {
                conversation.status = .active
                if var lastMsg = conversation.messages.last, lastMsg.isStreaming {
                    lastMsg.isStreaming = false
                    conversation.messages[conversation.messages.count - 1] = lastMsg
                }
                conversations[sessionId] = conversation
            }

        case .subAgentAnnounce(let sessionKey, let result):
            if let idx = subAgents.firstIndex(where: { $0.sessionKey == sessionKey }) {
                subAgents[idx].status = result.status == "success" ? .completed : .failed
                subAgents[idx].announceResult = result
            }

        case .error(let code, let message):
            print("Gateway error: \(code) - \(message)")

        case .pairingApproved:
            break
        }
    }

    private func addMessageToConversation(_ message: Message, sessionKey: String) {
        var conversation = conversations[sessionKey] ?? Conversation(
            id: sessionKey,
            sessionKey: sessionKey,
            agentId: currentAgent?.id ?? "unknown",
            label: nil,
            isSubAgent: sessionKey.contains(":subagent:"),
            parentSessionKey: nil,
            messages: [],
            createdAt: Date(),
            updatedAt: Date(),
            status: .active
        )

        conversation.messages.append(message)
        conversation.updatedAt = Date()
        conversations[sessionKey] = conversation
    }

    private func updateMessageWithDelta(sessionId: String, messageId: String, delta: String) {
        var conversation = conversations[sessionId] ?? Conversation(
            id: sessionId,
            sessionKey: sessionId,
            agentId: currentAgent?.id ?? "unknown",
            label: nil,
            isSubAgent: sessionId.contains(":subagent:"),
            parentSessionKey: nil,
            messages: [],
            createdAt: Date(),
            updatedAt: Date(),
            status: .streaming
        )

        if let idx = conversation.messages.firstIndex(where: { $0.id == messageId }) {
            conversation.messages[idx].content += delta
        } else {
            let newMessage = Message(
                id: messageId,
                conversationId: sessionId,
                role: .assistant,
                content: delta,
                timestamp: Date(),
                isStreaming: true,
                toolCalls: nil,
                location: nil
            )
            conversation.messages.append(newMessage)
        }

        conversation.updatedAt = Date()
        conversations[sessionId] = conversation
    }

    private func addToolCall(sessionId: String, toolId: String, toolName: String) {
        guard var conversation = conversations[sessionId],
              var lastMessage = conversation.messages.last,
              lastMessage.role == .assistant else { return }

        var toolCalls = lastMessage.toolCalls ?? []
        toolCalls.append(ToolCall(
            id: toolId,
            name: toolName,
            status: .running,
            result: nil,
            spawnedSessionKey: nil,
            spawnedLabel: nil
        ))
        lastMessage.toolCalls = toolCalls
        conversation.messages[conversation.messages.count - 1] = lastMessage
        conversations[sessionId] = conversation
    }

    private func updateToolCall(sessionId: String, toolId: String, result: String?) {
        guard var conversation = conversations[sessionId],
              var lastMessage = conversation.messages.last,
              var toolCalls = lastMessage.toolCalls,
              let idx = toolCalls.firstIndex(where: { $0.id == toolId }) else { return }

        toolCalls[idx].status = .completed
        toolCalls[idx].result = result
        lastMessage.toolCalls = toolCalls
        conversation.messages[conversation.messages.count - 1] = lastMessage
        conversations[sessionId] = conversation
    }

    // MARK: - Reconnection

    private func handleConnectionError(_ error: Error) {
        connectionState = .failed(error.localizedDescription)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectAttempt < maxReconnectAttempts else {
            connectionState = .failed("Max reconnection attempts exceeded")
            return
        }

        reconnectAttempt += 1
        connectionState = .reconnecting(attempt: reconnectAttempt)

        let delay = min(30.0, pow(2.0, Double(reconnectAttempt)))

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            connect()
        }
    }
}
