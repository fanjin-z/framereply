import Foundation
import SwiftData

@MainActor
enum ZeptlyDataStore {
    static let configurationName = "ZeptlyChatsV1"
    static let defaultStoreURL = URL.applicationSupportDirectory.appending(
        path: "\(configurationName).store"
    )

    static let schema = Schema([
        ChatRecord.self,
        ChatSelfAliasRecord.self,
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

    private static var preparedContainer: ModelContainer?
    private static let recoveryContainer: ModelContainer = {
        let configuration = ModelConfiguration(
            "ZeptlyRecovery",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        // The in-memory configuration is made only from bundled model types and is
        // the final non-crashing fallback for background App Intent initialization.
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    static var shared: ModelContainer {
        (try? prepareShared()) ?? recoveryContainer
    }

    static func prepareShared() throws -> ModelContainer {
        if let preparedContainer {
            return preparedContainer
        }
        let container = try makeContainer()
        try protectPersistentStoreFiles()
        preparedContainer = container
        return container
    }

    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(
                configurationName,
                schema: schema,
                url: url,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else if inMemory {
            configuration = ModelConfiguration(
                configurationName,
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                configurationName,
                schema: schema,
                url: defaultStoreURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func resetPersistentStore() throws {
        preparedContainer = nil
        for url in persistentStoreFileURLs where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func deleteAllUserData(in context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<ChatImportRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<SuggestedReplyCacheRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<ChatMemoryRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<ChatContextRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<ChatMessageRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<ChatSelfAliasRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<ChatRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<PersonaLearningReceiptRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<PersonaObservationRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<PersonaRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<StoreMetadataRecord>()) {
            context.delete(record)
        }
        try context.save()
    }

    static func protectPersistentStoreFiles() throws {
        for url in persistentStoreFileURLs where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try mutableURL.setResourceValues(values)
        }
    }

    private static var persistentStoreFileURLs: [URL] {
        [
            defaultStoreURL,
            URL(fileURLWithPath: defaultStoreURL.path + "-wal"),
            URL(fileURLWithPath: defaultStoreURL.path + "-shm")
        ]
    }
}
