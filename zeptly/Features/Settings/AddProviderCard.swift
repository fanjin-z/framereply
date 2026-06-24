//
//  AddProviderCard.swift
//  zeptly
//

import SwiftUI

struct AddProviderCard: View {
    @Binding var selectedPlatform: String
    @Binding var selectedEnvironment: String
    @Binding var apiKey: String
    @Binding var didConnect: Bool

    let platforms: [String]
    let environments: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add New Provider")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)

                Text("Connect a new language model API securely to your workspace.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .lineSpacing(2)
                    .foregroundStyle(RezplyColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 18) {
                PickerField(title: "Provider Platform", selection: $selectedPlatform, options: platforms)
                PickerField(title: "Environment", selection: $selectedEnvironment, options: environments)

                VStack(alignment: .leading, spacing: 9) {
                    Text("API Key")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)

                    HStack {
                        SecureField("sk-...", text: $apiKey)
                            .font(.system(size: 16, weight: .regular, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Image(systemName: "eye")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(RezplyColor.onSurfaceVariant)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .background {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.white.opacity(0.56))
                    }

                    Text("Keys are encrypted end-to-end and never stored in plain text.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(0.6)
                        .lineSpacing(3)
                        .foregroundStyle(RezplyColor.outline)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        didConnect = true
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: didConnect ? "checkmark" : "link")
                        Text(didConnect ? "Provider Queued" : "Connect Provider")
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 48)
                    .background {
                        Capsule(style: .continuous)
                            .fill(RezplyColor.primary)
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 8)
            }
        }
        .padding(22)
        .glassPanel(cornerRadius: 26)
    }
}
