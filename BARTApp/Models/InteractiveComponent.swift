import Foundation

// MARK: - Button Component

struct ButtonComponent: Codable, Identifiable {
    let type: String
    let id: String
    let label: String
    let action: String?
    let style: ButtonStyle?
    let icon: String?
    let disabled: Bool?

    enum ButtonStyle: String, Codable {
        case primary
        case secondary
        case destructive
        case danger  // alias for destructive
    }

    var effectiveAction: String {
        action ?? id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        action = try container.decode(String.self, forKey: .action)
        style = try container.decodeIfPresent(ButtonStyle.self, forKey: .style)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, label, action, style, icon, disabled
    }
}

// MARK: - Button Group Component

struct ButtonGroupComponent: Codable, Identifiable {
    let type: String
    let id: String
    let buttons: [ButtonComponent]
    let layout: LayoutStyle?

    enum LayoutStyle: String, Codable {
        case horizontal
        case vertical
        case grid
    }
}

// MARK: - Calendar Component

struct CalendarComponent: Codable, Identifiable {
    let type: String
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let description: String?
    let attendees: [String]?
    let actions: CalendarActions?

    struct CalendarActions: Codable {
        let addToCalendar: Bool?
        let decline: Bool?
        let propose: Bool?
    }
}

// MARK: - Email Draft Component

struct EmailDraftComponent: Codable, Identifiable {
    let type: String
    let id: String
    let to: [String]
    let cc: [String]?
    let bcc: [String]?
    let subject: String
    let body: String
    let isHTML: Bool?
    let attachments: [AttachmentInfo]?

    struct AttachmentInfo: Codable {
        let name: String
        let size: Int?
        let mimeType: String?
    }
}

// MARK: - Calendar Schedule Component (Day Agenda)

struct CalendarScheduleComponent: Codable, Identifiable {
    let type: String
    let id: String
    let title: String
    let date: String  // "2026-02-02" format
    let events: [ScheduleEvent]

    struct ScheduleEvent: Codable, Identifiable {
        let id: String
        let time: String  // "12:00" format
        let duration: Int?  // minutes
        let title: String
        let subtitle: String?
        let meet: String?  // Meeting URL
        let location: String?
    }

    // Custom decoder to handle missing id field
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "schedule-\(UUID().uuidString.prefix(8))"
        title = try container.decode(String.self, forKey: .title)
        date = try container.decode(String.self, forKey: .date)
        events = try container.decode([ScheduleEvent].self, forKey: .events)
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, title, date, events
    }
}

// MARK: - Form Component

struct FormComponent: Codable, Identifiable {
    let type: String
    let id: String
    let title: String?
    let fields: [FormField]
    let submitLabel: String?

    struct FormField: Codable, Identifiable {
        let id: String
        let label: String
        let fieldType: FieldType
        let required: Bool?
        let placeholder: String?
        let options: [String]?
        let defaultValue: String?

        enum FieldType: String, Codable {
            case text
            case textarea
            case select
            case number
            case email
            case phone
            case date
        }

        private enum CodingKeys: String, CodingKey {
            case id, label, required, placeholder, options, defaultValue
            case fieldType = "type"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "form-\(UUID().uuidString.prefix(8))"
        title = try container.decodeIfPresent(String.self, forKey: .title)
        fields = try container.decode([FormField].self, forKey: .fields)
        submitLabel = try container.decodeIfPresent(String.self, forKey: .submitLabel)
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, title, fields, submitLabel
    }
}

// MARK: - Code Snippet Component

struct CodeComponent: Codable, Identifiable {
    let type: String
    let id: String
    let language: String?
    let code: String
    let filename: String?
    let showLineNumbers: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "code-\(UUID().uuidString.prefix(8))"
        language = try container.decodeIfPresent(String.self, forKey: .language)
        code = try container.decode(String.self, forKey: .code)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        showLineNumbers = try container.decodeIfPresent(Bool.self, forKey: .showLineNumbers)
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, language, code, filename, showLineNumbers
    }
}

// MARK: - Link Preview Component

struct LinkPreviewComponent: Codable, Identifiable {
    let type: String
    let id: String
    let url: String
    let title: String?
    let description: String?
    let image: String?
    let domain: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "link-\(UUID().uuidString.prefix(8))"
        url = try container.decode(String.self, forKey: .url)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, url, title, description, image, domain
    }
}

// MARK: - File Component

struct FileComponent: Codable, Identifiable {
    let type: String
    let id: String
    let name: String
    let size: String?
    let fileType: String?  // e.g., "pdf", "image"
    let url: String?
    let thumbnail: String?
    let actions: [String]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "file-\(UUID().uuidString.prefix(8))"
        name = try container.decode(String.self, forKey: .name)
        size = try container.decodeIfPresent(String.self, forKey: .size)
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        actions = try container.decodeIfPresent([String].self, forKey: .actions)
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, name, size, url, thumbnail, actions
        case fileType = "fileType"
    }
}

// MARK: - Contact Component

struct ContactComponent: Codable, Identifiable {
    let type: String
    let id: String
    let name: String
    let role: String?
    let email: String?
    let phone: String?
    let avatar: String?
    let actions: [String]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "contact-\(UUID().uuidString.prefix(8))"
        name = try container.decode(String.self, forKey: .name)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        actions = try container.decodeIfPresent([String].self, forKey: .actions)
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, name, role, email, phone, avatar, actions
    }
}

// MARK: - Chart Component

struct ChartComponent: Codable, Identifiable {
    let type: String
    let id: String
    let chartType: ChartType
    let title: String?
    let data: [DataPoint]

    enum ChartType: String, Codable {
        case bar
        case line
        case pie
    }

    struct DataPoint: Codable, Identifiable {
        var id: String { label }
        let label: String
        let value: Double
        let color: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "chart-\(UUID().uuidString.prefix(8))"
        chartType = try container.decode(ChartType.self, forKey: .chartType)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        data = try container.decode([DataPoint].self, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, chartType, title, data
    }
}

// MARK: - Location Component

struct LocationComponent: Codable, Identifiable {
    let type: String
    let id: String
    let name: String?
    let address: String?
    let lat: Double
    let lng: Double
    let actions: [String]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "loc-\(UUID().uuidString.prefix(8))"
        name = try container.decodeIfPresent(String.self, forKey: .name)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        lat = try container.decode(Double.self, forKey: .lat)
        lng = try container.decode(Double.self, forKey: .lng)
        actions = try container.decodeIfPresent([String].self, forKey: .actions)
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, name, address, lat, lng, actions
    }
}

// MARK: - Tasks Component

struct TasksComponent: Codable, Identifiable {
    let type: String
    let id: String
    let title: String
    let items: [TaskItem]

    struct TaskItem: Codable, Identifiable {
        let id: String
        let text: String
        let due: String?
        let priority: Priority?
        let done: Bool?

        enum Priority: String, Codable {
            case high
            case medium
            case low
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "tasks-\(UUID().uuidString.prefix(8))"
        title = try container.decode(String.self, forKey: .title)
        items = try container.decode([TaskItem].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, title, items
    }
}

// MARK: - Options Component

struct OptionsComponent: Codable, Identifiable {
    let type: String
    let id: String
    let prompt: String?
    let options: [OptionItem]
    let allowMultiple: Bool?
    let required: Bool?

    struct OptionItem: Codable, Identifiable {
        let id: String
        let label: String
        let description: String?
        let icon: String?
        let selected: Bool?
    }
}

// MARK: - Parsed Content Block

enum ParsedContentBlock: Identifiable {
    case text(String)
    case button(ButtonComponent)
    case buttonGroup(ButtonGroupComponent)
    case calendar(CalendarComponent)
    case calendarSchedule(CalendarScheduleComponent)
    case emailDraft(EmailDraftComponent)
    case options(OptionsComponent)
    case tasks(TasksComponent)
    case form(FormComponent)
    case code(CodeComponent)
    case linkPreview(LinkPreviewComponent)
    case file(FileComponent)
    case contact(ContactComponent)
    case chart(ChartComponent)
    case location(LocationComponent)
    case resolved(ResolvedComponent)  // Flexible resolver output

    var id: String {
        switch self {
        case .text(let content):
            return "text-\(content.hashValue)"
        case .button(let component):
            return "button-\(component.id)"
        case .buttonGroup(let component):
            return "buttonGroup-\(component.id)"
        case .calendar(let component):
            return "calendar-\(component.id)"
        case .calendarSchedule(let component):
            return "calendarSchedule-\(component.id)"
        case .emailDraft(let component):
            return "emailDraft-\(component.id)"
        case .options(let component):
            return "options-\(component.id)"
        case .tasks(let component):
            return "tasks-\(component.id)"
        case .form(let component):
            return "form-\(component.id)"
        case .code(let component):
            return "code-\(component.id)"
        case .linkPreview(let component):
            return "linkPreview-\(component.id)"
        case .file(let component):
            return "file-\(component.id)"
        case .contact(let component):
            return "contact-\(component.id)"
        case .chart(let component):
            return "chart-\(component.id)"
        case .location(let component):
            return "location-\(component.id)"
        case .resolved(let component):
            return "resolved-\(resolvedId(component))"
        }
    }

    private func resolvedId(_ component: ResolvedComponent) -> String {
        switch component {
        case .calendarSchedule(let data): return data.id
        case .tasks(let data): return data.id
        case .code(let data): return data.id
        case .contact(let data): return data.id
        case .location(let data): return data.id
        case .linkPreview(let data): return data.id
        case .chart(let data): return data.id
        case .file(let data): return data.id
        case .form(let data): return data.id
        case .buttonGroup(let data): return data.id
        case .button(let data): return data.id
        case .options(let data): return data.id
        case .emailDraft(let data): return data.id
        case .calendarEvent(let data): return data.id
        }
    }
}
