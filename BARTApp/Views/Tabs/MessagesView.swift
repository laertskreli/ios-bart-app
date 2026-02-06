import SwiftUI

struct MessagesView: View {
    @StateObject private var service = MessagesService.shared
    @State private var selectedMessage: MessagesService.UnifiedMessage?
    @State private var showingReplySheet = false
    
    var importantMessages: [MessagesService.UnifiedMessage] {
        service.messages.filter { $0.isImportant }
    }
    
    var otherMessages: [MessagesService.UnifiedMessage] {
        service.messages.filter { !$0.isImportant }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                
                if service.isLoading {
                    ProgressView()
                        .tint(.white)
                } else if service.messages.isEmpty {
                    emptyState
                } else {
                    messagesList
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            try? await service.fetchImportantMessages()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $showingReplySheet) {
                if let message = selectedMessage {
                    MessageReplySheet(message: message) {
                        showingReplySheet = false
                        selectedMessage = nil
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No messages")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Your important messages will appear here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }
    
    private var messagesList: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                if !importantMessages.isEmpty {
                    Section {
                        ForEach(importantMessages) { message in
                            MessageCard(message: message) {
                                selectedMessage = message
                                Task {
                                    try? await service.markAsRead(id: message.id)
                                }
                                showingReplySheet = true
                            }
                        }
                    } header: {
                        SectionHeader(title: "Important", icon: "star.fill", color: .yellow)
                    }
                }
                
                if !otherMessages.isEmpty {
                    Section {
                        ForEach(otherMessages) { message in
                            MessageCard(message: message) {
                                selectedMessage = message
                                Task {
                                    try? await service.markAsRead(id: message.id)
                                }
                                showingReplySheet = true
                            }
                        }
                    } header: {
                        SectionHeader(title: "Recent", icon: "clock.fill", color: .gray)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .refreshable {
            try? await service.fetchImportantMessages()
        }
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial)
    }
}

struct MessageCard: View {
    let message: MessagesService.UnifiedMessage
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    private var sourceColor: Color {
        Color(hex: message.sourceColor) ?? .blue
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(sourceColor.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: message.sourceIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(sourceColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        HStack(spacing: 6) {
                            if !message.isRead {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 8, height: 8)
                            }
                            Text(message.from)
                                .font(.system(size: 15, weight: message.isRead ? .regular : .semibold))
                                .foregroundStyle(.white)
                        }
                        
                        Spacer()
                        
                        Text(message.relativeTime)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    if let subject = message.subject {
                        Text(subject)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    
                    Text(message.preview)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 4) {
                        Text(message.source.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(sourceColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(sourceColor.opacity(0.15))
                            )
                    }
                    .padding(.top, 4)
                }
            }
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.85))
                    
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(message.isRead ? 0.1 : 0.2),
                                    .white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .scaleEffect(isPressed ? 0.98 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
    }
}

struct MessageReplySheet: View {
    let message: MessagesService.UnifiedMessage
    let onDismiss: () -> Void
    
    @State private var replyText = ""
    @State private var isSending = false
    @State private var selectedSuggestion: String?
    @FocusState private var isReplyFocused: Bool
    
    private let service = MessagesService.shared
    
    private var sourceColor: Color {
        Color(hex: message.sourceColor) ?? .blue
    }
    
    private var quickReplies: [String] {
        service.generateQuickReplies(for: message)
    }
    
    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(sourceColor.opacity(0.2))
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: message.sourceIcon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(sourceColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.from)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            HStack(spacing: 6) {
                                Text(message.source.displayName)
                                    .font(.system(size: 13))
                                    .foregroundStyle(sourceColor)
                                
                                Text("•")
                                    .foregroundStyle(.secondary)
                                
                                Text(message.relativeTime)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                    
                    if let subject = message.subject {
                        Text(subject)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    
                    Text(message.fullContent)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(4)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                        )
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.yellow)
                            Text("Quick Replies")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        
                        FlowLayout(spacing: 8) {
                            ForEach(quickReplies, id: \.self) { reply in
                                QuickReplyPill(
                                    text: reply,
                                    isSelected: selectedSuggestion == reply
                                ) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedSuggestion = reply
                                        replyText = reply
                                    }
                                }
                            }
                        }
                    }
                    
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            TextField("Type a reply...", text: $replyText, axis: .vertical)
                                .lineLimit(1...5)
                                .focused($isReplyFocused)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                        )
                                )
                                .foregroundStyle(.white)
                        }
                        
                        Button {
                            sendReply()
                        } label: {
                            HStack(spacing: 8) {
                                if isSending {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                Text(isSending ? "Sending..." : "Send Reply")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? Color.secondary.opacity(0.3)
                                        : Color.accentColor
                                    )
                            )
                        }
                        .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private func sendReply() {
        guard !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSending = true
        Task {
            do {
                try await service.quickReply(id: message.id, text: replyText)
                await MainActor.run {
                    isSending = false
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    isSending = false
                }
            }
        }
    }
}

struct QuickReplyPill: View {
    let text: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.accentColor : Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    isSelected ? Color.accentColor : Color.white.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.bounds
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(
                x: bounds.minX + result.positions[index].x,
                y: bounds.minY + result.positions[index].y
            ), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var bounds: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
                bounds.width = max(bounds.width, x)
            }
            
            bounds.height = y + lineHeight
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    MessagesView()
}
