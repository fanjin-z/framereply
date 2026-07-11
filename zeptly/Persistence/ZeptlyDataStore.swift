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
        ChatContextRecord.self,
        ChatMemoryRecord.self,
        PersonaRecord.self,
        PersonaObservationRecord.self,
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
                "ZeptlyChatsV2",
                schema: schema,
                url: url,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else {
            if inMemory {
                configuration = ModelConfiguration(
                    "ZeptlyChatsV2",
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            } else {
                configuration = ModelConfiguration(
                    "ZeptlyChatsV2",
                    schema: schema,
                    url: URL.applicationSupportDirectory.appending(path: "ZeptlyChatsV2.store"),
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
            }
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
