import SwiftData

@MainActor
enum AppIntentDependencies {
    static func chatRepository() -> ChatRepository {
        ChatRepository(context: ModelContext(FrameReplyDataStore.shared))
    }

    static func screenshotImportCoordinator() -> ScreenshotImportCoordinator {
        let eventReporter = OSLogImportEventReporter()
        let providerStore = ProviderStore()
        return ScreenshotImportCoordinator(
            aiService: AIService(
                providerConfiguration: providerStore,
                registry: .live(eventReporter: eventReporter)
            ),
            repository: chatRepository(),
            eventReporter: eventReporter
        )
    }

    static func suggestedRepliesCoordinator() -> SuggestedRepliesCoordinator {
        let providerStore = ProviderStore()
        return SuggestedRepliesCoordinator(
            providerStore: providerStore,
            repository: chatRepository()
        )
    }
}
