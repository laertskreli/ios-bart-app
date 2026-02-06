import SwiftUI

/// An animated mesh gradient background for liquid glass aesthetics
/// Provides subtle, continuously shifting depth
struct LiquidGlassBackground: View {
    @State private var animationPhase: CGFloat = 0
    
    var primaryColor: Color = .purple
    var secondaryColor: Color = .blue
    var tertiaryColor: Color = .indigo
    var animationDuration: Double = 8.0
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            Canvas { context, size in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                drawMeshGradient(context: context, size: size, phase: phase)
            }
        }
        .ignoresSafeArea()
        .overlay {
            // Subtle noise texture for depth
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.1)
        }
    }
    
    private func drawMeshGradient(context: GraphicsContext, size: CGSize, phase: Double) {
        let speed = 0.3
        let t = phase * speed
        
        // Create flowing gradient positions
        let points: [(CGPoint, Color)] = [
            (
                CGPoint(
                    x: size.width * (0.2 + 0.1 * sin(t)),
                    y: size.height * (0.2 + 0.1 * cos(t * 1.2))
                ),
                primaryColor.opacity(0.6)
            ),
            (
                CGPoint(
                    x: size.width * (0.8 + 0.1 * cos(t * 0.8)),
                    y: size.height * (0.3 + 0.1 * sin(t * 0.9))
                ),
                secondaryColor.opacity(0.5)
            ),
            (
                CGPoint(
                    x: size.width * (0.5 + 0.15 * sin(t * 0.7)),
                    y: size.height * (0.7 + 0.1 * cos(t * 1.1))
                ),
                tertiaryColor.opacity(0.6)
            ),
            (
                CGPoint(
                    x: size.width * (0.3 + 0.1 * cos(t * 1.3)),
                    y: size.height * (0.9 + 0.05 * sin(t))
                ),
                primaryColor.opacity(0.4)
            )
        ]
        
        // Draw radial gradients at each point
        for (point, color) in points {
            let radius = max(size.width, size.height) * 0.6
            let gradient = Gradient(colors: [
                color,
                color.opacity(0)
            ])
            
            context.fill(
                Circle().path(in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .radialGradient(
                    gradient,
                    center: point,
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }
        
        // Dark base layer
        context.fill(
            Rectangle().path(in: CGRect(origin: .zero, size: size)),
            with: .color(.black.opacity(0.85))
        )
    }
}

// MARK: - Static Gradient Background

/// A simpler static gradient for performance-sensitive areas
struct LiquidGlassStaticBackground: View {
    var colors: [Color] = [.purple.opacity(0.3), .blue.opacity(0.2), .indigo.opacity(0.3)]
    
    var body: some View {
        ZStack {
            Color.black
            
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 60)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Preview

#Preview("Animated") {
    ZStack {
        LiquidGlassBackground()
        
        VStack(spacing: 20) {
            LiquidGlassCard {
                Text("Animated Background")
                    .font(.headline)
            }
            
            LiquidGlassCard.thin {
                Text("Content floats on glass")
            }
        }
        .padding()
    }
}

#Preview("Static") {
    ZStack {
        LiquidGlassStaticBackground()
        
        Text("Static Background")
            .font(.largeTitle)
            .fontWeight(.bold)
    }
}
