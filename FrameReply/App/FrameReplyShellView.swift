//
//  FrameReplyShellView.swift
//  FrameReply
//

import AppIntents
import SwiftData
import SwiftUI

struct FrameReplyShellView: View {
    @State private var selectedTab: AppTab
    @ObservedObject private var providerStore: ProviderStore
    private let aiAccess: AIAccessModel
    private let chatRepository: ChatRepository
    private let personaRepository: PersonaRepository
    private let suggestedRepliesCoordinator: any SuggestedRepliesCoordinating
    private let emptyProviderStartupBehavior: EmptyProviderStartupBehavior
    @State private var navigationPath: [FrameReplyRoute] = []
    @State private var importReviewRequest: (chatID: String, id: UUID)?
    @Query private var chatRecords: [ChatRecord]
    @Query private var chatContextRecords: [ChatContextRecord]
    @Query(filter: #Predicate<ChatMessageRecord> { $0.senderKind == "unknown" })
    private var unknownSenderMessages: [ChatMessageRecord]

    init(runtime: AppRuntime, initialTab: AppTab? = nil) {
        _selectedTab = State(initialValue: initialTab ?? .chats)
        providerStore = runtime.providerStore
        aiAccess = runtime.aiAccess
        chatRepository = runtime.chatRepository
        personaRepository = runtime.personaRepository
        suggestedRepliesCoordinator = runtime.suggestedRepliesCoordinator
        emptyProviderStartupBehavior = runtime.emptyProviderStartupBehavior
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            TabView(selection: $selectedTab) {
                Tab(value: AppTab.chats) {
                    ChatsView(
                        isActive: selectedTab == .chats,
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
                    .background { EtherealBackground() }
                } label: {
                    Label("Chats", systemImage: "bubble.left.and.bubble.right")
                }
                .accessibilityIdentifier("app-tab-chats")

                Tab(value: AppTab.personas) {
                    PersonasView(
                        repository: personaRepository,
                        onCreate: {
                            navigationPath.append(.newPersona)
                        },
                        onPersonaTap: { personaID in
                            navigationPath.append(.persona(personaID))
                        }
                    )
                    .background { EtherealBackground() }
                } label: {
                    Label("Personas", systemImage: "face.smiling")
                }
                .accessibilityIdentifier("app-tab-personas")

                Tab(value: AppTab.settings) {
                    SettingsView(
                        providerStore: providerStore,
                        aiAccess: aiAccess,
                        isActive: selectedTab == .settings,
                        onPersonalInfoTap: {
                            navigationPath.append(.personalInfo)
                        },
                        onPrivacyAndDataTap: {
                            navigationPath.append(.privacyAndData)
                        }
                    )
                    .background { EtherealBackground() }
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("app-tab-settings")
            }
            .tabBarMinimizeBehavior(.never)
            .toolbar(navigationPath.isEmpty ? .hidden : .visible, for: .navigationBar)
            .navigationDestination(for: FrameReplyRoute.self) { route in
                switch route {
                case .chatDetails(let chatID):
                    if let chat = chat(withID: chatID) {
                        ChatDetailsView(
                            chat: chat,
                            repository: chatRepository
                        )
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
                            onDeleted: {
                                navigationPath.removeAll()
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
                            importReviewRequestID:
                                importReviewRequest?.chatID == chatID
                                ? importReviewRequest?.id : nil,
                            onDetailsTap: {
                                navigationPath.append(.chatDetails(chatID))
                            },
                            onDeleted: {
                                navigationPath.removeAll()
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
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onAppIntentExecution(OpenShortcutImportIntent.self) { intent in
            importReviewRequest = intent.reviewRequired ? (intent.chatID, UUID()) : nil
            if selectedTab != .chats {
                selectedTab = .chats
            }
            let destination: [FrameReplyRoute] = [
                intent.reviewRequired
                    ? .chatImportReview(intent.chatID)
                    : .chatAssistant(intent.chatID)
            ]
            if navigationPath != destination {
                navigationPath = destination
            }
        }
        .task {
            if navigationPath.isEmpty,
                providerStore.providers.isEmpty,
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
