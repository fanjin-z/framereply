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
    var relationshipNotes: String
    var keyFactsJSON: String
    var currentInteractionGoal: String
    var preferredPersona: String

    init(
        id: UUID = UUID(),
        chatID: String,
        relationshipSubtitle: String,
        relationshipNotes: String,
        keyFactsJSON: String,
        currentInteractionGoal: String,
        preferredPersona: String
    ) {
        self.id = id
        self.chatID = chatID
        self.relationshipSubtitle = relationshipSubtitle
        self.relationshipNotes = relationshipNotes
        self.keyFactsJSON = keyFactsJSON
        self.currentInteractionGoal = currentInteractionGoal
        self.preferredPersona = preferredPersona
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
        sourceApp: String? = nil
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
