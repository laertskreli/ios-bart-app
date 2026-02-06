import SwiftUI

/// A view modifier that applies variable blur based on scroll position
/// Use with ScrollView to create dynamic glass effects
struct ScrollBlurModifier: ViewModifier {
    let scrollOffset: CGFloat
    var maxBlurRadius: CGFloat = 20
    var activationThreshold: CGFloat = 50
    var material: Material = .ultraThinMaterial
    
    private var blurProgress: CGFloat {
        guard scrollOffset > 0 else { return 0 }
        return min(1, scrollOffset / activationThreshold)
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                material
                    .opacity(blurProgress)
            )
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: blurProgress)
    }
}

// MARK: - View Extension

extension View {
    /// Applies a scroll-responsive blur effect
    /// - Parameters:
    ///   - scrollOffset: Current scroll offset (positive when scrolled down)
    ///   - maxBlurRadius: Maximum blur radius when fully activated
    ///   - activationThreshold: Scroll distance required for full blur
    ///   - material: The material to use for the blur effect
    func scrollBlur(
        offset: CGFloat,
        maxBlurRadius: CGFloat = 20,
        activationThreshold: CGFloat = 50,
        material: Material = .ultraThinMaterial
    ) -> some View {
        modifier(ScrollBlurModifier(
            scrollOffset: offset,
            maxBlurRadius: maxBlurRadius,
            activationThreshold: activationThreshold,
            material: material
        ))
    }
}

// MARK: - Scroll Offset Reader

/// A preference key for tracking scroll offset
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A view that tracks and reports scroll offset
struct ScrollOffsetReader: View {
    let coordinateSpace: String
    
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(
                    key: ScrollOffsetKey.self,
                    value: -geometry.frame(in: .named(coordinateSpace)).minY
                )
        }
        .frame(height: 0)
    }
}

// MARK: - Scroll View with Blur Header

/// A convenience wrapper that provides scroll-blurred header functionality
struct BlurredHeaderScrollView<Header: View, Content: View>: View {
    let header: Header
    let content: Content
    
    @State private var scrollOffset: CGFloat = 0
    
    private let coordinateSpace = "blurredScroll"
    
    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header()
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    ScrollOffsetReader(coordinateSpace: coordinateSpace)
                    content
                }
            }
            .coordinateSpace(name: coordinateSpace)
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                scrollOffset = value
            }
            
            header
                .scrollBlur(offset: scrollOffset)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Vibrancy Text Modifier

/// Applies vibrancy effect to text for better readability on glass
struct VibrancyTextModifier: ViewModifier {
    var style: VibrancyStyle = .primary
    
    enum VibrancyStyle {
        case primary
        case secondary
        case tertiary
        
        var opacity: CGFloat {
            switch self {
            case .primary: return 1.0
            case .secondary: return 0.7
            case .tertiary: return 0.5
            }
        }
    }
    
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary.opacity(style.opacity))
    }
}

extension View {
    func vibrancyText(_ style: VibrancyTextModifier.VibrancyStyle = .primary) -> some View {
        modifier(VibrancyTextModifier(style: style))
    }
}

// MARK: - Preview

#Preview {
    BlurredHeaderScrollView {
        Text("Dynamic Header")
            .font(.headline)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
    } content: {
        LazyVStack(spacing: 12) {
            ForEach(0..<30) { i in
                LiquidGlassCard {
                    HStack {
                        Circle()
                            .fill(.blue.opacity(0.3))
                            .frame(width: 40, height: 40)
                        
                        VStack(alignment: .leading) {
                            Text("Item \(i + 1)")
                                .vibrancyText(.primary)
                            Text("Secondary info")
                                .font(.subheadline)
                                .vibrancyText(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 60)
        .padding(.bottom, 100)
    }
    .background(LiquidGlassBackground())
}
