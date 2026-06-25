//
//  RezplyShellView.swift
//  zeptly
//

import SwiftUI

struct RezplyShellView: View {
    @State private var selectedTab: AppTab = .inbox
    @StateObject private var providerStore = ProviderStore()
    @State private var navigationPath: [RezplyRoute] = []
    @State private var contactContexts = RezplySampleData.initialContactContexts

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                EtherealBackground()

                VStack(spacing: 0) {
                    TopAppBar(selectedTab: selectedTab)

                    Group {
                        switch selectedTab {
                        case .inbox:
                            InboxView(
                                onChatTap: { chat in
                                    navigationPath.append(.chatIntelligence(chat.id))
                                },
                                onAvatarTap: { chat in
                                    navigationPath.append(.contactContext(chat.id))
                                }
                            )
                        case .personas:
                            PersonasView()
                        case .settings:
                            SettingsView(providerStore: providerStore)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                FloatingBottomNavigation(selectedTab: $selectedTab)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
            }
            .navigationDestination(for: RezplyRoute.self) { route in
                switch route {
                case let .contactContext(chatID):
                    if let chat = RezplySampleData.chat(withID: chatID) {
                        ContactContextView(
                            chat: chat,
                            context: contactContextBinding(for: chat)
                        )
                    }
                case let .chatIntelligence(chatID):
                    if let chat = RezplySampleData.chat(withID: chatID) {
                        ChatIntelligenceView(
                            chat: chat,
                            intelligence: RezplySampleData.chatIntelligence(withID: chatID),
                            onContactTap: {
                                navigationPath.append(.contactContext(chatID))
                            }
                        )
                    }
                }
            }
        }
        .tint(RezplyColor.primary)
    }

    private func contactContextBinding(for chat: Chat) -> Binding<ContactContext> {
        Binding(
            get: {
                contactContexts[chat.id] ?? chat.contactContext ?? ContactContext.empty
            },
            set: { newValue in
                contactContexts[chat.id] = newValue
            }
        )
    }
}
