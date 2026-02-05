import Foundation

/// Flexible content resolver that intelligently maps JSON to visual components
/// based on field detection rather than strict schema matching
struct ContentResolver {

    /// Resolve JSON to a component type based on detected fields
    static func resolve(_ json: [String: Any]) -> ResolvedComponent? {
        // Check explicit type first
        let explicitType = json["type"] as? String

        // Detect component based on fields present
        let detected = detectComponentType(json, explicitType: explicitType)

        guard let componentType = detected else {
            print("[Resolver] Could not detect component type for: \(json.keys)")
            return nil
        }

        print("[Resolver] Detected: \(componentType)")
        return buildComponent(componentType, from: json)
    }

    // MARK: - Detection Logic

    private static func detectComponentType(_ json: [String: Any], explicitType: String?) -> ComponentType? {
        // If explicit type matches known types, use it
        if let type = explicitType {
            if let known = ComponentType(rawValue: type) {
                return known
            }
            // Handle aliases
            switch type.lowercased() {
            case "schedule", "agenda", "meetings": return .calendarSchedule
            case "todo", "todos", "checklist", "tasks": return .tasks
            case "snippet", "codeblock", "code": return .code
            case "link", "url", "preview", "linkpreview": return .linkPreview
            case "person", "contact", "user": return .contact
            case "map", "place", "location", "address": return .location
            case "graph", "chart", "stats": return .chart
            case "attachment", "document", "file": return .file
            case "form", "input", "survey": return .form
            case "buttons", "actions", "buttongroup": return .buttonGroup
            case "options", "choices", "select", "picker": return .options
            case "email", "emaildraft", "mail": return .emailDraft
            case "event", "calendar", "meeting": return .calendar
            default: break
            }
        }

        // Heuristic detection based on fields

        // Calendar Schedule: has events array with time-like fields
        if let events = json["events"] as? [[String: Any]], !events.isEmpty {
            if events.first?["time"] != nil || events.first?["start"] != nil || events.first?["startTime"] != nil {
                return .calendarSchedule
            }
        }

        // Tasks: has items/tasks array with done/completed/checked fields
        if let items = (json["items"] ?? json["tasks"] ?? json["todos"]) as? [[String: Any]], !items.isEmpty {
            let first = items.first ?? [:]
            if first["done"] != nil || first["completed"] != nil || first["checked"] != nil ||
               first["status"] != nil || first["priority"] != nil || first["due"] != nil {
                return .tasks
            }
        }

        // Code: has code field or language field with content
        if json["code"] != nil || (json["language"] != nil && (json["content"] != nil || json["snippet"] != nil || json["source"] != nil)) {
            return .code
        }

        // Contact: has name + (email or phone)
        if json["name"] != nil && (json["email"] != nil || json["phone"] != nil || json["tel"] != nil) {
            return .contact
        }

        // Location: has coordinates
        if (json["lat"] != nil && json["lng"] != nil) ||
           (json["latitude"] != nil && json["longitude"] != nil) ||
           (json["coordinates"] != nil) {
            return .location
        }

        // Link Preview: has url + (title or description)
        if json["url"] != nil && (json["title"] != nil || json["description"] != nil || json["preview"] != nil) {
            return .linkPreview
        }

        // Chart: has data array with value/count fields
        if let data = json["data"] as? [[String: Any]], !data.isEmpty {
            let first = data.first ?? [:]
            if first["value"] != nil || first["count"] != nil || first["amount"] != nil {
                return .chart
            }
        }

        // File: has filename/name + (size or url or extension hint)
        if let name = (json["name"] ?? json["filename"] ?? json["file"]) as? String {
            if json["size"] != nil || json["url"] != nil || json["download"] != nil ||
               name.contains(".") {
                return .file
            }
        }

        // Form: has fields array
        if let fields = json["fields"] as? [[String: Any]], !fields.isEmpty {
            return .form
        }

        // Button Group: has buttons array
        if let buttons = json["buttons"] as? [[String: Any]], !buttons.isEmpty {
            return .buttonGroup
        }

        // Options: has options/choices array
        if let options = (json["options"] ?? json["choices"]) as? [[String: Any]], !options.isEmpty {
            return .options
        }

        // Single Button: has label + (action or id)
        if json["label"] != nil && (json["action"] != nil || json["id"] != nil || json["onClick"] != nil) {
            return .button
        }

        // Email: has to/recipients + subject
        if (json["to"] != nil || json["recipients"] != nil) && json["subject"] != nil {
            return .emailDraft
        }

        // Calendar Event: has title + (startDate or date + time) - must be string date values
        if json["title"] != nil {
            // Require actual date-like string values, not just any field presence
            let hasStartDate = (json["startDate"] as? String)?.contains(where: { $0.isNumber }) == true
            let hasStart = (json["start"] as? String)?.contains(where: { $0.isNumber }) == true
            let hasDateAndTime = (json["date"] as? String) != nil && (json["time"] as? String) != nil

            if hasStartDate || hasStart || hasDateAndTime {
                return .calendar
            }
        }

        return nil
    }

    // MARK: - Component Building

    private static func buildComponent(_ type: ComponentType, from json: [String: Any]) -> ResolvedComponent? {
        switch type {
        case .calendarSchedule:
            return buildCalendarSchedule(json)
        case .tasks:
            return buildTasks(json)
        case .code:
            return buildCode(json)
        case .contact:
            return buildContact(json)
        case .location:
            return buildLocation(json)
        case .linkPreview:
            return buildLinkPreview(json)
        case .chart:
            return buildChart(json)
        case .file:
            return buildFile(json)
        case .form:
            return buildForm(json)
        case .buttonGroup:
            return buildButtonGroup(json)
        case .button:
            return buildButton(json)
        case .options:
            return buildOptions(json)
        case .emailDraft:
            return buildEmailDraft(json)
        case .calendar:
            return buildCalendarEvent(json)
        }
    }

    // MARK: - Individual Builders

    private static func buildCalendarSchedule(_ json: [String: Any]) -> ResolvedComponent? {
        let events = (json["events"] ?? json["items"] ?? json["meetings"]) as? [[String: Any]] ?? []
        print("[Resolver] buildCalendarSchedule: found \(events.count) events in JSON")

        let resolvedEvents: [ResolvedCalendarEvent] = events.compactMap { event in
            print("[Resolver] Processing event: \(event)")
            let time = (event["time"] ?? event["start"] ?? event["startTime"]) as? String ?? ""
            let endTime = (event["endTime"] ?? event["end"]) as? String
            let title = (event["title"] ?? event["name"] ?? event["subject"]) as? String ?? "Untitled"
            let subtitle = (event["subtitle"] ?? event["type"] ?? event["category"]) as? String
            let description = event["description"] as? String
            let durationInt = event["duration"] as? Int
            let durationString = event["duration"] as? String

            // Parse meeting URL using helper
            let meetUrl = parseMeetingUrl(from: event)

            let location = (event["location"] ?? event["place"] ?? event["venue"]) as? String
            let account = (event["account"] ?? event["calendar"] ?? event["calendarName"]) as? String

            // Parse attendees - handle both string arrays and object arrays
            let attendees = parseAttendees(from: event)

            let id = (event["id"] as? String) ?? UUID().uuidString

            return ResolvedCalendarEvent(
                id: id,
                time: time,
                endTime: endTime,
                title: title,
                subtitle: subtitle,
                description: description,
                duration: durationInt,
                durationString: durationString,
                meetUrl: meetUrl,
                location: location,
                account: account,
                attendees: attendees,
                startDate: nil,
                endDate: nil
            )
        }

        print("[Resolver] Built \(resolvedEvents.count) resolved events")
        guard !resolvedEvents.isEmpty else {
            print("[Resolver] No events resolved, returning nil")
            return nil
        }

        return .calendarSchedule(ResolvedCalendarSchedule(
            id: json["id"] as? String ?? UUID().uuidString,
            title: (json["title"] ?? json["name"] ?? "Schedule") as? String ?? "Schedule",
            date: json["date"] as? String,
            events: resolvedEvents
        ))
    }

    /// Parse meeting URL from various field names
    private static func parseMeetingUrl(from event: [String: Any]) -> String? {
        // Try common meeting URL fields (Google Calendar uses hangoutLink)
        if let url = event["hangoutLink"] as? String { return url }
        if let url = event["joinUrl"] as? String { return url }
        if let url = event["joinLink"] as? String { return url }
        if let url = event["meet"] as? String { return url }
        if let url = event["meetingUrl"] as? String { return url }
        if let url = event["meetingLink"] as? String { return url }
        if let url = event["conferenceUrl"] as? String { return url }
        if let url = event["videoCall"] as? String { return url }
        if let url = event["zoomUrl"] as? String { return url }
        if let url = event["zoom"] as? String, url.contains("zoom") { return url }
        if let url = event["teamsUrl"] as? String { return url }
        if let url = event["teams"] as? String, url.contains("teams") { return url }
        if let url = event["hangoutsUrl"] as? String { return url }
        if let url = event["hangout"] as? String { return url }

        // Try nested conferenceData (Google Calendar format)
        if let conferenceData = event["conferenceData"] as? [String: Any],
           let entryPoints = conferenceData["entryPoints"] as? [[String: Any]] {
            for entry in entryPoints {
                if let entryType = entry["entryPointType"] as? String,
                   entryType == "video",
                   let uri = entry["uri"] as? String {
                    return uri
                }
            }
        }

        // Generic fallbacks - only if they look like URLs
        if let url = event["url"] as? String, url.hasPrefix("http") { return url }
        if let url = event["link"] as? String, url.hasPrefix("http") { return url }
        return nil
    }

    /// Parse attendees from various formats
    private static func parseAttendees(from event: [String: Any]) -> [String] {
        // Try different field names
        let attendeesRaw = event["attendees"] ?? event["participants"] ?? event["guests"] ??
                          event["invitees"] ?? event["members"] ?? event["people"]

        // If it's a string array, use directly
        if let stringArray = attendeesRaw as? [String] {
            return stringArray
        }

        // If it's an array of objects, extract names/emails
        if let objectArray = attendeesRaw as? [[String: Any]] {
            return objectArray.compactMap { attendee in
                // Try to get display name first, then email
                if let name = (attendee["name"] ?? attendee["displayName"] ?? attendee["fullName"]) as? String {
                    if let email = attendee["email"] as? String, !name.contains("@") {
                        return "\(name) (\(email))"
                    }
                    return name
                }
                // Fall back to just email
                if let email = attendee["email"] as? String {
                    return email
                }
                // Try responseStatus format (Google Calendar style)
                if let email = attendee["emailAddress"] as? String {
                    return email
                }
                return nil
            }
        }

        // If it's a single string (comma-separated), split it
        if let singleString = attendeesRaw as? String {
            return singleString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        return []
    }

    private static func buildTasks(_ json: [String: Any]) -> ResolvedComponent? {
        let items = (json["items"] ?? json["tasks"] ?? json["todos"]) as? [[String: Any]] ?? []

        let resolvedItems: [ResolvedTaskItem] = items.compactMap { item in
            let text = (item["text"] ?? item["title"] ?? item["name"] ?? item["task"] ?? item["description"]) as? String ?? ""
            guard !text.isEmpty else { return nil }

            let done = (item["done"] ?? item["completed"] ?? item["checked"]) as? Bool ?? false
            let due = (item["due"] ?? item["dueDate"] ?? item["deadline"]) as? String
            let priorityStr = (item["priority"] ?? item["importance"]) as? String
            let priority: ResolvedTaskItem.Priority? = {
                switch priorityStr?.lowercased() {
                case "high", "urgent", "critical", "1": return .high
                case "medium", "normal", "2": return .medium
                case "low", "3": return .low
                default: return nil
                }
            }()

            return ResolvedTaskItem(
                id: (item["id"] as? String) ?? UUID().uuidString,
                text: text,
                done: done,
                due: due,
                priority: priority
            )
        }

        guard !resolvedItems.isEmpty else { return nil }

        return .tasks(ResolvedTasks(
            id: json["id"] as? String ?? UUID().uuidString,
            title: (json["title"] ?? json["name"] ?? "Tasks") as? String ?? "Tasks",
            items: resolvedItems
        ))
    }

    private static func buildCode(_ json: [String: Any]) -> ResolvedComponent? {
        let code = (json["code"] ?? json["content"] ?? json["snippet"] ?? json["source"]) as? String ?? ""
        guard !code.isEmpty else { return nil }

        return .code(ResolvedCode(
            id: json["id"] as? String ?? UUID().uuidString,
            code: code,
            language: (json["language"] ?? json["lang"]) as? String,
            filename: (json["filename"] ?? json["file"] ?? json["name"]) as? String,
            showLineNumbers: json["showLineNumbers"] as? Bool ?? json["lineNumbers"] as? Bool ?? false
        ))
    }

    private static func buildContact(_ json: [String: Any]) -> ResolvedComponent? {
        let name = (json["name"] ?? json["fullName"] ?? json["displayName"]) as? String ?? "Unknown"

        return .contact(ResolvedContact(
            id: json["id"] as? String ?? UUID().uuidString,
            name: name,
            role: (json["role"] ?? json["title"] ?? json["position"] ?? json["company"]) as? String,
            email: (json["email"] ?? json["mail"]) as? String,
            phone: (json["phone"] ?? json["tel"] ?? json["mobile"]) as? String,
            avatar: (json["avatar"] ?? json["image"] ?? json["photo"] ?? json["picture"]) as? String
        ))
    }

    private static func buildLocation(_ json: [String: Any]) -> ResolvedComponent? {
        let lat: Double
        let lng: Double

        if let coords = json["coordinates"] as? [String: Any] {
            lat = (coords["lat"] ?? coords["latitude"]) as? Double ?? 0
            lng = (coords["lng"] ?? coords["longitude"] ?? coords["lon"]) as? Double ?? 0
        } else {
            lat = (json["lat"] ?? json["latitude"]) as? Double ?? 0
            lng = (json["lng"] ?? json["longitude"] ?? json["lon"]) as? Double ?? 0
        }

        guard lat != 0 || lng != 0 else { return nil }

        return .location(ResolvedLocation(
            id: json["id"] as? String ?? UUID().uuidString,
            name: (json["name"] ?? json["title"] ?? json["place"]) as? String,
            address: (json["address"] ?? json["formattedAddress"] ?? json["street"]) as? String,
            lat: lat,
            lng: lng
        ))
    }

    private static func buildLinkPreview(_ json: [String: Any]) -> ResolvedComponent? {
        guard let url = json["url"] as? String else { return nil }

        return .linkPreview(ResolvedLinkPreview(
            id: json["id"] as? String ?? UUID().uuidString,
            url: url,
            title: (json["title"] ?? json["name"]) as? String,
            description: (json["description"] ?? json["summary"] ?? json["excerpt"]) as? String,
            image: (json["image"] ?? json["thumbnail"] ?? json["preview"] ?? json["og:image"]) as? String,
            domain: (json["domain"] ?? json["site"] ?? json["host"]) as? String
        ))
    }

    private static func buildChart(_ json: [String: Any]) -> ResolvedComponent? {
        let data = (json["data"] ?? json["values"] ?? json["points"]) as? [[String: Any]] ?? []

        let resolvedData: [ResolvedChartData] = data.compactMap { point in
            let label = (point["label"] ?? point["name"] ?? point["x"]) as? String ?? ""
            let value = (point["value"] ?? point["count"] ?? point["amount"] ?? point["y"]) as? Double ??
                       Double((point["value"] ?? point["count"]) as? Int ?? 0)

            guard !label.isEmpty else { return nil }
            return ResolvedChartData(label: label, value: value)
        }

        guard !resolvedData.isEmpty else { return nil }

        let chartTypeStr = (json["chartType"] ?? json["type"] ?? json["kind"]) as? String ?? "bar"
        let chartType: ResolvedChart.ChartType = {
            switch chartTypeStr.lowercased() {
            case "pie", "donut": return .pie
            case "line": return .line
            default: return .bar
            }
        }()

        return .chart(ResolvedChart(
            id: json["id"] as? String ?? UUID().uuidString,
            title: (json["title"] ?? json["name"]) as? String,
            chartType: chartType,
            data: resolvedData
        ))
    }

    private static func buildFile(_ json: [String: Any]) -> ResolvedComponent? {
        let name = (json["name"] ?? json["filename"] ?? json["file"]) as? String ?? "Unknown"

        return .file(ResolvedFile(
            id: json["id"] as? String ?? UUID().uuidString,
            name: name,
            size: (json["size"] ?? json["fileSize"]) as? String,
            url: (json["url"] ?? json["download"] ?? json["link"]) as? String,
            mimeType: (json["mimeType"] ?? json["type"] ?? json["contentType"]) as? String
        ))
    }

    private static func buildForm(_ json: [String: Any]) -> ResolvedComponent? {
        let fields = (json["fields"] ?? json["inputs"]) as? [[String: Any]] ?? []

        let resolvedFields: [ResolvedFormField] = fields.compactMap { field in
            let label = (field["label"] ?? field["name"] ?? field["title"]) as? String ?? ""
            guard !label.isEmpty else { return nil }

            let typeStr = (field["type"] ?? field["inputType"]) as? String ?? "text"
            let fieldType: ResolvedFormField.FieldType = {
                switch typeStr.lowercased() {
                case "textarea", "multiline", "long": return .textarea
                case "select", "dropdown", "picker": return .select
                case "number", "integer", "decimal": return .number
                case "email", "mail": return .email
                case "phone", "tel": return .phone
                case "date", "datetime": return .date
                default: return .text
                }
            }()

            return ResolvedFormField(
                id: (field["id"] ?? field["name"]) as? String ?? UUID().uuidString,
                label: label,
                type: fieldType,
                placeholder: (field["placeholder"] ?? field["hint"]) as? String,
                required: field["required"] as? Bool ?? false,
                options: (field["options"] ?? field["choices"]) as? [String]
            )
        }

        guard !resolvedFields.isEmpty else { return nil }

        return .form(ResolvedForm(
            id: json["id"] as? String ?? UUID().uuidString,
            title: (json["title"] ?? json["name"]) as? String,
            fields: resolvedFields,
            submitLabel: (json["submitLabel"] ?? json["submit"] ?? json["action"]) as? String ?? "Submit"
        ))
    }

    private static func buildButtonGroup(_ json: [String: Any]) -> ResolvedComponent? {
        let buttons = (json["buttons"] ?? json["actions"]) as? [[String: Any]] ?? []

        let resolvedButtons: [ResolvedButton] = buttons.compactMap { btn in
            let label = (btn["label"] ?? btn["text"] ?? btn["title"]) as? String ?? ""
            guard !label.isEmpty else { return nil }

            let styleStr = (btn["style"] ?? btn["variant"]) as? String
            let style: ResolvedButton.Style = {
                switch styleStr?.lowercased() {
                case "primary", "main", "default": return .primary
                case "danger", "destructive", "delete", "red": return .danger
                default: return .secondary
                }
            }()

            return ResolvedButton(
                id: (btn["id"] ?? btn["action"]) as? String ?? UUID().uuidString,
                label: label,
                action: (btn["action"] ?? btn["onClick"] ?? btn["id"]) as? String ?? label,
                style: style,
                icon: (btn["icon"] ?? btn["symbol"]) as? String
            )
        }

        guard !resolvedButtons.isEmpty else { return nil }

        let layoutStr = (json["layout"] ?? json["direction"]) as? String
        let layout: ResolvedButtonGroup.Layout = {
            switch layoutStr?.lowercased() {
            case "vertical", "column": return .vertical
            case "grid": return .grid
            default: return .horizontal
            }
        }()

        return .buttonGroup(ResolvedButtonGroup(
            id: json["id"] as? String ?? UUID().uuidString,
            buttons: resolvedButtons,
            layout: layout
        ))
    }

    private static func buildButton(_ json: [String: Any]) -> ResolvedComponent? {
        let label = (json["label"] ?? json["text"] ?? json["title"]) as? String ?? ""
        guard !label.isEmpty else { return nil }

        let styleStr = (json["style"] ?? json["variant"]) as? String
        let style: ResolvedButton.Style = {
            switch styleStr?.lowercased() {
            case "primary", "main": return .primary
            case "danger", "destructive", "delete", "red": return .danger
            default: return .secondary
            }
        }()

        return .button(ResolvedButton(
            id: json["id"] as? String ?? UUID().uuidString,
            label: label,
            action: (json["action"] ?? json["onClick"] ?? json["id"]) as? String ?? label,
            style: style,
            icon: (json["icon"] ?? json["symbol"]) as? String
        ))
    }

    private static func buildOptions(_ json: [String: Any]) -> ResolvedComponent? {
        let options = (json["options"] ?? json["choices"] ?? json["items"]) as? [[String: Any]] ?? []

        let resolvedOptions: [ResolvedOption] = options.compactMap { opt in
            let label = (opt["label"] ?? opt["text"] ?? opt["title"] ?? opt["name"]) as? String ?? ""
            guard !label.isEmpty else { return nil }

            return ResolvedOption(
                id: (opt["id"] ?? opt["value"]) as? String ?? UUID().uuidString,
                label: label,
                description: (opt["description"] ?? opt["subtitle"] ?? opt["hint"]) as? String,
                icon: (opt["icon"] ?? opt["symbol"]) as? String
            )
        }

        guard !resolvedOptions.isEmpty else { return nil }

        return .options(ResolvedOptions(
            id: json["id"] as? String ?? UUID().uuidString,
            prompt: (json["prompt"] ?? json["question"] ?? json["title"]) as? String,
            options: resolvedOptions,
            allowMultiple: json["allowMultiple"] as? Bool ?? json["multiple"] as? Bool ?? false
        ))
    }

    private static func buildEmailDraft(_ json: [String: Any]) -> ResolvedComponent? {
        let to: [String]
        if let toArray = json["to"] as? [String] {
            to = toArray
        } else if let toString = json["to"] as? String {
            to = [toString]
        } else if let recipients = json["recipients"] as? [String] {
            to = recipients
        } else {
            return nil
        }

        let subject = (json["subject"] ?? json["title"]) as? String ?? ""

        return .emailDraft(ResolvedEmailDraft(
            id: json["id"] as? String ?? UUID().uuidString,
            to: to,
            subject: subject,
            body: (json["body"] ?? json["content"] ?? json["message"]) as? String ?? "",
            cc: json["cc"] as? [String],
            bcc: json["bcc"] as? [String]
        ))
    }

    private static func buildCalendarEvent(_ json: [String: Any]) -> ResolvedComponent? {
        let title = (json["title"] ?? json["name"] ?? json["subject"]) as? String ?? "Event"

        // Parse dates flexibly
        let startDate: Date?
        if let dateStr = (json["startDate"] ?? json["start"] ?? json["date"]) as? String {
            startDate = parseDate(dateStr)
        } else {
            startDate = nil
        }

        let endDate: Date?
        if let dateStr = (json["endDate"] ?? json["end"]) as? String {
            endDate = parseDate(dateStr)
        } else {
            endDate = startDate
        }

        // Parse meeting URL using helper
        let meetUrl = parseMeetingUrl(from: json)

        // Parse attendees using helper
        let attendees = parseAttendees(from: json)

        return .calendarEvent(ResolvedCalendarEvent(
            id: json["id"] as? String ?? UUID().uuidString,
            time: (json["time"] ?? json["startTime"]) as? String,
            endTime: (json["endTime"] ?? json["end"]) as? String,
            title: title,
            subtitle: (json["subtitle"] ?? json["type"]) as? String,
            description: (json["description"] ?? json["notes"] ?? json["body"]) as? String,
            duration: json["duration"] as? Int,
            durationString: json["duration"] as? String,
            meetUrl: meetUrl,
            location: (json["location"] ?? json["place"] ?? json["venue"]) as? String,
            account: (json["account"] ?? json["calendar"] ?? json["calendarName"]) as? String,
            attendees: attendees,
            startDate: startDate,
            endDate: endDate
        ))
    }

    // Cached date formatters to avoid expensive recreation
    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "dd/MM/yyyy"
        ]
        return formats.map { format in
            let f = DateFormatter()
            f.dateFormat = format
            return f
        }
    }()

    private nonisolated(unsafe) static let isoFormatter = ISO8601DateFormatter()

    private static func parseDate(_ string: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }

        // Try ISO8601
        return isoFormatter.date(from: string)
    }
}

// MARK: - Component Types

enum ComponentType: String {
    case calendarSchedule
    case tasks
    case code
    case contact
    case location
    case linkPreview
    case chart
    case file
    case form
    case buttonGroup
    case button
    case options
    case emailDraft
    case calendar
}

// MARK: - Resolved Models (Normalized)

enum ResolvedComponent {
    case calendarSchedule(ResolvedCalendarSchedule)
    case tasks(ResolvedTasks)
    case code(ResolvedCode)
    case contact(ResolvedContact)
    case location(ResolvedLocation)
    case linkPreview(ResolvedLinkPreview)
    case chart(ResolvedChart)
    case file(ResolvedFile)
    case form(ResolvedForm)
    case buttonGroup(ResolvedButtonGroup)
    case button(ResolvedButton)
    case options(ResolvedOptions)
    case emailDraft(ResolvedEmailDraft)
    case calendarEvent(ResolvedCalendarEvent)
}

struct ResolvedCalendarSchedule {
    let id: String
    let title: String
    let date: String?
    let events: [ResolvedCalendarEvent]
}

struct ResolvedCalendarEvent: Identifiable {
    let id: String
    var time: String?
    var endTime: String?
    let title: String
    let subtitle: String?
    let description: String?
    let duration: Int?
    let durationString: String?
    let meetUrl: String?
    let location: String?
    let account: String?
    let attendees: [String]
    var startDate: Date?
    var endDate: Date?
}

struct ResolvedTasks {
    let id: String
    let title: String
    let items: [ResolvedTaskItem]
}

struct ResolvedTaskItem: Identifiable {
    let id: String
    let text: String
    var done: Bool
    let due: String?
    let priority: Priority?

    enum Priority {
        case high, medium, low
    }
}

struct ResolvedCode {
    let id: String
    let code: String
    let language: String?
    let filename: String?
    let showLineNumbers: Bool
}

struct ResolvedContact {
    let id: String
    let name: String
    let role: String?
    let email: String?
    let phone: String?
    let avatar: String?
}

struct ResolvedLocation {
    let id: String
    let name: String?
    let address: String?
    let lat: Double
    let lng: Double
}

struct ResolvedLinkPreview {
    let id: String
    let url: String
    let title: String?
    let description: String?
    let image: String?
    let domain: String?
}

struct ResolvedChart {
    let id: String
    let title: String?
    let chartType: ChartType
    let data: [ResolvedChartData]

    enum ChartType {
        case bar, line, pie
    }
}

struct ResolvedChartData: Identifiable {
    var id: String { label }
    let label: String
    let value: Double
}

struct ResolvedFile {
    let id: String
    let name: String
    let size: String?
    let url: String?
    let mimeType: String?
}

struct ResolvedForm {
    let id: String
    let title: String?
    let fields: [ResolvedFormField]
    let submitLabel: String
}

struct ResolvedFormField: Identifiable {
    let id: String
    let label: String
    let type: FieldType
    let placeholder: String?
    let required: Bool
    let options: [String]?

    enum FieldType {
        case text, textarea, select, number, email, phone, date
    }
}

struct ResolvedButtonGroup {
    let id: String
    let buttons: [ResolvedButton]
    let layout: Layout

    enum Layout {
        case horizontal, vertical, grid
    }
}

struct ResolvedButton: Identifiable {
    let id: String
    let label: String
    let action: String
    let style: Style
    let icon: String?

    enum Style {
        case primary, secondary, danger
    }
}

struct ResolvedOptions {
    let id: String
    let prompt: String?
    let options: [ResolvedOption]
    let allowMultiple: Bool
}

struct ResolvedOption: Identifiable {
    let id: String
    let label: String
    let description: String?
    let icon: String?
}

struct ResolvedEmailDraft {
    let id: String
    let to: [String]
    let subject: String
    let body: String
    let cc: [String]?
    let bcc: [String]?
}
