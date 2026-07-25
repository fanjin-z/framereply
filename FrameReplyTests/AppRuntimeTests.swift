#if DEBUG
    import SwiftData
    import XCTest

    @testable import FrameReply

    @MainActor
    final class AppRuntimeTests: XCTestCase {
        func testLaunchModeRequiresExactShowcaseArgument() {
            XCTAssertEqual(AppLaunchMode.resolve(arguments: []), .standard)
            XCTAssertEqual(
                AppLaunchMode.resolve(arguments: ["--framereply-showcase"]),
                .showcase
            )
            XCTAssertEqual(
                AppLaunchMode.resolve(arguments: ["framereply-showcase"]),
                .standard
            )
        }

        func testShowcaseRepositoriesUseTheRuntimeContainer() throws {
            let runtime = try AppRuntime.showcase()
            let chatID = try XCTUnwrap(ShowcaseScenario.chats.first?.id)

            try runtime.chatRepository.renameChat(id: chatID, name: "Updated Showcase Name")

            let record = try runtime.modelContainer.mainContext.fetch(
                FetchDescriptor<ChatRecord>(
                    predicate: #Predicate { $0.id == chatID }
                )
            ).first
            XCTAssertEqual(record?.title, "Updated Showcase Name")
        }

        func testShowcaseProviderStorageDoesNotTouchStandardDefaults() throws {
            let key = "AppRuntimeTests.\(UUID().uuidString)"
            UserDefaults.standard.set("sentinel", forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            let runtime = try AppRuntime.showcase()

            XCTAssertTrue(runtime.providerStore.providers.isEmpty)
            XCTAssertEqual(UserDefaults.standard.string(forKey: key), "sentinel")
        }
    }
#endif
