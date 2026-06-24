//
//  SettingsView.swift
//  zeptly
//

import SwiftUI

struct SettingsView: View {
    @Binding var providers: [ProviderConnection]
    @State private var selectedPlatform = "Select provider..."
    @State private var selectedEnvironment = "Production"
    @State private var apiKey = ""
    @State private var didConnect = false

    private let platforms = ["Select provider...", "Google Gemini", "Cohere", "Mistral AI", "Custom Endpoint"]
    private let environments = ["Production", "Development", "Staging"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Image(systemName: "network")
                            .font(.system(size: 20, weight: .medium))
                        Text("Active Connections")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(RezplyColor.primary)
                    .padding(.top, 16)

                    VStack(spacing: 18) {
                        ForEach($providers) { $provider in
                            ProviderCard(provider: $provider)
                        }
                    }
                }

                AddProviderCard(
                    selectedPlatform: $selectedPlatform,
                    selectedEnvironment: $selectedEnvironment,
                    apiKey: $apiKey,
                    didConnect: $didConnect,
                    platforms: platforms,
                    environments: environments
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 94)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}
