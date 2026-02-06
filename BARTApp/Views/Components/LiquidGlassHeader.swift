import SwiftUI

/// Liquid glass header overlay that creates iOS 26-style translucent blur effect
/// Content scrolling underneath appears warped/blurred through the glass
struct LiquidGlassHeader<Content: View>: View {
    let title: String?
    let subtitle: String?
    let leadingContent: (() -> Content)?
    let trailingContent: (() -> Content)?
    var height: CGFloat = 60
    var showDivider: Bool = false
    
    init(
        title: String? = nil,
        subtitle: String? = nil,
        height: CGFloat = 60,
        showDivider: Bool = false,
        @ViewBuilder leadingContent: @escaping () -> Content = { EmptyView() as! Content },
        @ViewBuilder trailingContent: @escaping () -> Content = { EmptyView() as! Content }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.height = height
        self.showDivider = showDivider
        self.leadingContent = leadingContent
        self.trailingContent = trailingContent
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Glass header area - extends into safe area
            ZStack {
                // Multi-layer glass effect for depth
                glassLayers
                
                // Header content
                VStack(spacing: 0) {
                    Spacer()
                    
                    HStack(spacing: 16) {
                        // Leading content (back button, etc)
                        if let leading = leadingContent {
                            leading()
                        }
                        
                        // Title area
                        if let title = title {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                if let subtitle = subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Trailing content (action buttons, etc)
                        if let trailing = trailingContent {
                            trailing()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .frame(height: height)
            
            // Optional subtle divider
            if showDivider {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.15),
                                .white.opacity(0.05),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 0.5)
            }
        }
    }
    
    private var glassLayers: some View {
        ZStack {
            // Base blur layer - this creates the frosted glass effect
            Rectangle()
                .fill(.ultraThinMaterial)
            
            // Dark tint for depth
            Rectangle()
                .fill(Color.black.opacity(0.3))
            
            // Subtle gradient overlay for liquid glass feel
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.1),
                            .clear,
                            .black.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Top edge highlight
            VStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.2),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 1)
                Spacer()
            }
        }
    }
}

// MARK: - Convenience initializer without generics

extension LiquidGlassHeader where Content == EmptyView {
    init(
        title: String? = nil,
        subtitle: String? = nil,
        height: CGFloat = 60,
        showDivider: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.height = height
        self.showDivider = showDivider
        self.leadingContent = nil
        self.trailingContent = nil
    }
}

// MARK: - Container view that applies liquid glass header with proper scroll behavior

struct LiquidGlassContainer<Header: View, Content: View>: View {
    let headerHeight: CGFloat
    let header: () -> Header
    let content: () -> Content
    
    init(
        headerHeight: CGFloat = 100,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.headerHeight = headerHeight
        self.header = header
        self.content = content
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Content that scrolls under the header
            content()
                .padding(.top, headerHeight)
            
            // Glass header overlay
            VStack(spacing: 0) {
                header()
                    .frame(height: headerHeight)
                    .background(
                        ZStack {
                            // Ultra thin material for the blur
                            Rectangle()
                                .fill(.ultraThinMaterial)
                            
                            // Dark tint
                            Rectangle()
                                .fill(Color.black.opacity(0.3))
                            
                            // Gradient overlay
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.08),
                                            .clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            
                            // Bottom border
                            VStack {
                                Spacer()
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 0.5)
                            }
                        }
                    )
                
                Spacer()
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - Simple header style for tabs

struct LiquidGlassTabHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailingButton: (() -> AnyView)? = nil
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            if let trailing = trailingButton {
                trailing()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Preview

struct LiquidGlassHeader_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [.purple.opacity(0.3), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Demo content
            LiquidGlassContainer(headerHeight: 100) {
                LiquidGlassTabHeader(title: "Messages", subtitle: "3 unread")
            } content: {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(0..<20, id: \.self) { i in
                            HStack {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 44, height: 44)
                                
                                VStack(alignment: .leading) {
                                    Text("Contact \(i)")
                                        .foregroundColor(.white)
                                    Text("Last message preview...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
