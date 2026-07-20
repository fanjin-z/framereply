//
//  ChatRecords.swift
//  FrameReply
//

import Foundation
import SwiftData

nonisolated enum ImportIdentityReviewStatus: String, Codable, Equatable {
    case needsReview
    case confirmed
    case dismissed
}

nonisolated struct ChatImportReviewState: Codable, Equatable {
    var identityStatus: ImportIdentityReviewStatus
    var viewCount: Int
    var lastViewedAt: Date?
    var meaningfulActionCount: Int

    init(
        identityStatus: ImportIdentityReviewStatus,
        viewCount: Int = 0,
        lastViewedAt: Date? = nil,
        meaningfulActionCount: Int = 0
    ) {
        self.identityStatus = identityStatus
        self.viewCount = viewCount
        self.lastViewedAt = lastViewedAt
        self.meaningfulActionCount = meaningfulActionCount
    }

    init?(json: String?) {
        guard let data = json?.data(using: .utf8),
            let value = try? JSONDecoder().decode(Self.self, from: data)
        else {
            return nil
        }
        self = value
    }

    var jsonString: String? {
        guard let data = try? JSONEncoder().encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

@Model
final class ChatRecord {
    @Attribute(.unique) var id: String
    var title: String?
    var previewText: String?
    var conversationKindRaw: String
    var importReviewStateJSON: String?
    var updatedAt: Date

    var importReviewState: ChatImportReviewState? {
        get {
            ChatImportReviewState(json: importReviewStateJSON)
        }
        set {
            importReviewStateJSON = newValue?.jsonString
        }
    }

    var requiresImportIdentityReview: Bool {
        importReviewState?.identityStatus == .needsReview
    }

    var isProvisional: Bool {
        requiresImportIdentityReview
    }

    var conversationKind: ChatConversationKind {
        get { ChatConversationKind(rawValue: conversationKindRaw) ?? .unknown }
        set { conversationKindRaw = newValue.rawValue }
    }

    init(
        id: String,
        title: String?,
        previewText: String?,
        conversationKind: ChatConversationKind = .unknown,
        isProvisional: Bool = false,
        importReviewStateJSON: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.previewText = previewText
        self.conversationKindRaw = conversationKind.rawValue
        if let importReviewStateJSON {
            self.importReviewStateJSON = importReviewStateJSON
        } else if isProvisional {
            self.importReviewStateJSON =
                ChatImportReviewState(
                    identityStatus: .needsReview
                ).jsonString
        } else {
            self.importReviewStateJSON = nil
        }
        self.updatedAt = updatedAt
    }
}

@Model
final class ChatSelfAliasRecord {
    var id: UUID
    var chatID: String
    var displayLabel: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        chatID: String,
        displayLabel: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chatID = chatID
        self.displayLabel = displayLabel
        self.createdAt = createdAt
    }
}

@Model
final class ChatMessageRecord {
    var id: UUID
    var chatID: String
    var senderKind: String
    var senderName: String?
    var text: String
    var timeLabel: String
    var sortIndex: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        chatID: String,
        senderKind: String,
        senderName: String? = nil,
        text: String,
        timeLabel: String,
        sortIndex: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chatID = chatID
        self.senderKind = senderKind
        self.senderName = senderName
        self.text = text
        self.timeLabel = timeLabel
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}

@Model
final class ChatContextRecord {
    @Attribute(.unique) var chatID: String
    var currentInteractionGoal: String
    var personaID: UUID
    var personaAssignedAt: Date
    var participantAliasesJSON: String

    var participantAliases: [ChatParticipantAlias] {
        get {
            guard let data = participantAliasesJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ChatParticipantAlias].self, from: data)) ?? []
        }
        set {
            guard !newValue.isEmpty, let data = try? JSONEncoder().encode(newValue) else {
                participantAliasesJSON = "[]"
                return
            }
            participantAliasesJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    init(
        chatID: String,
        currentInteractionGoal: String,
        personaID: UUID,
        personaAssignedAt: Date = Date(),
        participantAliasesJSON: String = "[]"
    ) {
        self.chatID = chatID
        self.currentInteractionGoal = currentInteractionGoal
        self.personaID = personaID
        self.personaAssignedAt = personaAssignedAt
        self.participantAliasesJSON = participantAliasesJSON
    }

}

@Model
final class PersonaRecord {
    @Attribute(.unique) var id: UUID
    var builtInIDRaw: String?
    var nameOverride: String?
    var summaryOverride: String?
    var symbolName: String
    var accentKey: String
    var instructionsOverride: String?
    var learningEnabled: Bool
    var learningEnabledAt: Date
    var sampleCount: Int
    var createdAt: Date
    var updatedAt: Date

    var builtInID: BuiltInPersonaID? {
        builtInIDRaw.flatMap(BuiltInPersonaID.init(rawValue:))
    }

    var name: String {
        get { resolvedName() }
        set { nameOverride = newValue }
    }

    var summary: String {
        get { resolvedSummary() }
        set { summaryOverride = newValue }
    }

    var instructions: String {
        get { resolvedInstructions() }
        set { instructionsOverride = newValue }
    }

    init(
        id: UUID = UUID(), name: String, summary: String, symbolName: String,
        accentKey: String, instructions: String,
        learningEnabled: Bool = true, learningEnabledAt: Date = Date(),
        sampleCount: Int = 0,
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id
        self.builtInIDRaw = nil
        self.nameOverride = name
        self.summaryOverride = summary
        self.symbolName = symbolName
        self.accentKey = accentKey
        self.instructionsOverride = instructions
        self.learningEnabled = learningEnabled
        self.learningEnabledAt = learningEnabledAt
        self.sampleCount = sampleCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(
        id: UUID = UUID(), builtInID: BuiltInPersonaID,
        learningEnabled: Bool = true, learningEnabledAt: Date = Date(),
        sampleCount: Int = 0, createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        let definition = BuiltInPersonaDefinition.definition(for: builtInID)
        self.id = id
        self.builtInIDRaw = builtInID.rawValue
        self.nameOverride = nil
        self.summaryOverride = nil
        self.symbolName = definition.symbolName
        self.accentKey = definition.accentKey
        self.instructionsOverride = nil
        self.learningEnabled = learningEnabled
        self.learningEnabledAt = learningEnabledAt
        self.sampleCount = sampleCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func resolvedName(locale: Locale = .current) -> String {
        nameOverride ?? builtInID.map {
            BuiltInPersonaDefinition.definition(for: $0).localizedName(locale: locale)
        } ?? ""
    }

    func resolvedSummary(locale: Locale = .current) -> String {
        summaryOverride ?? builtInID.map {
            BuiltInPersonaDefinition.definition(for: $0).localizedSummary(locale: locale)
        } ?? ""
    }

    func resolvedInstructions(locale: Locale = .current) -> String {
        instructionsOverride ?? builtInID.map {
            BuiltInPersonaDefinition.definition(for: $0).localizedInstructions(locale: locale)
        } ?? ""
    }

    var promptInstructions: String {
        instructionsOverride ?? builtInID.map {
            BuiltInPersonaDefinition.definition(for: $0).canonicalInstructions
        } ?? ""
    }
}

@Model
final class PersonaObservationRecord {
    var id: UUID
    var personaID: UUID
    var text: String
    var templateIDRaw: String?
    var origin: String
    var isUserProtected: Bool
    var status: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(), personaID: UUID, text: String,
        templateIDRaw: String? = nil,
        origin: String, isUserProtected: Bool = false,
        status: String = PersonaObservationStatus.active.rawValue,
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id
        self.personaID = personaID
        self.text = text
        self.templateIDRaw = templateIDRaw
        self.origin = origin
        self.isUserProtected = isUserProtected
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var templateID: BuiltInObservationID? {
        templateIDRaw.flatMap(BuiltInObservationID.init(rawValue:))
    }

    var localizedText: String { templateID?.localizedText() ?? text }
    var promptText: String { templateID?.canonicalPromptText ?? text }
}

@Model
final class PersonaLearningReceiptRecord {
    @Attribute(.unique) var key: String
    var personaID: UUID
    var chatID: String
    var messageID: UUID

    init(personaID: UUID, chatID: String, messageID: UUID) {
        self.key = "\(personaID.uuidString.lowercased())|\(messageID.uuidString.lowercased())"
        self.personaID = personaID
        self.chatID = chatID
        self.messageID = messageID
    }
}

@Model
final class ChatMemoryRecord {
    var id: UUID
    var chatID: String
    var text: String
    var origin: String
    var certainty: String
    var status: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        chatID: String,
        text: String,
        origin: String,
        certainty: String,
        status: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.chatID = chatID
        self.text = text
        self.origin = origin
        self.certainty = certainty
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class SuggestedReplyCacheRecord {
    @Attribute(.unique) var key: String
    var chatID: String
    var presentationLanguageIdentifier: String
    var historySummary: String
    var summarizedMessageCount: Int
    var summarizedPrefixFingerprint: String
    var repliesJSON: String
    var conversationStrategy: String
    var strategyRationale: String
    var inputFingerprint: String
    var promptVersion: Int
    var generatedAt: Date

    init(
        chatID: String,
        presentationLanguageIdentifier: String,
        historySummary: String,
        summarizedMessageCount: Int,
        summarizedPrefixFingerprint: String,
        repliesJSON: String,
        conversationStrategy: String = "",
        strategyRationale: String = "",
        inputFingerprint: String,
        promptVersion: Int,
        generatedAt: Date = Date()
    ) {
        self.key = Self.makeKey(
            chatID: chatID, presentationLanguageIdentifier: presentationLanguageIdentifier)
        self.chatID = chatID
        self.presentationLanguageIdentifier = presentationLanguageIdentifier
        self.historySummary = historySummary
        self.summarizedMessageCount = summarizedMessageCount
        self.summarizedPrefixFingerprint = summarizedPrefixFingerprint
        self.repliesJSON = repliesJSON
        self.conversationStrategy = conversationStrategy
        self.strategyRationale = strategyRationale
        self.inputFingerprint = inputFingerprint
        self.promptVersion = promptVersion
        self.generatedAt = generatedAt
    }

    static func makeKey(chatID: String, presentationLanguageIdentifier: String) -> String {
        "\(chatID)|\(presentationLanguageIdentifier.lowercased())"
    }
}

@Model
final class ChatImportRecord {
    var id: UUID
    var chatID: String
    var transcriptFingerprint: String?
    var createdAt: Date
    var insertedMessageCount: Int
    var isDuplicate: Bool
    var requiresReview: Bool
    var diagnosticID: String?
    var matchedExisting: Bool
    var operationID: UUID
    var draftingInputStateRaw: String
    /// One-use text supplied from the screenshot Shortcut. It is never promoted
    /// to chat history, chat memory, or persona learning.
    var draftingInput: String?
    var draftingInputCreatedAt: Date?

    init(
        id: UUID = UUID(),
        chatID: String,
        transcriptFingerprint: String?,
        createdAt: Date = Date(),
        insertedMessageCount: Int,
        isDuplicate: Bool,
        requiresReview: Bool,
        diagnosticID: String? = nil,
        matchedExisting: Bool = false,
        operationID: UUID = UUID(),
        draftingInputStateRaw: String = DraftingInputState.pending.rawValue,
        draftingInput: String? = nil,
        draftingInputCreatedAt: Date? = nil
    ) {
        self.id = id
        self.chatID = chatID
        self.transcriptFingerprint = transcriptFingerprint
        self.createdAt = createdAt
        self.insertedMessageCount = insertedMessageCount
        self.isDuplicate = isDuplicate
        self.requiresReview = requiresReview
        self.diagnosticID = diagnosticID
        self.matchedExisting = matchedExisting
        self.operationID = operationID
        self.draftingInputStateRaw = draftingInputStateRaw
        self.draftingInput = draftingInput
        self.draftingInputCreatedAt = draftingInputCreatedAt
    }
}

@Model
final class StoreMetadataRecord {
    var key: String
    var value: String

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}
