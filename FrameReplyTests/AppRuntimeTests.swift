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
                AppLaunchMode.resolve(arguments: ["--framereply-showcase-onboarding"]),
                .showcaseOnboarding
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

        func testShowcaseOnboardingStartsPendingWithASeededDefaultPersona() throws {
            let runtime = try AppRuntime.showcase(completesOnboarding: false)

            XCTAssertEqual(runtime.onboardingStore.presentation, .initial)
            XCTAssertNotNil(try runtime.personaRepository.defaultPersonaID())
            XCTAssertFalse(runtime.providerStore.providers.isEmpty)
        }

    }
#endif
