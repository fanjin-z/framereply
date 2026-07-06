//
//  ChatRecords.swift
//  zeptly
//

import Foundation
import SwiftData

@Model
final class ChatRecord {
    var id: String
    var name: String
    var lastActivityLabel: String
    var preview: String
    var chipTitle: String
    var chipSymbol: String
    var avatarSymbol: String?
    @Attribute(.externalStorage) var avatarData: Data?
    var avatarPerceptualHash: Int64?
    var avatarFeaturePrintData: Data?
    // Optional so rows written before avatar support can lightweight-migrate safely.
    var avatarQuality: Double?
    var avatarAlgorithmRevision: Int?
    var avatarUpdatedAt: Date?
    var initials: String
    var appearanceStyle: Int
    var isUnread: Bool
    var isOnline: Bool
    var isProvisional: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        lastActivityLabel: String,
        preview: String,
        chipTitle: String,
        chipSymbol: String,
        avatarSymbol: String?,
        initials: String,
        appearanceStyle: Int,
        isUnread: Bool,
        isOnline: Bool,
        isProvisional: Bool = false,
        avatarData: Data? = nil,
        avatarPerceptualHash: Int64? = nil,
        avatarFeaturePrintData: Data? = nil,
        avatarQuality: Double = 0,
        avatarAlgorithmRevision: Int = 0,
        avatarUpdatedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.lastActivityLabel = lastActivityLabel
        self.preview = preview
        self.chipTitle = chipTitle
        self.chipSymbol = chipSymbol
        self.avatarSymbol = avatarSymbol
        self.avatarData = avatarData
        self.avatarPerceptualHash = avatarPerceptualHash
        self.avatarFeaturePrintData = avatarFeaturePrintData
        self.avatarQuality = avatarQuality
        self.avatarAlgorithmRevision = avatarAlgorithmRevision
        self.avatarUpdatedAt = avatarUpdatedAt
        self.initials = initials
        self.appearanceStyle = appearanceStyle
        self.isUnread = isUnread
        self.isOnline = isOnline
        self.isProvisional = isProvisional
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ChatMessageRecord {
    var id: UUID
    var chatID: String
    var senderKind: String
    var senderName: String?
    var text: String
    var normalizedText: String
    var timeLabel: String
    var timestamp: Date?
    var sortIndex: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        chatID: String,
        senderKind: String,
        senderName: String? = nil,
        text: String,
        normalizedText: String,
        timeLabel: String,
        timestamp: Date? = nil,
        sortIndex: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chatID = chatID
        self.senderKind = senderKind
        self.senderName = senderName
        self.text = text
        self.normalizedText = normalizedText
        self.timeLabel = timeLabel
        self.timestamp = timestamp
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}

@Model
final class ContactContextRecord {
    var id: UUID
    var chatID: String
    var relationshipSubtitle: String
    var currentInteractionGoal: String
    var personaID: UUID
    var personaAssignedAt: Date

    init(
        id: UUID = UUID(),
        chatID: String,
        relationshipSubtitle: String,
        currentInteractionGoal: String,
        personaID: UUID = PersonaDefaults.professionalID,
        personaAssignedAt: Date = Date()
    ) {
        self.id = id
        self.chatID = chatID
        self.relationshipSubtitle = relationshipSubtitle
        self.currentInteractionGoal = currentInteractionGoal
        self.personaID = personaID
        self.personaAssignedAt = personaAssignedAt
    }

    convenience init(
        id: UUID = UUID(), chatID: String, relationshipSubtitle: String,
        currentInteractionGoal: String, preferredPersona: String
    ) {
        let personaID: UUID
        switch preferredPersona.lowercased() {
        case let value where value.contains("spark") || value.contains("dating"):
            personaID = PersonaDefaults.sparkID
        case let value where value.contains("thought") || value.contains("warm") || value.contains("friendly"):
            personaID = PersonaDefaults.thoughtfulID
        default:
            personaID = PersonaDefaults.professionalID
        }
        self.init(
            id: id, chatID: chatID, relationshipSubtitle: relationshipSubtitle,
            currentInteractionGoal: currentInteractionGoal, personaID: personaID
        )
    }
}

@Model
final class PersonaRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var summary: String
    var symbolName: String
    var accentKey: String
    var templateKey: String
    var isBuiltIn: Bool
    var purposeInstructions: String
    var baselineStyleJSON: String
    var alwaysFollowRules: String
    var learningEnabled: Bool
    var learningEnabledAt: Date
    var sampleCount: Int
    var lastLearnedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(), name: String, summary: String, symbolName: String,
        accentKey: String, templateKey: String, isBuiltIn: Bool,
        purposeInstructions: String, baselineStyleJSON: String,
        alwaysFollowRules: String = "",
        learningEnabled: Bool = true, learningEnabledAt: Date = Date(),
        sampleCount: Int = 0, lastLearnedAt: Date? = nil,
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbolName = symbolName
        self.accentKey = accentKey
        self.templateKey = templateKey
        self.isBuiltIn = isBuiltIn
        self.purposeInstructions = purposeInstructions
        self.baselineStyleJSON = baselineStyleJSON
        self.alwaysFollowRules = alwaysFollowRules
        self.learningEnabled = learningEnabled
        self.learningEnabledAt = learningEnabledAt
        self.sampleCount = sampleCount
        self.lastLearnedAt = lastLearnedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PersonaStyleAdjustmentRecord {
    @Attribute(.unique) var key: String
    var personaID: UUID
    var dimensionKey: String
    var adjustment: Int
    var updatedAt: Date

    init(personaID: UUID, dimensionKey: String, adjustment: Int, updatedAt: Date = Date()) {
        self.key = "\(personaID.uuidString.lowercased())|\(dimensionKey)"
        self.personaID = personaID
        self.dimensionKey = dimensionKey
        self.adjustment = min(2, max(-2, adjustment))
        self.updatedAt = updatedAt
    }
}

@Model
final class PersonaLearnedTraitRecord {
    @Attribute(.unique) var id: UUID
    var personaID: UUID
    var dimensionKey: String
    var learnedLevel: Double?
    var observation: String
    var confidence: Double
    var evidenceCount: Int
    var origin: String
    var status: String
    var updatedAt: Date

    init(
        id: UUID = UUID(), personaID: UUID, dimensionKey: String,
        learnedLevel: Double? = nil, observation: String,
        confidence: Double, evidenceCount: Int, origin: String,
        status: String = PersonaTraitStatus.active.rawValue, updatedAt: Date = Date()
    ) {
        self.id = id
        self.personaID = personaID
        self.dimensionKey = dimensionKey
        self.learnedLevel = learnedLevel
        self.observation = observation
        self.confidence = confidence
        self.evidenceCount = evidenceCount
        self.origin = origin
        self.status = status
        self.updatedAt = updatedAt
    }
}

@Model
final class PersonaLearningReceiptRecord {
    @Attribute(.unique) var key: String
    var personaID: UUID
    var chatID: String
    var messageID: UUID
    var analyzedAt: Date

    init(personaID: UUID, chatID: String, messageID: UUID, analyzedAt: Date = Date()) {
        self.key = "\(personaID.uuidString.lowercased())|\(messageID.uuidString.lowercased())"
        self.personaID = personaID
        self.chatID = chatID
        self.messageID = messageID
        self.analyzedAt = analyzedAt
    }
}

@Model
final class ContactMemoryRecord {
    var id: UUID
    var chatID: String
    var text: String
    var origin: String
    var certainty: String
    var sourceMessageIDsJSON: String
    var status: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        chatID: String,
        text: String,
        origin: String,
        certainty: String,
        sourceMessageIDsJSON: String = "[]",
        status: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.chatID = chatID
        self.text = text
        self.origin = origin
        self.certainty = certainty
        self.sourceMessageIDsJSON = sourceMessageIDsJSON
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class SuggestedReplyCacheRecord {
    @Attribute(.unique) var chatID: String
    var historySummary: String
    var summarizedMessageCount: Int
    var summarizedPrefixFingerprint: String
    var repliesJSON: String
    var inputFingerprint: String
    var provider: String
    var model: String
    var promptVersion: Int
    var generatedAt: Date

    init(
        chatID: String,
        historySummary: String,
        summarizedMessageCount: Int,
        summarizedPrefixFingerprint: String,
        repliesJSON: String,
        inputFingerprint: String,
        provider: String,
        model: String,
        promptVersion: Int,
        generatedAt: Date = Date()
    ) {
        self.chatID = chatID
        self.historySummary = historySummary
        self.summarizedMessageCount = summarizedMessageCount
        self.summarizedPrefixFingerprint = summarizedPrefixFingerprint
        self.repliesJSON = repliesJSON
        self.inputFingerprint = inputFingerprint
        self.provider = provider
        self.model = model
        self.promptVersion = promptVersion
        self.generatedAt = generatedAt
    }
}

@Model
final class ChatImportRecord {
    var id: UUID
    var chatID: String
    var transcriptFingerprint: String?
    var provider: String
    var model: String
    var confidence: Double
    var createdAt: Date
    var insertedMessageCount: Int
    var isDuplicate: Bool
    var requiresReview: Bool
    var matchDisposition: String?
    var suggestedChatID: String?
    var matchReason: String?
    var avatarEvidence: String?
    var transcriptEvidence: String?
    var sourceApp: String?
    var diagnosticID: String?
    var matchedExisting: Bool?
    /// Correlates the Analyze and Generate Shortcut actions. Optional for
    /// lightweight migration of imports created by older app versions.
    var operationID: UUID?
    var draftingInputStateRaw: String?
    /// One-use text supplied from the screenshot Shortcut. It is never promoted
    /// to chat history, contact memory, or persona learning.
    var draftingInput: String?
    var draftingInputCreatedAt: Date?

    init(
        id: UUID = UUID(),
        chatID: String,
        transcriptFingerprint: String?,
        provider: String,
        model: String,
        confidence: Double,
        createdAt: Date = Date(),
        insertedMessageCount: Int,
        isDuplicate: Bool,
        requiresReview: Bool,
        matchDisposition: String? = nil,
        suggestedChatID: String? = nil,
        matchReason: String? = nil,
        avatarEvidence: String? = nil,
        transcriptEvidence: String? = nil,
        sourceApp: String? = nil,
        diagnosticID: String? = nil,
        matchedExisting: Bool? = nil,
        operationID: UUID? = nil,
        draftingInputStateRaw: String? = nil,
        draftingInput: String? = nil,
        draftingInputCreatedAt: Date? = nil
    ) {
        self.id = id
        self.chatID = chatID
        self.transcriptFingerprint = transcriptFingerprint
        self.provider = provider
        self.model = model
        self.confidence = confidence
        self.createdAt = createdAt
        self.insertedMessageCount = insertedMessageCount
        self.isDuplicate = isDuplicate
        self.requiresReview = requiresReview
        self.matchDisposition = matchDisposition
        self.suggestedChatID = suggestedChatID
        self.matchReason = matchReason
        self.avatarEvidence = avatarEvidence
        self.transcriptEvidence = transcriptEvidence
        self.sourceApp = sourceApp
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
