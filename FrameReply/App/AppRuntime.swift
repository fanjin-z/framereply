import SwiftData

enum EmptyProviderStartupBehavior: Equatable {
    case showSettings
    case stayOnChats
}

@MainActor
struct AppRuntime {
    let modelContainer: ModelContainer
    let providerStore: ProviderStore
    let chatRepository: ChatRepository
    let personaRepository: PersonaRepository
    let suggestedRepliesCoordinator: any SuggestedRepliesCoordinating
    let emptyProviderStartupBehavior: EmptyProviderStartupBehavior

    static func live() throws -> AppRuntime {
        let container = try FrameReplyDataStore.prepareShared()
        let chatRepository = ChatRepository(context: container.mainContext)
        let personaRepository = PersonaRepository(context: container.mainContext)
        try chatRepository.seedIfNeeded()
        try personaRepository.seedPersonasIfNeeded()
        try FrameReplyDataStore.protectPersistentStoreFiles()

        let providerStore = ProviderStore()
        return AppRuntime(
            modelContainer: container,
            providerStore: providerStore,
            chatRepository: chatRepository,
            personaRepository: personaRepository,
            suggestedRepliesCoordinator: SuggestedRepliesCoordinator(
                providerStore: providerStore,
                repository: chatRepository
            ),
            emptyProviderStartupBehavior: .showSettings
        )
    }
}
