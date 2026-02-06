import SwiftUI

// MARK: - Animated Gradient Background
/// Global background component for app-wide visual cohesion
/// Creates a subtle, animated gradient with dark theme colors

struct AnimatedGradientBackground: View {
    @State private var animateGradient = false
    
    var primaryColor: Color = .accentColor
    var secondaryColor: Color = .purple
    var baseColor: Color = Color(.systemBackground)
    
    var body: some View {
        ZStack {
            // Base dark layer
            Color.black
                .ignoresSafeArea()
            
            // Animated gradient overlay
            LinearGradient(
                colors: [
                    baseColor,
                    primaryColor.opacity(0.1),
                    secondaryColor.opacity(0.05)
                ],
                startPoint: animateGradient ? .topLeading : .bottomLeading,
                endPoint: animateGradient ? .bottomTrailing : .topTrailing
            )
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                    animateGradient = true
                }
            }
        }
    }
}

// MARK: - Dark Animated Background
/// Alternative simpler dark gradient background

struct DarkAnimatedBackground: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            // Subtle radial gradient pulse
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .scaleEffect(1 + phase * 0.1)
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
        }
    }
}

#Preview {
    AnimatedGradientBackground()
}
