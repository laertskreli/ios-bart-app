import SwiftUI
import UIKit

// MARK: - Main Resolved Component View

struct ResolvedComponentView: View {
    let component: ResolvedComponent
    let onAction: (String, String) -> Void

    var body: some View {
        switch component {
        case .calendarSchedule(let data):
            ResolvedScheduleView(data: data, onAction: onAction)
        case .tasks(let data):
            ResolvedTasksView(data: data, onAction: onAction)
        case .code(let data):
            ResolvedCodeView(data: data, onAction: onAction)
        case .contact(let data):
            ResolvedContactView(data: data, onAction: onAction)
        case .location(let data):
            ResolvedLocationView(data: data, onAction: onAction)
        case .linkPreview(let data):
            ResolvedLinkPreviewView(data: data, onAction: onAction)
        case .chart(let data):
            ResolvedChartView(data: data, onAction: onAction)
        case .file(let data):
            ResolvedFileView(data: data, onAction: onAction)
        case .form(let data):
            ResolvedFormView(data: data, onAction: onAction)
        case .buttonGroup(let data):
            ResolvedButtonGroupView(data: data, onAction: onAction)
        case .button(let data):
            ResolvedButtonView(data: data, onAction: onAction)
        case .options(let data):
            ResolvedOptionsView(data: data, onAction: onAction)
        case .emailDraft(let data):
            ResolvedEmailView(data: data, onAction: onAction)
        case .calendarEvent(let data):
            ResolvedEventView(data: data, onAction: onAction)
        }
    }
}

// MARK: - Schedule View

struct ResolvedScheduleView: View {
    let data: ResolvedCalendarSchedule
    let onAction: (String, String) -> Void

    @Environment(\.openURL) private var openURL
    @State private var selectedEvent: ResolvedCalendarEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 18, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(data.title)
                        .font(.headline)
                    if let date = data.date {
                        Text(formatDate(date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text("\(data.events.count) events")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            // Events
            VStack(spacing: 0) {
                ForEach(data.events) { event in
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        selectedEvent = event
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            // Time
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(event.time ?? "")
                                    .font(.system(.subheadline, design: .monospaced, weight: .medium))
                                if let durationStr = event.durationString {
                                    Text(durationStr)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                } else if let duration = event.duration {
                                    Text("\(duration)m")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .frame(width: 55, alignment: .trailing)

                            // Dot
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)

                            // Details
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)

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
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                }

                                if !event.attendees.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.2")
                                            .font(.system(size: 9))
                                        Text("\(event.attendees.count) attendee\(event.attendees.count == 1 ? "" : "s")")
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            // Join button or chevron
                            if let meetUrl = event.meetUrl, let url = URL(string: meetUrl) {
                                Button {
                                    openURL(url)
                                    onAction(data.id, "join:\(event.id)")
                                } label: {
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
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if event.id != data.events.last?.id {
                        Divider().padding(.leading, 75)
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackground)
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(event: event, scheduleId: data.id, onAction: onAction)
        }
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Event Detail Sheet

struct EventDetailSheet: View {
    let event: ResolvedCalendarEvent
    let scheduleId: String
    let onAction: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title section
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.title)
                            .font(.title2.bold())

                        if let subtitle = event.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    // Time section
                    VStack(alignment: .leading, spacing: 12) {
                        DetailRow(icon: "clock", title: "Time") {
                            VStack(alignment: .leading, spacing: 2) {
                                if let time = event.time {
                                    HStack(spacing: 4) {
                                        Text(time)
                                            .font(.subheadline)
                                        if let endTime = event.endTime {
                                            Text("–")
                                                .foregroundStyle(.secondary)
                                            Text(endTime)
                                                .font(.subheadline)
                                        }
                                    }
                                }
                                if let durationStr = event.durationString {
                                    Text("Duration: \(durationStr)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if let duration = event.duration {
                                    Text("Duration: \(duration) min")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let location = event.location {
                            DetailRow(icon: "mappin.circle", title: "Location") {
                                Text(location)
                                    .font(.subheadline)
                            }
                        }

                        if let account = event.account {
                            DetailRow(icon: "calendar", title: "Calendar") {
                                Text(account)
                                    .font(.subheadline)
                            }
                        }
                    }

                    // Attendees section
                    if !event.attendees.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 24)
                                Text("Attendees (\(event.attendees.count))")
                                    .font(.subheadline.bold())
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(event.attendees, id: \.self) { attendee in
                                    HStack(spacing: 10) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.accentColor.opacity(0.15))
                                            Text(attendeeInitial(attendee))
                                                .font(.caption.bold())
                                                .foregroundStyle(Color.accentColor)
                                        }
                                        .frame(width: 32, height: 32)

                                        Text(attendee)
                                            .font(.subheadline)
                                            .lineLimit(1)

                                        Spacer()

                                        Button {
                                            if let url = URL(string: "mailto:\(attendee)") {
                                                openURL(url)
                                            }
                                        } label: {
                                            Image(systemName: "envelope")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(.leading, 32)
                        }
                    }

                    // Description section
                    if let description = event.description, !description.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 24)
                                Text("Description")
                                    .font(.subheadline.bold())
                            }

                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 32)
                        }
                    }

                    // Action buttons
                    if event.meetUrl != nil {
                        Divider()

                        VStack(spacing: 12) {
                            if let meetUrl = event.meetUrl, let url = URL(string: meetUrl) {
                                Button {
                                    openURL(url)
                                    onAction(scheduleId, "join:\(event.id)")
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "video.fill")
                                        Text("Join Meeting")
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }

                            Button {
                                onAction(scheduleId, "addToCalendar:\(event.id)")
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "calendar.badge.plus")
                                    Text("Add to Calendar")
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.secondarySystemBackground))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func attendeeInitial(_ email: String) -> String {
        let name = email.components(separatedBy: "@").first ?? email
        return String(name.prefix(1)).uppercased()
    }
}

// MARK: - Detail Row Helper

private struct DetailRow<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                content
            }
        }
    }
}

// MARK: - Tasks View

struct ResolvedTasksView: View {
    let data: ResolvedTasks
    let onAction: (String, String) -> Void

    @State private var completedTasks: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 18, weight: .semibold))

                Text(data.title)
                    .font(.headline)

                Spacer()

                let doneCount = data.items.filter { $0.done || completedTasks.contains($0.id) }.count
                Text("\(doneCount)/\(data.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.systemGray5)))
            }

            Divider()

            VStack(spacing: 4) {
                ForEach(data.items) { item in
                    let isCompleted = item.done || completedTasks.contains(item.id)

                    Button {
                        toggleTask(item)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isCompleted ? Color.green : priorityColor(item.priority), lineWidth: 2)
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

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text)
                                    .font(.subheadline)
                                    .strikethrough(isCompleted)
                                    .foregroundStyle(isCompleted ? .secondary : .primary)

                                HStack(spacing: 8) {
                                    if let due = item.due {
                                        HStack(spacing: 4) {
                                            Image(systemName: "calendar")
                                                .font(.system(size: 9))
                                            Text(formatDue(due))
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(isOverdue(due) && !isCompleted ? .red : .secondary)
                                    }

                                    if let priority = item.priority, !isCompleted {
                                        Text(priorityText(priority))
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(priorityColor(priority).opacity(0.2)))
                                            .foregroundStyle(priorityColor(priority))
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
            }
        }
        .padding(14)
        .background(cardBackground)
        .onAppear {
            for item in data.items where item.done {
                completedTasks.insert(item.id)
            }
        }
    }

    private func toggleTask(_ item: ResolvedTaskItem) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        if completedTasks.contains(item.id) {
            completedTasks.remove(item.id)
            onAction(data.id, "uncomplete:\(item.id)")
        } else {
            completedTasks.insert(item.id)
            onAction(data.id, "complete:\(item.id)")
        }
    }

    private func priorityColor(_ priority: ResolvedTaskItem.Priority?) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        case .none: return .gray
        }
    }

    private func priorityText(_ priority: ResolvedTaskItem.Priority) -> String {
        switch priority {
        case .high: return "HIGH"
        case .medium: return "MED"
        case .low: return "LOW"
        }
    }

    private func formatDue(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }

        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }

        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func isOverdue(_ dateString: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return false }
        return date < Date() && !Calendar.current.isDateInToday(date)
    }
}

// MARK: - Code View

struct ResolvedCodeView: View {
    let data: ResolvedCode
    let onAction: (String, String) -> Void

    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if let filename = data.filename {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(filename)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }

                if let language = data.language {
                    Text(language)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(.systemGray5)))
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = data.code
                    let impact = UINotificationFeedbackGenerator()
                    impact.notificationOccurred(.success)
                    showCopied = true
                    onAction(data.id, "copied")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopied = false
                    }
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
                    if data.showLineNumbers {
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

                    Text(data.code)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, data.showLineNumbers ? 0 : 12)
                }
                .padding(.vertical, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var lineCount: Int {
        data.code.components(separatedBy: "\n").count
    }
}

// MARK: - Contact View

struct ResolvedContactView: View {
    let data: ResolvedContact
    let onAction: (String, String) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            if let avatarURL = data.avatar, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsView
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                initialsView
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(data.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let role = data.role {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if let phone = data.phone {
                    Button {
                        if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                            openURL(url)
                        }
                        onAction(data.id, "call")
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.green))
                    }
                }

                if let email = data.email {
                    Button {
                        if let url = URL(string: "mailto:\(email)") {
                            openURL(url)
                        }
                        onAction(data.id, "email")
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
        .background(cardBackground)
    }

    private var initialsView: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.2))
            Text(initials)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 50, height: 50)
    }

    private var initials: String {
        let parts = data.name.components(separatedBy: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? parts.last?.first.map(String.init) ?? "" : ""
        return (first + last).uppercased()
    }
}

// MARK: - Location View

struct ResolvedLocationView: View {
    let data: ResolvedLocation
    let onAction: (String, String) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Map placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(height: 100)

                VStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)

                    if let name = data.name {
                        Text(name)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }

            if let address = data.address {
                HStack(spacing: 8) {
                    Image(systemName: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(address)
                        .font(.subheadline)
                }
            }

            Text(String(format: "%.4f, %.4f", data.lat, data.lng))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                Button {
                    let urlString = "http://maps.apple.com/?daddr=\(data.lat),\(data.lng)"
                    if let url = URL(string: urlString) {
                        openURL(url)
                    }
                    onAction(data.id, "directions")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        Text("Directions")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    UIPasteboard.general.string = "\(data.lat), \(data.lng)"
                    let impact = UINotificationFeedbackGenerator()
                    impact.notificationOccurred(.success)
                    onAction(data.id, "copied")
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
        .background(cardBackground)
    }
}

// MARK: - Link Preview View

struct ResolvedLinkPreviewView: View {
    let data: ResolvedLinkPreview
    let onAction: (String, String) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: data.url) {
                openURL(url)
                onAction(data.id, "opened")
            }
        } label: {
            HStack(spacing: 12) {
                if let imageURL = data.image, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray5))
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray5))
                        Image(systemName: "link")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 60, height: 60)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let title = data.title {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if let description = data.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                        Text(data.domain ?? URL(string: data.url)?.host ?? data.url)
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
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chart View

struct ResolvedChartView: View {
    let data: ResolvedChart
    let onAction: (String, String) -> Void

    private var maxValue: Double {
        data.data.map(\.value).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = data.title {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(title)
                        .font(.headline)
                }
            }

            switch data.chartType {
            case .bar:
                barChart
            case .pie:
                pieChart
            case .line:
                barChart // Fallback
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var barChart: some View {
        VStack(spacing: 8) {
            ForEach(data.data) { point in
                HStack(spacing: 8) {
                    Text(point.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)

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

    private var pieChart: some View {
        let total = data.data.map(\.value).reduce(0, +)
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .yellow, .red, .cyan]

        return HStack(spacing: 16) {
            ZStack {
                ForEach(Array(data.data.enumerated()), id: \.element.id) { index, point in
                    Circle()
                        .trim(from: startAngle(for: index, total: total),
                              to: endAngle(for: index, total: total))
                        .stroke(colors[index % colors.count], lineWidth: 30)
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(data.data.enumerated()), id: \.element.id) { index, point in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(colors[index % colors.count])
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

    private func startAngle(for index: Int, total: Double) -> Double {
        data.data.prefix(index).map(\.value).reduce(0, +) / total
    }

    private func endAngle(for index: Int, total: Double) -> Double {
        data.data.prefix(index + 1).map(\.value).reduce(0, +) / total
    }

    private func formatValue(_ value: Double) -> String {
        value >= 1000 ? String(format: "%.1fK", value / 1000) : String(format: "%.0f", value)
    }
}

// MARK: - File View

struct ResolvedFileView: View {
    let data: ResolvedFile
    let onAction: (String, String) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(fileColor.opacity(0.15))
                Image(systemName: fileIcon)
                    .font(.title2)
                    .foregroundStyle(fileColor)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(data.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let size = data.size {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let urlStr = data.url, let url = URL(string: urlStr) {
                Button {
                    openURL(url)
                    onAction(data.id, "download")
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    private var fileIcon: String {
        let ext = data.name.components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "pdf": return "doc.text.fill"
        case "doc", "docx": return "doc.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "jpg", "jpeg", "png", "gif": return "photo.fill"
        case "mp4", "mov": return "film.fill"
        case "zip", "rar": return "doc.zipper"
        default: return "doc.fill"
        }
    }

    private var fileColor: Color {
        let ext = data.name.components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx": return .green
        case "jpg", "jpeg", "png", "gif": return .purple
        case "zip", "rar": return .brown
        default: return .gray
        }
    }
}

// MARK: - Form View

struct ResolvedFormView: View {
    let data: ResolvedForm
    let onAction: (String, String) -> Void

    @State private var values: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = data.title {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Color.accentColor)
                    Text(title)
                        .font(.headline)
                }
            }

            VStack(spacing: 12) {
                ForEach(data.fields) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(field.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if field.required {
                                Text("*").foregroundStyle(.red).font(.caption)
                            }
                        }

                        fieldInput(for: field)
                    }
                }
            }

            Button {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                if let json = try? JSONSerialization.data(withJSONObject: values),
                   let str = String(data: json, encoding: .utf8) {
                    onAction(data.id, "submit:\(str)")
                }
            } label: {
                Text(data.submitLabel)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    @ViewBuilder
    private func fieldInput(for field: ResolvedFormField) -> some View {
        switch field.type {
        case .text, .email, .phone, .number, .date:
            TextField(field.placeholder ?? "", text: binding(for: field.id))
                .textFieldStyle(.roundedBorder)

        case .textarea:
            TextField(field.placeholder ?? "", text: binding(for: field.id), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

        case .select:
            Menu {
                ForEach(field.options ?? [], id: \.self) { option in
                    Button(option) { values[field.id] = option }
                }
            } label: {
                HStack {
                    Text(values[field.id]?.isEmpty ?? true ? (field.placeholder ?? "Select...") : values[field.id]!)
                        .foregroundStyle(values[field.id]?.isEmpty ?? true ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 1))
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }
}

// MARK: - Button Group View

struct ResolvedButtonGroupView: View {
    let data: ResolvedButtonGroup
    let onAction: (String, String) -> Void

    var body: some View {
        Group {
            switch data.layout {
            case .horizontal:
                HStack(spacing: 8) {
                    ForEach(data.buttons) { button in
                        ResolvedButtonView(data: button, onAction: onAction)
                    }
                }
            case .vertical:
                VStack(spacing: 8) {
                    ForEach(data.buttons) { button in
                        ResolvedButtonView(data: button, onAction: onAction)
                    }
                }
            case .grid:
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(data.buttons) { button in
                        ResolvedButtonView(data: button, onAction: onAction)
                    }
                }
            }
        }
    }
}

// MARK: - Button View

struct ResolvedButtonView: View {
    let data: ResolvedButton
    let onAction: (String, String) -> Void

    var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onAction(data.id, data.action)
        } label: {
            HStack(spacing: 8) {
                if let icon = data.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                }
                Text(data.label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(buttonBackground)
            .foregroundStyle(buttonForeground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var buttonBackground: some View {
        Group {
            switch data.style {
            case .primary:
                Color.accentColor
            case .danger:
                Color.red
            case .secondary:
                Color(.systemGray5)
            }
        }
    }

    private var buttonForeground: Color {
        switch data.style {
        case .primary, .danger: return .white
        case .secondary: return .primary
        }
    }
}

// MARK: - Options View

struct ResolvedOptionsView: View {
    let data: ResolvedOptions
    let onAction: (String, String) -> Void

    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let prompt = data.prompt {
                Text(prompt)
                    .font(.subheadline.weight(.medium))
            }

            VStack(spacing: 4) {
                ForEach(data.options) { option in
                    let isSelected = selected.contains(option.id)

                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()

                        if data.allowMultiple {
                            if isSelected { selected.remove(option.id) }
                            else { selected.insert(option.id) }
                        } else {
                            selected = [option.id]
                            onAction(data.id, "selected:\(option.id)")
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                if data.allowMultiple {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 1.5)
                                        .frame(width: 20, height: 20)
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 4).fill(Color.accentColor).frame(width: 20, height: 20)
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                    }
                                } else {
                                    Circle()
                                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 1.5)
                                        .frame(width: 20, height: 20)
                                    if isSelected {
                                        Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                                    }
                                }
                            }

                            if let icon = option.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label).font(.subheadline)
                                if let desc = option.description {
                                    Text(desc).font(.caption).foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if data.allowMultiple {
                Button {
                    onAction(data.id, "selected:\(Array(selected).joined(separator: ","))")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Confirm")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selected.isEmpty)
            }
        }
        .padding(12)
        .background(cardBackground)
    }
}

// MARK: - Email View

struct ResolvedEmailView: View {
    let data: ResolvedEmailDraft
    let onAction: (String, String) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Email Draft")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text("To:").font(.caption).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                    Text(data.to.joined(separator: ", ")).font(.subheadline).lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text("Subject:").font(.caption).foregroundStyle(.secondary)
                    Text(data.subject).font(.subheadline.weight(.medium)).lineLimit(1)
                }
            }

            Text(data.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6).opacity(0.5)))

            HStack(spacing: 8) {
                Button {
                    let mailto = "mailto:\(data.to.joined(separator: ","))?subject=\(data.subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(data.body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                    if let url = URL(string: mailto) {
                        openURL(url)
                    }
                    onAction(data.id, "open")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane")
                        Text("Open in Mail")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    UIPasteboard.general.string = data.body
                    let impact = UINotificationFeedbackGenerator()
                    impact.notificationOccurred(.success)
                    onAction(data.id, "copied")
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
        .background(cardBackground)
    }
}

// MARK: - Event View

struct ResolvedEventView: View {
    let data: ResolvedCalendarEvent
    let onAction: (String, String) -> Void

    @Environment(\.openURL) private var openURL
    @State private var showDetail = false

    var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(Color.accentColor)
                    Text(data.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let time = data.time {
                    HStack(spacing: 8) {
                        Image(systemName: "clock").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text(time).font(.subheadline)
                            if let endTime = data.endTime {
                                Text("–").foregroundStyle(.secondary)
                                Text(endTime).font(.subheadline)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                if let location = data.location {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin").font(.caption).foregroundStyle(.secondary)
                        Text(location).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if !data.attendees.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2").font(.caption).foregroundStyle(.secondary)
                        Text("\(data.attendees.count) attendee\(data.attendees.count == 1 ? "" : "s")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if let subtitle = data.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let meetUrl = data.meetUrl, let url = URL(string: meetUrl) {
                    Button {
                        openURL(url)
                        onAction(data.id, "join")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                            Text("Join Meeting")
                        }
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(14)
            .background(cardBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            EventDetailSheet(event: data, scheduleId: data.id, onAction: onAction)
        }
    }
}

// MARK: - Shared Components

private struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemBackground))
    }
}

private var cardBackground: some View {
    CardBackground()
}
