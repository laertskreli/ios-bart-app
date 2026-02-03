import SwiftUI
import UIKit

// MARK: - Notification Names

extension Notification.Name {
    static let replyToMessage = Notification.Name("replyToMessage")
}

// MARK: - Markdown Text Renderer

struct MarkdownText: View {
    let text: String
    let isUserMessage: Bool

    init(_ text: String, isUserMessage: Bool = false) {
        self.text = text
        self.isUserMessage = isUserMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(parseInlineMarkdown(text))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .codeBlock(let code, let language):
            codeBlockView(code: code, language: language)

        case .bulletList(let items):
            bulletListView(items: items)

        case .numberedList(let items):
            numberedListView(items: items)

        case .blockquote(let text):
            blockquoteView(text: text)

        case .header(let text, let level):
            headerView(text: text, level: level)
        }
    }

    private func codeBlockView(code: String, language: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lang = language, !lang.isEmpty {
                Text(lang)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, language != nil ? 8 : 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemGray6).opacity(isUserMessage ? 0.3 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func bulletListView(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(parseInlineMarkdown(item))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func numberedListView(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                    Text(parseInlineMarkdown(item))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func blockquoteView(text: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 4)

            Text(parseInlineMarkdown(text))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
                .italic()
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private func headerView(text: String, level: Int) -> some View {
        Text(parseInlineMarkdown(text))
            .font(level == 1 ? .title2 : level == 2 ? .title3 : .headline)
            .fontWeight(.semibold)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            return try AttributedString(markdown: text, options: options)
        } catch {
            return AttributedString(text)
        }
    }

    private func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code block
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3))
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(codeLines.joined(separator: "\n"), language.isEmpty ? nil : language))
                i += 1
                continue
            }

            // Header
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let headerText = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                if level <= 4 && !headerText.isEmpty {
                    blocks.append(.header(headerText, level))
                    i += 1
                    continue
                }
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoteLines.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: " ")))
                continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                var items: [String] = []
                while i < lines.count {
                    let listLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if listLine.hasPrefix("- ") || listLine.hasPrefix("* ") || listLine.hasPrefix("• ") {
                        items.append(String(listLine.dropFirst(2)))
                        i += 1
                    } else { break }
                }
                blocks.append(.bulletList(items))
                continue
            }

            // Numbered list
            if let _ = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                var items: [String] = []
                while i < lines.count {
                    let listLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if let range = listLine.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        items.append(String(listLine[range.upperBound...]))
                        i += 1
                    } else { break }
                }
                blocks.append(.numberedList(items))
                continue
            }

            // Paragraph
            if !trimmed.isEmpty {
                var paragraphLines: [String] = []
                while i < lines.count {
                    let pTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if pTrimmed.isEmpty || pTrimmed.hasPrefix("```") || pTrimmed.hasPrefix("#") ||
                       pTrimmed.hasPrefix(">") || pTrimmed.hasPrefix("- ") || pTrimmed.hasPrefix("* ") ||
                       pTrimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                        break
                    }
                    paragraphLines.append(lines[i])
                    i += 1
                }
                if !paragraphLines.isEmpty {
                    blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
                }
                continue
            }
            i += 1
        }

        if blocks.isEmpty && !text.isEmpty {
            blocks.append(.paragraph(text))
        }
        return blocks
    }
}

private enum MarkdownBlock {
    case paragraph(String)
    case codeBlock(String, String?)
    case bulletList([String])
    case numberedList([String])
    case blockquote(String)
    case header(String, Int)
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    var onComponentAction: ((String, String) -> Void)?

    @State private var showCopied = false
    @State private var appeared = false

    /// Parsed content blocks - computed once and cached by SwiftUI
    private var parsedBlocks: [ParsedContentBlock] {
        ContentParser.parse(message.content)
    }

    /// Check if message contains rich components that should be full-width
    private var hasRichComponents: Bool {
        parsedBlocks.contains { block in
            switch block {
            case .resolved, .calendarSchedule, .calendar, .tasks, .chart, .form, .emailDraft, .code, .file, .contact, .location, .linkPreview:
                return true
            default:
                return false
            }
        }
    }

    /// Check if message is newly sent (for animation)
    private var isNewlySent: Bool {
        message.role == .user && message.deliveryStatus == .sending
    }

    var body: some View {
        Group {
            if message.role == .assistant && hasRichComponents {
                // Full-width layout for rich components
                fullWidthContent
            } else {
                // Standard bubble layout
                standardBubbleContent
            }
        }
        // iMessage-style fly-up animation for user messages
        .offset(y: appeared ? 0 : (message.role == .user ? 20 : 0))
        .opacity(appeared ? 1 : (message.role == .user ? 0 : 1))
        .scaleEffect(appeared ? 1 : (message.role == .user ? 0.95 : 1))
        .onAppear {
            if message.role == .user && !appeared {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
    }

    private var standardBubbleContent: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
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

    private var fullWidthContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Render rich components full-width
            richComponentsView

            // Show streaming indicator if needed
            if message.isStreaming {
                streamingIndicator
            }

            // Tool calls
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                toolCallsView(toolCalls)
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        HStack(alignment: .bottom, spacing: 4) {
            contentBlocksView

            // Delivery status inside bubble for user messages
            if message.role == .user {
                inBubbleDeliveryIndicator
                    .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bubbleBackground)
        .foregroundStyle(message.role == .user ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            Button {
                copyMessage()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button {
                triggerReply()
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }

            if message.role == .assistant {
                Button {
                    // Could add share functionality
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        } preview: {
            // Preview shown during long press
            Text(message.content.prefix(200) + (message.content.count > 200 ? "..." : ""))
                .padding()
                .frame(maxWidth: 300)
        }
        .onTapGesture { } // Empty tap to not interfere
        .overlay(alignment: .topTrailing) {
            if showCopied {
                Text("Copied")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.systemGray3)))
                    .transition(.opacity.combined(with: .scale))
                    .offset(y: -24)
            }
        }
    }

    /// Delivery indicator below the bubble - text-based status
    @ViewBuilder
    private var inBubbleDeliveryIndicator: some View {
        switch message.deliveryStatus {
        case .pending, .sending:
            // Sending state - animated text
            HStack(spacing: 2) {
                Text("sending")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                SendingDots()
            }
        case .delivered:
            // Delivered - show "sent" text
            Text("sent")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        case .received:
            // Agent acknowledged - show "received" text
            Text("received")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        case .failed:
            // Failed - red text with icon
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 9))
                Text("failed")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.red)
        }
    }
}

// MARK: - Sending Dots Animation (for "sending..." text)

struct SendingDots: View {
    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(String(repeating: ".", count: dotCount))
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: 12, alignment: .leading)
            .onReceive(timer) { _ in
                dotCount = (dotCount % 3) + 1
            }
    }
}

// MARK: - MessageBubble Helper Methods

extension MessageBubble {
    private func triggerReply() {
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Post notification to trigger reply in ChatThreadView
        NotificationCenter.default.post(
            name: .replyToMessage,
            object: nil,
            userInfo: ["messageId": message.id, "content": message.content, "role": message.role.rawValue]
        )
    }

    private func copyMessage() {
        UIPasteboard.general.string = message.content

        // Haptic feedback
        let impact = UINotificationFeedbackGenerator()
        impact.notificationOccurred(.success)

        // Show copied indicator
        withAnimation(.easeOut(duration: 0.2)) {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                showCopied = false
            }
        }
    }

    @ViewBuilder
    private var richComponentsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parsedBlocks) { block in
                switch block {
                case .text(let text):
                    // Render text in a subtle style for context
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                case .resolved(let component):
                    ResolvedComponentView(component: component, onAction: handleComponentAction)

                case .calendarSchedule(let component):
                    InteractiveCalendarScheduleView(component: component, onAction: handleComponentAction)

                case .calendar(let component):
                    InteractiveCalendarView(component: component, onAction: handleComponentAction)

                case .tasks(let component):
                    InteractiveTasksView(component: component, onAction: handleComponentAction)

                case .chart(let component):
                    InteractiveChartView(component: component, onAction: handleComponentAction)

                case .form(let component):
                    InteractiveFormView(component: component, onAction: handleComponentAction)

                case .emailDraft(let component):
                    InteractiveEmailDraftView(component: component, onAction: handleComponentAction)

                case .code(let component):
                    InteractiveCodeView(component: component, onAction: handleComponentAction)

                case .linkPreview(let component):
                    InteractiveLinkPreviewView(component: component, onAction: handleComponentAction)

                case .file(let component):
                    InteractiveFileView(component: component, onAction: handleComponentAction)

                case .contact(let component):
                    InteractiveContactView(component: component, onAction: handleComponentAction)

                case .location(let component):
                    InteractiveLocationView(component: component, onAction: handleComponentAction)

                case .button, .buttonGroup, .options:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private var contentBlocksView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Display image attachment if present
            if message.hasAttachment, message.isImageAttachment,
               let data = message.attachmentData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 240, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Display file attachment info if not an image
            if message.hasAttachment, !message.isImageAttachment,
               let filename = message.attachmentFilename {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.title3)
                        .foregroundStyle(message.role == .user ? .white.opacity(0.8) : .secondary)
                    Text(filename)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }

            ForEach(parsedBlocks) { block in
                switch block {
                case .text(let text):
                    // Skip placeholder text for attachments
                    if !message.hasAttachment || (!text.hasPrefix("[Image:") && !text.hasPrefix("[File:")) {
                        MarkdownText(text, isUserMessage: message.role == .user)
                    }

                case .button(let component):
                    InteractiveButtonView(component: component, onAction: handleComponentAction)

                case .buttonGroup(let component):
                    InteractiveButtonGroupView(component: component, onAction: handleComponentAction)

                case .calendar(let component):
                    InteractiveCalendarView(component: component, onAction: handleComponentAction)

                case .calendarSchedule(let component):
                    InteractiveCalendarScheduleView(component: component, onAction: handleComponentAction)

                case .emailDraft(let component):
                    InteractiveEmailDraftView(component: component, onAction: handleComponentAction)

                case .options(let component):
                    InteractiveOptionsView(component: component, onAction: handleComponentAction)

                case .tasks(let component):
                    InteractiveTasksView(component: component, onAction: handleComponentAction)

                case .form(let component):
                    InteractiveFormView(component: component, onAction: handleComponentAction)

                case .code(let component):
                    InteractiveCodeView(component: component, onAction: handleComponentAction)

                case .linkPreview(let component):
                    InteractiveLinkPreviewView(component: component, onAction: handleComponentAction)

                case .file(let component):
                    InteractiveFileView(component: component, onAction: handleComponentAction)

                case .contact(let component):
                    InteractiveContactView(component: component, onAction: handleComponentAction)

                case .chart(let component):
                    InteractiveChartView(component: component, onAction: handleComponentAction)

                case .location(let component):
                    InteractiveLocationView(component: component, onAction: handleComponentAction)

                case .resolved(let component):
                    ResolvedComponentView(component: component, onAction: handleComponentAction)
                }
            }
        }
    }

    private func handleComponentAction(_ componentId: String, _ action: String) {
        onComponentAction?(componentId, action)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
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
                .foregroundStyle(Color.accentColor)

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
                    .foregroundStyle(Color.accentColor)
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
            location: nil,
            deliveryStatus: .delivered
        ))

        MessageBubble(message: Message(
            id: "2",
            conversationId: "main",
            role: .user,
            content: "Sending...",
            timestamp: Date(),
            isStreaming: false,
            toolCalls: nil,
            location: nil,
            deliveryStatus: .sending
        ))

        MessageBubble(message: Message(
            id: "3",
            conversationId: "main",
            role: .user,
            content: "This message failed",
            timestamp: Date(),
            isStreaming: false,
            toolCalls: nil,
            location: nil,
            deliveryStatus: .failed
        ))

        MessageBubble(message: Message(
            id: "4",
            conversationId: "main",
            role: .assistant,
            content: "Hello! How can I help you today?",
            timestamp: Date(),
            isStreaming: false,
            toolCalls: [
                ToolCall(id: "t1", name: "web_search", status: .completed, result: nil, spawnedSessionKey: nil, spawnedLabel: nil)
            ],
            location: nil,
            deliveryStatus: .delivered
        ))

        MessageBubble(message: Message(
            id: "5",
            conversationId: "main",
            role: .assistant,
            content: "Let me think about that...",
            timestamp: Date(),
            isStreaming: true,
            toolCalls: nil,
            location: nil,
            deliveryStatus: .delivered
        ))
    }
    .padding()
    .background(Color(.systemBackground))
}
