import SwiftUI

enum MemoedTheme {
    static let cornerRadius: CGFloat = 24
    static let compactCornerRadius: CGFloat = 16
    static let contentSpacing: CGFloat = 18
    static let pagePadding: CGFloat = 20

    static let heroGradient = LinearGradient(
        colors: [.indigo, .purple, .cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(MemoedTheme.contentSpacing)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(
                cornerRadius: MemoedTheme.cornerRadius,
                style: .continuous
            ))
            .overlay {
                RoundedRectangle(cornerRadius: MemoedTheme.cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

extension View {
    func cardSurface() -> some View {
        modifier(CardSurface())
    }
}
