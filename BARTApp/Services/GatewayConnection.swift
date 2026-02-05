import Foundation
import Combine
import UIKit
import Security

@MainActor
class GatewayConnection: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var pairingState: PairingState = .unpaired
    @Published private(set) var currentAgent: AgentInfo?
    @Published private(set) var conversations: [String: Conversation] = [:]
    @Published private(set) var subAgents: [SubAgentInfo] = []
    @Published private(set) var deviceIdentity: DeviceIdentity
    @Published private(set) var isBotTyping: [String: Bool] = [:]  // sessionKey -> isTyping
    @Published private(set) var activeSessions: [SessionInfo] = []  // All active sessions including subagents
    @Published private(set) var lastLatency: TimeInterval?  // Last measured round-trip latency
    @Published private(set) var lastHeartbeat: Date?  // Last heartbeat received from gateway

    // Track streaming messages by session
    private var streamingMessageIds: [String: String] = [:]  // sessionKey -> messageId

    // Latency tracking
    private var lastPingTime: Date?

    // MARK: - Configuration

    private var gatewayHost: String
    private var port: Int
    private var useSSL: Bool
    private var gatewayToken: String = ""  // Set via manual entry or after pairing
    private var verificationCode: String?  // Optional QR verification code
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
    private var connectRequestSent = false

    // Polling for messages (fallback when subscriptions don't work)
    private var messagePollingTimer: Timer?
    private var lastKnownMessageCount: [String: Int] = [:]
    private var activePollingSessionKeys: Set<String> = []  // Sessions to poll - populated from sessions.list

    private let keychainService = "openclaw-node-token"
    private let gatewayConfigKey = "openclaw-gateway-config"
    private let conversationsStorageKey = "openclaw-conversations"

    // MARK: - Init

    private static let forceResetVersion = "v5_nuclear_2026_02_02"  // Increment to force another reset

    init(gatewayHost: String, port: Int = 443, useSSL: Bool = true) {
        self.gatewayHost = gatewayHost
        self.port = port
        self.useSSL = useSSL

        // Force a complete reset if we haven't done so for this version
        // This clears all stale cached data that causes nonce mismatch errors
        let lastResetVersion = UserDefaults.standard.string(forKey: "openclaw-reset-version")
        if lastResetVersion != Self.forceResetVersion {
            #if DEBUG
            print("🧹 FORCE RESET: Clearing ALL cached pairing/connection data...")
            #endif
            Self.performForceReset()
            UserDefaults.standard.set(Self.forceResetVersion, forKey: "openclaw-reset-version")
            UserDefaults.standard.synchronize()
            #if DEBUG
            print("🧹 FORCE RESET: Complete. Starting fresh.")
            #endif
        }

        self.deviceIdentity = Self.loadOrCreateDeviceIdentity()

        super.init()

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        // After force reset, there will be no saved token - start unpaired
        let keychainAccount = "openclaw-\(deviceIdentity.nodeId)"
        #if DEBUG
        print("🔍 Looking for saved token with key: \(keychainAccount)")
        #endif

        if let token = KeychainHelper.loadString(service: keychainService, account: keychainAccount) {
            self.pairingState = .paired(token: token)
            self.deviceIdentity.pairingToken = token
            self.gatewayToken = token  // Use saved device token for auth
            #if DEBUG
            let tokenPreview = String(token.prefix(8)) + "..."
            print("🔑 Loaded saved device token: \(tokenPreview)")
            #endif
        } else {
            #if DEBUG
            print("⚠️ No saved token found - will need to pair")
            #endif
        }

        #if DEBUG
        print("🌐 Gateway config: \(gatewayHost):\(port), SSL: \(useSSL)")
        #endif

        // Load saved conversations and pending messages
        loadSavedConversations()
        loadPendingMessages()
    }

    /// Performs a complete reset of all cached pairing/connection data
    private static func performForceReset() {
        // 1. Clear gateway config from UserDefaults
        UserDefaults.standard.removeObject(forKey: "openclaw-gateway-config")

        // 2. Clear device identity from UserDefaults
        UserDefaults.standard.removeObject(forKey: DeviceIdentity.storageKey)

        // 3. Clear conversations
        UserDefaults.standard.removeObject(forKey: "openclaw-conversations")

        // 4. Clear push token references
        UserDefaults.standard.removeObject(forKey: "pendingPushToken")
        UserDefaults.standard.removeObject(forKey: "apnsDeviceToken")

        // 5. Delete Ed25519 key pair (will be regenerated)
        DeviceIdentityManager.shared.deleteKeyPair()

        // 6. Clear ALL keychain entries for this service
        let keychainService = "openclaw-node-token"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        _ = SecItemDelete(query as CFDictionary)

        UserDefaults.standard.synchronize()
    }

    // MARK: - Gateway Configuration

    func setGatewayToken(_ token: String) {
        self.gatewayToken = token
        saveGatewayConfig()
    }

    func updateConnectionConfig(host: String, port: Int, useSSL: Bool) {
        self.gatewayHost = host
        self.port = port
        self.useSSL = useSSL
        saveGatewayConfig()
    }

    func connectWithQRPayload(_ payload: QRPairingPayload) {
        guard let config = payload.hostAndPort else {
            connectionState = .failed("Invalid gateway URL in QR code")
            return
        }

        self.gatewayHost = config.host
        self.port = config.port
        self.useSSL = config.useSSL

        // Use token from QR code if present
        if let token = payload.token, !token.isEmpty {
            self.gatewayToken = token
        }

        if let verificationCode = payload.verificationCode {
            self.verificationCode = verificationCode
        }

        saveGatewayConfig()
        connect()
    }

    private func saveGatewayConfig() {
        let config: [String: Any] = [
            "host": gatewayHost,
            "port": port,
            "useSSL": useSSL,
            "token": gatewayToken
        ]
        if let data = try? JSONSerialization.data(withJSONObject: config) {
            UserDefaults.standard.set(data, forKey: gatewayConfigKey)
        }
    }

    /// Clears cached gateway config if it contains a stale/different host than current config
    private func clearStaleGatewayConfig() {
        guard let data = UserDefaults.standard.data(forKey: gatewayConfigKey),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cachedHost = config["host"] as? String else {
            return
        }

        // If cached host differs from current config, clear it entirely
        if cachedHost != self.gatewayHost {
            UserDefaults.standard.removeObject(forKey: gatewayConfigKey)
            UserDefaults.standard.synchronize()
        }
    }

    private func loadSavedGatewayConfig() {
        guard let data = UserDefaults.standard.data(forKey: gatewayConfigKey),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // NOTE: We intentionally do NOT load host/port/useSSL from cache anymore.
        // These should always come from Configuration.swift or a fresh QR scan.
        // Only load the authentication token from cache.
        if let token = config["token"] as? String, !token.isEmpty {
            self.gatewayToken = token
        }
    }

    // MARK: - Conversation Persistence

    private func loadSavedConversations() {
        guard let data = UserDefaults.standard.data(forKey: conversationsStorageKey) else {
            return
        }

        do {
            let decoded = try JSONDecoder().decode([String: Conversation].self, from: data)
            self.conversations = decoded
        } catch {
            #if DEBUG
            print("❌ Failed to load conversations: \(error)")
            #endif
        }
    }

    private func saveConversations() {
        do {
            let data = try JSONEncoder().encode(conversations)
            UserDefaults.standard.set(data, forKey: conversationsStorageKey)
        } catch {
            #if DEBUG
            print("❌ Failed to save conversations: \(error)")
            #endif
        }
    }

    func clearConversationHistory() {
        conversations = [:]
        UserDefaults.standard.removeObject(forKey: conversationsStorageKey)
        ContentParser.clearCache()
    }

    // MARK: - Device Identity

    private static func loadOrCreateDeviceIdentity() -> DeviceIdentity {
        if let data = UserDefaults.standard.data(forKey: DeviceIdentity.storageKey),
           let identity = try? JSONDecoder().decode(DeviceIdentity.self, from: data) {
            return identity
        }

        // Use identifierForVendor for a deterministic device ID
        // This ensures the same device always gets the same nodeId
        // preventing "duplicate device" entries on the server
        let deviceId: String
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            // Use first 8 chars of IDFV hash for shorter, consistent ID
            let hash = idfv.data(using: .utf8)?.base64EncodedString() ?? ""
            deviceId = String(hash.prefix(8).filter { $0.isLetter || $0.isNumber }).lowercased()
        } else {
            // Fallback to random UUID if IDFV unavailable
            deviceId = UUID().uuidString.prefix(8).lowercased()
        }

        let newIdentity = DeviceIdentity(
            nodeId: "iphone-\(deviceId)",
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
              (connectionState != .connecting && connectionState != .connected) else {
            return
        }

        connectionState = .connecting
        isHandshakeComplete = false
        connectNonce = nil
        connectRequestSent = false

        let scheme = useSSL ? "wss" : "ws"
        let urlString = "\(scheme)://\(gatewayHost):\(port)"

        guard let url = URL(string: urlString) else {
            connectionState = .failed("Invalid gateway URL")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        // Connection timeout - if not connected after 15 seconds, fail
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self else { return }
            if case .connecting = self.connectionState {
                self.connectionState = .failed("Connection timeout - gateway not reachable")
                self.webSocketTask?.cancel()
            }
        }
    }

    func disconnect() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        messagePollingTimer?.invalidate()
        messagePollingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        isReceiving = false
        isHandshakeComplete = false
    }

    // MARK: - App Lifecycle (Background/Foreground)

    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var wasConnectedBeforeBackground = false
    private var lastActiveTimestamp: Date?

    /// Called when the app is about to enter background
    /// Requests extended background time for clean disconnection
    func handleAppWillBackground() {
        guard connectionState.isConnected else { return }

        wasConnectedBeforeBackground = true
        lastActiveTimestamp = Date()

        // Request extended background execution time
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "CleanDisconnect") { [weak self] in
            // Expiration handler - system is about to kill background time
            // Must dispatch to MainActor since this callback may come from background thread
            print("⏰ Background time expiring, ending task")
            Task { @MainActor in
                self?.endBackgroundTask()
            }
        }

        #if DEBUG
        print("🌙 Background task started, keeping connection briefly...")
        #endif

        // Keep connection alive for a short time to receive any pending messages
        // Then disconnect gracefully after 25 seconds (iOS gives ~30 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self = self,
                  UIApplication.shared.applicationState == .background else { return }

            #if DEBUG
            print("🌙 Background time limit approaching, disconnecting gracefully...")
            #endif
            self.disconnect()
            self.endBackgroundTask()
        }
    }

    /// Called when app becomes active (returns to foreground)
    func handleAppDidBecomeActive() {
        // End any lingering background task
        endBackgroundTask()

        // If we were connected before going to background, reconnect
        if wasConnectedBeforeBackground || connectionState == .disconnected {
            let timeSinceLastActive = lastActiveTimestamp.map { Date().timeIntervalSince($0) } ?? 0

            if connectionState != .connected && connectionState != .connecting {
                // Only auto-connect if we have a token (means we're paired)
                if !gatewayToken.isEmpty {
                    #if DEBUG
                    print("☀️ App active, reconnecting... (was inactive for \(Int(timeSinceLastActive))s)")
                    #endif
                    reconnectAttempt = 0  // Reset reconnect counter
                    connect()
                }
            }

            // Fetch latest messages to catch up on anything missed
            if connectionState.isConnected {
                fetchSessionsList()
            }
        }

        wasConnectedBeforeBackground = false
    }

    private func endBackgroundTask() {
        guard backgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
    }

    // MARK: - Message Polling (Fallback)

    /// Start polling for new messages as a fallback when subscriptions don't work
    private func startMessagePolling() {
        messagePollingTimer?.invalidate()
        messagePollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.pollForNewMessages()
            }
        }
        #if DEBUG
        print("📡 Started message polling (5s interval)")
        #endif
    }

    private func pollForNewMessages() {
        // Poll all active sessions silently
        for sessionKey in activePollingSessionKeys {
            pollSession(sessionKey)
        }
    }

    /// Add a session to the polling list
    func addSessionToPolling(_ sessionKey: String) {
        activePollingSessionKeys.insert(sessionKey)
    }

    private func pollSession(_ sessionKey: String) {
        let params: [String: Any] = [
            "keys": [sessionKey],
            "limit": 10
        ]

        sendRPC(method: "sessions.preview", params: params) { [weak self] response in
            guard let self = self else { return }

            // Parse response - previews can be an ARRAY or a dictionary
            var sessionPreview: [String: Any]?

            // Try to get previews from result or payload
            let previewsContainer: Any?
            if let result = response["result"] as? [String: Any] {
                previewsContainer = result["previews"]
            } else if let payload = response["payload"] as? [String: Any] {
                previewsContainer = payload["previews"]
            } else {
                previewsContainer = response["previews"]
            }

            // Handle array format: [{key: "ios-chat", items: [...]}]
            if let previewsArray = previewsContainer as? [[String: Any]] {
                for preview in previewsArray {
                    if let key = preview["key"] as? String, key == sessionKey {
                        sessionPreview = preview
                        break
                    }
                }
            }
            // Handle dictionary format: {"ios-chat": {messages: [...]}}
            else if let previewsDict = previewsContainer as? [String: Any] {
                sessionPreview = previewsDict[sessionKey] as? [String: Any]
            }

            guard let preview = sessionPreview else { return }

            // Check status
            let status = preview["status"] as? String ?? "unknown"
            if status == "empty" { return }

            // Get messages - could be "items" or "messages"
            let messages: [[String: Any]]
            if let items = preview["items"] as? [[String: Any]] {
                messages = items
            } else if let msgs = preview["messages"] as? [[String: Any]] {
                messages = msgs
            } else {
                return
            }

            // Check for new messages
            let currentCount = messages.count
            let lastCount = self.lastKnownMessageCount[sessionKey] ?? 0

            if currentCount > lastCount || lastCount == 0 {
                Task { @MainActor in
                    self.processPolledMessages(messages, sessionKey: sessionKey)
                    self.lastKnownMessageCount[sessionKey] = currentCount
                }
            }
        }
    }

    private func processPolledMessages(_ messages: [[String: Any]], sessionKey: String) {
        let existingMessages = conversations[sessionKey]?.messages ?? []
        let existingContent = Set(existingMessages.map { $0.content })

        for msg in messages {
            let role = msg["role"] as? String ?? "unknown"
            guard role == "assistant" else { continue }

            // Extract text content
            var fullText = ""
            if let content = msg["content"] as? [[String: Any]] {
                for item in content {
                    if let text = item["text"] as? String {
                        fullText += text
                    }
                }
            } else if let content = msg["content"] as? String {
                fullText = content
            }

            // Skip empty or duplicate messages
            if fullText.isEmpty || existingContent.contains(fullText) {
                continue
            }

            print("💬 New message received")
            addAgentResponseToUI(fullText, sessionKey: sessionKey)
        }
    }

    // MARK: - Connect Handshake

    private func handleConnectChallenge(nonce: String) {
        self.connectNonce = nonce
        // Small delay to ensure WebSocket is fully ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.sendConnectRequest()
        }
    }

    private func sendConnectRequest() {
        // Only send connect once
        guard !connectRequestSent else {
            print("⚠️ Connect already sent, skipping")
            return
        }
        connectRequestSent = true

        // Build connect params
        var params: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 3,
            "client": [
                "id": "openclaw-ios",
                "displayName": deviceIdentity.displayName,
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                "platform": "ios",
                "mode": "node"
            ],
            "role": "operator"
        ]

        // Use token auth if we have a token (from QR code or saved device token)
        if !gatewayToken.isEmpty {
            params["auth"] = ["token": gatewayToken]
            let tokenPreview = String(gatewayToken.prefix(8)) + "..." + String(gatewayToken.suffix(4))
            print("🔑 Using token authentication: \(tokenPreview)")
            print("🔑 Full token length: \(gatewayToken.count) chars")
        } else {
            print("⚠️ No token available, falling back to device signature")
            // Fallback to device signature auth if no token
            do {
                try DeviceIdentityManager.shared.generateKeyPair()
                let deviceId = try DeviceIdentityManager.shared.getDeviceId()
                let publicKey = try DeviceIdentityManager.shared.getPublicKeyBase64Url()
                let signedAtMs = Int(Date().timeIntervalSince1970 * 1000)

                let payload = DeviceIdentityManager.shared.buildDeviceAuthPayload(
                    deviceId: deviceId,
                    clientId: "openclaw-ios",
                    clientMode: "node",
                    role: "operator",
                    scopes: [],
                    signedAtMs: signedAtMs,
                    token: nil,
                    nonce: connectNonce
                )

                let signature = try DeviceIdentityManager.shared.signPayload(payload)

                params["device"] = [
                    "id": deviceId,
                    "publicKey": publicKey,
                    "signature": signature,
                    "signedAt": signedAtMs,
                    "nonce": connectNonce ?? ""
                ]
                print("🔐 Using device signature authentication")
            } catch {
                print("❌ Failed to create device signature: \(error)")
            }
        }

        print("📤 Sending connect request...")

        sendRPC(method: "connect", params: params) { [weak self] response in
            guard let self = self else { return }

            // Debug: print full response
            print("📥 Connect response received:")
            if let data = try? JSONSerialization.data(withJSONObject: response, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }

            // Check for hello-ok success response
            let responseType = response["type"] as? String
            let isOk = response["ok"] as? Bool ?? false

            // Also check inside "result" object (OpenClaw may wrap responses)
            let result = response["result"] as? [String: Any]
            let resultOk = result?["ok"] as? Bool ?? false

            print("📊 Response check: type=\(responseType ?? "nil"), ok=\(isOk), resultOk=\(resultOk)")

            if responseType == "hello-ok" || isOk || resultOk {
                // Extract device token - check both top-level and inside result
                let auth = (response["auth"] as? [String: Any]) ?? (result?["auth"] as? [String: Any])
                let deviceToken = auth?["deviceToken"] as? String

                Task { @MainActor in
                    print("🔄 Setting connection state to CONNECTED")
                    self.isHandshakeComplete = true
                    self.connectionState = .connected

                    // Use deviceToken from response, or fall back to current gatewayToken
                    let tokenToSave = deviceToken ?? self.gatewayToken

                    if !tokenToSave.isEmpty {
                        if deviceToken != nil {
                            print("🎉 Connected! Device token from response: \(String(tokenToSave.prefix(8)))...")
                        } else {
                            print("✅ Connected! Saving current token: \(String(tokenToSave.prefix(8)))...")
                        }

                        print("🔄 Setting pairing state to PAIRED")
                        self.pairingState = .paired(token: tokenToSave)
                        self.gatewayToken = tokenToSave

                        // Store the token to keychain
                        let keychainAccount = "openclaw-\(self.deviceIdentity.nodeId)"
                        let saved = KeychainHelper.saveString(
                            tokenToSave,
                            service: self.keychainService,
                            account: keychainAccount
                        )
                        print("💾 Saved token to keychain (\(keychainAccount)): \(saved)")

                        // Also save gateway config
                        self.saveGatewayConfig()
                        print("💾 Saved gateway config")
                    } else {
                        print("⚠️ Connected but no token to save - setting paired anyway")
                        self.pairingState = .paired(token: "")
                    }

                    print("✅ State update complete - pairingState: \(self.pairingState)")

                    // Subscribe to events, fetch history, sessions, start polling, register push token
                    self.subscribeToEvents()
                    self.fetchChatHistory()
                    self.fetchSessionsList()
                    self.startMessagePolling()
                    self.registerPendingPushToken()

                    // Send any queued offline messages
                    self.sendPendingMessages()
                }
            } else if let error = response["error"] as? [String: Any] {
                let code = error["code"] as? String
                let codeInt = error["code"] as? Int
                let message = error["message"] as? String ?? "Connect failed"

                if code == "NOT_PAIRED" {
                    // Extract requestId and send pairing request
                    if let details = error["details"] as? [String: Any],
                       let requestId = details["requestId"] as? String {
                        print("⚠️ Not paired. Request ID: \(requestId)")
                        Task { @MainActor in
                            self.isHandshakeComplete = true
                            self.sendNodePairingRequest(requestId: requestId)
                        }
                    } else {
                        // No requestId, just request pairing normally
                        Task { @MainActor in
                            self.isHandshakeComplete = true
                            self.requestPairing()
                        }
                    }
                } else if code == "AUTH_FAILED" || code == "UNAUTHORIZED" || codeInt == 401 {
                    // Authentication failed - could be expired timestamp or invalid HMAC
                    print("🔐 Auth failed: \(message)")
                    Task { @MainActor in
                        self.handleAuthFailure(message: message)
                    }
                } else {
                    Task { @MainActor in
                        print("❌ Connect error: \(message)")
                        self.connectionState = .failed(message)
                    }
                }
            }
        }
    }

    /// Handle authentication failure - reconnect with fresh timestamp
    private func handleAuthFailure(message: String) {
        print("🔐 Handling auth failure, will retry with fresh credentials")

        // Reset connection state
        connectRequestSent = false
        isHandshakeComplete = false

        // Small delay before retrying to avoid rapid reconnection loops
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }

            // Check if we've exceeded retry limit
            if self.reconnectAttempt >= self.maxReconnectAttempts {
                self.connectionState = .failed("Authentication failed: \(message)")
                return
            }

            self.reconnectAttempt += 1
            print("🔄 Retrying connection with fresh timestamp (attempt \(self.reconnectAttempt))")

            // Disconnect and reconnect
            self.webSocketTask?.cancel()
            self.webSocketTask = nil
            self.connect()
        }
    }

    // MARK: - Pairing

    private func sendNodePairingRequest(requestId: String) {
        print("📤 Sending node.pair.request with requestId: \(requestId)")

        let params: [String: Any] = [
            "requestId": requestId,
            "displayName": UIDevice.current.name,
            "note": "iOS app pairing request"
        ]

        sendRPC(method: "node.pair.request", params: params) { [weak self] response in
            guard let self = self else { return }

            if let result = response["result"] as? [String: Any] {
                let status = result["status"] as? String ?? "unknown"
                print("✅ Pairing request status: \(status)")

                if status == "pending" {
                    let code = result["code"] as? String ?? ""
                    Task { @MainActor in
                        print("⏳ Waiting for approval on Mac...")
                        print("   Run: openclaw nodes pending")
                        print("   Then: openclaw nodes approve \(requestId)")
                        self.pairingState = .pendingApproval(code: code, requestId: requestId)
                        self.startPollingForApproval()
                    }
                }
            } else if let error = response["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Pairing failed"
                print("❌ Pairing error: \(message)")
                Task { @MainActor in
                    self.pairingState = .failed(message)
                }
            }
        }
    }

    private func requestPairing() {
        guard isHandshakeComplete else {
            print("Waiting for connect handshake before pairing")
            return
        }

        do {
            let deviceId = try DeviceIdentityManager.shared.getDeviceId()

            let params: [String: Any] = [
                "nodeId": deviceId,
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
                            print("✅ Pairing request sent, code: \(code)")
                            print("⏳ Waiting for approval on Mac...")
                            print("   Run: openclaw nodes pending")
                            print("   Then: openclaw nodes approve \(requestId)")
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
        } catch {
            print("❌ Failed to get device ID: \(error)")
        }
    }

    private func startPollingForApproval() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollForApproval()
            }
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
        print("🗑️ Resetting all credentials and device identity...")

        // Stop any active operations
        pollingTimer?.invalidate()
        pollingTimer = nil
        disconnect()

        // Clear device token from Keychain
        KeychainHelper.delete(service: keychainService, account: "openclaw-\(deviceIdentity.nodeId)")
        print("  ✓ Cleared device token")

        // Delete Ed25519 key pair (will regenerate on next connect)
        DeviceIdentityManager.shared.deleteKeyPair()
        print("  ✓ Deleted Ed25519 key pair")

        // Clear device identity from UserDefaults
        UserDefaults.standard.removeObject(forKey: DeviceIdentity.storageKey)
        print("  ✓ Cleared device identity")

        // Clear saved gateway config
        UserDefaults.standard.removeObject(forKey: gatewayConfigKey)
        print("  ✓ Cleared gateway config")

        // Clear saved conversations
        UserDefaults.standard.removeObject(forKey: conversationsStorageKey)
        conversations = [:]
        print("  ✓ Cleared conversation history")

        // Synchronize UserDefaults
        UserDefaults.standard.synchronize()

        // Create fresh device identity
        deviceIdentity = Self.loadOrCreateDeviceIdentity()
        print("  ✓ Created new device identity: \(deviceIdentity.nodeId)")

        // Reset state
        pairingState = .unpaired
        connectionState = .disconnected
        verificationCode = nil
        gatewayToken = ""

        print("✅ Reset complete. Ready to pair as new device.")
    }

    // MARK: - RPC

    // Track request timestamps for latency measurement
    private var requestTimestamps: [String: Date] = [:]

    private func sendRPC(method: String, params: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        let requestId = UUID().uuidString
        let sendTime = Date()

        // OpenClaw frame format (not JSON-RPC)
        let message: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": method,
            "params": params
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: data, encoding: .utf8) else {
            print("❌ Failed to serialize RPC message")
            return
        }

        // Debug: print what we're sending
        if let prettyData = try? JSONSerialization.data(withJSONObject: message, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            print("📤 Sending RPC [\(method)]:")
            print(prettyString)
        }

        // Track request time for latency
        requestTimestamps[requestId] = sendTime

        // Wrap completion to measure latency
        responseHandlers[requestId] = { [weak self] response in
            if let startTime = self?.requestTimestamps.removeValue(forKey: requestId) {
                let latency = Date().timeIntervalSince(startTime)
                Task { @MainActor in
                    self?.lastLatency = latency
                }
            }
            completion(response)
        }

        let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
        webSocketTask?.send(wsMessage) { [weak self] error in
            if let error = error {
                print("❌ WebSocket send error: \(error)")
                Task { @MainActor [weak self] in
                    self?.responseHandlers.removeValue(forKey: requestId)
                    self?.requestTimestamps.removeValue(forKey: requestId)
                    completion(["error": ["message": error.localizedDescription]])
                }
            } else {
                print("✅ RPC sent successfully")
            }
        }

        // Timeout after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if let handler = self?.responseHandlers.removeValue(forKey: requestId) {
                self?.requestTimestamps.removeValue(forKey: requestId)
                handler(["error": ["message": "Request timed out"]])
            }
        }
    }

    // MARK: - Push Notifications

    private var registeredPushToken: String?

    /// Register APNs device token with the gateway server
    func registerPushToken(_ token: String) {
        // Don't re-register the same token
        guard token != registeredPushToken else {
            print("📱 Push token already registered")
            return
        }

        // Wait for connection if not connected yet
        guard connectionState.isConnected else {
            print("📱 Saving push token for later registration (not connected)")
            // Token will be registered when connection is established
            // Store it temporarily
            UserDefaults.standard.set(token, forKey: "pendingPushToken")
            return
        }

        let params: [String: Any] = [
            "nodeId": deviceIdentity.nodeId,
            "platform": "ios",
            "token": token,
            "bundleId": Bundle.main.bundleIdentifier ?? "com.laert.bartapp"
        ]

        print("📱 Registering push token with gateway...")

        sendRPC(method: "node.registerPushToken", params: params) { [weak self] response in
            if let error = response["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Unknown error"
                print("❌ Push token registration failed: \(message)")
            } else {
                print("✅ Push token registered successfully")
                self?.registeredPushToken = token
                UserDefaults.standard.removeObject(forKey: "pendingPushToken")
            }
        }
    }

    /// Called after successful connection to register any pending push token
    private func registerPendingPushToken() {
        // Check for pending token
        if let pendingToken = UserDefaults.standard.string(forKey: "pendingPushToken") {
            print("📱 Registering pending push token...")
            registerPushToken(pendingToken)
        }
        // Also check for stored APNs token
        else if let storedToken = UserDefaults.standard.string(forKey: "apnsDeviceToken"),
                storedToken != registeredPushToken {
            print("📱 Re-registering stored push token...")
            registerPushToken(storedToken)
        }
    }

    // MARK: - Offline Message Queue

    /// Queue of messages waiting to be sent when reconnected
    private var pendingMessages: [PendingMessage] = []
    private let pendingMessagesKey = "openclaw-pending-messages"

    struct PendingMessage: Codable {
        let id: String
        let text: String
        let sessionKey: String
        let timestamp: Date
    }

    /// Queue a message for later sending when offline
    private func queueMessage(_ text: String, sessionKey: String, messageId: String) {
        let pending = PendingMessage(id: messageId, text: text, sessionKey: sessionKey, timestamp: Date())
        pendingMessages.append(pending)
        savePendingMessages()
        print("📦 Message queued for later: \(text.prefix(30))...")
    }

    private func savePendingMessages() {
        if let data = try? JSONEncoder().encode(pendingMessages) {
            UserDefaults.standard.set(data, forKey: pendingMessagesKey)
        }
    }

    private func loadPendingMessages() {
        if let data = UserDefaults.standard.data(forKey: pendingMessagesKey),
           let messages = try? JSONDecoder().decode([PendingMessage].self, from: data) {
            pendingMessages = messages
        }
    }

    /// Send all queued messages when reconnected
    func sendPendingMessages() {
        guard connectionState == .connected else { return }
        guard !pendingMessages.isEmpty else { return }

        print("📤 Sending \(pendingMessages.count) queued message(s)...")

        let messagesToSend = pendingMessages
        pendingMessages = []
        savePendingMessages()

        Task {
            for pending in messagesToSend {
                do {
                    try await sendMessageInternal(pending.text, sessionKey: pending.sessionKey, messageId: pending.id)
                } catch {
                    print("❌ Failed to send queued message: \(error.localizedDescription)")
                    // Re-queue if still failing
                    queueMessage(pending.text, sessionKey: pending.sessionKey, messageId: pending.id)
                }
            }
        }
    }

    // MARK: - Chat

    func sendMessage(_ text: String, sessionKey: String? = nil) async throws {
        let agentId = currentAgent?.id ?? "main"
        let key = sessionKey ?? "agent:\(agentId):node:dm:\(deviceIdentity.nodeId)"
        let messageId = UUID().uuidString

        // Add user message to conversation with pending status
        let userMessage = Message(
            id: messageId,
            conversationId: key,
            role: .user,
            content: text,
            timestamp: Date(),
            isStreaming: false,
            toolCalls: nil,
            location: nil,
            deliveryStatus: connectionState == .connected ? .sending : .pending
        )
        addMessageToConversation(userMessage, sessionKey: key)

        // If not connected, queue for later
        guard connectionState == .connected else {
            queueMessage(text, sessionKey: key, messageId: messageId)
            return
        }

        try await sendMessageInternal(text, sessionKey: key, messageId: messageId)
    }

    private func sendMessageInternal(_ text: String, sessionKey: String, messageId: String) async throws {
        // Update status to sending
        updateMessageDeliveryStatus(messageId: messageId, sessionKey: sessionKey, status: .sending)

        // Use chat.send for direct agent chat
        let params: [String: Any] = [
            "sessionKey": sessionKey,
            "message": text,
            "idempotencyKey": messageId
        ]

        print("💬 [Send] Sending to sessionKey: \(sessionKey)")
        print("💬 [Send] Message: \(text.prefix(50))...")

        // Ensure we're polling this session for responses
        addSessionToPolling(sessionKey)

        return try await withCheckedThrowingContinuation { continuation in
            sendRPC(method: "chat.send", params: params) { [weak self] response in
                guard let self = self else { return }

                Task { @MainActor in
                    if let error = response["error"] as? [String: Any] {
                        let message = error["message"] as? String ?? "Unknown error"
                        print("❌ Message send error: \(message)")
                        // Update to failed
                        self.updateMessageDeliveryStatus(messageId: messageId, sessionKey: sessionKey, status: .failed)
                        continuation.resume(throwing: NSError(
                            domain: "Gateway",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: message]
                        ))
                    } else {
                        print("✅ Message sent successfully")
                        // Update to delivered
                        self.updateMessageDeliveryStatus(messageId: messageId, sessionKey: sessionKey, status: .delivered)
                        continuation.resume()
                    }
                }
            }
        }
    }

    /// Updates the delivery status of a message
    private func updateMessageDeliveryStatus(messageId: String, sessionKey: String, status: MessageDeliveryStatus) {
        guard var conversation = conversations[sessionKey],
              let index = conversation.messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        conversation.messages[index].deliveryStatus = status
        conversation.updatedAt = Date()
        conversations[sessionKey] = conversation
        saveConversations()
    }

    /// Marks the last user message in the conversation as "received" when agent responds
    private func markLastUserMessageAsReceived(sessionKey: String) {
        guard var conversation = conversations[sessionKey] else { return }
        // Find the last user message that was delivered (sent)
        if let index = conversation.messages.lastIndex(where: { $0.role == .user && $0.deliveryStatus == .delivered }) {
            conversation.messages[index].deliveryStatus = .received
            conversations[sessionKey] = conversation
        }
    }

    /// Sends an attachment (image or file) to the chat
    func sendAttachment(_ attachment: AttachmentItem, sessionKey: String? = nil) async throws {
        guard connectionState == .connected else {
            throw NSError(domain: "Gateway", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }

        let agentId = currentAgent?.id ?? "main"
        let key = sessionKey ?? "agent:\(agentId):node:dm:\(deviceIdentity.nodeId)"
        let messageId = UUID().uuidString

        // Create a message content that describes the attachment
        let base64Data = attachment.data.base64EncodedString()
        let attachmentInfo: [String: Any] = [
            "type": "attachment",
            "filename": attachment.filename,
            "mimeType": attachment.mimeType,
            "size": attachment.data.count,
            "data": base64Data
        ]

        // Create display content for the local message
        let displayContent: String
        switch attachment.type {
        case .image:
            displayContent = "[Image: \(attachment.filename)]"
        case .file:
            displayContent = "[File: \(attachment.filename)]"
        }

        // Add user message to conversation with sending status
        var userMessage = Message(
            id: messageId,
            conversationId: key,
            role: .user,
            content: displayContent,
            timestamp: Date(),
            isStreaming: false,
            toolCalls: nil,
            location: nil,
            deliveryStatus: .sending
        )
        userMessage.attachmentData = attachment.data
        userMessage.attachmentFilename = attachment.filename
        userMessage.attachmentMimeType = attachment.mimeType
        addMessageToConversation(userMessage, sessionKey: key)

        // Send via RPC
        let params: [String: Any] = [
            "sessionKey": key,
            "attachment": attachmentInfo,
            "idempotencyKey": messageId
        ]

        print("📎 [Send] Sending attachment: \(attachment.filename) (\(attachment.data.count) bytes)")

        // Ensure we're polling this session for responses
        addSessionToPolling(key)

        return try await withCheckedThrowingContinuation { continuation in
            sendRPC(method: "chat.sendAttachment", params: params) { [weak self] response in
                guard let self = self else { return }

                Task { @MainActor in
                    if let error = response["error"] as? [String: Any] {
                        let message = error["message"] as? String ?? "Unknown error"
                        print("❌ Attachment send error: \(message)")
                        // Update to failed
                        self.updateMessageDeliveryStatus(messageId: messageId, sessionKey: key, status: .failed)
                        continuation.resume(throwing: NSError(
                            domain: "Gateway",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: message]
                        ))
                    } else {
                        print("✅ Attachment sent successfully")
                        // Update to delivered
                        self.updateMessageDeliveryStatus(messageId: messageId, sessionKey: key, status: .delivered)
                        continuation.resume()
                    }
                }
            }
        }
    }

    // Subscribe to events - currently not supported by this gateway, relying on polling
    private func subscribeToEvents() {
        print("📡 Real-time subscriptions not supported, using polling fallback")
        // Add the default session to polling
        let defaultSession = "agent:main:node:dm:\(deviceIdentity.nodeId)"
        addSessionToPolling(defaultSession)
    }

    /// Subscribe to a specific session (currently just adds to polling)
    func subscribeToSession(_ sessionKey: String) {
        addSessionToPolling(sessionKey)
    }

    // Send a test message after successful connection
    func sendTestMessage() {
        // Use proper session key format
        let sessionKey = "agent:main:node:dm:\(deviceIdentity.nodeId)"

        let params: [String: Any] = [
            "sessionKey": sessionKey,
            "message": "Hello from my iPhone app!",
            "idempotencyKey": UUID().uuidString
        ]

        print("📤 Sending test message to sessionKey: \(sessionKey)")

        // Add this session to polling
        addSessionToPolling(sessionKey)

        sendRPC(method: "chat.send", params: params) { response in
            if let ok = response["ok"] as? Bool, ok {
                print("✅ Test message sent!")
            } else if let error = response["error"] as? [String: Any] {
                let msg = error["message"] as? String ?? "Unknown error"
                print("❌ Test message error: \(msg)")
            } else {
                print("📥 Response: \(response)")
            }
        }
    }

    // Fetch chat history for debugging
    func fetchChatHistory() {
        let params: [String: Any] = [
            "sessionKey": "ios-chat",
            "limit": 10
        ]

        print("📜 Fetching chat history...")

        sendRPC(method: "chat.history", params: params) { response in
            if let result = response["result"] as? [String: Any] {
                print("📜 Chat history:")
                if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else if let error = response["error"] as? [String: Any] {
                let msg = error["message"] as? String ?? "Unknown error"
                print("❌ History error: \(msg)")
            }
        }
    }

    // MARK: - Sessions List

    /// Fetches all sessions from the gateway including subagents
    func fetchSessionsList() {
        let params: [String: Any] = [
            "limit": 50
        ]

        print("📋 [Sessions] Fetching sessions list...")

        sendRPC(method: "sessions.list", params: params) { [weak self] response in
            guard let self = self else { return }

            print("📋 [Sessions] Response received")

            // Debug log
            if let data = try? JSONSerialization.data(withJSONObject: response, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                print("📋 Sessions list response:")
                print(str.prefix(1000))
            }

            // Parse response - could be in result or payload
            let sessions: [[String: Any]]
            if let result = response["result"] as? [String: Any],
               let s = result["sessions"] as? [[String: Any]] {
                sessions = s
            } else if let payload = response["payload"] as? [String: Any],
                      let s = payload["sessions"] as? [[String: Any]] {
                sessions = s
            } else if let s = response["sessions"] as? [[String: Any]] {
                sessions = s
            } else {
                print("⚠️ Could not parse sessions list response")
                return
            }

            Task { @MainActor in
                print("📋 [Sessions] Parsing \(sessions.count) sessions...")

                // Log all session keys and add them ALL to polling
                for sessionData in sessions {
                    if let key = sessionData["key"] as? String {
                        let msgCount = (sessionData["messages"] as? [[String: Any]])?.count ?? 0
                        let status = sessionData["status"] as? String ?? "unknown"
                        print("📋 [Sessions] Found: \(key) (msgs: \(msgCount), status: \(status))")
                        // Add ALL sessions to polling
                        self.addSessionToPolling(key)
                    }
                }

                self.activeSessions = sessions.compactMap { sessionData -> SessionInfo? in
                    guard let key = sessionData["key"] as? String,
                          let sessionId = sessionData["sessionId"] as? String else {
                        return nil
                    }

                    let label = sessionData["label"] as? String
                    let displayName = sessionData["displayName"] as? String
                    let updatedAt = sessionData["updatedAt"] as? Int64 ?? 0
                    let model = sessionData["model"] as? String
                    let totalTokens = sessionData["totalTokens"] as? Int
                    let topic = sessionData["topic"] as? String
                    let participantName = sessionData["participantName"] as? String
                    let messageCount = (sessionData["messages"] as? [[String: Any]])?.count ?? 0

                    // Parse category from session key or metadata
                    let category = SessionInfo.parseCategory(from: key, metadata: sessionData)
                    let isSubagent = category == .subagent

                    // Determine friendly name
                    let friendlyName: String
                    if let lbl = label, !lbl.isEmpty {
                        friendlyName = lbl
                    } else if let dn = displayName, !dn.isEmpty {
                        friendlyName = dn
                    } else if let participant = participantName, !participant.isEmpty {
                        friendlyName = participant
                    } else if isSubagent {
                        // Extract subagent ID from key
                        friendlyName = String(key.components(separatedBy: ":subagent:").last?.prefix(8) ?? "")
                    } else {
                        friendlyName = category.displayName
                    }

                    return SessionInfo(
                        id: sessionId,
                        sessionKey: key,
                        label: friendlyName,
                        isMain: !isSubagent && (key == "ios-chat" || key.contains(":dm:")),
                        isActive: true,
                        lastActivity: Date(timeIntervalSince1970: TimeInterval(updatedAt) / 1000),
                        unreadCount: 0,
                        model: model,
                        totalTokens: totalTokens,
                        category: category,
                        topic: topic,
                        messageCount: messageCount,
                        participantName: participantName
                    )
                }
                // Filter out heartbeat channel from session list
                .filter { session in
                    let key = session.sessionKey.lowercased()
                    let label = session.label.lowercased()
                    return !key.contains("heartbeat") && !label.contains("heartbeat")
                }

                print("📋 [Sessions] Loaded \(self.activeSessions.count) sessions, polling: \(self.activePollingSessionKeys)")

                // Also update subAgents list from sessions that contain :subagent:
                let subagentSessions = self.activeSessions.filter { $0.sessionKey.contains(":subagent:") }
                print("📋 Found \(subagentSessions.count) subagent sessions")
            }
        }
    }

    /// Fetches message history for a specific session
    func fetchSessionHistory(sessionKey: String, completion: @escaping ([Message]) -> Void) {
        let params: [String: Any] = [
            "sessionKey": sessionKey,
            "limit": 50
        ]

        print("📜 Fetching history for session: \(sessionKey)")

        sendRPC(method: "sessions.history", params: params) { [weak self] response in
            guard let self = self else { return }

            var messages: [Message] = []

            // Parse response
            let rawMessages: [[String: Any]]
            if let result = response["result"] as? [String: Any],
               let m = result["messages"] as? [[String: Any]] {
                rawMessages = m
            } else if let payload = response["payload"] as? [String: Any],
                      let m = payload["messages"] as? [[String: Any]] {
                rawMessages = m
            } else if let m = response["messages"] as? [[String: Any]] {
                rawMessages = m
            } else {
                print("⚠️ Could not parse session history response")
                completion([])
                return
            }

            for msgData in rawMessages {
                guard let roleStr = msgData["role"] as? String else { continue }

                let role: MessageRole = roleStr == "user" ? .user : .assistant
                var content = ""

                // Extract text content
                if let contentArray = msgData["content"] as? [[String: Any]] {
                    for item in contentArray {
                        if let text = item["text"] as? String {
                            content += text
                        }
                    }
                } else if let contentStr = msgData["content"] as? String {
                    content = contentStr
                }

                if !content.isEmpty {
                    let messageId = msgData["id"] as? String ?? UUID().uuidString
                    let timestamp: Date
                    if let ts = msgData["timestamp"] as? Int64 {
                        timestamp = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
                    } else {
                        timestamp = Date()
                    }

                    let message = Message(
                        id: messageId,
                        conversationId: sessionKey,
                        role: role,
                        content: content,
                        timestamp: timestamp,
                        isStreaming: false,
                        toolCalls: nil,
                        location: nil,
                        deliveryStatus: .delivered
                    )
                    messages.append(message)
                }
            }

            // Sort by timestamp
            messages.sort { $0.timestamp < $1.timestamp }

            Task { @MainActor in
                // Update conversation with fetched messages
                if !messages.isEmpty {
                    var conversation = self.conversations[sessionKey] ?? Conversation(
                        id: sessionKey,
                        sessionKey: sessionKey,
                        agentId: self.currentAgent?.id ?? "main",
                        label: nil,
                        isSubAgent: sessionKey.contains(":subagent:"),
                        parentSessionKey: nil,
                        messages: [],
                        createdAt: Date(),
                        updatedAt: Date(),
                        status: .active
                    )
                    conversation.messages = messages
                    conversation.updatedAt = Date()
                    self.conversations[sessionKey] = conversation
                    self.saveConversations()
                }
                completion(messages)
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
        guard !isReceiving else {
            print("📥 Already receiving messages, skipping")
            return
        }
        isReceiving = true
        print("📥 Setting up message receive handler...")

        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                self.isReceiving = false

                switch result {
                case .success(let message):
                    print("📥 ✅ Received WebSocket message")
                    self.handleMessage(message)
                    self.receiveMessages()

                case .failure(let error):
                    print("📥 ❌ WebSocket receive error: \(error.localizedDescription)")
                    self.handleConnectionError(error)
                }
            }
        }
        print("📥 Message receive handler set up, waiting for messages...")
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        print("📦 handleMessage() called")
        let data: Data
        switch message {
        case .data(let d):
            print("📦 Message type: binary data (\(d.count) bytes)")
            data = d
        case .string(let s):
            print("📦 Message type: string (\(s.count) characters)")
            print("📦 Message content: \(s.prefix(200))\(s.count > 200 ? "..." : "")")
            data = s.data(using: .utf8) ?? Data()
        @unknown default:
            print("📦 ⚠️ Unknown message type")
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("📦 ❌ Failed to parse message as JSON")
            if let str = String(data: data, encoding: .utf8) {
                print("📦 Raw content: \(str)")
            }
            return
        }

        print("📦 ✅ Parsed JSON message")
        if let type = json["type"] as? String {
            print("📦 Message type: \(type)")
        }
        if let method = json["method"] as? String {
            print("📦 Message method: \(method)")
        }
        if let id = json["id"] as? String {
            print("📦 Message id: \(id)")
        }

        // Handle EVENTS - multiple formats
        // Format 1: type: "event", event: "chat"
        if let type = json["type"] as? String, type == "event",
           let event = json["event"] as? String {
            handleEvent(event: event, message: json)
            return
        }

        // Format 2: type: "chat" (event type directly in type field)
        if let type = json["type"] as? String,
           ["chat", "agent", "sessions.spawn", "sessions.announce", "subagent.spawn", "subagent.announce"].contains(type) {
            print("📨 [Event] type=\(type) (direct)")
            handleEvent(event: type, message: json)
            return
        }

        // Format 3: event field at top level without type
        if let event = json["event"] as? String {
            print("📨 [Event] event=\(event) (no type wrapper)")
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
        // Payload can be in different places depending on format
        let payload: [String: Any]
        if let p = message["payload"] as? [String: Any] {
            payload = p
        } else if let p = message["data"] as? [String: Any] {
            payload = p
        } else {
            // Payload might be the message itself (minus type/event fields)
            var p = message
            p.removeValue(forKey: "type")
            p.removeValue(forKey: "event")
            p.removeValue(forKey: "id")
            payload = p
        }

        if payload.isEmpty {
            print("⚠️ Event \(event) has empty/no payload")
            return
        }

        switch event {
        case "connect.challenge":
            if let nonce = payload["nonce"] as? String {
                print("Received connect.challenge with nonce")
                handleConnectChallenge(nonce: nonce)
            }

        case "chat":
            handleChatEvent(payload)

        case "agent":
            // Agent lifecycle events (optional logging)
            if let stream = payload["stream"] as? String {
                print("🤖 Agent stream: \(stream)")
            }

        case "sessions.spawn", "subagent.spawn":
            handleSubagentSpawn(payload)

        case "sessions.announce", "subagent.announce":
            handleSubagentAnnounce(payload)

        case "health", "tick":
            // Heartbeat events - connection is healthy
            Task { @MainActor in
                self.lastHeartbeat = Date()
            }

        default:
            print("📨 Unhandled event: \(event)")
        }
    }

    private func handleChatEvent(_ payload: [String: Any]) {
        guard let state = payload["state"] as? String,
              let sessionKey = payload["sessionKey"] as? String else {
            print("⚠️ [Chat] Invalid chat event - missing state or sessionKey")
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                print("   Payload: \(str.prefix(300))")
            }
            return
        }

        print("💬 [Chat] Event: state=\(state), sessionKey=\(sessionKey)")

        // Log delta content if present
        if state == "delta", let delta = payload["delta"] as? [String: Any] {
            let text = delta["text"] as? String ?? ""
            print("   Delta text: \(text.prefix(100))...")
        }

        switch state {
        case "start", "thinking":
            // Bot started processing - show typing indicator and mark message as received
            Task { @MainActor in
                self.isBotTyping[sessionKey] = true
                self.markLastUserMessageAsReceived(sessionKey: sessionKey)
            }

        case "delta":
            // Streaming update - append text to streaming message
            if let delta = payload["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                Task { @MainActor in
                    self.appendToStreamingMessage(text, sessionKey: sessionKey)
                }
            }

        case "final":
            // Response complete - extract content first (can be done off main thread)
            var fullText = ""
            if let message = payload["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for item in content {
                    if let text = item["text"] as? String {
                        fullText += text
                    }
                }
            }
            let runId = payload["runId"] as? String

            // All state mutations and reads must be on MainActor to avoid race conditions
            Task { @MainActor in
                self.isBotTyping[sessionKey] = false
                self.finalizeStreamingMessage(sessionKey: sessionKey)

                // Check if message content was in the payload
                if !fullText.isEmpty {
                    // Only add if we don't already have a streaming message with this content
                    if self.streamingMessageIds[sessionKey] == nil {
                        print("💬 Agent response (inline): \(fullText.prefix(100))...")
                        self.addAgentResponseToUI(fullText, sessionKey: sessionKey)
                    }
                } else if self.streamingMessageIds[sessionKey] == nil {
                    // No streaming message and no inline content - fetch via sessions.preview
                    print("💬 Final event received, fetching message via sessions.preview...")
                    if let runId = runId {
                        self.fetchLatestMessage(sessionKey: sessionKey, runId: runId)
                    }
                }
            }

        case "error":
            Task { @MainActor in
                self.isBotTyping[sessionKey] = false
                self.finalizeStreamingMessage(sessionKey: sessionKey)
            }
            if let error = payload["error"] as? [String: Any],
               let errorMsg = error["message"] as? String {
                print("❌ Chat error: \(errorMsg)")
            }

        default:
            print("📨 Unknown chat state: \(state)")
        }
    }

    private func appendToStreamingMessage(_ text: String, sessionKey: String) {
        if let existingId = streamingMessageIds[sessionKey] {
            // Append to existing streaming message
            if var conversation = conversations[sessionKey],
               let index = conversation.messages.firstIndex(where: { $0.id == existingId }) {
                conversation.messages[index].content += text
                conversation.updatedAt = Date()
                conversations[sessionKey] = conversation
            }
        } else {
            // Create new streaming message
            let messageId = UUID().uuidString
            streamingMessageIds[sessionKey] = messageId

            let streamingMessage = Message(
                id: messageId,
                conversationId: sessionKey,
                role: .assistant,
                content: text,
                timestamp: Date(),
                isStreaming: true,
                toolCalls: nil,
                location: nil,
                deliveryStatus: .delivered
            )
            addMessageToConversation(streamingMessage, sessionKey: sessionKey)
        }
    }

    private func finalizeStreamingMessage(sessionKey: String) {
        guard let messageId = streamingMessageIds[sessionKey] else { return }

        if var conversation = conversations[sessionKey],
           let index = conversation.messages.firstIndex(where: { $0.id == messageId }) {
            conversation.messages[index].isStreaming = false
            conversation.updatedAt = Date()
            conversations[sessionKey] = conversation
            saveConversations()
        }

        streamingMessageIds.removeValue(forKey: sessionKey)
    }

    private func addAgentResponseToUI(_ text: String, sessionKey: String) {
        let agentMessage = Message(
            id: UUID().uuidString,
            conversationId: sessionKey,
            role: .assistant,
            content: text,
            timestamp: Date(),
            isStreaming: false,
            toolCalls: nil,
            location: nil,
            deliveryStatus: .delivered
        )

        Task { @MainActor in
            // Mark the last user message as "received" since agent responded
            self.markLastUserMessageAsReceived(sessionKey: sessionKey)
            self.addMessageToConversation(agentMessage, sessionKey: sessionKey)

            // Send notification if app is in background
            if UIApplication.shared.applicationState != .active {
                let preview = text.prefix(100) + (text.count > 100 ? "..." : "")
                NotificationManager.shared.sendMessageNotification(
                    from: "BART",
                    content: String(preview),
                    sessionKey: sessionKey
                )
            }

            // Check for emergency keywords
            if text.lowercased().contains("breach") ||
               text.lowercased().contains("alert") ||
               text.lowercased().contains("emergency") ||
               text.lowercased().contains("critical") {
                NotificationManager.shared.sendEmergencyNotification(
                    title: "Security Alert",
                    body: String(text.prefix(200))
                )
            }
        }
    }

    private func fetchLatestMessage(sessionKey: String, runId: String) {
        // Use sessions.preview to get the latest messages
        let params: [String: Any] = [
            "keys": [sessionKey],
            "limit": 5
        ]

        sendRPC(method: "sessions.preview", params: params) { [weak self] response in
            guard let self = self else { return }

            print("📜 sessions.preview response:")
            if let data = try? JSONSerialization.data(withJSONObject: response, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }

            // Response format: { payload: { previews: { "ios-chat": { messages: [...] } } } }
            if let payload = response["payload"] as? [String: Any],
               let previews = payload["previews"] as? [String: Any],
               let sessionPreview = previews[sessionKey] as? [String: Any],
               let messages = sessionPreview["messages"] as? [[String: Any]] {
                self.processPreviewMessages(messages, sessionKey: sessionKey)
            } else if let result = response["result"] as? [String: Any],
                      let previews = result["previews"] as? [String: Any],
                      let sessionPreview = previews[sessionKey] as? [String: Any],
                      let messages = sessionPreview["messages"] as? [[String: Any]] {
                self.processPreviewMessages(messages, sessionKey: sessionKey)
            } else {
                print("⚠️ Could not parse sessions.preview response")
            }
        }
    }

    private func processPreviewMessages(_ messages: [[String: Any]], sessionKey: String) {
        for msg in messages {
            guard let role = msg["role"] as? String, role == "assistant" else { continue }

            // Extract text content
            var fullText = ""
            if let content = msg["content"] as? [[String: Any]] {
                for item in content {
                    if let text = item["text"] as? String {
                        fullText += text
                    }
                }
            } else if let content = msg["content"] as? String {
                fullText = content
            }

            if !fullText.isEmpty {
                // Check if we already have this message (avoid duplicates)
                let existingMessages = conversations[sessionKey]?.messages ?? []
                let isDuplicate = existingMessages.contains { $0.content == fullText }

                if !isDuplicate {
                    print("💬 Agent response (from preview): \(fullText.prefix(100))...")
                    addAgentResponseToUI(fullText, sessionKey: sessionKey)
                }
            }
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
                    location: nil,
                    deliveryStatus: .delivered
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

    // MARK: - Subagent Handling

    private func handleSubagentSpawn(_ payload: [String: Any]) {
        guard let sessionKey = payload["sessionKey"] as? String,
              let parentSessionKey = payload["parentSessionKey"] as? String,
              let label = payload["label"] as? String else {
            print("⚠️ Invalid subagent spawn payload")
            return
        }

        let id = payload["id"] as? String ?? UUID().uuidString
        let task = payload["task"] as? String ?? label

        let subAgent = SubAgentInfo(
            id: id,
            sessionKey: sessionKey,
            parentSessionKey: parentSessionKey,
            label: label,
            task: task,
            spawnedAt: Date(),
            status: .running,
            announceResult: nil
        )

        Task { @MainActor in
            // Remove any existing subagent with same sessionKey
            self.subAgents.removeAll { $0.sessionKey == sessionKey }
            self.subAgents.append(subAgent)
            print("🤖 Subagent spawned: \(label) (\(sessionKey))")

            // Send notification
            NotificationManager.shared.sendSubagentNotification(
                label: label,
                status: "Started",
                sessionKey: sessionKey
            )
        }
    }

    private func handleSubagentAnnounce(_ payload: [String: Any]) {
        guard let sessionKey = payload["sessionKey"] as? String else {
            return
        }

        let status = payload["status"] as? String ?? "completed"
        let result = payload["result"] as? String
        let notes = payload["notes"] as? String
        let runtime = payload["runtime"] as? TimeInterval
        let tokens = payload["tokens"] as? Int
        let cost = payload["cost"] as? Double

        let announceResult = AnnounceResult(
            status: status,
            result: result,
            notes: notes,
            runtime: runtime,
            tokens: tokens,
            cost: cost
        )

        Task { @MainActor in
            if let index = self.subAgents.firstIndex(where: { $0.sessionKey == sessionKey }) {
                let label = self.subAgents[index].label
                self.subAgents[index].status = status == "failed" ? .failed : .completed
                self.subAgents[index].announceResult = announceResult
                print("🤖 Subagent announced: \(sessionKey) - \(status)")

                // Send notification
                NotificationManager.shared.sendSubagentNotification(
                    label: label,
                    status: status.capitalized,
                    sessionKey: sessionKey
                )
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

        // Persist conversations to disk
        saveConversations()
    }

    // MARK: - Reconnection

    private func handleConnectionError(_ error: Error) {
        print("❌ Connection error: \(error.localizedDescription)")
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

extension GatewayConnection: URLSessionWebSocketDelegate, URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("✅ WebSocket connected")
        print("🔄 Starting message receive loop...")
        Task { @MainActor in
            self.reconnectAttempt = 0
            self.isReceiving = false
            self.receiveMessages()
            print("🔄 Receive loop started")

            // Generate our own nonce and send connect request immediately
            // Don't wait for connect.challenge - some gateways expect client to initiate
            // DISABLED: Wait for server challenge instead
            // if self.connectNonce == nil {
                // self.connectNonce = UUID().uuidString
                // print("📤 Sending connect request with self-generated nonce")
                // self.sendConnectRequest()
            // }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        print("⚠️ WebSocket disconnected: \(closeCode) reason: \(reasonString)")
        
        // Auto-recovery for nonce mismatch: clear stale credentials and re-pair
        if reasonString.contains("nonce mismatch") || reasonString.contains("device nonce") {
            print("🔄 Detected nonce mismatch - clearing stale credentials for fresh pairing")
            DeviceIdentityManager.shared.deleteKeyPair()
            UserDefaults.standard.removeObject(forKey: DeviceIdentity.storageKey)
            Task { @MainActor in
                self.connectionState = .disconnected
                self.isHandshakeComplete = false
                self.pairingState = .unpaired
            }
            return
        }

        // Handle "pairing required" or "device identity required" (code 1008) - this is a PENDING state, not a failure!
        // The gateway sends this when the device needs approval before connecting.
        // We should show the "Waiting for approval" screen, not an error.
        let needsPairing = reasonString == "pairing required" || reasonString == "device identity required" || reasonString.contains("identity required")
        if closeCode.rawValue == 1008 && needsPairing {
            print("📋 Pairing required (\(reasonString)) - reconnecting to request pairing")
            Task { @MainActor in
                self.connectionState = .disconnected
                self.isHandshakeComplete = false
                // Reconnect after a short delay - the gateway will allow us to request pairing
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self else { return }
                    print("🔄 Reconnecting to request pairing...")
                    self.connect()
                }
            }
            return
        }

        // Handle authentication failure via close code
        // Close codes: 1008 = Policy Violation (often used for auth failures)
        // Also check reason string for auth-related messages
        let isAuthFailure = reasonString.lowercased().contains("auth") ||
                           reasonString.lowercased().contains("unauthorized") ||
                           reasonString.lowercased().contains("401") ||
                           reasonString.lowercased().contains("expired")
        if isAuthFailure {
            print("🔐 WebSocket closed due to auth failure: \(reasonString)")
            Task { @MainActor in
                self.handleAuthFailure(message: reasonString)
            }
            return
        }

        Task { @MainActor in
            self.connectionState = .disconnected
            self.isHandshakeComplete = false
            self.scheduleReconnect()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            let nsError = error as NSError
            print("❌ URLSession task failed: \(error.localizedDescription)")
            print("   Error domain: \(nsError.domain), code: \(nsError.code)")
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                print("   Underlying: \(underlying.localizedDescription)")
            }

            Task { @MainActor in
                self.connectionState = .failed(error.localizedDescription)
            }
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
