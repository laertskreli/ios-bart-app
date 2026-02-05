//
//  CalendarView.swift
//  BARTApp
//
//  Complete Calendar view with Month/Week/Day modes for OpenClaw iOS v4.
//  Dark theme with Color.black backgrounds, NO FAB - uses toolbar buttons.
//  NavigationStack with inline title and black toolbar.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Models

/// Calendar event source type
enum CalendarSource: String, CaseIterable, Hashable {
    case google = "google"
    case apple = "apple"
    case outlook = "outlook"
    case agent = "agent"
    
    var displayName: String {
        switch self {
        case .google: return "Google Calendar"
        case .apple: return "Apple Calendar"
        case .outlook: return "Outlook"
        case .agent: return "Agent Created"
        }
    }
    
    var color: Color {
        switch self {
        case .google: return .blue
        case .apple: return .red
        case .outlook: return .cyan
        case .agent: return .orange
        }
    }
    
    var icon: String {
        switch self {
        case .google: return "g.circle.fill"
        case .apple: return "apple.logo"
        case .outlook: return "envelope.fill"
        case .agent: return "brain"
        }
    }
}

/// Attendee response status
enum AttendeeStatus: String, CaseIterable {
    case accepted
    case declined
    case tentative
    case pending
    
    var icon: String {
        switch self {
        case .accepted: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        case .tentative: return "questionmark.circle.fill"
        case .pending: return "clock.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .accepted: return .green
        case .declined: return .red
        case .tentative: return .orange
        case .pending: return .secondary
        }
    }
}

/// Event attendee model
struct CalendarAttendee: Identifiable, Hashable {
    let id: String
    let name: String
    let email: String
    let status: AttendeeStatus
    let isOrganizer: Bool
    
    init(id: String = UUID().uuidString, name: String, email: String, status: AttendeeStatus = .pending, isOrganizer: Bool = false) {
        self.id = id
        self.name = name
        self.email = email
        self.status = status
        self.isOrganizer = isOrganizer
    }
}

/// Event reminder model
struct CalendarReminder: Identifiable, Hashable {
    let id: String
    let minutesBefore: Int
    
    init(id: String = UUID().uuidString, minutesBefore: Int) {
        self.id = id
        self.minutesBefore = minutesBefore
    }
    
    var displayText: String {
        if minutesBefore == 0 {
            return "At time of event"
        } else if minutesBefore < 60 {
            return "\(minutesBefore) minutes before"
        } else if minutesBefore < 1440 {
            let hours = minutesBefore / 60
            return "\(hours) hour\(hours == 1 ? "" : "s") before"
        } else {
            let days = minutesBefore / 1440
            return "\(days) day\(days == 1 ? "" : "s") before"
        }
    }
}

/// Calendar event model
struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startTime: Date
    let endTime: Date
    let isAllDay: Bool
    let source: CalendarSource
    let location: String?
    let videoCallURL: URL?
    let attendees: [CalendarAttendee]
    let notes: String?
    let agentNotes: String?
    let reminders: [CalendarReminder]
    let isAgentCreated: Bool
    let recurrenceRule: String?
    
    init(
        id: String = UUID().uuidString,
        title: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool = false,
        source: CalendarSource = .apple,
        location: String? = nil,
        videoCallURL: URL? = nil,
        attendees: [CalendarAttendee] = [],
        notes: String? = nil,
        agentNotes: String? = nil,
        reminders: [CalendarReminder] = [],
        isAgentCreated: Bool = false,
        recurrenceRule: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
        self.source = source
        self.location = location
        self.videoCallURL = videoCallURL
        self.attendees = attendees
        self.notes = notes
        self.agentNotes = agentNotes
        self.reminders = reminders
        self.isAgentCreated = isAgentCreated
        self.recurrenceRule = recurrenceRule
    }
    
    /// Duration in seconds
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    /// Formatted duration text
    var durationText: String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) hr"
            } else {
                return "\(hours) hr \(remainingMinutes) min"
            }
        }
    }
    
    /// Formatted time range text
    var timeRangeText: String {
        if isAllDay {
            return "All day"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ViewModel

@MainActor
class CalendarViewModel: ObservableObject {
    @Published var selectedDate: Date = Date()
    @Published var events: [CalendarEvent] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showingAgentResponse: Bool = false
    @Published var agentResponse: String?
    @Published var connectedAccounts: [String] = []  // Google accounts that are authed
    
    private let calendar = Calendar.current
    private(set) weak var gatewayConnection: GatewayConnection?
    private var cancellables = Set<AnyCancellable>()
    
    init(gatewayConnection: GatewayConnection? = nil) {
        self.gatewayConnection = gatewayConnection
        
        // Subscribe to incoming messages to catch calendar data responses
        if let gateway = gatewayConnection {
            // Listen for conversation updates that might contain calendar data
            gateway.$conversations
                .sink { [weak self] conversations in
                    self?.checkForCalendarData(in: conversations)
                }
                .store(in: &cancellables)
        }
        
        // Load placeholder data initially
        loadPlaceholderEvents()
    }
    
    /// Request calendar events from the agent via gog
    func fetchRealCalendarEvents() async {
        guard let gateway = gatewayConnection else {
            errorMessage = "Not connected to gateway"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let today = Date()
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        
        let fromDate = dateFormatter.string(from: today)
        let toDate = dateFormatter.string(from: nextWeek)
        
        // Send a request to the agent asking for calendar data
        let request = "[CALENDAR_REQUEST] Fetch my Google Calendar events from \(fromDate) to \(toDate). Return as JSON with format: [CALENDAR_DATA]{\"events\":[...]}"
        
        do {
            try await gateway.sendMessage(request)
            // The response will come through the conversations subscriber
            // Give it a moment then stop loading
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    /// Check incoming messages for calendar data
    private func checkForCalendarData(in conversations: [String: Conversation]) {
        print("📅 checkForCalendarData: \(conversations.count) conversations")
        for (_, conversation) in conversations {
            for message in conversation.messages.reversed() {
                // Look for calendar data marker
                if message.role == .assistant,
                   message.content.contains("[CALENDAR_DATA]") {
                    parseCalendarData(from: message.content)
                    return
                }
            }
        }
    }
    
    /// Parse calendar data from agent response
    private func parseCalendarData(from content: String) {
        print("📅 parseCalendarData called with content length: \(content.count)")
        // Extract JSON between [CALENDAR_DATA] and end of JSON block
        guard let startRange = content.range(of: "[CALENDAR_DATA]") else { return }
        let jsonStart = content[startRange.upperBound...]
        
        // Find the JSON object
        guard let jsonStartIndex = jsonStart.firstIndex(of: "{") else { return }
        let jsonString = String(jsonStart[jsonStartIndex...])
        
        // Find matching closing brace
        var braceCount = 0
        var endIndex = jsonString.startIndex
        for (index, char) in jsonString.enumerated() {
            if char == "{" { braceCount += 1 }
            if char == "}" { braceCount -= 1 }
            if braceCount == 0 {
                endIndex = jsonString.index(jsonString.startIndex, offsetBy: index + 1)
                break
            }
        }
        
        let extractedJSON = String(jsonString[..<endIndex])
        
        guard let jsonData = extractedJSON.data(using: .utf8) else { return }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let eventsArray = json["events"] as? [[String: Any]] {
                
                let parsedEvents = eventsArray.compactMap { parseEvent($0) }
                print("📅 Parsed \(parsedEvents.count) events from \(eventsArray.count) raw events")
                
                Task { @MainActor in
                    // Merge with existing events, replacing Google ones
                    self.events = self.events.filter { $0.source != .google } + parsedEvents
                    self.isLoading = false
                }
            }
        } catch {
            print("Failed to parse calendar data: \(error)")
        }
    }
    
    /// Parse a single event from JSON
    private func parseEvent(_ json: [String: Any]) -> CalendarEvent? {
        guard let title = json["title"] as? String ?? json["summary"] as? String,
              let startStr = json["start"] as? String,
              let endStr = json["end"] as? String else {
            return nil
        }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Try parsing with different formats
        let startDate = isoFormatter.date(from: startStr) ?? parseFlexibleDate(startStr)
        let endDate = isoFormatter.date(from: endStr) ?? parseFlexibleDate(endStr)
        
        guard let start = startDate, let end = endDate else {
            return nil
        }
        
        let isAllDay = (json["allDay"] as? Bool) ?? ((json["start"] as? String)?.count == 10)
        
        var attendees: [CalendarAttendee] = []
        if let attendeesArray = json["attendees"] as? [[String: Any]] {
            attendees = attendeesArray.compactMap { att in
                guard let email = att["email"] as? String else { return nil }
                let name = att["displayName"] as? String ?? email.components(separatedBy: "@").first ?? email
                let statusStr = att["responseStatus"] as? String ?? "needsAction"
                let status: AttendeeStatus = {
                    switch statusStr {
                    case "accepted": return .accepted
                    case "declined": return .declined
                    case "tentative": return .tentative
                    default: return .pending
                    }
                }()
                return CalendarAttendee(name: name, email: email, status: status)
            }
        }
        
        return CalendarEvent(
            id: json["id"] as? String ?? UUID().uuidString,
            title: title,
            startTime: start,
            endTime: end,
            isAllDay: isAllDay,
            source: .google,
            location: json["location"] as? String,
            videoCallURL: (json["hangoutLink"] as? String ?? json["meet"] as? String).flatMap { URL(string: $0) },
            attendees: attendees,
            notes: json["description"] as? String
        )
    }
    
    private func parseFlexibleDate(_ str: String) -> Date? {
        let formatters: [DateFormatter] = [
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
        ]
        for formatter in formatters {
            if let date = formatter.date(from: str) { return date }
        }
        return nil
    }
    
    func loadEvents() async {
        isLoading = true
        
        // Try to fetch real events if connected
        if gatewayConnection != nil {
            await fetchRealCalendarEvents()
        } else {
            // Fall back to placeholder
            try? await Task.sleep(nanoseconds: 500_000_000)
            loadPlaceholderEvents()
            isLoading = false
        }
    }
    
    func refreshEvents() async {
    }
    
    /// Connect to gateway for real calendar data
    func setGateway(_ gateway: GatewayConnection) {
        print("📅 setGateway called")
        self.gatewayConnection = gateway
        // Subscribe to conversations
        gateway.$conversations
            .sink { [weak self] conversations in
                self?.checkForCalendarData(in: conversations)
            }
            .store(in: &cancellables)

        Task { await loadEvents() }
    }
    private func loadPlaceholderEvents() {
        let now = Date()
        let calendar = Calendar.current
        
        // Create sample events for today and nearby dates
        var sampleEvents: [CalendarEvent] = []
        
        // Today's events
        if let today9am = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now),
           let today10am = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) {
            sampleEvents.append(CalendarEvent(
                title: "Daily Standup",
                startTime: today9am,
                endTime: today10am,
                source: .google,
                videoCallURL: URL(string: "https://meet.google.com/abc-defg-hij"),
                attendees: [
                    CalendarAttendee(name: "John Smith", email: "john@example.com", status: .accepted),
                    CalendarAttendee(name: "Jane Doe", email: "jane@example.com", status: .tentative)
                ],
                reminders: [CalendarReminder(minutesBefore: 10)]
            ))
        }
        
        if let today12pm = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now),
           let today1pm = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: now) {
            sampleEvents.append(CalendarEvent(
                title: "Lunch with Sarah",
                startTime: today12pm,
                endTime: today1pm,
                source: .apple,
                location: "The Coffee Shop, 123 Main St",
                notes: "Discuss Q1 marketing plans"
            ))
        }
        
        if let today3pm = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: now),
           let today4pm = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: now) {
            sampleEvents.append(CalendarEvent(
                title: "Project Review",
                startTime: today3pm,
                endTime: today4pm,
                source: .outlook,
                location: "Conference Room B",
                attendees: [
                    CalendarAttendee(name: "Mike Johnson", email: "mike@example.com", status: .accepted, isOrganizer: true),
                    CalendarAttendee(name: "Lisa Brown", email: "lisa@example.com", status: .accepted)
                ],
                reminders: [CalendarReminder(minutesBefore: 15), CalendarReminder(minutesBefore: 60)]
            ))
        }
        
        // Tomorrow's event
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           let tomorrow10am = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow),
           let tomorrow11am = calendar.date(bySettingHour: 11, minute: 30, second: 0, of: tomorrow) {
            sampleEvents.append(CalendarEvent(
                title: "Client Presentation",
                startTime: tomorrow10am,
                endTime: tomorrow11am,
                source: .agent,
                videoCallURL: URL(string: "https://zoom.us/j/123456789"),
                agentNotes: "Scheduled by agent based on email thread with client",
                reminders: [CalendarReminder(minutesBefore: 30)],
                isAgentCreated: true
            ))
        }
        
        // Event 3 days from now
        if let future = calendar.date(byAdding: .day, value: 3, to: now),
           let futureStart = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: future),
           let futureEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: future) {
            sampleEvents.append(CalendarEvent(
                title: "Team Building Day",
                startTime: futureStart,
                endTime: futureEnd,
                isAllDay: true,
                source: .google,
                location: "Adventure Park",
                notes: "Bring comfortable clothes and sneakers"
            ))
        }
        
        events = sampleEvents
    }
    
    func eventsForDate(_ date: Date) -> [CalendarEvent] {
        events.filter { event in
            calendar.isDate(event.startTime, inSameDayAs: date)
        }.sorted { $0.startTime < $1.startTime }
    }
    
    func eventsForMonth(containing date: Date) -> [Date: [CalendarEvent]] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else {
            return [:]
        }
        
        var result: [Date: [CalendarEvent]] = [:]
        
        for event in events {
            if event.startTime >= monthInterval.start && event.startTime < monthInterval.end {
                let dayStart = calendar.startOfDay(for: event.startTime)
                if result[dayStart] == nil {
                    result[dayStart] = []
                }
                result[dayStart]?.append(event)
            }
        }
        
        return result
    }
    
    func deleteEvent(_ event: CalendarEvent) {
        events.removeAll { $0.id == event.id }
    }
    
    func processAgentCommand(_ command: String) {
        isLoading = true
        // Simulate agent processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.isLoading = false
            self?.agentResponse = "I've processed your request: \"\(command)\""
            self?.showingAgentResponse = true
        }
    }
    
    func dismissAgentResponse() {
        showingAgentResponse = false
        agentResponse = nil
    }
    
    func undoLastAgentAction() {
        // Placeholder for undo functionality
        dismissAgentResponse()
    }
}

// MARK: - Calendar View

struct CalendarView: View {
    @EnvironmentObject var gateway: GatewayConnection
    @StateObject private var viewModel = CalendarViewModel()
    @State private var viewMode: CalendarViewMode = .month
    @State private var showingEventDetail: CalendarEvent?
    @State private var showingAddEvent: Bool = false

    enum CalendarViewMode: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Dark background - v4 style
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header with month/year and view mode picker
                    CalendarHeaderView(
                        selectedDate: $viewModel.selectedDate,
                        viewMode: $viewMode
                    )

                    // Calendar content based on view mode
                    switch viewMode {
                    case .month:
                        MonthCalendarView(
                            selectedDate: $viewModel.selectedDate,
                            events: viewModel.eventsForMonth(containing: viewModel.selectedDate),
                            onDateSelected: { date in
                                viewModel.selectedDate = date
                            }
                        )

                        Divider()
                            .background(Color.white.opacity(0.2))
                            .padding(.horizontal)

                        // Event list for selected date
                        EventListView(
                            date: viewModel.selectedDate,
                            events: viewModel.eventsForDate(viewModel.selectedDate),
                            onEventTap: { event in
                                showingEventDetail = event
                            }
                        )
                        .frame(maxHeight: .infinity)

                    case .week:
                        WeekCalendarView(
                            selectedDate: $viewModel.selectedDate,
                            events: viewModel.events,
                            onEventTap: { event in
                                showingEventDetail = event
                            }
                        )

                    case .day:
                        DayCalendarView(
                            date: viewModel.selectedDate,
                            events: viewModel.eventsForDate(viewModel.selectedDate),
                            onEventTap: { event in
                                showingEventDetail = event
                            }
                        )
                    }
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.selectedDate = Date()
                        }
                    } label: {
                        Text("Today")
                            .font(.subheadline.weight(.medium))
                    }
                    .disabled(Calendar.current.isDateInToday(viewModel.selectedDate))
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $showingEventDetail) { event in
                CalendarEventDetailSheet(event: event, viewModel: viewModel)
            }
            .sheet(isPresented: $showingAddEvent) {
                AddEventSheet(viewModel: viewModel, selectedDate: viewModel.selectedDate)
            }
            .task {
                viewModel.setGateway(gateway)
                await viewModel.loadEvents()
            }
            .refreshable {
                await viewModel.refreshEvents()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Calendar Header

struct CalendarHeaderView: View {
    @Binding var selectedDate: Date
    @Binding var viewMode: CalendarView.CalendarViewMode

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                // Month/Year navigation
                HStack(spacing: 8) {
                    Button {
                        navigateMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }

                    Text(monthYearString)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 180)

                    Button {
                        navigateMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }

                Spacer()
            }
            .padding(.horizontal)

            // View mode picker
            Picker("View Mode", selection: $viewMode) {
                ForEach(CalendarView.CalendarViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }
        .padding(.vertical, 6)
        .background(Color.black)
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }

    private func navigateMonth(by value: Int) {
        withAnimation(.spring(response: 0.3)) {
            if let newDate = calendar.date(byAdding: .month, value: value, to: selectedDate) {
                selectedDate = newDate
            }
        }
    }
}

// MARK: - Month Calendar View

struct MonthCalendarView: View {
    @Binding var selectedDate: Date
    let events: [Date: [CalendarEvent]]
    let onDateSelected: (Date) -> Void

    private let calendar = Calendar.current
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 4) {
            // Day of week headers
            HStack(spacing: 0) {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)

            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(daysInMonth, id: \.self) { date in
                    if let date = date {
                        MonthDayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            isCurrentMonth: calendar.isDate(date, equalTo: selectedDate, toGranularity: .month),
                            eventSources: eventSourcesForDate(date)
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.2)) {
                                onDateSelected(date)
                            }
                        }
                    } else {
                        Color.clear
                            .frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
    }

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }

        var days: [Date?] = []
        var currentDate = monthFirstWeek.start

        // Add days from previous month to fill the first week
        while currentDate < monthInterval.start {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        // Add all days in the current month
        while currentDate < monthInterval.end {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        // Add days from next month to complete the last week
        let remainingDays = (7 - (days.count % 7)) % 7
        for _ in 0..<remainingDays {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return days
    }

    private func eventSourcesForDate(_ date: Date) -> [CalendarSource] {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEvents = events[dayStart] else { return [] }
        return Array(Set(dayEvents.map { $0.source })).sorted { $0.rawValue < $1.rawValue }
    }
}

struct MonthDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let eventSources: [CalendarSource]

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Selection/Today background
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 34, height: 34)
                } else if isToday {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: 34, height: 34)
                }

                Text("\(calendar.component(.day, from: date))")
                    .font(.system(.body, design: .rounded).weight(isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(
                        isSelected ? .white :
                        isToday ? .accentColor :
                        isCurrentMonth ? .white : Color.gray.opacity(0.5)
                    )
            }
            .frame(height: 34)

            // Event indicators
            HStack(spacing: 2) {
                ForEach(eventSources.prefix(3), id: \.self) { source in
                    Circle()
                        .fill(source.color)
                        .frame(width: 5, height: 5)
                }

                if eventSources.count > 3 {
                    Text("+")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.gray)
                }
            }
            .frame(height: 6)
        }
        .frame(height: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Week Calendar View

struct WeekCalendarView: View {
    @Binding var selectedDate: Date
    let events: [CalendarEvent]
    let onEventTap: (CalendarEvent) -> Void

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 60
    private let timeColumnWidth: CGFloat = 50

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    // Day headers
                    WeekHeaderView(selectedDate: $selectedDate)

                    // Time grid
                    HStack(spacing: 0) {
                        // Time labels column
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                HStack {
                                    Spacer()
                                    Text(hourString(hour))
                                        .font(.caption2)
                                        .foregroundStyle(.gray)
                                    Spacer()
                                }
                                .frame(width: timeColumnWidth, height: hourHeight)
                            }
                        }

                        // Days columns with events
                        HStack(spacing: 1) {
                            ForEach(weekDays, id: \.self) { day in
                                WeekDayColumn(
                                    date: day,
                                    events: eventsForDay(day),
                                    hourHeight: hourHeight,
                                    onEventTap: onEventTap
                                )
                            }
                        }
                    }
                }
                .onAppear {
                    // Scroll to current time
                    let currentHour = calendar.component(.hour, from: Date())
                    if currentHour > 6 {
                        withAnimation {
                            proxy.scrollTo(currentHour - 1, anchor: .top)
                        }
                    }
                }
            }
        }
        .background(Color.black)
    }

    private var weekDays: [Date] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return []
        }

        var days: [Date] = []
        var currentDate = weekInterval.start

        while currentDate < weekInterval.end {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return days
    }

    private func eventsForDay(_ date: Date) -> [CalendarEvent] {
        events.filter { event in
            calendar.isDate(event.startTime, inSameDayAs: date)
        }.sorted { $0.startTime < $1.startTime }
    }

    private func hourString(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date).lowercased()
    }
}

struct WeekHeaderView: View {
    @Binding var selectedDate: Date

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            // Empty space for time column
            Color.clear
                .frame(width: 50)

            // Day headers
            HStack(spacing: 1) {
                ForEach(weekDays, id: \.self) { day in
                    VStack(spacing: 4) {
                        Text(dayOfWeek(day))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.gray)

                        Text("\(calendar.component(.day, from: day))")
                            .font(.title3.weight(calendar.isDateInToday(day) ? .bold : .regular))
                            .foregroundStyle(calendar.isDateInToday(day) ? .white : .white.opacity(0.8))
                            .frame(width: 32, height: 32)
                            .background {
                                if calendar.isDateInToday(day) {
                                    Circle()
                                        .fill(Color.accentColor)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(calendar.isDate(day, inSameDayAs: selectedDate) ? Color.accentColor.opacity(0.15) : Color.clear)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.2)) {
                            selectedDate = day
                        }
                    }
                }
            }
        }
        .background(Color(white: 0.1))
    }

    private var weekDays: [Date] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return []
        }

        var days: [Date] = []
        var currentDate = weekInterval.start

        while currentDate < weekInterval.end {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return days
    }

    private func dayOfWeek(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
}

struct WeekDayColumn: View {
    let date: Date
    let events: [CalendarEvent]
    let hourHeight: CGFloat
    let onEventTap: (CalendarEvent) -> Void

    private let calendar = Calendar.current

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Hour grid lines
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .frame(height: hourHeight, alignment: .top)
                        .id(hour)
                }
            }

            // Current time indicator
            if calendar.isDateInToday(date) {
                CurrentTimeIndicator(hourHeight: hourHeight)
            }

            // Events
            ForEach(events) { event in
                WeekEventCard(
                    event: event,
                    hourHeight: hourHeight,
                    onTap: { onEventTap(event) }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct WeekEventCard: View {
    let event: CalendarEvent
    let hourHeight: CGFloat
    let onTap: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        let startMinutes = CGFloat(calendar.component(.hour, from: event.startTime) * 60 +
                                   calendar.component(.minute, from: event.startTime))
        let durationMinutes = CGFloat(event.duration / 60)

        let topOffset = (startMinutes / 60) * hourHeight
        let height = max((durationMinutes / 60) * hourHeight, 24)

        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(height > 40 ? 2 : 1)

                if height > 50 {
                    Text(event.timeRangeText)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height, alignment: .top)
            .background(event.source.color.opacity(0.3))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(event.source.color)
                    .frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .offset(y: topOffset)
        .padding(.horizontal, 2)
    }
}

struct CurrentTimeIndicator: View {
    let hourHeight: CGFloat

    private let calendar = Calendar.current

    var body: some View {
        let now = Date()
        let minutes = CGFloat(calendar.component(.hour, from: now) * 60 +
                             calendar.component(.minute, from: now))
        let offset = (minutes / 60) * hourHeight

        HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            Rectangle()
                .fill(Color.red)
                .frame(height: 1)
        }
        .offset(y: offset - 4)
    }
}

// MARK: - Day Calendar View

// MARK: - Event Layout Helper

struct EventLayoutInfo: Identifiable {
    var id: String { event.id }
    let event: CalendarEvent
    let column: Int
    let totalColumns: Int
}

func calculateEventLayout(events: [CalendarEvent]) -> [EventLayoutInfo] {
    guard !events.isEmpty else { return [] }
    
    let sorted = events.sorted { e1, e2 in
        if e1.startTime == e2.startTime {
            return e1.duration > e2.duration
        }
        return e1.startTime < e2.startTime
    }
    
    var columnEndTimes: [Date] = []
    var assignments: [(event: CalendarEvent, column: Int)] = []
    
    for event in sorted {
        var assignedColumn = -1
        for (idx, endTime) in columnEndTimes.enumerated() {
            if event.startTime >= endTime {
                assignedColumn = idx
                columnEndTimes[idx] = event.endTime
                break
            }
        }
        
        if assignedColumn == -1 {
            assignedColumn = columnEndTimes.count
            columnEndTimes.append(event.endTime)
        }
        
        assignments.append((event, assignedColumn))
    }
    
    var result: [EventLayoutInfo] = []
    
    for (event, column) in assignments {
        var maxCols = column + 1
        for (otherEvent, otherCol) in assignments {
            if event.startTime < otherEvent.endTime && otherEvent.startTime < event.endTime {
                maxCols = max(maxCols, otherCol + 1)
            }
        }
        result.append(EventLayoutInfo(event: event, column: column, totalColumns: maxCols))
    }
    
    return result
}

// MARK: - Day Calendar View

struct DayCalendarView: View {
    let date: Date
    let events: [CalendarEvent]
    let onEventTap: (CalendarEvent) -> Void

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 60
    private let leftMargin: CGFloat = 66
    private let rightPadding: CGFloat = 16

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    let availableWidth = geometry.size.width - leftMargin - rightPadding
                    let layoutInfos = calculateEventLayout(events: events)
                    
                    ZStack(alignment: .topLeading) {
                        // Time grid
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(hourString(hour))
                                        .font(.caption)
                                        .foregroundStyle(.gray)
                                        .frame(width: 50, alignment: .trailing)

                                    VStack {
                                        Divider()
                                            .background(Color.white.opacity(0.2))
                                        Spacer()
                                    }
                                }
                                .frame(height: hourHeight)
                                .id(hour)
                            }
                        }

                        // Current time indicator
                        if calendar.isDateInToday(date) {
                            let now = Date()
                            let minutes = CGFloat(calendar.component(.hour, from: now) * 60 +
                                                 calendar.component(.minute, from: now))
                            let offset = (minutes / 60) * hourHeight

                            HStack(spacing: 0) {
                                Text(currentTimeString)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.red)
                                    .frame(width: 50, alignment: .trailing)
                                    .padding(.trailing, 4)

                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)

                                Rectangle()
                                    .fill(Color.red)
                                    .frame(height: 1)
                            }
                            .offset(y: offset - 4)
                        }

                        // Events with overlap handling
                        ForEach(layoutInfos) { info in
                            DayEventCard(
                                event: info.event,
                                column: info.column,
                                totalColumns: info.totalColumns,
                                availableWidth: availableWidth,
                                leftMargin: leftMargin,
                                hourHeight: hourHeight,
                                onTap: { onEventTap(info.event) }
                            )
                        }
                    }
                    .padding()
                }
                .frame(height: CGFloat(24) * hourHeight + 40)
                .onAppear {
                    let targetHour: Int
                    if let firstEvent = events.first {
                        targetHour = max(0, calendar.component(.hour, from: firstEvent.startTime) - 1)
                    } else {
                        targetHour = max(0, calendar.component(.hour, from: Date()) - 1)
                    }

                    withAnimation {
                        proxy.scrollTo(targetHour, anchor: .top)
                    }
                }
            }
        }
        .background(Color.black)
    }

    private func hourString(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }

    private var currentTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: Date())
    }
}

struct DayEventCard: View {
    let event: CalendarEvent
    let column: Int
    let totalColumns: Int
    let availableWidth: CGFloat
    let leftMargin: CGFloat
    let hourHeight: CGFloat
    let onTap: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        let startMinutes = CGFloat(calendar.component(.hour, from: event.startTime) * 60 +
                                   calendar.component(.minute, from: event.startTime))
        let durationMinutes = CGFloat(event.duration / 60)

        let topOffset = (startMinutes / 60) * hourHeight
        let height = max((durationMinutes / 60) * hourHeight, 44)
        
        let columnWidth = availableWidth / CGFloat(totalColumns)
        let horizontalOffset = leftMargin + CGFloat(column) * columnWidth

        Button(action: onTap) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(event.source.color)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if height > 50 {
                        Text(event.timeRangeText)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }

                    if let location = event.location, height > 70 {
                        Label(location, systemImage: "location")
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }

                    if event.videoCallURL != nil, height > 70 {
                        Label("Video call", systemImage: "video")
                            .font(.caption)
                            .foregroundStyle(event.source.color)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: columnWidth - 4, height: height, alignment: .topLeading)
            .background(event.source.color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(event.source.color.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .offset(x: horizontalOffset, y: topOffset)
    }
}
struct EventListView: View {
    let date: Date
    let events: [CalendarEvent]
    let onEventTap: (CalendarEvent) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date header
            HStack {
                Text(dateHeader)
                    .font(.headline)
                    .foregroundStyle(.white)

                if calendar.isDateInToday(date) {
                    Text("Today")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }

                Spacer()

                Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if events.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 40))
                        .foregroundStyle(.gray.opacity(0.5))

                    Text("No events scheduled")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(events) { event in
                            EventCard(event: event)
                                .onTapGesture {
                                    onEventTap(event)
                                }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color.black)
    }

    private var dateHeader: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }
}

struct EventCard: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 12) {
            // Source color indicator
            Circle()
                .fill(event.source.color)
                .frame(width: 10, height: 10)

            // Time
            VStack(alignment: .leading, spacing: 2) {
                Text(timeString)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text(event.durationText)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            .frame(width: 70, alignment: .leading)

            // Event details
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let location = event.location {
                        Label(location, systemImage: "location")
                            .lineLimit(1)
                    }

                    if event.videoCallURL != nil {
                        Label("Video", systemImage: "video")
                    }

                    if !event.attendees.isEmpty {
                        Label("\(event.attendees.count)", systemImage: "person.2")
                    }

                    if event.isAgentCreated {
                        Label("Agent", systemImage: "brain")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.gray)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.gray.opacity(0.5))
        }
        .padding(12)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var timeString: String {
        if event.isAllDay {
            return "All day"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: event.startTime)
    }
}

// MARK: - Event Detail Sheet

// MARK: - Event Detail Sheet

struct CalendarEventDetailSheet: View {
    let event: CalendarEvent
    @ObservedObject var viewModel: CalendarViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    Divider().background(Color.white.opacity(0.2))
                    dateTimeSection
                    locationSection
                    videoCallSection
                    attendeesSection
                    agentNotesSection
                    notesSection
                    remindersSection
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    toolbarMenu
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Extracted Sections

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(event.source.color)
                    .frame(width: 12, height: 12)
                Text(event.source.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.gray)
                if event.isAgentCreated {
                    Label("Agent created", systemImage: "brain")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            Text(event.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var dateTimeSection: some View {
        CalendarDetailRow(
            icon: "calendar",
            iconColor: .accentColor,
            title: formattedDate,
            subtitle: event.isAllDay ? "All day" : event.timeRangeText
        )
        if !event.isAllDay {
            CalendarDetailRow(
                icon: "clock",
                iconColor: .gray,
                title: event.durationText,
                subtitle: "Duration"
            )
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        if let location = event.location {
            CalendarDetailRow(
                icon: "location",
                iconColor: .red,
                title: location,
                subtitle: "Location"
            )
        }
    }

    @ViewBuilder
    private var videoCallSection: some View {
        if let videoURL = event.videoCallURL {
            Button {
                // Open video call
            } label: {
                CalendarDetailRow(
                    icon: "video",
                    iconColor: .green,
                    title: "Join video call",
                    subtitle: videoURL.host ?? "Video meeting"
                )
            }
        }
    }

    @ViewBuilder
    private var attendeesSection: some View {
        if !event.attendees.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Attendees", systemImage: "person.2")
                    .font(.headline)
                    .foregroundStyle(.white)
                ForEach(event.attendees) { attendee in
                    attendeeRow(attendee)
                }
            }
        }
    }

    @ViewBuilder
    private func attendeeRow(_ attendee: CalendarAttendee) -> some View {
        HStack {
            Circle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(String(attendee.name.prefix(1)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(attendee.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text(attendee.email)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            Spacer()
            Image(systemName: attendee.status.icon)
                .foregroundStyle(attendee.status.color)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var agentNotesSection: some View {
        if let agentNotes = event.agentNotes {
            VStack(alignment: .leading, spacing: 8) {
                Label("Agent Notes", systemImage: "brain")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(agentNotes)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if let notes = event.notes {
            VStack(alignment: .leading, spacing: 8) {
                Label("Notes", systemImage: "note.text")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        if !event.reminders.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Reminders", systemImage: "bell")
                    .font(.headline)
                    .foregroundStyle(.white)
                ForEach(event.reminders) { reminder in
                    Text(reminder.displayText)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
            }
        }
    }

    private var toolbarMenu: some View {
        Menu {
            Button {
                // Edit event
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                // Duplicate event
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Divider()
            Button(role: .destructive) {
                viewModel.deleteEvent(event)
                dismiss()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: event.startTime)
    }
}
struct CalendarDetailRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            Spacer()
        }
    }
}

// MARK: - Add Event Sheet

struct AddEventSheet: View {
    @ObservedObject var viewModel: CalendarViewModel
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var isAllDay: Bool = false
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var selectedSource: CalendarSource = .apple
    
    init(viewModel: CalendarViewModel, selectedDate: Date) {
        self.viewModel = viewModel
        self.selectedDate = selectedDate
        
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let nextHour = calendar.date(bySettingHour: hour + 1, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let nextHourPlus1 = calendar.date(byAdding: .hour, value: 1, to: nextHour) ?? nextHour
        
        _startTime = State(initialValue: nextHour)
        _endTime = State(initialValue: nextHourPlus1)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event title", text: $title)
                        .foregroundStyle(.white)
                }
                .listRowBackground(Color(white: 0.12))
                
                Section {
                    Toggle("All-day", isOn: $isAllDay)
                    
                    if !isAllDay {
                        DatePicker("Starts", selection: $startTime)
                        DatePicker("Ends", selection: $endTime)
                    } else {
                        DatePicker("Date", selection: $startTime, displayedComponents: .date)
                    }
                }
                .listRowBackground(Color(white: 0.12))
                
                Section {
                    TextField("Location", text: $location)
                        .foregroundStyle(.white)
                }
                .listRowBackground(Color(white: 0.12))
                
                Section {
                    Picker("Calendar", selection: $selectedSource) {
                        ForEach([CalendarSource.apple, .google, .outlook], id: \.self) { source in
                            HStack {
                                Circle()
                                    .fill(source.color)
                                    .frame(width: 10, height: 10)
                                Text(source.displayName)
                            }
                            .tag(source)
                        }
                    }
                }
                .listRowBackground(Color(white: 0.12))
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .foregroundStyle(.white)
                }
                .listRowBackground(Color(white: 0.12))
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addEvent()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func addEvent() {
        let event = CalendarEvent(
            title: title,
            startTime: startTime,
            endTime: isAllDay ? Calendar.current.date(byAdding: .day, value: 1, to: startTime) ?? startTime : endTime,
            isAllDay: isAllDay,
            source: selectedSource,
            location: location.isEmpty ? nil : location,
            notes: notes.isEmpty ? nil : notes
        )
        viewModel.events.append(event)
    }
}

// MARK: - Preview

#Preview {
    CalendarView()
}
