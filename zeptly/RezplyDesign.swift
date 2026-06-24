//
//  RezplyDesign.swift
//  zeptly
//

import SwiftUI

enum RezplyColor {
    static let surface = Color(hex: 0xFBF8FF)
    static let surfaceDim = Color(hex: 0xD4D7FF)
    static let surfaceContainerLow = Color(hex: 0xF4F2FF)
    static let surfaceContainer = Color(hex: 0xEDECFF)
    static let surfaceContainerHigh = Color(hex: 0xE6E6FF)
    static let surfaceVariant = Color(hex: 0xDFE0FF)
    static let onSurface = Color(hex: 0x111741)
    static let onSurfaceVariant = Color(hex: 0x45464E)
    static let outline = Color(hex: 0x76767F)
    static let outlineVariant = Color(hex: 0xC6C5CF)
    static let primary = Color(hex: 0x515C87)
    static let primaryContainer = Color(hex: 0xA6B1E1)
    static let primaryFixed = Color(hex: 0xDCE1FF)
    static let secondary = Color(hex: 0x5F5B77)
    static let secondaryContainer = Color(hex: 0xE2DCFD)
    static let tertiaryContainer = Color(hex: 0xB6B1C1)
    static let deepNavy = Color(hex: 0x272D57)
    static let peach = Color(hex: 0xF2C59B)
    static let connected = Color(hex: 0x2DD287)
}

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct EtherealBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    RezplyColor.surface,
                    RezplyColor.surfaceContainerLow,
                    RezplyColor.surfaceContainerHigh
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    RezplyColor.primaryContainer.opacity(0.22),
                    .clear,
                    RezplyColor.secondaryContainer.opacity(0.36)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .blur(radius: 24)
        }
        .ignoresSafeArea()
    }
}

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
                    .shadow(color: RezplyColor.primaryContainer.opacity(0.16), radius: 24, x: 0, y: 16)
            }
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 32, padding: CGFloat = 0) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, padding: padding))
    }
}

struct PillChip: View {
    let title: String
    var symbolName: String?
    var tint: Color = RezplyColor.primary

    var body: some View {
        HStack(spacing: 6) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint.opacity(0.9))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.16), lineWidth: 1)
                }
        }
    }
}

struct AvatarMark: View {
    let initials: String
    let symbolName: String?
    let colors: [Color]
    var size: CGFloat = 64
    var showsOnline: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle().stroke(Color.white.opacity(0.72), lineWidth: 2)
                }
                .shadow(color: RezplyColor.primaryContainer.opacity(0.22), radius: 14, x: 0, y: 8)
                .overlay {
                    if let symbolName {
                        Image(systemName: symbolName)
                            .font(.system(size: size * 0.36, weight: .medium))
                            .foregroundStyle(RezplyColor.primary)
                    } else {
                        Text(initials)
                            .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: RezplyColor.deepNavy.opacity(0.32), radius: 2, x: 0, y: 1)
                    }
                }
                .frame(width: size, height: size)

            if showsOnline {
                Circle()
                    .fill(RezplyColor.connected)
                    .frame(width: size * 0.2, height: size * 0.2)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: -2, y: -2)
            }
        }
        .frame(width: size, height: size)
    }
}
