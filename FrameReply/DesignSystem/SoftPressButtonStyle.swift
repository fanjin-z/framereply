//
//  SoftPressButtonStyle.swift
//  FrameReply
//

import SwiftUI

struct SoftPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.78),
                value: configuration.isPressed)
    }
}
