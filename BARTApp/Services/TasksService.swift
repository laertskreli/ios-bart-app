import Foundation

/// Direct HTTP service for tasks operations via gateway
/// Pattern matches CalendarService - direct HTTP, no agent for simple CRUD
class TasksService {
    static let shared = TasksService()
    
    // Gateway endpoint on Tailscale
    private let baseURL = "http://100.102.89.44:18789"
    
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    
    private init() {}
    
    /// Fetch tasks from gateway
    func fetchTasks() async throws -> [TaskItem] {
        guard let url = URL(string: "\(baseURL)/api/tasks/list") else {
            throw TasksServiceError.invalidURL
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TasksServiceError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw TasksServiceError.httpError(httpResponse.statusCode)
            }
            
            let tasksResponse = try decoder.decode(TasksResponse.self, from: data)
            return tasksResponse.tasks
        } catch is URLError {
            // Gateway not available - return mock data for development
            return Self.mockTasks()
        } catch is DecodingError {
            // Fallback to mock if response doesn't match expected format
            return Self.mockTasks()
        }
    }
    
    /// Complete a task
    func completeTask(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/tasks/complete") else {
            throw TasksServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["id": id]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TasksServiceError.completeFailed
        }
    }
    
    /// Health check
    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    /// Mock data for development/offline
    static func mockTasks() -> [TaskItem] {
        let now = Date()
        let calendar = Calendar.current
        
        return [
            TaskItem(
                id: "1",
                title: "Review Q1 roadmap",
                description: "Go through the product roadmap and update priorities",
                dueDate: calendar.date(byAdding: .hour, value: 2, to: now),
                source: .appleReminders,
                priority: 1,
                completed: false,
                completedAt: nil
            ),
            TaskItem(
                id: "2",
                title: "Daily backup verification",
                description: "Automated cron job to check backup integrity",
                dueDate: calendar.date(byAdding: .hour, value: 4, to: now),
                source: .cronJob,
                priority: 2,
                completed: false,
                completedAt: nil
            ),
            TaskItem(
                id: "3",
                title: "Prepare investor deck",
                description: "Final review of slides for next week",
                dueDate: calendar.date(byAdding: .day, value: 1, to: now),
                source: .todoist,
                priority: 1,
                completed: false,
                completedAt: nil
            ),
            TaskItem(
                id: "4",
                title: "Team standup notes",
                description: nil,
                dueDate: now,
                source: .appleReminders,
                priority: 3,
                completed: false,
                completedAt: nil
            ),
            TaskItem(
                id: "5",
                title: "SSL certificate renewal",
                description: "Auto-renew via certbot cron",
                dueDate: calendar.date(byAdding: .day, value: 7, to: now),
                source: .cronJob,
                priority: 2,
                completed: false,
                completedAt: nil
            ),
            TaskItem(
                id: "6",
                title: "Review PR #234",
                description: "Code review for feature branch",
                dueDate: calendar.date(byAdding: .day, value: 2, to: now),
                source: .todoist,
                priority: 2,
                completed: false,
                completedAt: nil
            )
        ]
    }
}

// MARK: - Models

struct TasksResponse: Codable {
    let tasks: [TaskItem]
}

struct TaskItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let dueDate: Date?
    let source: TaskSource
    let priority: Int?
    let completed: Bool
    let completedAt: Date?
    
    /// Priority display color
    var priorityColor: String {
        switch priority {
        case 1: return "red"      // High/urgent
        case 2: return "orange"   // Medium
        case 3: return "blue"     // Low
        default: return "gray"    // No priority
        }
    }
    
    /// Relative due date text
    var relativeDueDate: String? {
        guard let due = dueDate else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(due) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Today, \(formatter.string(from: due))"
        } else if calendar.isDateInTomorrow(due) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Tomorrow, \(formatter.string(from: due))"
        } else if due < now {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Overdue \(formatter.localizedString(for: due, relativeTo: now))"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: due)
        }
    }
    
    /// Check if task is overdue
    var isOverdue: Bool {
        guard let due = dueDate else { return false }
        return due < Date() && !completed
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: TaskItem, rhs: TaskItem) -> Bool {
        lhs.id == rhs.id
    }
}

enum TaskSource: String, Codable, CaseIterable {
    case appleReminders = "appleReminders"
    case cronJob = "cronJob"
    case todoist = "todoist"
    
    var displayName: String {
        switch self {
        case .appleReminders: return "Apple Reminders"
        case .cronJob: return "Cron Job"
        case .todoist: return "Todoist"
        }
    }
    
    var icon: String {
        switch self {
        case .appleReminders: return "calendar"
        case .cronJob: return "clock.badge"
        case .todoist: return "checkmark.square"
        }
    }
    
    var emoji: String {
        switch self {
        case .appleReminders: return "📅"
        case .cronJob: return "⏰"
        case .todoist: return "✅"
        }
    }
    
    var color: String {
        switch self {
        case .appleReminders: return "red"
        case .cronJob: return "purple"
        case .todoist: return "orange"
        }
    }
}

enum TasksServiceError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case completeFailed
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid tasks service URL"
        case .invalidResponse: return "Invalid response from tasks service"
        case .httpError(let code): return "HTTP error: \(code)"
        case .completeFailed: return "Failed to complete task"
        case .decodingError: return "Failed to decode task data"
        }
    }
}
