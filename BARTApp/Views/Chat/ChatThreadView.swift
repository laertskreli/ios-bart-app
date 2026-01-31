import SwiftUI

struct ChatThreadView: View {
    let sessionKey: String
    let title: String

    @EnvironmentObject var gateway: GatewayConnection
    @State private var inputText = ""
    @State private var showLocationSheet = false
    @FocusState private var isInputFocused: Bool

    private var conversation: Conversation? {
        gateway.conversations[sessionKey]
    }

    private var messages: [Message] {
        conversation?.messages ?? []
    }

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                ConnectionStatusBanner(state: gateway.connectionState)
                    .animation(.spring(response: 0.3), value: gateway.connectionState)

                messagesScrollView

                Divider()
                    .opacity(0.3)

                inputBar
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLocationSheet) {
            LocationShareSheet(sessionKey: sessionKey)
        }
        .onTapGesture {
            isInputFocused = false
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.systemBackground).opacity(0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if messages.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }
                    }
                }
                .padding()
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.last?.content) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 100)

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Start a conversation with BART")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Your messages are private and encrypted")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            Button {
                showLocationSheet = true
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.ultraThinMaterial))
            }

            HStack(spacing: 8) {
                TextField("Message BART...", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .textFieldStyle(.plain)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
                        )
                }
                .disabled(!canSend)
                .animation(.spring(response: 0.2), value: canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        gateway.connectionState.isConnected
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""

        Task {
            try? await gateway.sendMessage(text, sessionKey: sessionKey)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastId = messages.last?.id {
            withAnimation(.spring(response: 0.3)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChatThreadView(sessionKey: "main", title: "BART")
            .environmentObject(GatewayConnection(gatewayHost: "localhost"))
    }
}
