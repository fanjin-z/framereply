import SwiftUI
import UIKit

/// Semantic surfaces and accents retain the lavender palette in every appearance.
enum FrameReplyColor {
    static let surface = adaptive(light: 0xFBF8FF, dark: 0x14141E)
    static let surfaceDim = adaptive(light: 0xD4D7FF, dark: 0x252638)
    static let surfaceContainerLow = adaptive(light: 0xF4F2FF, dark: 0x1E1E2B)
    static let surfaceContainer = adaptive(light: 0xEDECFF, dark: 0x282838)
    static let surfaceContainerHigh = adaptive(light: 0xE6E6FF, dark: 0x333345)
    static let surfaceVariant = adaptive(light: 0xDFE0FF, dark: 0x3B3C50)
    static let onSurface = Color(uiColor: .label)
    static let onSurfaceVariant = Color(uiColor: .secondaryLabel)
    static let outline = Color(uiColor: .secondaryLabel)
    static let outlineVariant = Color(uiColor: .separator)
    static let primary = adaptive(
        light: 0x515C87, dark: 0xC0C7FF, highContrastLight: 0x323E69, highContrastDark: 0xE0E4FF)
    static let primaryContainer = adaptive(light: 0xA6B1E1, dark: 0x484F7B)
    static let primaryFixed = adaptive(light: 0xDCE1FF, dark: 0x343B63)
    static let secondary = adaptive(light: 0x5F5B77, dark: 0xC8C0E7)
    static let secondaryContainer = adaptive(light: 0xE2DCFD, dark: 0x39344F)
    static let tertiaryContainer = adaptive(light: 0xB6B1C1, dark: 0x494353)
    static let deepNavy = Color(hex: 0x272D57)
    static let actionFill = adaptive(
        light: 0x515C87, dark: 0x515D99, highContrastLight: 0x323E69, highContrastDark: 0x424E84)
    static let peach = adaptive(light: 0x94551C, dark: 0xF2C59B)
    static let connected = Color(uiColor: .systemGreen)
    static let fieldSurface = Color(uiColor: .tertiarySystemGroupedBackground)
    static let cardSurface = Color(uiColor: .secondarySystemGroupedBackground)

    private static func adaptive(
        light: UInt, dark: UInt,
        highContrastLight: UInt? = nil, highContrastDark: UInt? = nil
    ) -> Color {
        Color(
            uiColor: UIColor { traits in
                let isDark = traits.userInterfaceStyle == .dark
                let increasedContrast = traits.accessibilityContrast == .high
                let hex =
                    isDark
                    ? (increasedContrast ? highContrastDark ?? dark : dark)
                    : (increasedContrast ? highContrastLight ?? light : light)
                return UIColor(
                    red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1
                )
            })
    }
}
