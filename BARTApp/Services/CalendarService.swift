import Foundation

/// Direct HTTP service for calendar operations via calendar-proxy
/// Bypasses agent for fast, cheap calendar CRUD
class CalendarService {
    static let shared = CalendarService()
    
    // Calendar proxy on Tailscale - update if IP changes
    private let baseURL = "http://100.102.89.44:3001"
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5  // 5 second timeout
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()
    
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    
    private init() {}
    
    /// Fetch events from calendar-proxy
    func fetchEvents(
        calendar: String = "primary",
        account: String? = nil,
        from: Date,
        to: Date
    ) async throws -> CalendarProxyResponse {
        var components = URLComponents(string: "\(baseURL)/events")!
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        var queryItems = [
            URLQueryItem(name: "calendar", value: calendar),
            URLQueryItem(name: "from", value: formatter.string(from: from)),
            URLQueryItem(name: "to", value: formatter.string(from: to))
        ]
        
        if let account = account {
            queryItems.append(URLQueryItem(name: "account", value: account))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw CalendarServiceError.invalidURL
        }
        
        print("📅 CalendarService: fetching from \(url)")
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarServiceError.invalidResponse
        }
        
        print("📅 CalendarService: got response \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            throw CalendarServiceError.httpError(httpResponse.statusCode)
        }
        
        return try decoder.decode(CalendarProxyResponse.self, from: data)
    }
    
    /// Create event via calendar-proxy
    func createEvent(
        calendar: String = "primary",
        account: String? = nil,
        summary: String,
        from: Date,
        to: Date,
        description: String? = nil,
        location: String? = nil
    ) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/events") else {
            throw CalendarServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        var body: [String: Any] = [
            "calendar": calendar,
            "summary": summary,
            "from": formatter.string(from: from),
            "to": formatter.string(from: to)
        ]
        
        if let account = account { body["account"] = account }
        if let description = description { body["description"] = description }
        if let location = location { body["location"] = location }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            throw CalendarServiceError.createFailed
        }
        
        return data
    }
    
    /// Health check
    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Response Models

struct CalendarProxyResponse: Codable {
    let events: [CalendarProxyEvent]
}

struct CalendarProxyEvent: Codable {
    let id: String
    let summary: String?
    let start: CalendarDateTime?
    let end: CalendarDateTime?
    let location: String?
    let description: String?
    let htmlLink: String?
    let hangoutLink: String?
    let status: String?
    let organizer: CalendarPerson?
    let attendees: [CalendarPersonAttendee]?
    
    struct CalendarDateTime: Codable {
        let dateTime: String?
        let date: String?
        let timeZone: String?
    }
    
    struct CalendarPerson: Codable {
        let email: String?
        let displayName: String?
    }
    
    struct CalendarPersonAttendee: Codable {
        let email: String?
        let displayName: String?
        let responseStatus: String?
    }
}

enum CalendarServiceError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case createFailed
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid calendar service URL"
        case .invalidResponse: return "Invalid response from calendar service"
        case .httpError(let code): return "HTTP error: \(code)"
        case .createFailed: return "Failed to create event"
        case .decodingError: return "Failed to decode calendar data"
        }
    }
}
