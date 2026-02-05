import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var gateway: GatewayConnection
    @State private var selectedTab: Tab = .chat
    
    enum Tab: String, CaseIterable {
        case chat = "Chat"
        case calendar = "Calendar"
        case tasks = "Tasks"
        case email = "Email"
        case trading = "Trading"
        case settings = "Settings"
        
        var icon: String {
            switch self {
            case .chat: return "bubble.left.and.bubble.right"
            case .calendar: return "calendar"
            case .tasks: return "checklist"
            case .email: return "envelope"
            case .trading: return "chart.line.uptrend.xyaxis"
            case .settings: return "gear"
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            TabbedChatView()
                .tabItem {
                    Label(Tab.chat.rawValue, systemImage: Tab.chat.icon)
                }
                .tag(Tab.chat)
            
            CalendarView()
                .tabItem {
                    Label(Tab.calendar.rawValue, systemImage: Tab.calendar.icon)
                }
                .tag(Tab.calendar)
            
            TasksView()
                .tabItem {
                    Label(Tab.tasks.rawValue, systemImage: Tab.tasks.icon)
                }
                .tag(Tab.tasks)
            
            EmailView()
                .tabItem {
                    Label(Tab.email.rawValue, systemImage: Tab.email.icon)
                }
                .tag(Tab.email)
            
            TradingView()
                .tabItem {
                    Label(Tab.trading.rawValue, systemImage: Tab.trading.icon)
                }
                .tag(Tab.trading)
            
            SettingsView()
                .tabItem {
                    Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
                }
                .tag(Tab.settings)
        }
        .tint(.white)
    }
}

#Preview {
    MainTabView()
        .environmentObject(GatewayConnection(gatewayHost: "localhost"))
}
