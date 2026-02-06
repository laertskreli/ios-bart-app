import SwiftUI

/// A header component with variable blur intensity based on scroll position
/// Provides dynamic liquid glass effect that responds to content scrolling
struct LiquidGlassHeader: View {
    let title: String
    var scrollOffset: CGFloat = 0
    var height: CGFloat = 44
    var showDivider: Bool = true
    
    /// Blur intensity increases as you scroll down (0 to 1)
    private var blurIntensity: CGFloat {
        min(1, max(0, scrollOffset / 100))
    }
    
    /// Title opacity fades in as you scroll
    private var titleOpacity: CGFloat {
        min(1, max(0, (scrollOffset - 20) / 60))
    }
    
    var body: some View {
        ZStack {
            // Variable blur background
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(blurIntensity)
            
            // Subtle border at bottom
            if showDivider {
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(.white.opacity(0.1 * blurIntensity))
                        .frame(height: 0.5)
                }
            }
            
            // Title with fade-in effect
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .opacity(titleOpacity)
        }
        .frame(height: height)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: scrollOffset)
    }
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Scrollable Header Container

/// A container view that provides scroll offset tracking for LiquidGlassHeader
struct LiquidGlassScrollView<Content: View>: View {
    let title: String
    let content: Content
    @State private var scrollOffset: CGFloat = 0
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    // Scroll offset tracker
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: -geometry.frame(in: .named("scroll")).minY
                            )
                    }
                    .frame(height: 0)
                    
                    content
                }
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
            
            // Floating glass header
            LiquidGlassHeader(title: title, scrollOffset: scrollOffset)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Preview

#Preview {
    LiquidGlassScrollView(title: "Messages") {
        LazyVStack(spacing: 12) {
            ForEach(0..<20) { i in
                LiquidGlassCard {
                    HStack {
                        Circle()
                            .fill(.blue.opacity(0.3))
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading) {
                            Text("Message \(i + 1)")
                                .font(.headline)
                            Text("This is a sample message")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 60)
    }
    .background(
        LinearGradient(
            colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
