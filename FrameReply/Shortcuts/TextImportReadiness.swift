import AppIntents
import Foundation

nonisolated enum TextImportReadiness: Equatable, Sendable {
    case ready
    case missingSenderMetadata

    init(analysis: ChatImportAnalysis) {
        let hasUnattributedMessage = analysis.messages.contains { message in
            guard message.sender == .unknown else {
                return false
            }
            guard
                let senderName = message.senderName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !senderName.isEmpty
            else {
                return true
            }
            return false
        }
        self = hasUnattributedMessage ? .missingSenderMetadata : .ready
    }
}

protocol TextImportMetadataPromptingIntent: AppIntent {}

extension TextImportMetadataPromptingIntent {
    func stopForMissingSenderMetadata() async throws -> Never {
        let close = IntentChoiceOption(
            title: AppStrings.Shortcut.close,
            style: .cancel
        )
        _ = try await requestChoice(
            between: [close],
            dialog: IntentDialog(AppStrings.Shortcut.missingSenderMetadataDialog)
        )
        throw CancellationError()
    }
}
