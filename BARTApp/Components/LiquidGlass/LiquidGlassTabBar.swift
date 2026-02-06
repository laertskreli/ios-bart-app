import SwiftUI

/// Tab item model for LiquidGlassTabBar
struct LiquidGlassTab: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let selectedIcon: String?
    
    init(id: String, icon: String, title: String, selectedIcon: String? = nil) {
        self.id = id
        self.icon = icon
        self.title = title
        self.selectedIcon = selectedIcon
    }
    
    var displayIcon: String {
        selectedIcon ?? icon
    }
}

/// A floating tab bar with liquid glass effect
/// Floats above content - NOT attached to bottom edge
struct LiquidGlassTabBar: View {
    let tabs: [LiquidGlassTab]
    @Binding var selectedTab: String
    var hapticFeedback: Bool = true
    
    @Namespace private var tabNamespace
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
        .padding(.horizontal, 40)
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private func tabButton(for tab: LiquidGlassTab) -> some View {
        let isSelected = selectedTab == tab.id
        
        Button {
            if hapticFeedback {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            }
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                selectedTab = tab.id
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.displayIcon : tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                
                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .medium : .regular))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .matchedGeometryEffect(id: "selectedTab", in: tabNamespace)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab Bar Container

/// A view container that positions content with a floating glass tab bar
struct LiquidGlassTabContainer<Content: View>: View {
    let tabs: [LiquidGlassTab]
    @Binding var selectedTab: String
    let content: Content
    
    init(
        tabs: [LiquidGlassTab],
        selectedTab: Binding<String>,
        @ViewBuilder content: () -> Content
    ) {
        self.tabs = tabs
        self._selectedTab = selectedTab
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            LiquidGlassTabBar(tabs: tabs, selectedTab: $selectedTab)
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewContainer: View {
        @State private var selectedTab = "chat"
        
        let tabs: [LiquidGlassTab] = [
            LiquidGlassTab(id: "chat", icon: "bubble.left", title: "Chat", selectedIcon: "bubble.left.fill"),
            LiquidGlassTab(id: "calendar", icon: "calendar", title: "Calendar", selectedIcon: "calendar.circle.fill"),
            LiquidGlassTab(id: "tasks", icon: "checkmark.circle", title: "Tasks", selectedIcon: "checkmark.circle.fill"),
            LiquidGlassTab(id: "inbox", icon: "tray", title: "Inbox", selectedIcon: "tray.fill")
        ]
        
        var body: some View {
            LiquidGlassTabContainer(tabs: tabs, selectedTab: $selectedTab) {
                ZStack {
                    LiquidGlassBackground()
                    
                    VStack {
                        Text("Selected: \(selectedTab)")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
    
    return PreviewContainer()
}
