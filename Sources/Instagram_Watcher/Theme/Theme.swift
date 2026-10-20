import SwiftUI

/// Sistema di design centralizzato per stili visivi, gradienti moderni e componenti grafici dell'app
public enum Theme {
    // 🎨 Palette Gradienti Vibranti
    public static let instagramGradient = LinearGradient(
        colors: [
            Color(red: 0.51, green: 0.15, blue: 0.79), // Viola IG
            Color(red: 0.88, green: 0.17, blue: 0.44), // Magenta IG
            Color(red: 0.99, green: 0.47, blue: 0.22)  // Arancio/Giallo IG
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let notFollowingGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.22, blue: 0.38), Color(red: 1.0, green: 0.45, blue: 0.20)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let fansGradient = LinearGradient(
        colors: [Color(red: 0.05, green: 0.75, blue: 0.55), Color(red: 0.15, green: 0.88, blue: 0.70)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let mutualsGradient = LinearGradient(
        colors: [Color(red: 0.38, green: 0.28, blue: 0.95), Color(red: 0.58, green: 0.42, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let lostGradient = LinearGradient(
        colors: [Color(red: 0.95, green: 0.45, blue: 0.12), Color(red: 1.0, green: 0.65, blue: 0.22)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let ghostsGradient = LinearGradient(
        colors: [Color(red: 0.58, green: 0.35, blue: 0.92), Color(red: 0.42, green: 0.22, blue: 0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let anonymousGradient = LinearGradient(
        colors: [Color(red: 0.12, green: 0.53, blue: 0.90), Color(red: 0.45, green: 0.25, blue: 0.88)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)
}

public struct GlassCardModifier: ViewModifier {
    var strokeColor: Color = Color.primary.opacity(0.06)
    var cornerRadius: CGFloat = 20

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }
}

public extension View {
    func glassCard(strokeColor: Color = Color.primary.opacity(0.06), cornerRadius: CGFloat = 20) -> some View {
        self.modifier(GlassCardModifier(strokeColor: strokeColor, cornerRadius: cornerRadius))
    }
}
