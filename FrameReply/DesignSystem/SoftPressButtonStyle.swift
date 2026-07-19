//
//  SoftPressButtonStyle.swift
//  FrameReply
//

import SwiftUI

struct SoftPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}
