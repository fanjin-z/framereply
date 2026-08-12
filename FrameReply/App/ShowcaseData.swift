#if DEBUG
    import Foundation
    import SwiftData

    /// All identities and conversation content in this fixture are fictional and
    /// licensed as repository test content for FrameReply's App Store showcase.
    enum ShowcaseScenario {
        enum ChatID {
            static let maya = "showcase.maya"
            static let jordan = "showcase.jordan"
            static let riley = "showcase.riley"
            static let sam = "showcase.sam"
        }

        struct Chat {
            let id: String
            let name: String
            let preview: String
            let updatedMinuteOfDay: Int
            let goal: String
            let persona: BuiltInPersonaID
            let messages: [Message]
            let memory: Memory?
            let suggestedReplies: [String]
            let conversationStrategy: String
            let strategyRationale: String
        }

        struct Message {
            let id: UUID
            let senderKind: String
            let senderName: String?
            let text: String
            let timeLabel: String
            let minutesBeforeUpdate: Int
        }

        struct Memory {
            let id: UUID
            let text: String
            let minutesBeforeUpdate: Int
        }

        static let chats: [Chat] = [
            Chat(
                id: ChatID.maya,
                name: "Maya",
                preview: "Perfect 😊 I’ll find a pastry stall for us.",
                updatedMinuteOfDay: 9 * 60 + 35,
                goal: "Confirm Saturday plans and keep the tone warm.",
                persona: .thoughtful,
                messages: [
                    Message(
                        id: uuid("10000000-0000-4000-8000-000000000001"),
                        senderKind: "other_participant",
                        senderName: "Maya",
                        text: "I love finding new weekend markets and trying local pastries.",
                        timeLabel: "9:04 AM",
                        minutesBeforeUpdate: 31
                    ),
                    Message(
                        id: uuid("10000000-0000-4000-8000-000000000002"),
                        senderKind: "other_participant",
                        senderName: "Maya",
                        text: "I found a farmers’ market by the park. Want to go Saturday morning?",
                        timeLabel: "9:29 AM",
                        minutesBeforeUpdate: 6
                    ),
                    Message(
                        id: uuid("10000000-0000-4000-8000-000000000003"),
                        senderKind: "user",
                        senderName: nil,
                        text: "That sounds lovely! I can bring coffee.",
                        timeLabel: "9:32 AM",
                        minutesBeforeUpdate: 3
                    ),
                    Message(
                        id: uuid("10000000-0000-4000-8000-000000000004"),
                        senderKind: "other_participant",
                        senderName: "Maya",
                        text: "Perfect 😊 I’ll find a pastry stall for us.",
                        timeLabel: "9:35 AM",
                        minutesBeforeUpdate: 0
                    )
                ],
                memory: Memory(
                    id: uuid("20000000-0000-4000-8000-000000000001"),
                    text: "Maya enjoys visiting weekend markets and trying local pastries.",
                    minutesBeforeUpdate: 30
                ),
                suggestedReplies: [
                    "Perfect 😊 Send me the time and I’ll bring the coffee.",
                    "Lovely! Tell me when to meet you, and I’ll bring coffee."
                ],
                conversationStrategy:
                    "Confirm the meeting time while matching Maya’s warm, easygoing tone.",
                strategyRationale:
                    "Maya has agreed and is checking the stalls; the only open detail is when to meet."
            ),
            Chat(
                id: ChatID.jordan,
                name: "Jordan",
                preview: "Absolutely—I’ll update it and send the final outline before lunch.",
                updatedMinuteOfDay: 9 * 60 + 24,
                goal: "Confirm the revision and delivery time.",
                persona: .professional,
                messages: [
                    Message(
                        id: uuid("30000000-0000-4000-8000-000000000001"),
                        senderKind: "user",
                        senderName: nil,
                        text: "I tightened the intro and added the project timeline.",
                        timeLabel: "9:17 AM",
                        minutesBeforeUpdate: 7
                    ),
                    Message(
                        id: uuid("30000000-0000-4000-8000-000000000002"),
                        senderKind: "other_participant",
                        senderName: "Jordan",
                        text: "It reads clearly now. Could we move the summary to the top?",
                        timeLabel: "9:21 AM",
                        minutesBeforeUpdate: 3
                    ),
                    Message(
                        id: uuid("30000000-0000-4000-8000-000000000003"),
                        senderKind: "user",
                        senderName: nil,
                        text: "Absolutely—I’ll update it and send the final outline before lunch.",
                        timeLabel: "9:24 AM",
                        minutesBeforeUpdate: 0
                    )
                ],
                memory: nil,
                suggestedReplies: [
                    "Absolutely—I’ll move the summary to the top and send the revised outline before lunch.",
                    "Will do. I’ll lead with the summary and share the final outline before lunch."
                ],
                conversationStrategy:
                    "Confirm the requested edit and provide a clear delivery time.",
                strategyRationale:
                    "Jordan asked for one concrete revision and the timing is already established."
            ),
            Chat(
                id: ChatID.riley,
                name: "Riley",
                preview: "Basil and mint—coffee and plant shopping next?",
                updatedMinuteOfDay: 9 * 60 + 12,
                goal: "Say yes and keep the plan playful.",
                persona: .spark,
                messages: [
                    Message(
                        id: uuid("40000000-0000-4000-8000-000000000001"),
                        senderKind: "other_participant",
                        senderName: "Riley",
                        text: "I finally found a sunny spot for my little herb garden.",
                        timeLabel: "9:06 AM",
                        minutesBeforeUpdate: 6
                    ),
                    Message(
                        id: uuid("40000000-0000-4000-8000-000000000002"),
                        senderKind: "user",
                        senderName: nil,
                        text: "That sounds perfect. What are you planting first?",
                        timeLabel: "9:09 AM",
                        minutesBeforeUpdate: 3
                    ),
                    Message(
                        id: uuid("40000000-0000-4000-8000-000000000003"),
                        senderKind: "other_participant",
                        senderName: "Riley",
                        text: "Basil and mint—coffee and plant shopping next?",
                        timeLabel: "9:12 AM",
                        minutesBeforeUpdate: 0
                    )
                ],
                memory: nil,
                suggestedReplies: [
                    "That sounds like a perfect afternoon—coffee first, then plant shopping?",
                    "I’m in! Let’s get coffee and pick out something for the herb garden."
                ],
                conversationStrategy:
                    "Accept the invitation and keep Riley’s light, playful energy.",
                strategyRationale:
                    "Riley suggested a relaxed plan and invited an enthusiastic response."
            ),
            Chat(
                id: ChatID.sam,
                name: "Sam",
                preview: "I’m glad it worked—save me a slice!",
                updatedMinuteOfDay: 8 * 60 + 58,
                goal: "Reply warmly and promise a slice.",
                persona: .thoughtful,
                messages: [
                    Message(
                        id: uuid("50000000-0000-4000-8000-000000000001"),
                        senderKind: "user",
                        senderName: nil,
                        text: "I tried your banana bread recipe this morning.",
                        timeLabel: "8:48 AM",
                        minutesBeforeUpdate: 10
                    ),
                    Message(
                        id: uuid("50000000-0000-4000-8000-000000000002"),
                        senderKind: "other_participant",
                        senderName: "Sam",
                        text: "How did it turn out?",
                        timeLabel: "8:51 AM",
                        minutesBeforeUpdate: 7
                    ),
                    Message(
                        id: uuid("50000000-0000-4000-8000-000000000003"),
                        senderKind: "user",
                        senderName: nil,
                        text: "Soft in the middle, and the kitchen smells amazing.",
                        timeLabel: "8:55 AM",
                        minutesBeforeUpdate: 3
                    ),
                    Message(
                        id: uuid("50000000-0000-4000-8000-000000000004"),
                        senderKind: "other_participant",
                        senderName: "Sam",
                        text: "I’m glad it worked—save me a slice!",
                        timeLabel: "8:58 AM",
                        minutesBeforeUpdate: 0
                    )
                ],
                memory: nil,
                suggestedReplies: [
                    "Definitely—there’ll be a slice waiting for you 😊",
                    "You’ve earned a slice for sharing such a good recipe!"
                ],
                conversationStrategy:
                    "Promise a slice and thank Sam with warm, natural language.",
                strategyRationale:
                    "Sam is celebrating the successful bake and making a playful request."
            )
        ]

        static func chat(id: String) -> Chat? {
            chats.first { $0.id == id }
        }

        private static func uuid(_ value: String) -> UUID {
            UUID(uuidString: value)!
        }
    }

    @MainActor
    enum ShowcaseDataSeeder {
        static func seed(in container: ModelContainer, now: Date = Date()) throws {
            let context = container.mainContext
            let personaRepository = PersonaRepository(context: context)
            let personas = try personaRepository.personas()
            let personasByBuiltInID = Dictionary(
                uniqueKeysWithValues: personas.compactMap { record in
                    record.builtInID.map { ($0, record) }
                }
            )
            let startOfDay = Calendar.current.startOfDay(for: now)

            for scenario in ShowcaseScenario.chats {
                guard let persona = personasByBuiltInID[scenario.persona] else {
                    throw ShowcaseDataError.missingBuiltInPersona(scenario.persona)
                }
                let updatedAt = Calendar.current.date(
                    byAdding: .minute,
                    value: scenario.updatedMinuteOfDay,
                    to: startOfDay
                )!

                context.insert(
                    ChatRecord(
                        id: scenario.id,
                        title: scenario.name,
                        previewText: scenario.preview,
                        conversationKind: .direct,
                        isProvisional: false,
                        updatedAt: updatedAt
                    )
                )
                context.insert(
                    ChatContextRecord(
                        chatID: scenario.id,
                        currentInteractionGoal: scenario.goal,
                        personaID: persona.id,
                        personaAssignedAt: updatedAt.addingTimeInterval(-60 * 60)
                    )
                )
                for (sortIndex, message) in scenario.messages.enumerated() {
                    context.insert(
                        ChatMessageRecord(
                            id: message.id,
                            chatID: scenario.id,
                            senderKind: message.senderKind,
                            senderName: message.senderName,
                            text: message.text,
                            timeLabel: message.timeLabel,
                            sortIndex: sortIndex,
                            createdAt: updatedAt.addingTimeInterval(
                                TimeInterval(-message.minutesBeforeUpdate * 60)
                            )
                        )
                    )
                }
                if let memory = scenario.memory {
                    context.insert(
                        ChatMemoryRecord(
                            id: memory.id,
                            chatID: scenario.id,
                            text: memory.text,
                            origin: ChatMemoryOrigin.ai.rawValue,
                            certainty: ChatMemoryCertainty.userConfirmed.rawValue,
                            status: ChatMemoryStatus.active.rawValue,
                            createdAt: updatedAt.addingTimeInterval(
                                TimeInterval(-memory.minutesBeforeUpdate * 60)
                            ),
                            updatedAt: updatedAt
                        )
                    )
                }
                context.insert(
                    SuggestedReplyCacheRecord(
                        chatID: scenario.id,
                        appLanguage: "en",
                        historySummary: "",
                        summarizedMessageCount: 0,
                        summarizedPrefixFingerprint: "",
                        repliesJSON: try repliesJSON(scenario.suggestedReplies),
                        conversationStrategy: scenario.conversationStrategy,
                        strategyRationale: scenario.strategyRationale,
                        inputFingerprint: "showcase-presentation-only",
                        promptVersion: SuggestedReplyPrompt.version,
                        generatedAt: updatedAt
                    )
                )
            }

            try context.save()
        }

        private static func repliesJSON(_ replies: [String]) throws -> String {
            let data = try JSONEncoder().encode(replies)
            guard let value = String(data: data, encoding: .utf8) else {
                throw ShowcaseDataError.invalidReplies
            }
            return value
        }
    }

    @MainActor
    final class ShowcaseSuggestedRepliesCoordinator: SuggestedRepliesCoordinating {
        func cachedReplies(
            chatID: String,
            localization: LocalizationContext
        ) throws -> SuggestedRepliesOutcome? {
            try outcome(for: chatID, source: .cached)
        }

        func generate(
            chatID: String,
            draftingInput: String?,
            force: Bool,
            localization: LocalizationContext,
            traceID: ImportTraceID
        ) async throws -> SuggestedRepliesOutcome {
            try outcome(for: chatID, source: .generated)
        }

        private func outcome(
            for chatID: String,
            source: SuggestedReplyGenerationSource
        ) throws -> SuggestedRepliesOutcome {
            guard let scenario = ShowcaseScenario.chat(id: chatID) else {
                throw SuggestedRepliesError.chatNotFound
            }
            return SuggestedRepliesOutcome(
                replies: scenario.suggestedReplies,
                conversationStrategy: scenario.conversationStrategy,
                strategyRationale: scenario.strategyRationale,
                source: source
            )
        }
    }

    @MainActor
    extension AppRuntime {
        static func showcase() throws -> AppRuntime {
            let container = try FrameReplyDataStore.makeContainer(inMemory: true)
            let chatRepository = ChatRepository(context: container.mainContext)
            let personaRepository = PersonaRepository(context: container.mainContext)
            try personaRepository.seedPersonasIfNeeded()
            try ShowcaseDataSeeder.seed(in: container)

            let providerStore = try ShowcaseEnvironment.makeProviderStore()
            let onboardingStore = OnboardingStore(
                userDefaults: ShowcaseEnvironment.userDefaults,
                installationMarkerKey: ProviderStore.installationMarkerKey
            )
            onboardingStore.completeCurrentOnboarding()
            return AppRuntime(
                modelContainer: container,
                onboardingStore: onboardingStore,
                providerStore: providerStore,
                chatRepository: chatRepository,
                personaRepository: personaRepository,
                suggestedRepliesCoordinator: ShowcaseSuggestedRepliesCoordinator(),
                emptyProviderStartupBehavior: .stayOnChats
            )
        }
    }

    @MainActor
    private enum ShowcaseEnvironment {
        private static let defaultsSuiteName = "com.gigabeyond.framereply.showcase"

        static var userDefaults: UserDefaults {
            UserDefaults(suiteName: defaultsSuiteName)!
        }

        static func makeProviderStore() throws -> ProviderStore {
            let defaults = userDefaults
            defaults.removePersistentDomain(forName: defaultsSuiteName)
            return ProviderStore(
                userDefaults: defaults,
                registry: .live(),
                keychain: InMemoryKeychainStore(),
                reconcileInstallation: false
            )
        }
    }

    private final class InMemoryKeychainStore: KeychainStoring {
        private var values: [String: String] = [:]

        func set(_ value: String, for account: String) throws {
            values[account] = value
        }

        func get(account: String) throws -> String? {
            values[account]
        }

        func delete(account: String) throws {
            values.removeValue(forKey: account)
        }
    }

    private enum ShowcaseDataError: Error {
        case missingBuiltInPersona(BuiltInPersonaID)
        case invalidReplies
    }
#endif
