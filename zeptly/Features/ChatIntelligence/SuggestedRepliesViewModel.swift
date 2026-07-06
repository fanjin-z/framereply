import Combine
import Foundation

@MainActor
final class SuggestedRepliesViewModel: ObservableObject {
    @Published private(set) var replies: [SuggestedReply] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let chatID: String
    private let coordinator: SuggestedRepliesCoordinator
    private var loadID = 0

    init(chatID: String, coordinator: SuggestedRepliesCoordinator) {
        self.chatID = chatID
        self.coordinator = coordinator
    }

    func loadCached() {
        do {
            let outcome = try coordinator.cachedReplies(chatID: chatID)
            replies = outcome?.replies.map(SuggestedReply.init(text:)) ?? []
            if !isLoading {
                errorMessage = nil
            }
        } catch {
            replies = []
            if !isLoading {
                errorMessage = error.localizedDescription
            }
        }
    }

    func regenerate(discardExisting: Bool = false) async {
        loadID += 1
        let currentLoadID = loadID
        if discardExisting {
            replies = []
        }
        errorMessage = nil
        isLoading = true
        defer {
            if loadID == currentLoadID {
                isLoading = false
            }
        }

        do {
            let outcome = try await coordinator.generate(chatID: chatID, force: true)
            try Task.checkCancellation()
            guard loadID == currentLoadID else { return }
            replies = outcome.replies.map(SuggestedReply.init(text:))
        } catch is CancellationError {
            return
        } catch {
            guard loadID == currentLoadID else { return }
            if discardExisting {
                replies = []
            }
            errorMessage = error.localizedDescription
        }
    }
}
