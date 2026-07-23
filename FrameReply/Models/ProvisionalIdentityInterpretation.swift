import Foundation

struct ProvisionalIdentityInterpretation: Equatable {
    let chatID: String
    let selfDisplayLabel: String
    let counterpartDisplayLabel: String
    let displayTitle: String
    let senderKindsByMessageID: [UUID: String]

    func senderKind(for message: ChatMessageRecord) -> String {
        senderKindsByMessageID[message.id] ?? message.senderKind
    }

    func senderName(for message: ChatMessageRecord) -> String? {
        switch senderKind(for: message) {
        case "user":
            nil
        case "other_participant":
            counterpartDisplayLabel
        default:
            message.senderName
        }
    }
}

@MainActor
enum ProvisionalIdentityResolver {
    static func resolve(
        chat: ChatRecord?,
        messages: [ChatMessageRecord],
        previouslyUsedSelfAliasLabels: [String]
    ) -> ProvisionalIdentityInterpretation? {
        guard let chat,
            chat.requiresImportIdentityReview,
            chat.conversationKind == .direct
        else {
            return nil
        }

        let unknownMessages = messages.filter { $0.senderKind == "unknown" }
        guard !unknownMessages.isEmpty else {
            return nil
        }

        let groups = UnknownSenderLabelGroup.make(from: unknownMessages)
        guard groups.count == 2,
            groups.reduce(0, { $0 + $1.messageIDs.count }) == unknownMessages.count
        else {
            return nil
        }

        let usedAliasKeys = Set(
            previouslyUsedSelfAliasLabels.compactMap {
                IdentityLabelPolicy.normalizedKey($0)
            }
        )
        let matchingGroups = groups.filter { usedAliasKeys.contains($0.normalizedLabel) }
        guard matchingGroups.count == 1,
            let selfGroup = matchingGroups.first,
            let counterpartGroup = groups.first(where: {
                $0.normalizedLabel != selfGroup.normalizedLabel
            }),
            let displayTitle =
                IdentityLabelPolicy.displayLabel(chat.title)
                ?? IdentityLabelPolicy.displayLabel(counterpartGroup.displayLabel)
        else {
            return nil
        }

        var senderKindsByMessageID: [UUID: String] = [:]
        for message in unknownMessages {
            guard let labelKey = IdentityLabelPolicy.normalizedKey(message.senderName) else {
                return nil
            }
            senderKindsByMessageID[message.id] =
                labelKey == selfGroup.normalizedLabel ? "user" : "other_participant"
        }

        return ProvisionalIdentityInterpretation(
            chatID: chat.id,
            selfDisplayLabel: selfGroup.displayLabel,
            counterpartDisplayLabel: counterpartGroup.displayLabel,
            displayTitle: displayTitle,
            senderKindsByMessageID: senderKindsByMessageID
        )
    }

    static func previouslyUsedSelfAliasLabels(
        in chatContexts: [ChatContextRecord]
    ) -> [String] {
        chatContexts.flatMap(\.selfAliases).map(\.displayLabel)
    }
}
