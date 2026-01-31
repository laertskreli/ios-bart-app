import SwiftUI

struct TabbedChatView: View {
    @EnvironmentObject var gateway: GatewayConnection
    @State private var selectedTab: String = "main"
    @Namespace private var tabAnimation

    private var runningSubAgents: [SubAgentInfo] {
        gateway.subAgents.filter { $0.status == .running }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    ChatThreadView(sessionKey: "main", title: "BART")
                        .tag("main")

                    ForEach(runningSubAgents) { subAgent in
                        ChatThreadView(sessionKey: subAgent.sessionKey, title: subAgent.label)
                            .tag(subAgent.sessionKey)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                customTabBar
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionStatusView(state: gateway.connectionState)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(currentTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: gateway.subAgents) { _, newAgents in
            if let newest = newAgents.last, newest.status == .running {
                withAnimation(.spring(response: 0.3)) {
                    selectedTab = newest.sessionKey
                }
            }
        }
    }

    private var currentTitle: String {
        if selectedTab == "main" {
            return "BART"
        }
        return runningSubAgents.first { $0.sessionKey == selectedTab }?.label ?? "Chat"
    }

    private var customTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TabButton(
                    title: "BART",
                    icon: "brain.head.profile",
                    isSelected: selectedTab == "main",
                    namespace: tabAnimation
                ) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = "main"
                    }
                }

                ForEach(runningSubAgents) { subAgent in
                    TabButton(
                        title: subAgent.label,
                        icon: "bubble.left.and.bubble.right",
                        isSelected: selectedTab == subAgent.sessionKey,
                        namespace: tabAnimation,
                        showBadge: subAgent.status == .running
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedTab = subAgent.sessionKey
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var namespace: Namespace.ID
    var showBadge: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if showBadge {
                    PulsingDot(color: .green)
                }
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "selectedTab", in: namespace)
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TabbedChatView()
        .environmentObject(GatewayConnection(gatewayHost: "localhost"))
}
