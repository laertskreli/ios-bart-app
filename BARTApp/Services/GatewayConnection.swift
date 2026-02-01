import Foundation
import Combine
import UIKit

@MainActor
class GatewayConnection: NSObject, ObservableObject {

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
    private var urlSession: URLSession!
    private var responseHandlers: [String: ([String: Any]) -> Void] = [:]
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 5
    private var isReceiving = false
    private var pollingTimer: Timer?

    // Connection handshake state
    private var isHandshakeComplete = false
    private var connectNonce: String?

    private let keychainService = "openclaw-node-token"

    // MARK: - Init

    init(gatewayHost: String, port: Int = 443) {
        self.gatewayHost = gatewayHost
        self.port = port
        self.deviceIdentity = Self.loadOrCreateDeviceIdentity()

        super.init()

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        if let token = KeychainHelper.loadString(service: keychainService, account: "openclaw-\(deviceIdentity.nodeId)") {
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
        isHandshakeComplete = false
        connectNonce = nil

        // Use wss:// without port (Tailscale Serve handles it)
        let urlString: String
        if port == 443 {
            urlString = "wss://\(gatewayHost)"
        } else {
            urlString = "wss://\(gatewayHost):\(port)"
        }

        guard let url = URL(string: urlString) else {
            connectionState = .failed("Invalid gateway URL")
            return
        }

        let request = URLRequest(url: url)
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
    }

    func disconnect() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        isReceiving = false
        isHandshakeComplete = false
    }

    // MARK: - Connect Handshake

    private func handleConnectChallenge(nonce: String) {
        self.connectNonce = nonce
        sendConnectRequest()
    }

    private func sendConnectRequest() {
        let params: [String: Any] = [
            "minProtocol": 1,
            "maxProtocol": 1,
            "client": [
                "id": "ios-node",
                "displayName": deviceIdentity.displayName,
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                "platform": "ios",
                "deviceFamily": UIDevice.current.model,
                "modelIdentifier": UIDevice.current.modelIdentifier,
                "mode": "node"
            ],
            "role": "node",
            "caps": ["chat", "location"],
            "commands": ["location.get"]
        ]

        sendRPC(method: "connect", params: params) { [weak self] response in
            guard let self = self else { return }

            if let _ = response["result"] as? [String: Any] {
                Task { @MainActor in
                    print("Connect handshake complete")
                    self.isHandshakeComplete = true

                    // Now proceed with pairing or verification
                    if case .paired(let token) = self.pairingState {
                        self.verifyPairing(token: token)
                    } else {
                        self.requestPairing()
                    }
                }
            } else if let error = response["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Connect failed"
                Task { @MainActor in
                    self.connectionState = .failed(message)
                }
            }
        }
    }

    // MARK: - Pairing

    private func requestPairing() {
        guard isHandshakeComplete else {
            print("Waiting for connect handshake before pairing")
            return
        }

        let params: [String: Any] = [
            "nodeId": deviceIdentity.nodeId,
            "displayName": deviceIdentity.displayName,
            "platform": "ios",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "deviceFamily": UIDevice.current.model,
            "modelIdentifier": UIDevice.current.modelIdentifier,
            "caps": ["chat", "location"],
            "commands": ["location.get"]
        ]

        sendRPC(method: "node.pair.request", params: params) { [weak self] response in
            guard let self = self else { return }

            if let result = response["result"] as? [String: Any],
               let status = result["status"] as? String {
                if status == "pending" {
                    let code = result["code"] as? String ?? ""
                    let requestId = result["requestId"] as? String ?? ""
                    Task { @MainActor in
                        print("Pairing request sent, code: \(code)")
                        self.pairingState = .pendingApproval(code: code, requestId: requestId)
                        self.startPollingForApproval()
                    }
                }
            } else if let error = response["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Unknown error"
                Task { @MainActor in
                    self.pairingState = .failed(message)
                }
            }
        }
    }

    private func startPollingForApproval() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollForApproval()
        }
    }

    private func pollForApproval() {
        guard case .pendingApproval = pairingState else {
            pollingTimer?.invalidate()
            pollingTimer = nil
            return
        }

        let params: [String: Any] = [
            "nodeId": deviceIdentity.nodeId,
            "token": ""
        ]

        sendRPC(method: "node.pair.verify", params: params) { [weak self] response in
            guard let self = self else { return }

            if let result = response["result"] as? [String: Any],
               let ok = result["ok"] as? Bool, ok,
               let node = result["node"] as? [String: Any],
               let token = node["token"] as? String {

                Task { @MainActor in
                    self.pollingTimer?.invalidate()
                    self.pollingTimer = nil

                    self.deviceIdentity.pairingToken = token
                    self.deviceIdentity.pairedAt = Date()
                    self.saveDeviceIdentity()

                    _ = KeychainHelper.saveString(
                        token,
                        service: self.keychainService,
                        account: "openclaw-\(self.deviceIdentity.nodeId)"
                    )

                    self.pairingState = .paired(token: token)
                    self.connectionState = .connected
                }
            }
        }
    }

    private func verifyPairing(token: String) {
        guard isHandshakeComplete else {
            print("Waiting for connect handshake before verifying")
            return
        }

        let params: [String: Any] = [
            "nodeId": deviceIdentity.nodeId,
            "token": token
        ]

        sendRPC(method: "node.pair.verify", params: params) { [weak self] response in
            guard let self = self else { return }

            if let result = response["result"] as? [String: Any],
               let ok = result["ok"] as? Bool, ok {
                Task { @MainActor in
                    self.connectionState = .connected
                }
            } else {
                Task { @MainActor in
                    KeychainHelper.delete(
                        service: self.keychainService,
                        account: "openclaw-\(self.deviceIdentity.nodeId)"
                    )
                    self.deviceIdentity.pairingToken = nil
                    self.saveDeviceIdentity()
                    self.pairingState = .unpaired
                    self.requestPairing()
                }
            }
        }
    }

    func resetPairing() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        KeychainHelper.delete(service: keychainService, account: "openclaw-\(deviceIdentity.nodeId)")
        deviceIdentity.pairingToken = nil
        deviceIdentity.pairedAt = nil
        saveDeviceIdentity()
        pairingState = .unpaired
        disconnect()
    }

    // MARK: - RPC

    private func sendRPC(method: String, params: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        let requestId = UUID().uuidString

        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestId,
            "method": method,
            "params": params
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        responseHandlers[requestId] = completion

        let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
        webSocketTask?.send(wsMessage) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
                Task { @MainActor in
                    self.responseHandlers.removeValue(forKey: requestId)
                    completion(["error": ["message": error.localizedDescription]])
                }
            }
        }

        // Timeout after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if let handler = self?.responseHandlers.removeValue(forKey: requestId) {
                handler(["error": ["message": "Request timed out"]])
            }
        }
    }

    // MARK: - Chat

    func sendMessage(_ text: String, sessionKey: String? = nil) async throws {
        guard case .paired(let token) = pairingState else {
            throw NSError(domain: "Gateway", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not paired"])
        }

        guard isHandshakeComplete else {
            throw NSError(domain: "Gateway", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }

        let agentId = currentAgent?.id ?? "main"
        let key = sessionKey ?? "agent:\(agentId):ios-node:dm:\(deviceIdentity.nodeId)"

        // Add user message to conversation
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

        let params: [String: Any] = [
            "auth": [
                "nodeId": deviceIdentity.nodeId,
                "token": token
            ],
            "agentId": agentId,
            "sessionKey": key,
            "content": [
                ["type": "text", "text": text]
            ]
        ]

        return try await withCheckedThrowingContinuation { continuation in
            sendRPC(method: "sessions.send", params: params) { response in
                if let error = response["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown error"
                    continuation.resume(throwing: NSError(
                        domain: "Gateway",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    ))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func sendLocation(_ location: LocationShare, sessionKey: String? = nil) async throws {
        guard case .paired(let token) = pairingState else {
            throw NSError(domain: "Gateway", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not paired"])
        }

        guard isHandshakeComplete else {
            throw NSError(domain: "Gateway", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }

        let agentId = currentAgent?.id ?? "main"
        let key = sessionKey ?? "agent:\(agentId):ios-node:dm:\(deviceIdentity.nodeId)"

        let params: [String: Any] = [
            "auth": [
                "nodeId": deviceIdentity.nodeId,
                "token": token
            ],
            "agentId": agentId,
            "sessionKey": key,
            "content": [
                [
                    "type": "location",
                    "latitude": location.latitude,
                    "longitude": location.longitude,
                    "accuracy": location.accuracy ?? 0,
                    "ttl": location.ttl
                ]
            ]
        ]

        return try await withCheckedThrowingContinuation { continuation in
            sendRPC(method: "sessions.send", params: params) { response in
                if let error = response["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown error"
                    continuation.resume(throwing: NSError(
                        domain: "Gateway",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    ))
                } else {
                    continuation.resume()
                }
            }
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

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Handle EVENTS (type: "event")
        if let type = json["type"] as? String, type == "event",
           let event = json["event"] as? String {
            handleEvent(event: event, message: json)
            return
        }

        // Handle RPC responses (jsonrpc: "2.0", id: "...")
        if let id = json["id"] as? String,
           let handler = responseHandlers.removeValue(forKey: id) {
            handler(json)
            return
        }

        // Handle server-initiated RPC methods (method: "...")
        if let method = json["method"] as? String {
            handleServerMessage(method: method, message: json)
        }
    }

    private func handleEvent(event: String, message: [String: Any]) {
        switch event {
        case "connect.challenge":
            if let payload = message["payload"] as? [String: Any],
               let nonce = payload["nonce"] as? String {
                print("Received connect.challenge with nonce")
                handleConnectChallenge(nonce: nonce)
            }

        default:
            print("Unhandled event: \(event)")
        }
    }

    private func handleServerMessage(method: String, message: [String: Any]) {
        guard let params = message["params"] as? [String: Any] else { return }

        switch method {
        case "agent.message":
            handleAgentMessage(params)

        case "node.pair.resolved":
            handlePairResolved(params)

        case "agent.typing":
            // Could show typing indicator
            break

        default:
            print("Unhandled server method: \(method)")
        }
    }

    private func handleAgentMessage(_ params: [String: Any]) {
        guard let content = params["content"] as? [[String: Any]] else { return }

        let sessionKey = params["sessionKey"] as? String ?? "main"

        for item in content {
            if let text = item["text"] as? String {
                let messageId = UUID().uuidString
                let newMessage = Message(
                    id: messageId,
                    conversationId: sessionKey,
                    role: .assistant,
                    content: text,
                    timestamp: Date(),
                    isStreaming: false,
                    toolCalls: nil,
                    location: nil
                )
                addMessageToConversation(newMessage, sessionKey: sessionKey)
            }
        }
    }

    private func handlePairResolved(_ params: [String: Any]) {
        if let decision = params["decision"] as? String {
            if decision == "approved" {
                pollForApproval()
            } else {
                Task { @MainActor in
                    self.pairingState = .failed("Pairing rejected")
                }
            }
        }
    }

    private func addMessageToConversation(_ message: Message, sessionKey: String) {
        var conversation = conversations[sessionKey] ?? Conversation(
            id: sessionKey,
            sessionKey: sessionKey,
            agentId: currentAgent?.id ?? "main",
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

    // MARK: - Reconnection

    private func handleConnectionError(_ error: Error) {
        connectionState = .failed(error.localizedDescription)
        isHandshakeComplete = false
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

// MARK: - URLSessionWebSocketDelegate

extension GatewayConnection: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("WebSocket connected, waiting for connect.challenge")
        Task { @MainActor in
            self.reconnectAttempt = 0
            self.isReceiving = false
            self.receiveMessages()
            // Don't set connectionState to .connected yet - wait for handshake
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("WebSocket disconnected: \(closeCode)")
        Task { @MainActor in
            self.connectionState = .disconnected
            self.isHandshakeComplete = false
            self.scheduleReconnect()
        }
    }
}

// MARK: - UIDevice Extension

extension UIDevice {
    var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}
