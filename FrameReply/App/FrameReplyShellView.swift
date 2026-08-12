//
//  FrameReplyShellView.swift
//  FrameReply
//

import SwiftData
import SwiftUI

struct FrameReplyShellView: View {
    @State private var selectedTab: AppTab
    @ObservedObject private var providerStore: ProviderStore
    @ObservedObject private var shortcutNavigation = ShortcutNavigationCenter.shared
    private let chatRepository: ChatRepository
    private let personaRepository: PersonaRepository
    private let suggestedRepliesCoordinator: any SuggestedRepliesCoordinating
    private let emptyProviderStartupBehavior: EmptyProviderStartupBehavior
    @State private var navigationPath: [FrameReplyRoute] = []
    @Query private var chatRecords: [ChatRecord]
    @Query private var chatContextRecords: [ChatContextRecord]
    @Query(filter: #Predicate<ChatMessageRecord> { $0.senderKind == "unknown" })
    private var unknownSenderMessages: [ChatMessageRecord]

    init(runtime: AppRuntime, initialTab: AppTab? = nil) {
        _selectedTab = State(initialValue: initialTab ?? .chats)
        providerStore = runtime.providerStore
        chatRepository = runtime.chatRepository
        personaRepository = runtime.personaRepository
        suggestedRepliesCoordinator = runtime.suggestedRepliesCoordinator
        emptyProviderStartupBehavior = runtime.emptyProviderStartupBehavior
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                EtherealBackground()

                EdgeSwipeTabPager(
                    selectedTab: $selectedTab,
                    isSwipeEnabled: navigationPath.isEmpty
                ) { tab, isActive in
                    switch tab {
                    case .chats:
                        ChatsView(
                            isActive: isActive,
                            providerStore: providerStore,
                            chatRepository: chatRepository,
                            personaRepository: personaRepository,
                            onChatTap: { chat in
                                navigationPath.append(.chatAssistant(chat.id))
                            },
                            onImportCompleted: { chatID in
                                navigationPath.append(.chatAssistant(chatID))
                            }
                        )
                    case .personas:
                        PersonasView(
                            repository: personaRepository,
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
                            onPersonalInfoTap: {
                                navigationPath.append(.personalInfo)
                            },
                            onPrivacyAndDataTap: {
                                navigationPath.append(.privacyAndData)
                            }
                        )
                    }
                }
                .ignoresSafeArea(.container, edges: .bottom)

                FloatingBottomNavigation(selectedTab: $selectedTab)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationDestination(for: FrameReplyRoute.self) { route in
                switch route {
                case .chatDetails(let chatID):
                    if let chat = chat(withID: chatID) {
                        ChatDetailsView(
                            chat: chat,
                            repository: chatRepository
                        ) {
                            navigationPath.removeAll()
                        }
                    }
                case .chatAssistant(let chatID):
                    if let chat = chat(withID: chatID) {
                        ChatAssistantView(
                            chat: chat,
                            providerStore: providerStore,
                            repository: chatRepository,
                            suggestedRepliesCoordinator: suggestedRepliesCoordinator,
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
                            repository: chatRepository,
                            suggestedRepliesCoordinator: suggestedRepliesCoordinator,
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
                    CreatePersonaView(
                        providerStore: providerStore,
                        chatRepository: chatRepository,
                        personaRepository: personaRepository
                    ) { record in
                        if navigationPath.last == .newPersona {
                            navigationPath.removeLast()
                        }
                        navigationPath.append(.persona(record.id))
                    }
                case .persona(let personaID):
                    PersonaDetailView(
                        personaID: personaID,
                        providerStore: providerStore,
                        chatRepository: chatRepository,
                        personaRepository: personaRepository
                    )
                case .personalInfo:
                    PersonalInfoView(repository: chatRepository)
                case .privacyAndData:
                    PrivacyAndDataView(providerStore: providerStore)
                }
            }
        }
        .keyboardDismissable()
        .tint(FrameReplyColor.primary)
        .onChange(of: shortcutNavigation.request) { _, request in
            guard let request else { return }
            selectedTab = .chats
            navigationPath = [
                request.reviewRequired
                    ? .chatImportReview(request.chatID)
                    : .chatAssistant(request.chatID)
            ]
        }
        .task {
            if let request = shortcutNavigation.request {
                selectedTab = .chats
                navigationPath = [
                    request.reviewRequired
                        ? .chatImportReview(request.chatID)
                        : .chatAssistant(request.chatID)
                ]
            } else if providerStore.providers.isEmpty,
                emptyProviderStartupBehavior == .showSettings
            {
                selectedTab = .settings
            }
        }
    }

    private func chat(withID id: String) -> Chat? {
        guard let record = chatRecords.first(where: { $0.id == id }) else {
            return nil
        }
        let interpretation = ProvisionalIdentityResolver.resolve(
            chat: record,
            messages: unknownSenderMessages.filter { $0.chatID == id },
            previouslyUsedSelfAliasLabels:
                ProvisionalIdentityResolver.previouslyUsedSelfAliasLabels(
                    in: chatContextRecords
                )
        )
        return Chat(record: record, provisionalIdentity: interpretation)
    }

    private func replaceCurrentRoute(with route: FrameReplyRoute) {
        guard !navigationPath.isEmpty else {
            navigationPath.append(route)
            return
        }

        navigationPath[navigationPath.count - 1] = route
    }
}
