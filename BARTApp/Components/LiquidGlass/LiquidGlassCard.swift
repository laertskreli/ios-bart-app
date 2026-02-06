import SwiftUI

/// A card component with real iOS liquid glass material effect
/// Uses .ultraThinMaterial for authentic translucency
struct LiquidGlassCard<Content: View>: View {
    let content: Content
    var blur: Material = .ultraThinMaterial
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16
    
    init(
        blur: Material = .ultraThinMaterial,
        cornerRadius: CGFloat = 20,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.blur = blur
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(blur, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }
}

// MARK: - Convenience Initializers

extension LiquidGlassCard {
    /// Creates a thin material card (slightly more opaque)
    static func thin(
        cornerRadius: CGFloat = 20,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) -> LiquidGlassCard {
        LiquidGlassCard(
            blur: .thinMaterial,
            cornerRadius: cornerRadius,
            padding: padding,
            content: content
        )
    }
    
    /// Creates a regular material card (most opaque)
    static func regular(
        cornerRadius: CGFloat = 20,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) -> LiquidGlassCard {
        LiquidGlassCard(
            blur: .regularMaterial,
            cornerRadius: cornerRadius,
            padding: padding,
            content: content
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(
            colors: [.purple, .blue, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        VStack(spacing: 20) {
            LiquidGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ultra Thin Material")
                        .font(.headline)
                    Text("Content shows through beautifully")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            LiquidGlassCard.thin {
                Text("Thin Material Card")
            }
            
            LiquidGlassCard.regular {
                Text("Regular Material Card")
            }
        }
        .padding()
    }
}
