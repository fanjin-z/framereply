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
                            providerStore: providerStore,
                            onChatTap: { chat in
                                navigationPath.append(.chatIntelligence(chat.id))
                            },
                            onAvatarTap: { chat in
                                navigationPath.append(.contactContext(chat.id))
                            },
                            onImportCompleted: { chatID in
                                navigationPath.append(.chatIntelligence(chatID))
                            }
                        )
                    case .personas:
                        PersonasView(
                            onPersonaTap: { personaID in
                                navigationPath.append(.persona(personaID))
                            },
                            onCreateTap: {
                                navigationPath.append(.newPersona)
                            }
                        )
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
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationDestination(for: RezplyRoute.self) { route in
                switch route {
                case .contactContext(let chatID):
                    if let chat = chat(withID: chatID) {
                        PersistedContactContextView(chat: chat)
                    }
                case .chatIntelligence(let chatID):
                    if let chat = chat(withID: chatID) {
                        ChatIntelligenceView(
                            chat: chat,
                            intelligence: RezplySampleData.chatIntelligence(withID: chatID),
                            providerStore: providerStore,
                            onContactTap: {
                                navigationPath.append(.contactContext(chatID))
                            },
                            onMergedIntoChat: { targetChatID in
                                replaceCurrentRoute(with: .chatIntelligence(targetChatID))
                            }
                        )
                    }
                case .newPersona:
                    CreatePersonaView(providerStore: providerStore) { record in
                        if navigationPath.last == .newPersona {
                            navigationPath.removeLast()
                        }
                        navigationPath.append(.persona(record.id))
                    }
                case .persona(let personaID):
                    PersonaDetailView(personaID: personaID, providerStore: providerStore)
                }
            }
        }
        .keyboardDismissable()
        .tint(RezplyColor.primary)
    }

    private func chat(withID id: String) -> Chat? {
        chatRecords.first(where: { $0.id == id }).map { Chat(record: $0) }
    }

    private func replaceCurrentRoute(with route: RezplyRoute) {
        guard !navigationPath.isEmpty else {
            navigationPath.append(route)
            return
        }

        navigationPath[navigationPath.count - 1] = route
    }
}
