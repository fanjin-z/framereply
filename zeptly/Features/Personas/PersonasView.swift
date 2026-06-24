//
//  PersonasView.swift
//  zeptly
//

import SwiftUI

struct PersonasView: View {
    @State private var didTapCreate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 12) {
                    ForEach(RezplySampleData.personas) { persona in
                        PersonaCard(persona: persona)
                    }
                }
                .padding(.top, 14)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        didTapCreate.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .medium))
                        Text(didTapCreate ? "Ready to Create" : "Create New Persona")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background {
                        Capsule(style: .continuous)
                            .fill(RezplyColor.primary)
                            .shadow(color: RezplyColor.primaryContainer.opacity(0.34), radius: 22, x: 0, y: 12)
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 94)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}
