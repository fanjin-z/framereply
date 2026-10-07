import SwiftUI

/// Quiet content surfaces sit beneath the system's Liquid Glass controls.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 32
    var padding: CGFloat = 0
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(FrameReplyColor.cardSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                FrameReplyColor.outlineVariant,
                                lineWidth: contrast == .increased ? 1.5 : 0.5
                            )
                    }
            }
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 32, padding: CGFloat = 0) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, padding: padding))
    }
}
