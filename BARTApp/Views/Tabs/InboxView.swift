import SwiftUI
import Combine

// MARK: - Inbox Item Types

enum InboxSource: String, CaseIterable {
    case imessage = "iMessage"
    case signal = "Signal"
    case email = "Email"
    
    var icon: String {
        switch self {
        case .imessage: return "message.fill"
        case .signal: return "lock.shield.fill"
        case .email: return "envelope.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .imessage: return .green
        case .signal: return Color(red: 0.23, green: 0.47, blue: 0.87)
        case .email: return .blue
        }
    }
}

enum InboxPriority: Int, CaseIterable {
    case urgent = 0
    case important = 1
    case normal = 2
    case low = 3
    
    var label: String {
        switch self {
        case .urgent: return "Urgent"
        case .important: return "Important"
        case .normal: return "Normal"
        case .low: return "Low Priority"
        }
    }
    
    var color: Color {
        switch self {
        case .urgent: return .red
        case .important: return .orange
        case .normal: return .blue
        case .low: return .gray
        }
    }
}

struct InboxItem: Identifiable, Hashable {
    let id: String
    let sender: String
    let senderAvatar: String?
    let subject: String?
    let preview: String
    let timestamp: Date
    let source: InboxSource
    let priority: InboxPriority
    let isRead: Bool
    let isStarred: Bool
    let threadCount: Int
    
    init(
        id: String = UUID().uuidString,
        sender: String,
        senderAvatar: String? = nil,
        subject: String? = nil,
        preview: String,
        timestamp: Date = Date(),
        source: InboxSource,
        priority: InboxPriority = .normal,
        isRead: Bool = false,
        isStarred: Bool = false,
        threadCount: Int = 1
    ) {
        self.id = id
        self.sender = sender
        self.senderAvatar = senderAvatar
        self.subject = subject
        self.preview = preview
        self.timestamp = timestamp
        self.source = source
        self.priority = priority
        self.isRead = isRead
        self.isStarred = isStarred
        self.threadCount = threadCount
    }
    
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Inbox ViewModel

@MainActor
class InboxViewModel: ObservableObject {
    @Published var items: [InboxItem] = []
    @Published var isLoading = false
    @Published var selectedFilter: InboxFilter = .all
    @Published var searchText = ""
    
    enum InboxFilter: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case starred = "Starred"
        
        var icon: String {
            switch self {
            case .all: return "tray.full"
            case .unread: return "envelope.badge"
            case .starred: return "star"
            }
        }
    }
    
    var filteredItems: [InboxItem] {
        var result = items
        
        switch selectedFilter {
        case .all:
            break
        case .unread:
            result = result.filter { !$0.isRead }
        case .starred:
            result = result.filter { $0.isStarred }
        }
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.sender.localizedCaseInsensitiveContains(searchText) ||
                $0.preview.localizedCaseInsensitiveContains(searchText) ||
                ($0.subject?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        return result
    }
    
    var urgentItems: [InboxItem] {
        filteredItems.filter { $0.priority == .urgent }
    }
    
    var importantItems: [InboxItem] {
        filteredItems.filter { $0.priority == .important }
    }
    
    var normalItems: [InboxItem] {
        filteredItems.filter { $0.priority == .normal || $0.priority == .low }
    }
    
    func loadItems() async {
        isLoading = true
        try? await Task.sleep(nanoseconds: 300_000_000)
        items = Self.mockItems()
        isLoading = false
    }
    
    func markAsRead(_ item: InboxItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = InboxItem(
                id: item.id,
                sender: item.sender,
                senderAvatar: item.senderAvatar,
                subject: item.subject,
                preview: item.preview,
                timestamp: item.timestamp,
                source: item.source,
                priority: item.priority,
                isRead: true,
                isStarred: item.isStarred,
                threadCount: item.threadCount
            )
        }
    }
    
    func toggleStar(_ item: InboxItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = InboxItem(
                id: item.id,
                sender: item.sender,
                senderAvatar: item.senderAvatar,
                subject: item.subject,
                preview: item.preview,
                timestamp: item.timestamp,
                source: item.source,
                priority: item.priority,
                isRead: item.isRead,
                isStarred: !item.isStarred,
                threadCount: item.threadCount
            )
        }
    }
    
    func archive(_ item: InboxItem) {
        withAnimation(.spring(response: 0.3)) {
            items.removeAll { $0.id == item.id }
        }
    }
    
    static func mockItems() -> [InboxItem] {
        let now = Date()
        return [
            InboxItem(
                sender: "Sarah Chen",
                subject: "Urgent: Server outage detected",
                preview: "We are seeing a spike in errors on production. Can you take a look ASAP?",
                timestamp: now.addingTimeInterval(-300),
                source: .email,
                priority: .urgent,
                threadCount: 3
            ),
            InboxItem(
                sender: "Mom",
                preview: "Do not forget dinner tomorrow at 7!",
                timestamp: now.addingTimeInterval(-1800),
                source: .imessage,
                priority: .important
            ),
            InboxItem(
                sender: "Alex Thompson",
                subject: "Re: Q4 Planning",
                preview: "Great points on the roadmap. I have updated the doc with my feedback.",
                timestamp: now.addingTimeInterval(-3600),
                source: .email,
                priority: .important,
                threadCount: 8
            ),
            InboxItem(
                sender: "Signal Group: Family",
                preview: "Mike: Who is bringing dessert?",
                timestamp: now.addingTimeInterval(-7200),
                source: .signal,
                priority: .normal
            ),
            InboxItem(
                sender: "John from Work",
                preview: "Sounds good, let us sync tomorrow morning",
                timestamp: now.addingTimeInterval(-14400),
                source: .imessage,
                priority: .normal,
                isRead: true
            ),
            InboxItem(
                sender: "GitHub",
                subject: "[openclaw/agent] PR #1234 merged",
                preview: "Your pull request has been successfully merged into main.",
                timestamp: now.addingTimeInterval(-28800),
                source: .email,
                priority: .low,
                isRead: true
            ),
        ]
    }
}

// MARK: - Inbox View

struct InboxView: View {
    @StateObject private var viewModel = InboxViewModel()
    @State private var showingItemDetail: InboxItem?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1).opacity(0.8),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    searchBar
                    filterPicker
                    
                    if viewModel.isLoading && viewModel.items.isEmpty {
                        loadingView
                    } else if viewModel.filteredItems.isEmpty {
                        emptyView
                    } else {
                        inboxList
                    }
                }
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .task {
                await viewModel.loadItems()
            }
            .refreshable {
                await viewModel.loadItems()
            }
            .sheet(item: $showingItemDetail) { item in
                InboxItemDetailSheet(item: item, viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search messages", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
            
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var filterPicker: some View {
        HStack(spacing: 8) {
            ForEach(InboxViewModel.InboxFilter.allCases, id: \.self) { filter in
                filterButton(filter)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private func filterButton(_ filter: InboxViewModel.InboxFilter) -> some View {
        Button {
            withAnimation(.spring(response: 0.2)) {
                viewModel.selectedFilter = filter
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.caption)
                Text(filter.rawValue)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                viewModel.selectedFilter == filter ?
                Capsule().fill(.thinMaterial) :
                Capsule().fill(Color.clear)
            )
            .overlay(
                viewModel.selectedFilter == filter ?
                Capsule().stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                ) : nil
            )
            .foregroundStyle(viewModel.selectedFilter == filter ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }
    
    private var inboxList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                if !viewModel.urgentItems.isEmpty {
                    Section {
                        ForEach(viewModel.urgentItems) { item in
                            inboxRow(item)
                        }
                    } header: {
                        sectionHeader("URGENT", color: .red, count: viewModel.urgentItems.count)
                    }
                }
                
                if !viewModel.importantItems.isEmpty {
                    Section {
                        ForEach(viewModel.importantItems) { item in
                            inboxRow(item)
                        }
                    } header: {
                        sectionHeader("IMPORTANT", color: .orange, count: viewModel.importantItems.count)
                    }
                }
                
                if !viewModel.normalItems.isEmpty {
                    Section {
                        ForEach(viewModel.normalItems) { item in
                            inboxRow(item)
                        }
                    } header: {
                        sectionHeader("EVERYTHING ELSE", color: .gray, count: viewModel.normalItems.count)
                    }
                }
            }
            .padding(.bottom, 100)
        }
    }
    
    private func sectionHeader(_ title: String, color: Color, count: Int) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            
            Text("\(count)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
    
    private func inboxRow(_ item: InboxItem) -> some View {
        InboxRowView(
            item: item,
            onTap: {
                viewModel.markAsRead(item)
                showingItemDetail = item
            },
            onStar: {
                viewModel.toggleStar(item)
            },
            onArchive: {
                viewModel.archive(item)
            }
        )
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            Text("Loading inbox...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)
            
            Text("Inbox Zero")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            
            Text("You are all caught up")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Inbox Row View

struct InboxRowView: View {
    let item: InboxItem
    let onTap: () -> Void
    let onStar: () -> Void
    let onArchive: () -> Void
    
    @State private var offset: CGFloat = 0
    
    var body: some View {
        ZStack {
            HStack {
                HStack {
                    Image(systemName: "archivebox.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                    Text("Archive")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 20)
                .background(Color.green)
                
                Spacer()
                
                HStack {
                    Text(item.isStarred ? "Unstar" : "Star")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Image(systemName: item.isStarred ? "star.slash.fill" : "star.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 20)
                .background(Color.orange)
            }
            
            rowContent
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = value.translation.width
                        }
                        .onEnded { value in
                            if offset > 100 {
                                withAnimation(.spring(response: 0.3)) {
                                    offset = UIScreen.main.bounds.width
                                }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    onArchive()
                                }
                            } else if offset < -100 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onStar()
                                withAnimation(.spring(response: 0.3)) {
                                    offset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.3)) {
                                    offset = 0
                                }
                            }
                        }
                )
        }
    }
    
    private var rowContent: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(item.source.color.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: item.source.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(item.source.color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.sender)
                            .font(.subheadline.weight(item.isRead ? .regular : .semibold))
                            .foregroundStyle(item.isRead ? Color.secondary : Color.white)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if item.isStarred {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        
                        Text(item.relativeTime)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    
                    if let subject = item.subject {
                        Text(subject)
                            .font(.subheadline.weight(item.isRead ? .regular : .medium))
                            .foregroundStyle(item.isRead ? Color.secondary : Color.white)
                            .lineLimit(1)
                    }
                    
                    HStack {
                        Text(item.preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        if item.threadCount > 1 {
                            Spacer()
                            Text("\(item.threadCount)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.thinMaterial))
                        }
                    }
                }
                
                if !item.isRead {
                    Circle()
                        .fill(item.priority.color)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inbox Item Detail Sheet

struct InboxItemDetailSheet: View {
    let item: InboxItem
    @ObservedObject var viewModel: InboxViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(item.source.color.opacity(0.2))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: item.source.icon)
                                .font(.title2)
                                .foregroundStyle(item.source.color)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.sender)
                                .font(.headline)
                                .foregroundStyle(.white)
                            
                            HStack(spacing: 6) {
                                Text(item.source.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(item.source.color)
                                
                                Text("•")
                                    .foregroundStyle(.tertiary)
                                
                                Text(item.relativeTime)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button {
                            viewModel.toggleStar(item)
                        } label: {
                            Image(systemName: item.isStarred ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundStyle(item.isStarred ? .orange : .secondary)
                        }
                    }
                    
                    Divider().background(Color.white.opacity(0.2))
                    
                    if let subject = item.subject {
                        Text(subject)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    
                    Text(item.preview)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                    
                    Spacer(minLength: 40)
                    
                    HStack(spacing: 12) {
                        actionButton(icon: "arrowshape.turn.up.left.fill", label: "Reply")
                        actionButton(icon: "arrowshape.turn.up.forward.fill", label: "Forward")
                        actionButton(icon: "archivebox.fill", label: "Archive") {
                            viewModel.archive(item)
                            dismiss()
                        }
                    }
                }
                .padding()
            }
            .background(.ultraThinMaterial)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func actionButton(icon: String, label: String, action: (() -> Void)? = nil) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action?()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    InboxView()
}
