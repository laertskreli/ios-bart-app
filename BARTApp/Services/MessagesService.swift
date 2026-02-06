import Foundation

/// Unified messaging service that aggregates messages from multiple sources
class MessagesService: ObservableObject {
    static let shared = MessagesService()
    
    @Published var messages: [UnifiedMessage] = []
    @Published var isLoading = false
    
    private init() {
        // Load mock data on init
        Task {
            try? await fetchImportantMessages()
        }
    }
    
    // MARK: - Models
    
    struct UnifiedMessage: Codable, Identifiable {
        let id: String
        let source: MessageSource
        let from: String
        let subject: String?
        let preview: String
        let fullContent: String
        let timestamp: Date
        var isRead: Bool
        let isImportant: Bool
        let threadId: String?
        
        var sourceIcon: String {
            switch source {
            case .email: return "envelope.fill"
            case .signal: return "bubble.left.and.bubble.right.fill"
            case .sms: return "message.fill"
            case .telegram: return "paperplane.fill"
            case .whatsapp: return "phone.bubble.fill"
            case .imessage: return "bubble.left.fill"
            }
        }
        
        var sourceColor: String {
            switch source {
            case .email: return "#3B82F6"      // Blue
            case .signal: return "#06B6D4"     // Cyan
            case .sms: return "#22C55E"        // Green
            case .telegram: return "#0088CC"   // Telegram blue
            case .whatsapp: return "#25D366"   // WhatsApp green
            case .imessage: return "#007AFF"   // Apple blue
            }
        }
        
        var relativeTime: String {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: timestamp, relativeTo: Date())
        }
    }
    
    enum MessageSource: String, Codable, CaseIterable {
        case email
        case signal
        case sms
        case telegram
        case whatsapp
        case imessage
        
        var displayName: String {
            switch self {
            case .email: return "Email"
            case .signal: return "Signal"
            case .sms: return "SMS"
            case .telegram: return "Telegram"
            case .whatsapp: return "WhatsApp"
            case .imessage: return "iMessage"
            }
        }
    }
    
    // MARK: - Mock Data
    
    private func generateMockMessages() -> [UnifiedMessage] {
        let now = Date()
        let calendar = Calendar.current
        
        return [
            // Important emails
            UnifiedMessage(
                id: "email-1",
                source: .email,
                from: "Sarah Chen",
                subject: "Q4 Board Presentation - Review Needed",
                preview: "Hi, the board presentation for Q4 is ready for your review. Please take a look before tomorrow's meeting...",
                fullContent: "Hi,\n\nThe board presentation for Q4 is ready for your review. Please take a look before tomorrow's meeting at 2pm.\n\nKey points covered:\n- Revenue growth: 23% YoY\n- New market expansion\n- Product roadmap updates\n\nLet me know if you have any questions.\n\nBest,\nSarah",
                timestamp: calendar.date(byAdding: .minute, value: -15, to: now)!,
                isRead: false,
                isImportant: true,
                threadId: "thread-1"
            ),
            UnifiedMessage(
                id: "email-2",
                source: .email,
                from: "Alex Rivera",
                subject: "Contract renewal - Action required",
                preview: "The vendor contract is expiring next week. We need your signature on the renewal docs...",
                fullContent: "Hi,\n\nThe vendor contract with CloudTech is expiring on Friday. We need your signature on the renewal documents by Wednesday.\n\nI've attached the updated terms - main changes are:\n- 10% price increase\n- Extended support hours\n- New SLA terms\n\nPlease review and let me know if you want to negotiate any terms.\n\nThanks,\nAlex",
                timestamp: calendar.date(byAdding: .hour, value: -2, to: now)!,
                isRead: false,
                isImportant: true,
                threadId: "thread-2"
            ),
            UnifiedMessage(
                id: "email-3",
                source: .email,
                from: "Newsletter",
                subject: "Your weekly digest",
                preview: "Here's what happened this week in tech...",
                fullContent: "Your Weekly Tech Digest\n\n• Apple announces new M4 chips\n• AI regulation updates\n• Startup funding trends\n\nRead more online.",
                timestamp: calendar.date(byAdding: .hour, value: -5, to: now)!,
                isRead: true,
                isImportant: false,
                threadId: "thread-3"
            ),
            
            // Signal messages
            UnifiedMessage(
                id: "signal-1",
                source: .signal,
                from: "Mike",
                subject: nil,
                preview: "Hey, are we still on for dinner tonight? I made reservations at that new place",
                fullContent: "Hey, are we still on for dinner tonight? I made reservations at that new place downtown. 7pm work?",
                timestamp: calendar.date(byAdding: .minute, value: -45, to: now)!,
                isRead: false,
                isImportant: true,
                threadId: "signal-thread-1"
            ),
            UnifiedMessage(
                id: "signal-2",
                source: .signal,
                from: "Dev Team",
                subject: nil,
                preview: "Deployment successful! All tests passing in prod 🎉",
                fullContent: "Deployment successful! All tests passing in prod 🎉\n\nv2.4.1 is now live.",
                timestamp: calendar.date(byAdding: .hour, value: -3, to: now)!,
                isRead: true,
                isImportant: false,
                threadId: "signal-thread-2"
            ),
            
            // Telegram
            UnifiedMessage(
                id: "telegram-1",
                source: .telegram,
                from: "Julia",
                subject: nil,
                preview: "Sent you the flight details. Check your email!",
                fullContent: "Sent you the flight details. Check your email!\n\nFlight is at 8am, don't forget your passport 😅",
                timestamp: calendar.date(byAdding: .hour, value: -1, to: now)!,
                isRead: false,
                isImportant: true,
                threadId: "tg-thread-1"
            ),
            
            // SMS
            UnifiedMessage(
                id: "sms-1",
                source: .sms,
                from: "Mom",
                subject: nil,
                preview: "Call me when you get a chance, nothing urgent just wanted to chat",
                fullContent: "Call me when you get a chance, nothing urgent just wanted to chat. Love you!",
                timestamp: calendar.date(byAdding: .hour, value: -4, to: now)!,
                isRead: false,
                isImportant: false,
                threadId: "sms-thread-1"
            )
        ]
    }
    
    // MARK: - API Methods
    
    @MainActor
    func fetchImportantMessages(limit: Int = 50) async throws {
        isLoading = true
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000)
        
        messages = generateMockMessages()
        isLoading = false
    }
    
    @MainActor
    func markAsRead(id: String) async throws {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].isRead = true
        }
    }
    
    func quickReply(id: String, text: String) async throws {
        // In production, this would send via the appropriate service
        print("Quick reply to \(id): \(text)")
        
        // Simulate send delay
        try await Task.sleep(nanoseconds: 300_000_000)
    }
    
    func generateQuickReplies(for message: UnifiedMessage) -> [String] {
        // AI-generated replies would come from backend
        // For now, return context-aware mock suggestions
        
        if message.preview.lowercased().contains("dinner") || message.preview.lowercased().contains("tonight") {
            return [
                "Sounds good, I'll be there!",
                "Can we make it 7:30 instead?",
                "Sorry, something came up. Reschedule?"
            ]
        } else if message.preview.lowercased().contains("review") || message.preview.lowercased().contains("look") {
            return [
                "I'll review it right away",
                "Let me check my calendar and get back to you",
                "Can you give me until end of day?"
            ]
        } else if message.preview.lowercased().contains("contract") || message.preview.lowercased().contains("signature") {
            return [
                "I'll sign it today",
                "Let's schedule a quick call to discuss",
                "Can you send me a summary of the changes?"
            ]
        } else {
            return [
                "Sounds good, I'll be there",
                "Let me check my calendar and get back to you",
                "Can we reschedule?"
            ]
        }
    }
}
