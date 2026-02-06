import SwiftUI

/// A button style with liquid glass material effect
struct LiquidGlassButtonStyle: ButtonStyle {
    var material: Material = .ultraThinMaterial
    var cornerRadius: CGFloat = 12
    var horizontalPadding: CGFloat = 20
    var verticalPadding: CGFloat = 12
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(configuration.isPressed ? 0.2 : 0.1), lineWidth: 0.5)
            )
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.1 : 0.2),
                radius: configuration.isPressed ? 5 : 10,
                y: configuration.isPressed ? 2 : 5
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Convenience Extension

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle { LiquidGlassButtonStyle() }
    
    static func liquidGlass(
        material: Material = .ultraThinMaterial,
        cornerRadius: CGFloat = 12
    ) -> LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(material: material, cornerRadius: cornerRadius)
    }
}

// MARK: - Icon Button

/// A circular icon button with liquid glass effect
struct LiquidGlassIconButton: View {
    let systemName: String
    let action: () -> Void
    
    var size: CGFloat = 44
    var iconSize: CGFloat = 20
    var material: Material = .ultraThinMaterial
    var haptic: Bool = true
    
    @State private var isPressed = false
    
    var body: some View {
        Button {
            if haptic {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            }
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .frame(width: size, height: size)
                .background(material, in: Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Primary Action Button

/// A prominent action button with tinted glass effect
struct LiquidGlassPrimaryButton: View {
    let title: String
    let action: () -> Void
    
    var icon: String? = nil
    var tint: Color = .blue
    var isLoading: Bool = false
    var haptic: Bool = true
    
    var body: some View {
        Button {
            if haptic && !isLoading {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            }
            if !isLoading {
                action()
            }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(tint.gradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial.opacity(0.3))
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: tint.opacity(0.4), radius: 15, y: 8)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isLoading)
    }
}

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LiquidGlassBackground()
        
        VStack(spacing: 24) {
            // Standard button style
            Button("Liquid Glass Button") {}
                .buttonStyle(.liquidGlass)
            
            // Icon buttons
            HStack(spacing: 16) {
                LiquidGlassIconButton(systemName: "plus") {}
                LiquidGlassIconButton(systemName: "mic.fill") {}
                LiquidGlassIconButton(systemName: "paperplane.fill") {}
            }
            
            // Primary action
            LiquidGlassPrimaryButton(title: "Send Message", icon: "paperplane.fill") {}
            
            // Loading state
            LiquidGlassPrimaryButton(title: "Sending...", isLoading: true) {}
        }
        .padding()
    }
}
