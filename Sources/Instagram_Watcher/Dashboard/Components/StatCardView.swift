import SwiftUI

/// Card statistica premium con effetto glassmorphism, bagliore d'accento e contatore bold
public struct StatCardView: View {
    public let title: String
    public let count: Int
    public let subtitle: String
    public let systemIcon: String
    public let gradient: LinearGradient
    public let accentColor: Color

    public init(
        title: String,
        count: Int,
        subtitle: String,
        systemIcon: String,
        gradient: LinearGradient = Theme.instagramGradient,
        accentColor: Color = .blue
    ) {
        self.title = title
        self.count = count
        self.subtitle = subtitle
        self.systemIcon = systemIcon
        self.gradient = gradient
        self.accentColor = accentColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header card: icona a gradiente con ombra al neon + contatore prominente
            HStack(alignment: .center) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(gradient)
                        .frame(width: 44, height: 44)
                        .shadow(color: accentColor.opacity(0.38), radius: 10, x: 0, y: 5)

                    Image(systemName: systemIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                Text("\(count)")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
            }

            // Testi e freccia
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(accentColor)
                    .padding(7)
                    .background(accentColor.opacity(0.12))
                    .clipShape(Circle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))

                // Bagliore d'accento soffuso nell'angolo superiore
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [accentColor.opacity(0.08), Color.clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 90
                        )
                    )
            }
            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [accentColor.opacity(0.38), accentColor.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
    }
}
