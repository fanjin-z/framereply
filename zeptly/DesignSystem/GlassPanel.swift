//
//  GlassPanel.swift
//  zeptly
//

import SwiftUI

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 32
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.48))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.78),
                                        Color.white.opacity(0.16)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: RezplyColor.primaryContainer.opacity(0.16), radius: 24, x: 0, y: 16)
            }
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 32, padding: CGFloat = 0) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, padding: padding))
    }
}
