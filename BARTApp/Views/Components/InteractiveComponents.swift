import SwiftUI
import EventKit
import MessageUI

// MARK: - Button Component View

struct InteractiveButtonView: View {
    let component: ButtonComponent
    let onAction: (String, String) -> Void

    var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onAction(component.id, component.effectiveAction)
        } label: {
            HStack(spacing: 8) {
                if let icon = component.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                }
                Text(component.label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(buttonBackground)
            .foregroundStyle(buttonForeground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(component.disabled ?? false)
        .opacity((component.disabled ?? false) ? 0.5 : 1)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        switch component.style ?? .secondary {
        case .primary:
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            Color(.systemGray5)
        case .destructive, .danger:
            Color.red
        }
    }

    private var buttonForeground: Color {
        switch component.style ?? .secondary {
        case .primary, .destructive, .danger:
            return .white
        case .secondary:
            return .primary
        }
    }
}

// MARK: - Button Group View

struct InteractiveButtonGroupView: View {
    let component: ButtonGroupComponent
    let onAction: (String, String) -> Void

    var body: some View {
        Group {
            switch component.layout ?? .horizontal {
            case .horizontal:
                HStack(spacing: 8) {
                    ForEach(component.buttons) { button in
                        InteractiveButtonView(component: button, onAction: onAction)
                    }
                }
            case .vertical:
                VStack(spacing: 8) {
                    ForEach(component.buttons) { button in
                        InteractiveButtonView(component: button, onAction: onAction)
                    }
                }
            case .grid:
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(component.buttons) { button in
                        InteractiveButtonView(component: button, onAction: onAction)
                    }
                }
            }
        }
    }
}

// MARK: - Calendar Component View

struct InteractiveCalendarView: View {
    let component: CalendarComponent
    let onAction: (String, String) -> Void

    @State private var showingAlert = false
    @State private var alertMessage = ""

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 16, weight: .semibold))
                Text(component.title)
                    .font(.headline)
                Spacer()
            }

            // Date/Time
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dateFormatter.string(from: component.startDate))
                        .font(.subheadline)
                }

                if component.startDate != component.endDate {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(dateFormatter.string(from: component.endDate))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Location
            if let location = component.location {
                HStack(spacing: 8) {
                    Image(systemName: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(location)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Description
            if let description = component.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            // Attendees
            if let attendees = component.attendees, !attendees.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(attendees.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Actions
            HStack(spacing: 8) {
                if component.actions?.addToCalendar ?? true {
                    Button {
                        addToCalendar()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add to Calendar")
                        }
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if component.actions?.decline ?? false {
                    Button {
                        onAction(component.id, "decline")
                    } label: {
                        Text("Decline")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if component.actions?.propose ?? false {
                    Button {
                        onAction(component.id, "propose")
                    } label: {
                        Text("Propose New Time")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(GlassBackground(cornerRadius: 16))
        .alert("Calendar", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func addToCalendar() {
        let eventStore = EKEventStore()

        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents { granted, error in
                handleCalendarAccess(granted: granted, error: error, eventStore: eventStore)
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, error in
                handleCalendarAccess(granted: granted, error: error, eventStore: eventStore)
            }
        }
    }

    private func handleCalendarAccess(granted: Bool, error: Error?, eventStore: EKEventStore) {
        guard granted, error == nil else {
            DispatchQueue.main.async {
                alertMessage = "Calendar access denied. Please enable in Settings."
                showingAlert = true
                onAction(component.id, "calendar_access_denied")
            }
            return
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = component.title
        event.startDate = component.startDate
        event.endDate = component.endDate
        event.location = component.location
        event.notes = component.description
        event.calendar = eventStore.defaultCalendarForNewEvents

        do {
            try eventStore.save(event, span: .thisEvent)
            DispatchQueue.main.async {
                let impact = UINotificationFeedbackGenerator()
                impact.notificationOccurred(.success)
                alertMessage = "Event added to your calendar!"
                showingAlert = true
                onAction(component.id, "added_to_calendar")
            }
        } catch {
            DispatchQueue.main.async {
                alertMessage = "Failed to add event: \(error.localizedDescription)"
                showingAlert = true
                onAction(component.id, "calendar_error")
            }
        }
    }
}

// MARK: - Email Draft Component View

struct InteractiveEmailDraftView: View {
    let component: EmailDraftComponent
    let onAction: (String, String) -> Void

    @State private var showMailCompose = false
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 16, weight: .semibold))
                Text("Email Draft")
                    .font(.headline)
                Spacer()
            }

            // Recipients
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text("To:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                    Text(component.to.joined(separator: ", "))
                        .font(.subheadline)
                        .lineLimit(2)
                }

                if let cc = component.cc, !cc.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Text("CC:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                        Text(cc.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // Subject
            HStack(spacing: 8) {
                Text("Subject:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(component.subject)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }

            // Body preview
            Text(component.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6).opacity(0.5))
                )

            // Attachments
            if let attachments = component.attachments, !attachments.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Actions
            HStack(spacing: 8) {
                if MFMailComposeViewController.canSendMail() {
                    Button {
                        showMailCompose = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane")
                            Text("Open in Mail")
                        }
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button {
                    UIPasteboard.general.string = component.body
                    let impact = UINotificationFeedbackGenerator()
                    impact.notificationOccurred(.success)
                    showCopied = true
                    onAction(component.id, "copied")

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        Text(showCopied ? "Copied!" : "Copy Body")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(GlassBackground(cornerRadius: 16))
        .sheet(isPresented: $showMailCompose) {
            MailComposeView(
                recipients: component.to,
                cc: component.cc ?? [],
                bcc: component.bcc ?? [],
                subject: component.subject,
                body: component.body,
                isHTML: component.isHTML ?? false
            ) { result in
                switch result {
                case .sent:
                    onAction(component.id, "sent")
                case .saved:
                    onAction(component.id, "saved")
                case .cancelled:
                    onAction(component.id, "cancelled")
                case .failed:
                    onAction(component.id, "failed")
                @unknown default:
                    break
                }
            }
        }
    }
}

// MARK: - Calendar Schedule Component View (Day Agenda)

struct InteractiveCalendarScheduleView: View {
    let component: CalendarScheduleComponent
    let onAction: (String, String) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 18, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(component.title)
                        .font(.headline)
                    Text(formatDate(component.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(component.events.count) events")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            // Events list
            VStack(spacing: 0) {
                ForEach(component.events) { event in
                    ScheduleEventRow(event: event) {
                        if let meetURL = event.meet, let url = URL(string: meetURL) {
                            openURL(url)
                            onAction(component.id, "join:\(event.id)")
                        }
                    }

                    if event.id != component.events.last?.id {
                        Divider()
                            .padding(.leading, 50)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func formatDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"

        guard let date = inputFormatter.date(from: dateString) else {
            return dateString
        }

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "EEEE, MMM d"
        return outputFormatter.string(from: date)
    }
}

struct ScheduleEventRow: View {
    let event: CalendarScheduleComponent.ScheduleEvent
    let onJoin: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time column
            VStack(alignment: .trailing, spacing: 2) {
                Text(event.time)
                    .font(.system(.subheadline, design: .monospaced, weight: .medium))
                    .foregroundStyle(.primary)

                if let duration = event.duration {
                    Text("\(duration)m")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 44, alignment: .trailing)

            // Timeline indicator
            VStack(spacing: 4) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)

                if event.duration != nil {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: 2)
                }
            }

            // Event details
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let location = event.location {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 9))
                        Text(location)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Join button if there's a meeting link
            if event.meet != nil {
                Button(action: onJoin) {
                    HStack(spacing: 4) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 10))
                        Text("Join")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Tasks Component View

struct InteractiveTasksView: View {
    let component: TasksComponent
    let onAction: (String, String) -> Void

    @State private var completedTasks: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "checklist")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 18, weight: .semibold))

                Text(component.title)
                    .font(.headline)

                Spacer()

                let doneCount = component.items.filter { ($0.done ?? false) || completedTasks.contains($0.id) }.count
                Text("\(doneCount)/\(component.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.systemGray5)))
            }

            Divider()

            // Tasks list
            VStack(spacing: 2) {
                ForEach(component.items) { item in
                    TaskItemRow(
                        item: item,
                        isCompleted: (item.done ?? false) || completedTasks.contains(item.id)
                    ) {
                        toggleTask(item)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .onAppear {
            // Initialize completed tasks from done state
            for item in component.items where item.done ?? false {
                completedTasks.insert(item.id)
            }
        }
    }

    private func toggleTask(_ item: TasksComponent.TaskItem) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        if completedTasks.contains(item.id) {
            completedTasks.remove(item.id)
            onAction(component.id, "uncomplete:\(item.id)")
        } else {
            completedTasks.insert(item.id)
            onAction(component.id, "complete:\(item.id)")
        }
    }
}

struct TaskItemRow: View {
    let item: TasksComponent.TaskItem
    let isCompleted: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isCompleted ? Color.green : priorityColor, lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isCompleted {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green)
                            .frame(width: 22, height: 22)

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                // Task text
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .font(.subheadline)
                        .strikethrough(isCompleted)
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        // Due date
                        if let due = item.due {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 9))
                                Text(formatDueDate(due))
                            }
                            .font(.caption2)
                            .foregroundStyle(isDueUrgent(due) && !isCompleted ? Color.red : Color.secondary)
                        }

                        // Priority badge
                        if let priority = item.priority, !isCompleted {
                            Text(priority.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(priorityColor.opacity(0.2)))
                                .foregroundStyle(priorityColor)
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var priorityColor: Color {
        switch item.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        case .none: return .gray
        }
    }

    private func formatDueDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"

        guard let date = inputFormatter.date(from: dateString) else {
            return dateString
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMM d"
        return outputFormatter.string(from: date)
    }

    private func isDueUrgent(_ dateString: String) -> Bool {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"

        guard let date = inputFormatter.date(from: dateString) else {
            return false
        }

        let calendar = Calendar.current
        return calendar.isDateInToday(date) || date < Date()
    }
}

// MARK: - Options Component View

struct InteractiveOptionsView: View {
    let component: OptionsComponent
    let onAction: (String, String) -> Void

    @State private var selectedOptions: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let prompt = component.prompt {
                Text(prompt)
                    .font(.subheadline.weight(.medium))
            }

            VStack(spacing: 4) {
                ForEach(component.options) { option in
                    OptionRowView(
                        option: option,
                        isSelected: selectedOptions.contains(option.id),
                        allowMultiple: component.allowMultiple ?? false
                    ) {
                        toggleOption(option)
                    }
                }
            }

            if component.allowMultiple ?? false {
                Button {
                    let selection = Array(selectedOptions).joined(separator: ",")
                    onAction(component.id, "selected:\(selection)")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Confirm Selection")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selectedOptions.isEmpty && (component.required ?? false))
            }
        }
        .padding(12)
        .background(GlassBackground(cornerRadius: 16))
        .onAppear {
            // Pre-select options marked as selected
            for option in component.options where option.selected ?? false {
                selectedOptions.insert(option.id)
            }
        }
    }

    private func toggleOption(_ option: OptionsComponent.OptionItem) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        if component.allowMultiple ?? false {
            if selectedOptions.contains(option.id) {
                selectedOptions.remove(option.id)
            } else {
                selectedOptions.insert(option.id)
            }
        } else {
            // Single selection - immediately send action
            selectedOptions = [option.id]
            onAction(component.id, "selected:\(option.id)")
        }
    }
}

// MARK: - Option Row View

struct OptionRowView: View {
    let option: OptionsComponent.OptionItem
    let isSelected: Bool
    let allowMultiple: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    if allowMultiple {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 20, height: 20)

                        if isSelected {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor)
                                .frame(width: 20, height: 20)

                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    } else {
                        Circle()
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 20, height: 20)

                        if isSelected {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 12, height: 12)
                        }
                    }
                }

                // Icon if present
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }

                // Label and description
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    if let description = option.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Form Component View

struct InteractiveFormView: View {
    let component: FormComponent
    let onAction: (String, String) -> Void

    @State private var fieldValues: [String: String] = [:]
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            if let title = component.title {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 16, weight: .semibold))
                    Text(title)
                        .font(.headline)
                }
            }

            // Fields
            VStack(spacing: 12) {
                ForEach(component.fields) { field in
                    FormFieldView(
                        field: field,
                        value: Binding(
                            get: { fieldValues[field.id] ?? field.defaultValue ?? "" },
                            set: { fieldValues[field.id] = $0 }
                        )
                    )
                }
            }

            // Submit button
            Button {
                submitForm()
            } label: {
                HStack {
                    if isSubmitting {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(component.submitLabel ?? "Submit")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isSubmitting || !isFormValid)
            .opacity(isFormValid ? 1 : 0.6)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var isFormValid: Bool {
        for field in component.fields where field.required ?? false {
            let value = fieldValues[field.id] ?? ""
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }
        return true
    }

    private func submitForm() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        isSubmitting = true

        // Encode field values as JSON
        if let data = try? JSONSerialization.data(withJSONObject: fieldValues),
           let json = String(data: data, encoding: .utf8) {
            onAction(component.id, "submit:\(json)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSubmitting = false
        }
    }
}

struct FormFieldView: View {
    let field: FormComponent.FormField
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(field.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if field.required ?? false {
                    Text("*")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            switch field.fieldType {
            case .text, .email, .phone, .number:
                TextField(field.placeholder ?? "", text: $value)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(keyboardType)

            case .textarea:
                TextField(field.placeholder ?? "", text: $value, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

            case .select:
                Menu {
                    ForEach(field.options ?? [], id: \.self) { option in
                        Button(option) {
                            value = option
                        }
                    }
                } label: {
                    HStack {
                        Text(value.isEmpty ? (field.placeholder ?? "Select...") : value)
                            .foregroundStyle(value.isEmpty ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                }

            case .date:
                TextField(field.placeholder ?? "YYYY-MM-DD", text: $value)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var keyboardType: UIKeyboardType {
        switch field.fieldType {
        case .email: return .emailAddress
        case .phone: return .phonePad
        case .number: return .decimalPad
        default: return .default
        }
    }
}

// MARK: - Code Component View

struct InteractiveCodeView: View {
    let component: CodeComponent
    let onAction: (String, String) -> Void

    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if let filename = component.filename {
                    HStack(spacing: 6) {
                        Image(systemName: fileIcon)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(filename)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }

                if let language = component.language {
                    Text(language)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(.systemGray5)))
                }

                Spacer()

                Button {
                    copyCode()
                } label: {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(showCopied ? .green : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))

            // Code
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    if component.showLineNumbers ?? false {
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(1...lineCount, id: \.self) { line in
                                Text("\(line)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(height: 18)
                            }
                        }
                        .padding(.leading, 12)

                        Divider()
                    }

                    Text(component.code)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, component.showLineNumbers ?? false ? 0 : 12)
                }
                .padding(.vertical, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var lineCount: Int {
        component.code.components(separatedBy: "\n").count
    }

    private var fileIcon: String {
        switch component.language?.lowercased() {
        case "swift": return "swift"
        case "python", "py": return "text.alignleft"
        case "javascript", "js", "typescript", "ts": return "curlybraces"
        case "json": return "curlybraces"
        default: return "doc.text"
        }
    }

    private func copyCode() {
        UIPasteboard.general.string = component.code
        let impact = UINotificationFeedbackGenerator()
        impact.notificationOccurred(.success)

        showCopied = true
        onAction(component.id, "copied")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopied = false
        }
    }
}

// MARK: - Link Preview Component View

struct InteractiveLinkPreviewView: View {
    let component: LinkPreviewComponent
    let onAction: (String, String) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: component.url) {
                openURL(url)
                onAction(component.id, "opened")
            }
        } label: {
            HStack(spacing: 12) {
                // Thumbnail/Icon
                if let imageURL = component.image, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                        Image(systemName: "link")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 60, height: 60)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let title = component.title {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if let description = component.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                        Text(component.domain ?? URL(string: component.url)?.host ?? component.url)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File Component View

struct InteractiveFileView: View {
    let component: FileComponent
    let onAction: (String, String) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            // File icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(fileColor.opacity(0.15))
                Image(systemName: fileIcon)
                    .font(.title2)
                    .foregroundStyle(fileColor)
            }
            .frame(width: 50, height: 50)

            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(component.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let size = component.size {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                if component.actions?.contains("preview") ?? false {
                    Button {
                        onAction(component.id, "preview")
                    } label: {
                        Image(systemName: "eye")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color(.systemGray5)))
                    }
                }

                if component.actions?.contains("download") ?? true {
                    Button {
                        if let urlStr = component.url, let url = URL(string: urlStr) {
                            openURL(url)
                        }
                        onAction(component.id, "download")
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var fileIcon: String {
        let ext = component.name.components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "pdf": return "doc.text.fill"
        case "doc", "docx": return "doc.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.fill.on.rectangle.fill"
        case "jpg", "jpeg", "png", "gif", "webp": return "photo.fill"
        case "mp4", "mov", "avi": return "film.fill"
        case "mp3", "wav", "m4a": return "music.note"
        case "zip", "rar", "7z": return "doc.zipper"
        case "swift", "py", "js", "ts": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.fill"
        }
    }

    private var fileColor: Color {
        let ext = component.name.components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx": return .green
        case "ppt", "pptx": return .orange
        case "jpg", "jpeg", "png", "gif", "webp": return .purple
        case "mp4", "mov", "avi": return .pink
        case "zip", "rar", "7z": return .brown
        default: return .gray
        }
    }
}

// MARK: - Contact Component View

struct InteractiveContactView: View {
    let component: ContactComponent
    let onAction: (String, String) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            if let avatarURL = component.avatar, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsView
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                initialsView
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(component.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let role = component.role {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                if let phone = component.phone, component.actions?.contains("call") ?? true {
                    Button {
                        if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                            openURL(url)
                        }
                        onAction(component.id, "call")
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.green))
                    }
                }

                if let email = component.email, component.actions?.contains("email") ?? true {
                    Button {
                        if let url = URL(string: "mailto:\(email)") {
                            openURL(url)
                        }
                        onAction(component.id, "email")
                    } label: {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.accentColor))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
            Text(initials)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 50, height: 50)
    }

    private var initials: String {
        let parts = component.name.components(separatedBy: " ")
        let firstInitial = parts.first?.first.map(String.init) ?? ""
        let lastInitial = parts.count > 1 ? parts.last?.first.map(String.init) ?? "" : ""
        return (firstInitial + lastInitial).uppercased()
    }
}

// MARK: - Chart Component View

struct InteractiveChartView: View {
    let component: ChartComponent
    let onAction: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            if let title = component.title {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(title)
                        .font(.headline)
                }
            }

            // Chart
            switch component.chartType {
            case .bar:
                BarChartView(data: component.data)
            case .line:
                // Simplified line chart
                BarChartView(data: component.data)  // Fallback to bar for now
            case .pie:
                PieChartView(data: component.data)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct BarChartView: View {
    let data: [ChartComponent.DataPoint]

    private var maxValue: Double {
        data.map(\.value).max() ?? 1
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(data) { point in
                HStack(spacing: 8) {
                    Text(point.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * (point.value / maxValue))
                    }
                    .frame(height: 20)

                    Text(formatValue(point.value))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)
                }
            }
        }
    }

    private func formatValue(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fK", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}

struct PieChartView: View {
    let data: [ChartComponent.DataPoint]

    private var total: Double {
        data.map(\.value).reduce(0, +)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Simple pie representation using stacked bars
            ZStack {
                ForEach(Array(data.enumerated()), id: \.element.id) { index, point in
                    Circle()
                        .trim(from: startAngle(for: index), to: endAngle(for: index))
                        .stroke(colorForIndex(index), lineWidth: 30)
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 80, height: 80)

            // Legend
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(data.enumerated()), id: \.element.id) { index, point in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(colorForIndex(index))
                            .frame(width: 10, height: 10)
                        Text(point.label)
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.0f%%", (point.value / total) * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func startAngle(for index: Int) -> Double {
        let precedingSum = data.prefix(index).map(\.value).reduce(0, +)
        return precedingSum / total
    }

    private func endAngle(for index: Int) -> Double {
        let includingSum = data.prefix(index + 1).map(\.value).reduce(0, +)
        return includingSum / total
    }

    private func colorForIndex(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .yellow, .red, .cyan]
        return colors[index % colors.count]
    }
}

// MARK: - Location Component View

struct InteractiveLocationView: View {
    let component: LocationComponent
    let onAction: (String, String) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Map preview (simplified - shows coordinates)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(height: 120)

                VStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.red)

                    if let name = component.name {
                        Text(name)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }

            // Address
            if let address = component.address {
                HStack(spacing: 8) {
                    Image(systemName: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(address)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            }

            // Coordinates
            Text(String(format: "%.4f, %.4f", component.lat, component.lng))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Actions
            HStack(spacing: 12) {
                if component.actions?.contains("directions") ?? true {
                    Button {
                        openDirections()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            Text("Directions")
                        }
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button {
                    copyCoordinates()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func openDirections() {
        let urlString = "http://maps.apple.com/?daddr=\(component.lat),\(component.lng)"
        if let url = URL(string: urlString) {
            openURL(url)
        }
        onAction(component.id, "directions")
    }

    private func copyCoordinates() {
        UIPasteboard.general.string = "\(component.lat), \(component.lng)"
        let impact = UINotificationFeedbackGenerator()
        impact.notificationOccurred(.success)
        onAction(component.id, "copied")
    }
}

// MARK: - Mail Compose View

struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let cc: [String]
    let bcc: [String]
    let subject: String
    let body: String
    let isHTML: Bool
    let onComplete: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients(recipients)
        composer.setCcRecipients(cc)
        composer.setBccRecipients(bcc)
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: isHTML)
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onComplete: (MFMailComposeResult) -> Void

        init(onComplete: @escaping (MFMailComposeResult) -> Void) {
            self.onComplete = onComplete
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onComplete(result)
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            InteractiveButtonView(
                component: try! JSONDecoder().decode(
                    ButtonComponent.self,
                    from: """
                    {"type":"button","id":"btn-1","label":"Confirm","action":"confirm","style":"primary","icon":"checkmark"}
                    """.data(using: .utf8)!
                )
            ) { id, action in
                print("Button \(id): \(action)")
            }

            InteractiveOptionsView(
                component: OptionsComponent(
                    type: "options",
                    id: "opt-1",
                    prompt: "Choose your preferred time:",
                    options: [
                        .init(id: "9am", label: "9:00 AM", description: "Morning slot", icon: "sun.max", selected: false),
                        .init(id: "2pm", label: "2:00 PM", description: "Afternoon slot", icon: "sun.haze", selected: false),
                        .init(id: "5pm", label: "5:00 PM", description: "Evening slot", icon: "moon", selected: false)
                    ],
                    allowMultiple: false,
                    required: true
                )
            ) { id, action in
                print("Options \(id): \(action)")
            }
        }
        .padding()
    }
    .background(Color(.systemBackground))
}
