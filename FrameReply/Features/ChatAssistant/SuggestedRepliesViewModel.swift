import Combine
import Foundation

@MainActor
final class SuggestedRepliesViewModel: ObservableObject {
    @Published private(set) var replies: [SuggestedReply] = []
    @Published private(set) var conversationStrategy = ""
    @Published private(set) var strategyRationale = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let chatID: String
    private let coordinator: SuggestedRepliesCoordinator
    private var loadID = 0

    init(chatID: String, coordinator: SuggestedRepliesCoordinator) {
        self.chatID = chatID
        self.coordinator = coordinator
    }

    func loadCached(localization: LocalizationContext = .current) {
        do {
            let outcome = try coordinator.cachedReplies(
                chatID: chatID, localization: localization)
            replies = outcome?.replies.map(SuggestedReply.init(text:)) ?? []
            conversationStrategy = outcome?.conversationStrategy ?? ""
            strategyRationale = outcome?.strategyRationale ?? ""
            if !isLoading {
                errorMessage = nil
            }
        } catch {
            replies = []
            conversationStrategy = ""
            strategyRationale = ""
            if !isLoading {
                errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func generate(
        draftingInput: String? = nil,
        force: Bool = true,
        discardExisting: Bool = false,
        localization: LocalizationContext = .current
    ) async -> Bool {
        loadID += 1
        let currentLoadID = loadID
        if discardExisting {
            replies = []
            conversationStrategy = ""
            strategyRationale = ""
        }
        errorMessage = nil
        isLoading = true
        defer {
            if loadID == currentLoadID {
                isLoading = false
            }
        }

        do {
            let outcome = try await coordinator.generate(
                chatID: chatID,
                draftingInput: draftingInput,
                force: force,
                localization: localization
            )
            try Task.checkCancellation()
            guard loadID == currentLoadID else { return false }
            replies = outcome.replies.map(SuggestedReply.init(text:))
            conversationStrategy = outcome.conversationStrategy
            strategyRationale = outcome.strategyRationale
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard loadID == currentLoadID else { return false }
            if discardExisting {
                replies = []
                conversationStrategy = ""
                strategyRationale = ""
            }
            errorMessage = error.localizedDescription
            return false
        }
    }
}
