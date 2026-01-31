import SwiftUI

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                messageContent

                if message.isStreaming {
                    streamingIndicator
                }

                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    toolCallsView(toolCalls)
                }

                if let location = message.location {
                    locationPreview(location)
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        Text(message.content)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bubbleBackground)
            .foregroundStyle(message.role == .user ? .white : .primary)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
    }

    private var streamingIndicator: some View {
        HStack(spacing: 6) {
            StreamingIndicator()
            Text("Thinking...")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
    }

    private func toolCallsView(_ toolCalls: [ToolCall]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(toolCalls) { tool in
                ToolCallBadge(toolCall: tool)
            }
        }
    }

    private func locationPreview(_ location: LocationShare) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .foregroundStyle(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Location shared")
                    .font(.caption.bold())

                Text("\(location.latitude, specifier: "%.4f"), \(location.longitude, specifier: "%.4f")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(GlassBackground(cornerRadius: 12))
    }
}

struct ToolCallBadge: View {
    let toolCall: ToolCall

    var body: some View {
        HStack(spacing: 6) {
            if toolCall.status == .running {
                ProgressView()
                    .scaleEffect(0.6)
            } else if toolCall.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Text(formatToolName(toolCall.name))
                .font(.caption)
                .foregroundStyle(.secondary)

            if toolCall.name == "sessions_spawn", let label = toolCall.spawnedLabel {
                Text("→ \(label)")
                    .font(.caption2)
                    .foregroundStyle(.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    private func formatToolName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageBubble(message: Message(
            id: "1",
            conversationId: "main",
            role: .user,
            content: "Hello BART!",
            timestamp: Date(),
            isStreaming: false,
            toolCalls: nil,
            location: nil
        ))

        MessageBubble(message: Message(
            id: "2",
            conversationId: "main",
            role: .assistant,
            content: "Hello! How can I help you today?",
            timestamp: Date(),
            isStreaming: false,
            toolCalls: [
                ToolCall(id: "t1", name: "web_search", status: .completed, result: nil, spawnedSessionKey: nil, spawnedLabel: nil)
            ],
            location: nil
        ))

        MessageBubble(message: Message(
            id: "3",
            conversationId: "main",
            role: .assistant,
            content: "Let me think about that...",
            timestamp: Date(),
            isStreaming: true,
            toolCalls: nil,
            location: nil
        ))
    }
    .padding()
    .background(Color(.systemBackground))
}
