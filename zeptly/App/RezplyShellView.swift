//
//  RezplyShellView.swift
//  zeptly
//

import SwiftData
import SwiftUI

struct RezplyShellView: View {
    @State private var selectedTab: AppTab = .inbox
    @StateObject private var providerStore = ProviderStore()
    @State private var navigationPath: [RezplyRoute] = []
    @Query private var chatRecords: [ChatRecord]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                EtherealBackground()

                EdgeSwipeTabPager(
                    selectedTab: $selectedTab,
                    isSwipeEnabled: navigationPath.isEmpty
                ) { tab, isActive in
                    switch tab {
                    case .inbox:
                        InboxView(
                            isActive: isActive,
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
                        SettingsView(
                            providerStore: providerStore,
                            isActive: isActive
                        )
                    }
                }

                FloatingBottomNavigation(selectedTab: $selectedTab)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
            }
            .navigationDestination(for: RezplyRoute.self) { route in
                switch route {
                case let .contactContext(chatID):
                    if let chat = chat(withID: chatID) {
                        PersistedContactContextView(chat: chat)
                    }
                case let .chatIntelligence(chatID):
                    if let chat = chat(withID: chatID) {
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

    private func chat(withID id: String) -> Chat? {
        chatRecords.first(where: { $0.id == id }).map { Chat(record: $0) }
    }
}
