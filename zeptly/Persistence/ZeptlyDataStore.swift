//
//  ZeptlyDataStore.swift
//  zeptly
//

import Foundation
import SwiftData

enum ZeptlyDataStore {
    static let schema = Schema([
        ChatRecord.self,
        ChatMessageRecord.self,
        ContactContextRecord.self,
        ContactMemoryRecord.self,
        PersonaRecord.self,
        PersonaLearnedTraitRecord.self,
        PersonaLearningReceiptRecord.self,
        SuggestedReplyCacheRecord.self,
        ChatImportRecord.self,
        StoreMetadataRecord.self
    ])

    static let shared: ModelContainer = {
        do {
            return try makeContainer()
        } catch {
            fatalError("Unable to create Zeptly data store: \(error)")
        }
    }()

    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(
                "ZeptlyPersonasV1",
                schema: schema,
                url: url,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                "ZeptlyPersonasV1",
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: .none
            )
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
