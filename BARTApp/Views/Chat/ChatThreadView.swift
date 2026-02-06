import SwiftUI
import Combine
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct ChatThreadView: View {
    let initialSessionKey: String
    let initialTitle: String

    @EnvironmentObject var gateway: GatewayConnection
    @State private var inputText = ""
    @State private var showLocationSheet = false
    @FocusState private var isInputFocused: Bool
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isAtBottom = true
    @Namespace private var bottomID

    @State private var currentSessionKey: String = ""
    @State private var currentTitle: String = ""

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var attachments: [AttachmentItem] = []
    @State private var showFilePicker = false

    @State private var showConnectionToast = false

    @State private var sendAnimationTrigger = false
    @State private var sendRippleScale: CGFloat = 1.0
    @State private var sendRippleOpacity: Double = 0.0
    @State private var keyboardHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    @State private var showInputBar = false
    @State private var hideToolbar = false
    @State private var replyToMessageId: String?
    @State private var replyToContent: String?
    @State private var replyToRole: String?

    private let replyNotification = NotificationCenter.default.publisher(for: .replyToMessage)
    private let keyboardWillShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
    private let keyboardWillHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)

    private var conversation: Conversation? {
        gateway.conversations[currentSessionKey]
    }

    private var messages: [Message] {
        conversation?.messages ?? []
    }

    private var isBotTyping: Bool {
        gateway.isBotTyping[currentSessionKey] ?? false
    }

    private var showTypingIndicator: Bool {
        if gateway.isBotTyping[currentSessionKey] == true {
            return true
        }
        if let lastMessage = messages.last, lastMessage.role == .assistant && lastMessage.isStreaming {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            // Liquid glass background with subtle animation
            LiquidGlassStaticBackground(
                colors: [.purple.opacity(0.2), .blue.opacity(0.15), .indigo.opacity(0.2)]
            )
            
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Scroll offset tracker for header blur
                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: -geo.frame(in: .named("chatScroll")).minY
                                    )
                            }
                            .frame(height: 0)
                            
                            Spacer(minLength: 0)
                            
                            LazyVStack(spacing: 12) {
                                if messages.isEmpty && !showTypingIndicator {
                                    emptyStateView
                                        .frame(maxHeight: 400)
                                        
                                } else {
                                    if showConnectionToast {
                                        ConnectionStatusMessage()
                                            .id("connection-status")
                                    }

                                    ForEach(messages) { message in
                                        MessageBubble(message: message, onComponentAction: handleComponentAction, onDoubleTap: { enterFocusMode() })
                                            .id(message.id)
                                            .transition(.asymmetric(
                                                insertion: .scale(scale: 0.95).combined(with: .opacity),
                                                removal: .opacity
                                            ))
                                    }

                                    if showTypingIndicator {
                                        TypingIndicatorBubble()
                                            .id("typing-indicator")
                                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                                    }

                                    Color.clear
                                        .frame(height: 1)
                                        .id("bottom")
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(minHeight: geometry.size.height)
                    }
                    .coordinateSpace(name: "chatScroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        scrollOffset = value
                    }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { enterFocusMode() }
                .onTapGesture(count: 1) {
                    isInputFocused = false
                }
                .onAppear {
                    scrollProxy = proxy
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        scrollToBottom(animated: false)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if !messages.isEmpty {
                            scrollToBottom(animated: false)
                        }
                    }
                }
                .onReceive(keyboardWillShow) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        scrollToBottom(animated: true)
                    }
                }
                .onReceive(keyboardWillHide) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if !isInputFocused {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                showInputBar = false
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .enterChatFocusMode)) { _ in
                    enterFocusMode()
                }

                .onChange(of: messages.count) { oldCount, newCount in
                    if newCount > oldCount {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            scrollToBottom(animated: true)
                        }
                    } else if oldCount == 0 && newCount > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            scrollToBottom(animated: false)
                        }
                    }
                }
                .onChange(of: messages.last?.content) { _, _ in
                    scrollToBottom(animated: false)
                }
                .onChange(of: showTypingIndicator) { _, isTyping in
                    if isTyping {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            scrollToBottom(animated: true)
                        }
                    }
                }
                .onChange(of: isInputFocused) { _, focused in
                    if focused {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            scrollToBottom(animated: true)
                        }
                    } else {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            hideToolbar = false
                            showInputBar = false
                        }
                    }
                }
                .onChange(of: selectedPhotos) { _, newItems in
                    Task {
                        await loadPhotos(from: newItems)
                    }
                }
                .onChange(of: gateway.connectionState) { oldState, newState in
                    if case .connected = newState, !oldState.isConnected {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            showConnectionToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                showConnectionToast = false
                            }
                        }
                    }
                }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if showInputBar {
                    if replyToMessageId != nil {
                        replyPreviewBar
                    }
                    if !attachments.isEmpty {
                        attachmentPreviewBar
                    }
                    inputBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(.ultraThinMaterial)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showInputBar)
        }
        .onReceive(replyNotification) { notification in
            if let messageId = notification.userInfo?["messageId"] as? String,
               let content = notification.userInfo?["content"] as? String,
               let role = notification.userInfo?["role"] as? String {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    replyToMessageId = messageId
                    replyToContent = content
                    replyToRole = role
                }
                isInputFocused = true
            }
        }
        
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(hideToolbar ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ConnectionIndicator(state: gateway.connectionState)
            }

            ToolbarItem(placement: .principal) {
                SessionPickerButton(
                    currentSessionKey: currentSessionKey,
                    sessions: gateway.activeSessions,
                    onSelect: { session in
                        switchToSession(session)
                    }
                )
            }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    LiquidGlassButton(icon: "gearshape.fill")
                }
            }
        }
        .sheet(isPresented: $showLocationSheet) {
            LocationShareSheet(sessionKey: currentSessionKey)
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPickerView(attachments: $attachments)
        }
        .onAppear {
            if currentSessionKey.isEmpty {
                currentSessionKey = initialSessionKey
                currentTitle = initialTitle
            }
        }
    }

    private func switchToSession(_ session: SessionInfo) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            currentSessionKey = session.sessionKey
            currentTitle = session.friendlyName
        }

        if gateway.conversations[session.sessionKey] == nil {
            gateway.fetchSessionHistory(sessionKey: session.sessionKey) { messages in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    scrollToBottom(animated: false)
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                scrollToBottom(animated: false)
            }
        }
    }

    private var emptyStateView: some View {
        LiquidGlassCard(blur: .thinMaterial, cornerRadius: 24, padding: 32) {
            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)

                Text("Start a conversation")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Messages are private and encrypted")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var replyPreviewBar: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor)
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(replyToRole == "user" ? "You" : "BART")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)

                Text(replyToContent?.prefix(50) ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    replyToMessageId = nil
                    replyToContent = nil
                    replyToRole = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.thinMaterial))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var attachmentPreviewBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentPreviewCell(attachment: attachment) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            attachments.removeAll { $0.id == attachment.id }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.1))

            HStack(spacing: 4) {
                Menu {
                    Section {
                        Button {
                        } label: {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }

                        Button {
                            showFilePicker = true
                        } label: {
                            Label("Files", systemImage: "folder")
                        }
                    }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(.thinMaterial, in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .overlay {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 10,
                        matching: .any(of: [.images, .screenshots]),
                        photoLibrary: .shared()
                    ) {
                        Color.clear
                    }
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(true)
                }

                Button {
                    showLocationSheet = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(.thinMaterial, in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())

                HStack(spacing: 8) {
                    TextField("Message", text: $inputText, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($isInputFocused)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 10)
                        .padding(.leading, 4)
                        .contentShape(Rectangle())

                    Button(action: triggerSendAnimation) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.3))
                                .frame(width: 32, height: 32)
                                .scaleEffect(sendRippleScale)
                                .opacity(sendRippleOpacity)

                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(canSend ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color(red: 0.55, green: 0.55, blue: 0.57))
                                )
                                .scaleEffect(sendAnimationTrigger ? 0.85 : 1.0)
                        }
                    }
                    .disabled(!canSend)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !attachments.isEmpty
        return (hasText || hasAttachments) && gateway.connectionState.isConnected
    }

    private func triggerSendAnimation() {
        guard canSend else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            sendAnimationTrigger = true
        }

        sendRippleScale = 1.0
        sendRippleOpacity = 0.6
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            sendRippleScale = 2.5
            sendRippleOpacity = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                sendAnimationTrigger = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendMessage()
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentAttachments = attachments

        guard !text.isEmpty || !currentAttachments.isEmpty else { return }

        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.prepare()
        impact.impactOccurred()

        let replyContext = buildReplyContext()

        inputText = ""
        attachments = []
        selectedPhotos = []

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            replyToMessageId = nil
            replyToContent = nil
            replyToRole = nil
        }

        Task {
            var attachmentErrors: [String] = []
            for (index, attachment) in currentAttachments.enumerated() {
                do {
                    try await gateway.sendAttachment(attachment, sessionKey: currentSessionKey)
                    if index < currentAttachments.count - 1 {
                        try await Task.sleep(nanoseconds: 300_000_000)
                    }
                } catch {
                    attachmentErrors.append(attachment.filename)
                    print("⚠️ Failed to send attachment \(attachment.filename): \(error)")
                }
            }

            var messageToSend = text
            if let context = replyContext {
                messageToSend = context + "\n\n" + text
            }

            if !attachmentErrors.isEmpty {
                let failedNote = "[Note: \(attachmentErrors.count) attachment(s) failed to send]"
                messageToSend = messageToSend.isEmpty ? failedNote : messageToSend + "\n\n" + failedNote
            }

            if !messageToSend.isEmpty {
                try? await gateway.sendMessage(messageToSend, sessionKey: currentSessionKey)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            scrollToBottom(animated: true)
        }
    }

    private func buildReplyContext() -> String? {
        guard let content = replyToContent, let role = replyToRole else {
            return nil
        }

        let truncatedContent = String(content.prefix(200))
        let sender = role == "user" ? "my previous message" : "your message"

        return "[Replying to \(sender): \"\(truncatedContent)\(content.count > 200 ? "..." : "")\"]"
    }

    private func loadPhotos(from items: [PhotosPickerItem]) async {
        for item in items {
            if attachments.contains(where: { $0.pickerItemId == item.itemIdentifier }) {
                continue
            }

            if let data = try? await item.loadTransferable(type: Data.self) {
                if let uiImage = UIImage(data: data) {
                    let attachment = AttachmentItem(
                        type: .image,
                        data: data,
                        thumbnail: uiImage,
                        filename: "photo_\(Date().timeIntervalSince1970).jpg",
                        mimeType: "image/jpeg",
                        pickerItemId: item.itemIdentifier
                    )
                    await MainActor.run {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            attachments.append(attachment)
                        }
                    }
                }
            }
        }
    }

    private func enterFocusMode() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            showInputBar = true
        }
        isInputFocused = true
    }

    private func scrollToBottom(animated: Bool) {
        guard let proxy = scrollProxy else { return }

        if animated {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func handleComponentAction(_ componentId: String, _ action: String) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        let actionMessage = "[Component Response] \(componentId): \(action)"

        Task {
            try? await gateway.sendMessage(actionMessage, sessionKey: currentSessionKey)
        }
    }
}

// MARK: - Connection Status Message

struct ConnectionStatusMessage: View {
    var body: some View {
        Text("Connected")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }
}

// MARK: - Connection Indicator

struct ConnectionIndicator: View {
    let state: ConnectionState
    @State private var showStatusPopup = false
    @State private var isPulsing = false
    @EnvironmentObject var gateway: GatewayConnection

    private var color: Color {
        switch state {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .disconnected, .failed:
            return .gray
        }
    }

    private var isAnimating: Bool {
        switch state {
        case .connecting, .reconnecting:
            return true
        case .connected:
            return true
        default:
            return false
        }
    }

    var body: some View {
        Button {
            showStatusPopup = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)

                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .shadow(color: color.opacity(0.6), radius: isPulsing ? 4 : 2)
                    .scaleEffect(isPulsing ? 1.15 : 1.0)
            }
        }
        .buttonStyle(.plain)
        .animation(
            isAnimating ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
            value: isPulsing
        )
        .onAppear {
            isPulsing = isAnimating
        }
        .onChange(of: state) { _, _ in
            isPulsing = isAnimating
        }
        .popover(isPresented: $showStatusPopup) {
            ConnectionStatusPopup(state: state, latency: gateway.lastLatency, lastHeartbeat: gateway.lastHeartbeat)
                .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Connection Status Popup

struct ConnectionStatusPopup: View {
    let state: ConnectionState
    let latency: TimeInterval?
    let lastHeartbeat: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)

                Text(statusText)
                    .font(.headline)
            }

            if let latency = latency, state.isConnected {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Latency: \(Int(latency * 1000))ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let heartbeat = lastHeartbeat, state.isConnected {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.pink)
                    Text("Last heartbeat: \(heartbeatText(heartbeat))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if case .reconnecting(let attempt) = state {
                Text("Attempt \(attempt) of 5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case .failed(let message) = state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding()
        .frame(minWidth: 180)
        .background(.regularMaterial)
    }

    private func heartbeatText(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 {
            return "just now"
        } else if seconds < 60 {
            return "\(seconds)s ago"
        } else {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        }
    }

    private var statusColor: Color {
        switch state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected, .failed: return .gray
        }
    }

    private var statusText: String {
        switch state {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .reconnecting: return "Reconnecting..."
        case .disconnected: return "Disconnected"
        case .failed: return "Connection Failed"
        }
    }
}


// MARK: - Session Picker Button

struct SessionPickerButton: View {
    let currentSessionKey: String
    let sessions: [SessionInfo]
    let onSelect: (SessionInfo) -> Void

    @State private var showPicker = false

    private var currentSessionInfo: SessionInfo? {
        sessions.first { $0.sessionKey == currentSessionKey }
    }

    private var displayName: String {
        currentSessionInfo?.shortName ?? "Chat"
    }

    var body: some View {
        Button {
            showPicker = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Text(displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        }
        .sheet(isPresented: $showPicker) {
            SessionPickerSheet(sessions: sessions, currentSessionKey: currentSessionKey, onSelect: { session in
                showPicker = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onSelect(session)
                }
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }
}

// MARK: - Session Picker Sheet

struct SessionPickerSheet: View {
    let sessions: [SessionInfo]
    let currentSessionKey: String
    let onSelect: (SessionInfo) -> Void

    @Environment(\.dismiss) private var dismiss

    private var groupedSessions: [(session: SessionInfo, isNested: Bool)] {
        var result: [(session: SessionInfo, isNested: Bool)] = []

        let mainSessions = sessions.filter { !$0.isSubagent }
        let subagentSessions = sessions.filter { $0.isSubagent }

        for mainSession in mainSessions {
            result.append((mainSession, false))

            let matchingSubagents = subagentSessions.filter { subagent in
                let subagentParts = subagent.sessionKey.components(separatedBy: ":subagent:")
                if subagentParts.count > 1 {
                    let parentPrefix = subagentParts[0]
                    return mainSession.sessionKey.hasPrefix(parentPrefix) ||
                           parentPrefix.hasPrefix(mainSession.sessionKey.replacingOccurrences(of: "-chat", with: ""))
                }
                return false
            }

            for subagent in matchingSubagents {
                result.append((subagent, true))
            }
        }

        let addedSubagentKeys = Set(result.filter { $0.isNested }.map { $0.session.sessionKey })
        for subagent in subagentSessions where !addedSubagentKeys.contains(subagent.sessionKey) {
            result.append((subagent, true))
        }

        return result
    }

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Text("No active sessions")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groupedSessions, id: \.session.id) { item in
                        sessionRowView(for: item.session, isNested: item.isNested)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRowView(for session: SessionInfo, isNested: Bool = false) -> some View {
        Button {
            onSelect(session)
        } label: {
            HStack(spacing: 12) {
                if isNested {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 2, height: 24)
                            .padding(.leading, 8)
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: session.icon)
                    .font(.system(size: isNested ? 16 : 20))
                    .foregroundStyle(colorFromName(session.colorName))
                    .frame(width: isNested ? 26 : 32, height: isNested ? 26 : 32)
                    .background(
                        Circle()
                            .fill(colorFromName(session.colorName).opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.friendlyName)
                            .font(isNested ? .subheadline : .body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        if session.category != .agent && !isNested {
                            Text(session.category.displayName)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(colorFromName(session.colorName))
                                )
                        }
                    }

                    if let topic = session.topic, !topic.isEmpty {
                        Text(topic)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let model = session.model {
                        Text(model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if session.unreadCount > 0 {
                    Text("\(session.unreadCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.red))
                }

                if session.sessionKey == currentSessionKey {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
    }

    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "orange": return .orange
        case "cyan": return .cyan
        case "green": return .green
        case "indigo": return .indigo
        case "purple": return .purple
        case "red": return .red
        case "mint": return .mint
        case "teal": return .teal
        case "gray": return .gray
        case "yellow": return .yellow
        case "pink": return .pink
        default: return .blue
        }
    }
}

// MARK: - Typing Indicator Bubble

struct TypingIndicatorBubble: View {
    @State private var phase: Int = 0
    @State private var timerCancellable: AnyCancellable?

    private let timer = Timer.publish(every: 0.4, on: .main, in: .common)

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase == index ? 1.0 : 0.6)
                        .opacity(phase == index ? 1.0 : 0.4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: phase)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)

            Spacer(minLength: 60)
        }
        .onAppear {
            timerCancellable = timer.connect() as? AnyCancellable
        }
        .onDisappear {
            timerCancellable?.cancel()
            timerCancellable = nil
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - Attachment Types

struct AttachmentItem: Identifiable {
    let id = UUID()
    let type: AttachmentType
    let data: Data
    let thumbnail: UIImage?
    let filename: String
    let mimeType: String
    var pickerItemId: String?

    enum AttachmentType {
        case image
        case file
    }
}

// MARK: - Attachment Preview Cell

struct AttachmentPreviewCell: View {
    let attachment: AttachmentItem
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch attachment.type {
                case .image:
                    if let thumbnail = attachment.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                case .file:
                    VStack(spacing: 4) {
                        Image(systemName: fileIcon(for: attachment.filename))
                            .font(.system(size: 24))
                            .foregroundStyle(fileColor(for: attachment.filename))

                        Text(attachment.filename)
                            .font(.system(size: 8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(width: 64, height: 64)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, Color(.systemGray))
            }
            .offset(x: 6, y: -6)
        }
    }

    private func fileIcon(for filename: String) -> String {
        let ext = filename.components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "pdf": return "doc.text.fill"
        case "doc", "docx": return "doc.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.fill.on.rectangle.fill"
        case "txt", "rtf": return "doc.plaintext.fill"
        case "zip", "rar", "7z": return "doc.zipper"
        case "mp3", "wav", "m4a": return "music.note"
        case "mp4", "mov", "avi": return "film.fill"
        default: return "doc.fill"
        }
    }

    private func fileColor(for filename: String) -> Color {
        let ext = filename.components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx": return .green
        case "ppt", "pptx": return .orange
        case "zip", "rar", "7z": return .purple
        default: return .gray
        }
    }
}

// MARK: - Document Picker

struct DocumentPickerView: UIViewControllerRepresentable {
    @Binding var attachments: [AttachmentItem]
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [
            .pdf, .plainText, .rtf,
            .spreadsheet, .presentation,
            .image, .movie, .audio,
            .zip, .data
        ]

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView

        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                if let data = try? Data(contentsOf: url) {
                    let filename = url.lastPathComponent
                    let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

                    var thumbnail: UIImage?
                    if let image = UIImage(data: data) {
                        thumbnail = image
                    }

                    let attachment = AttachmentItem(
                        type: thumbnail != nil ? .image : .file,
                        data: data,
                        thumbnail: thumbnail,
                        filename: filename,
                        mimeType: mimeType
                    )

                    DispatchQueue.main.async {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            self.parent.attachments.append(attachment)
                        }
                    }
                }
            }
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        ChatThreadView(initialSessionKey: "main", initialTitle: "Main Chat")
            .environmentObject(GatewayConnection(gatewayHost: "localhost"))
    }
}

#Preview("Typing Indicator") {
    VStack {
        TypingIndicatorBubble()
    }
    .padding()
    .background(Color.black)
}
