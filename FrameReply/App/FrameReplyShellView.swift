//
//  FrameReplyShellView.swift
//  FrameReply
//

import SwiftData
import SwiftUI

struct FrameReplyShellView: View {
    @State private var selectedTab: AppTab = .inbox
    @StateObject private var providerStore = ProviderStore()
    @ObservedObject private var shortcutNavigation = ShortcutNavigationCenter.shared
    @State private var navigationPath: [FrameReplyRoute] = []
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
                                navigationPath.append(.chatAssistant(chat.id))
                            },
                            onImportCompleted: { chatID in
                                navigationPath.append(.chatAssistant(chatID))
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
                            isActive: isActive,
                            onPrivacyAndDataTap: {
                                navigationPath.append(.privacyAndData)
                            }
                        )
                    }
                }

                FloatingBottomNavigation(selectedTab: $selectedTab)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationDestination(for: FrameReplyRoute.self) { route in
                switch route {
                case .chatDetails(let chatID):
                    if let chat = chat(withID: chatID) {
                        ChatDetailsView(chat: chat) {
                            navigationPath.removeAll()
                        }
                    }
                case .chatAssistant(let chatID):
                    if let chat = chat(withID: chatID) {
                        ChatAssistantView(
                            chat: chat,
                            providerStore: providerStore,
                            onDetailsTap: {
                                navigationPath.append(.chatDetails(chatID))
                            },
                            onMergedIntoChat: { targetChatID in
                                replaceCurrentRoute(with: .chatAssistant(targetChatID))
                            }
                        )
                    }
                case .chatImportReview(let chatID):
                    if let chat = chat(withID: chatID) {
                        ChatAssistantView(
                            chat: chat,
                            providerStore: providerStore,
                            presentImportReviewOnAppear: true,
                            onDetailsTap: {
                                navigationPath.append(.chatDetails(chatID))
                            },
                            onMergedIntoChat: { targetChatID in
                                replaceCurrentRoute(with: .chatAssistant(targetChatID))
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
                case .privacyAndData:
                    PrivacyAndDataView(providerStore: providerStore)
                }
            }
        }
        .keyboardDismissable()
        .tint(FrameReplyColor.primary)
        .onChange(of: shortcutNavigation.request) { _, request in
            guard let request else { return }
            selectedTab = .inbox
            navigationPath = [
                request.reviewRequired
                    ? .chatImportReview(request.chatID)
                    : .chatAssistant(request.chatID)
            ]
        }
        .task {
            if let request = shortcutNavigation.request {
                selectedTab = .inbox
                navigationPath = [
                    request.reviewRequired
                        ? .chatImportReview(request.chatID)
                        : .chatAssistant(request.chatID)
                ]
            }
        }
    }

    private func chat(withID id: String) -> Chat? {
        chatRecords.first(where: { $0.id == id }).map { Chat(record: $0) }
    }

    private func replaceCurrentRoute(with route: FrameReplyRoute) {
        guard !navigationPath.isEmpty else {
            navigationPath.append(route)
            return
        }

        navigationPath[navigationPath.count - 1] = route
    }
}
