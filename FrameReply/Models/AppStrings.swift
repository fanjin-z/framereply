import Foundation

/// Typed access to FrameReply-owned strings that are reused, interpolated, or
/// resolved outside a SwiftUI view. One-off SwiftUI copy remains compiler-extracted.
nonisolated enum AppStrings {
    static func resolve(
        _ resource: LocalizedStringResource,
        locale: Locale = .current
    ) -> String {
        var localizedResource = resource
        localizedResource.locale = locale
        return String(localized: localizedResource)
    }

    enum Common {
        static let tryAgain = LocalizedStringResource("Try again.")
    }

    enum Chat {
        static let importedFallback = LocalizedStringResource(
            "chat.fallback.imported",
            defaultValue: "Imported Chat",
            comment: "Fallback title for an imported chat whose participant is not known."
        )
        static let titleFallback = LocalizedStringResource(
            "chat.fallback.title",
            defaultValue: "Imported Chat",
            comment: "Fallback title for an imported chat whose participant or title is unknown."
        )
        static let previewFallback = LocalizedStringResource(
            "chat.fallback.preview",
            defaultValue: "No messages yet",
            comment: "Preview text for a chat that has no stored messages."
        )

        static func mergeCandidate(title: String, alias: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "chat.merge.candidate.alias",
                defaultValue: "\(title) — also \(alias)",
                comment:
                    "Merge candidate label. First value is the chat title; second is another known participant name."
            )
        }
    }

    enum Errors {
        enum AI {
            static let noProvider = LocalizedStringResource(
                "error.ai.no-provider",
                defaultValue: "Connect and select a model provider first."
            )
            static let missingKey = LocalizedStringResource(
                "error.ai.missing-key",
                defaultValue:
                    "The selected provider API key is unavailable. Reconnect it in Settings."
            )
            static let consentRequired = LocalizedStringResource(
                "error.ai.consent-required",
                defaultValue:
                    "Review and accept this provider's data-sharing disclosure in Settings first."
            )
            static let unsupportedProvider = LocalizedStringResource(
                "error.ai.unsupported-provider",
                defaultValue: "The selected provider is not available."
            )
            static let unsupportedCapability = LocalizedStringResource(
                "error.ai.unsupported-capability",
                defaultValue: "The selected provider does not support this AI task."
            )
        }

        enum Chat {
            static let unavailable = LocalizedStringResource(
                "error.chat.unavailable",
                defaultValue: "That chat is no longer available."
            )
            static let directRequired = LocalizedStringResource(
                "error.chat.direct-required",
                defaultValue: "Participant names are available for one-to-one chats only."
            )
            static let emptyName = LocalizedStringResource(
                "error.chat.empty-name",
                defaultValue: "Enter a display name for this chat."
            )
            static let senderLabelUnavailable = LocalizedStringResource(
                "error.chat.sender-label-unavailable",
                defaultValue:
                    "That sender label is no longer available. Reopen the review and try again."
            )
        }

        enum Import {
            static let noImage = LocalizedStringResource(
                "error.import.no-image",
                defaultValue: "Select at least one screenshot to import."
            )
            static let noTranscript = LocalizedStringResource(
                "error.import.no-transcript",
                defaultValue: "Share or copy at least one text message before importing."
            )
            static let transcriptTooLarge = LocalizedStringResource(
                "error.import.transcript-too-large",
                defaultValue: "The chat text is too large. Select fewer messages and try again."
            )
            static let tooManyImages = LocalizedStringResource(
                "error.import.too-many-images",
                defaultValue: "Select no more than eight screenshots from one chat."
            )
            static let unsupportedImage = LocalizedStringResource(
                "error.import.unsupported-image",
                defaultValue:
                    "A selected image could not be processed safely. Use a still PNG, JPEG, or HEIC image."
            )
            static let imagesTooLarge = LocalizedStringResource(
                "error.import.images-too-large",
                defaultValue:
                    "The selected images are too large to process safely. Choose fewer or smaller images."
            )
            static let noProvider = LocalizedStringResource(
                "error.import.no-provider",
                defaultValue: "Connect and select a model provider before importing messages."
            )
            static let consentRequired = LocalizedStringResource(
                "error.import.consent-required",
                defaultValue: "Allow provider sharing in Settings → Privacy & Data first."
            )
            static let unsupportedProvider = LocalizedStringResource(
                "error.import.unsupported-provider",
                defaultValue: "The selected provider cannot analyze chat imports."
            )
            static let unreadableImage = LocalizedStringResource(
                "error.import.unreadable-image",
                defaultValue:
                    "The selected screenshot could not be read. Choose a still PNG, JPEG, or HEIC image."
            )
        }

        enum Provider {
            static let missingKey = LocalizedStringResource(
                "error.provider.missing-key", defaultValue: "Enter an API key before saving."
            )
            static let invalidKey = LocalizedStringResource(
                "error.provider.invalid-key",
                defaultValue: "This provider rejected the API key. Check it and try again."
            )
            static let insufficientBalance = LocalizedStringResource(
                "error.provider.insufficient-balance",
                defaultValue: "This account does not have enough available API credit or quota."
            )
            static let rateLimited = LocalizedStringResource(
                "error.provider.rate-limited",
                defaultValue: "This provider is rate limiting the key. Wait a moment and try again."
            )
            static let unavailable = LocalizedStringResource(
                "error.provider.unavailable",
                defaultValue: "This provider is temporarily unavailable. Try again shortly."
            )
            static let invalidRequest = LocalizedStringResource(
                "error.provider.invalid-request",
                defaultValue:
                    "The provider could not process this request. Check the configuration and try again."
            )
            static let invalidResponse = LocalizedStringResource(
                "error.provider.invalid-response",
                defaultValue: "The provider returned an unreadable response. Try again."
            )
            static let emptyResponse = LocalizedStringResource(
                "error.provider.empty-response",
                defaultValue: "The provider returned an empty response."
            )
            static let truncatedResponse = LocalizedStringResource(
                "error.provider.truncated-response",
                defaultValue: "The provider response was cut off before it finished."
            )
            static let invalidJSON = LocalizedStringResource(
                "error.provider.invalid-json",
                defaultValue: "The provider returned malformed JSON."
            )
            static let schemaMismatch = LocalizedStringResource(
                "error.provider.schema-mismatch",
                defaultValue: "The provider response did not match the chat format."
            )
            static let invalidChat = LocalizedStringResource(
                "error.provider.invalid-chat",
                defaultValue: "The provider selected an unknown chat."
            )
            static let incompleteMessages = LocalizedStringResource(
                "error.provider.incomplete-messages",
                defaultValue: "The provider returned incomplete chat messages."
            )
            static let network = LocalizedStringResource(
                "error.provider.network",
                defaultValue:
                    "FrameReply could not reach the provider. Check your connection and try again."
            )
            static let keychain = LocalizedStringResource(
                "error.provider.keychain",
                defaultValue: "The API key was valid, but FrameReply could not save it securely."
            )
            static let consentRequired = LocalizedStringResource(
                "error.provider.consent-required",
                defaultValue: "Allow provider data sharing before connecting."
            )
            static let unsupported = LocalizedStringResource(
                "error.provider.unsupported",
                defaultValue: "This provider is not available yet."
            )
        }

        enum Replies {
            static let noProvider = LocalizedStringResource(
                "error.replies.no-provider",
                defaultValue: "Connect and select a model provider to generate replies."
            )
            static let consentRequired = LocalizedStringResource(
                "error.replies.consent-required",
                defaultValue: "Allow provider sharing in Settings → Privacy & Data first."
            )
            static let noMessages = LocalizedStringResource(
                "error.replies.no-messages",
                defaultValue: "Import at least one chat message before generating replies."
            )
            static let chatNotFound = LocalizedStringResource(
                "error.replies.chat-not-found",
                defaultValue: "This chat is no longer available."
            )
            static let unsupportedProvider = LocalizedStringResource(
                "error.replies.unsupported-provider",
                defaultValue: "The selected provider cannot generate suggested replies."
            )
            static let invalidResponse = LocalizedStringResource(
                "error.replies.invalid-response",
                defaultValue:
                    "The provider could not generate replies in the expected format. Try again."
            )
        }

        enum Shortcut {
            static let noAnalyzedChat = LocalizedStringResource(
                "error.shortcut.no-analyzed-chat",
                defaultValue: "No analyzed chat was provided."
            )
            static let noImages = LocalizedStringResource(
                "error.shortcut.no-images", defaultValue: "No chat images were provided."
            )
            static let operationMismatch = LocalizedStringResource(
                "error.shortcut.operation-mismatch",
                defaultValue: "The analyzed chat does not match this Shortcut run."
            )
            static let analyzedChatUnavailable = LocalizedStringResource(
                "error.shortcut.analyzed-chat-unavailable",
                defaultValue: "The analyzed chat has expired or is unavailable."
            )
            static let contextUnavailable = LocalizedStringResource(
                "error.shortcut.context-unavailable",
                defaultValue:
                    "The optional context for this analyzed chat is no longer available. Run an Analyze action again."
            )
            static let notReady = LocalizedStringResource(
                "error.shortcut.not-ready",
                defaultValue: "The analyzed chat is not ready yet. Run the Analyze action again."
            )

            static func tooManyImages(maximum: Int) -> LocalizedStringResource {
                LocalizedStringResource(
                    "error.shortcut.too-many-images",
                    defaultValue: "Choose no more than \(maximum) images from the same chat."
                )
            }

            static func invalidImage(position: Int) -> LocalizedStringResource {
                LocalizedStringResource(
                    "error.shortcut.invalid-image",
                    defaultValue: "Image \(position) is empty or is not a readable image."
                )
            }
        }
    }

    enum Import {
        static func noNewMessages(chatTitle: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "import.no-new-messages",
                defaultValue: "No new messages found in \(chatTitle)."
            )
        }

        static func reviewRequired(count: Int) -> LocalizedStringResource {
            LocalizedStringResource(
                "import.review-required",
                defaultValue: "Imported \(count) messages. Review may be needed.",
                comment:
                    "Import result. The catalog supplies singular and plural variants for the message count."
            )
        }

        static func addedMessages(count: Int, chatTitle: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "import.added-messages",
                defaultValue: "Added \(count) messages to \(chatTitle).",
                comment:
                    "Import result. The catalog supplies singular and plural variants for the message count."
            )
        }
    }

    enum Persona {
        static func name(for id: BuiltInPersonaID) -> LocalizedStringResource {
            switch id {
            case .professional:
                LocalizedStringResource(
                    "persona.professional.name", defaultValue: "Professional")
            case .spark:
                LocalizedStringResource("persona.spark.name", defaultValue: "Spark")
            case .thoughtful:
                LocalizedStringResource("persona.thoughtful.name", defaultValue: "Thoughtful")
            }
        }

        static func summary(for id: BuiltInPersonaID) -> LocalizedStringResource {
            switch id {
            case .professional:
                LocalizedStringResource(
                    "persona.professional.summary",
                    defaultValue: "Concise, polished replies for work and formal conversations."
                )
            case .spark:
                LocalizedStringResource(
                    "persona.spark.summary",
                    defaultValue: "Playful, confident, genuine dating messages that read the room."
                )
            case .thoughtful:
                LocalizedStringResource(
                    "persona.thoughtful.summary",
                    defaultValue:
                        "Warm, empathetic replies for friends, family, and delicate moments."
                )
            }
        }

        static func instructions(for id: BuiltInPersonaID) -> LocalizedStringResource {
            switch id {
            case .professional:
                LocalizedStringResource(
                    "persona.professional.instructions",
                    defaultValue:
                        "Write clear, structured messages for professional and formal conversations. Be decisive and avoid filler."
                )
            case .spark:
                LocalizedStringResource(
                    "persona.spark.instructions",
                    defaultValue:
                        "Write genuine dating messages that read the room. Match the other person's emotional intensity and never force flirtation or over-escalate."
                )
            case .thoughtful:
                LocalizedStringResource(
                    "persona.thoughtful.instructions",
                    defaultValue:
                        "Write tactful messages for friends, family, and delicate moments. Acknowledge emotion without inventing feelings or becoming overly sentimental."
                )
            }
        }

        static func observation(for id: BuiltInObservationID) -> LocalizedStringResource {
            switch id {
            case .polishedConversational:
                LocalizedStringResource(
                    "persona.observation.polished-conversational",
                    defaultValue: "Uses polished, complete phrasing while remaining conversational."
                )
            case .concise:
                LocalizedStringResource(
                    "persona.observation.concise",
                    defaultValue: "Keeps replies concise and omits nonessential detail."
                )
            case .clearDirect:
                LocalizedStringResource(
                    "persona.observation.clear-direct",
                    defaultValue: "States the main point clearly and directly."
                )
            case .noEmoji:
                LocalizedStringResource(
                    "persona.observation.no-emoji", defaultValue: "Does not use emoji.")
            case .casualConversational:
                LocalizedStringResource(
                    "persona.observation.casual-conversational",
                    defaultValue: "Keeps wording casual and conversational."
                )
            case .warmAcknowledgment:
                LocalizedStringResource(
                    "persona.observation.warm-acknowledgment",
                    defaultValue: "Shows clear warmth and considerate acknowledgment."
                )
            case .lightPlayfulness:
                LocalizedStringResource(
                    "persona.observation.light-playfulness",
                    defaultValue: "Allows light playfulness when it fits naturally."
                )
            case .tactfulClarity:
                LocalizedStringResource(
                    "persona.observation.tactful-clarity",
                    defaultValue: "Balances clarity with tact."
                )
            case .naturalDetail:
                LocalizedStringResource(
                    "persona.observation.natural-detail",
                    defaultValue: "Uses the amount of detail naturally required by the message."
                )
            case .occasionalEmoji:
                LocalizedStringResource(
                    "persona.observation.occasional-emoji",
                    defaultValue: "Uses an occasional emoji only when it fits the conversation."
                )
            case .veryRelaxed:
                LocalizedStringResource(
                    "persona.observation.very-relaxed",
                    defaultValue:
                        "Uses very relaxed, conversational wording and natural contractions."
                )
            case .highlyFormal:
                LocalizedStringResource(
                    "persona.observation.highly-formal",
                    defaultValue: "Uses highly polished, formal phrasing and avoids slang."
                )
            case .restrainedNeutral:
                LocalizedStringResource(
                    "persona.observation.restrained-neutral",
                    defaultValue: "Keeps emotional tone restrained and neutral."
                )
            case .limitedWarmth:
                LocalizedStringResource(
                    "persona.observation.limited-warmth",
                    defaultValue: "Shows limited warmth while staying courteous."
                )
            case .openWarmth:
                LocalizedStringResource(
                    "persona.observation.open-warmth",
                    defaultValue: "Writes with open warmth and empathy without inventing feelings."
                )
            case .oneConciseSentence:
                LocalizedStringResource(
                    "persona.observation.one-concise-sentence",
                    defaultValue: "Usually replies in one very concise sentence."
                )
            case .fullerContext:
                LocalizedStringResource(
                    "persona.observation.fuller-context",
                    defaultValue: "Usually gives fuller replies with useful context."
                )
            case .detailedWithoutFiller:
                LocalizedStringResource(
                    "persona.observation.detailed-without-filler",
                    defaultValue: "Writes detailed replies while avoiding repetition and filler."
                )
            case .rareEmoji:
                LocalizedStringResource(
                    "persona.observation.rare-emoji",
                    defaultValue: "Uses emoji rarely and only when it reads naturally."
                )
            case .frequentEmoji:
                LocalizedStringResource(
                    "persona.observation.frequent-emoji",
                    defaultValue: "Uses emoji fairly often when they fit the conversation."
                )
            case .expressiveEmoji:
                LocalizedStringResource(
                    "persona.observation.expressive-emoji",
                    defaultValue: "Uses expressive emoji naturally without cluttering the message."
                )
            }
        }

        static func copyName(_ sourceName: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "persona.copy-name",
                defaultValue: "\(sourceName) Copy",
                comment:
                    "Name assigned when duplicating a persona. The placeholder is the original persona name."
            )
        }
    }

    enum Provider {
        static let openAIDestination = LocalizedStringResource(
            "provider.destination.openai",
            defaultValue: "OpenAI in the United States or another region selected by OpenAI"
        )
        static let zaiInternationalDestination = LocalizedStringResource(
            "provider.destination.zai-international",
            defaultValue: "Z.ai International, which generally processes API data in Singapore"
        )
        static let zhipuChinaDestination = LocalizedStringResource(
            "provider.destination.zhipu-china",
            defaultValue: "Zhipu AI in mainland China"
        )

        static func consentTitle(providerName: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "provider.consent.title",
                defaultValue: "Share chat content with \(providerName)?",
                comment: "Provider data-sharing consent title. The placeholder is a provider brand."
            )
        }

        static func consentMessage(providerName: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "provider.consent.message",
                defaultValue:
                    "FrameReply will send the messages, images, names, and drafts you select directly to \(providerName), a third-party AI provider, to analyze chats and create replies.",
                comment: "Privacy disclosure. The placeholder is the third-party provider brand."
            )
        }

        static func consentSummary(destination: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "provider.consent.summary",
                defaultValue:
                    "FrameReply sends selected screenshots or message text, participant names, chat context, and drafts to \(destination) to analyze conversations and generate replies. Your provider may retain request data under its policy and may charge your provider account. FrameReply does not operate a proxy server.",
                comment:
                    "Detailed provider privacy disclosure. The placeholder describes the processing destination."
            )
        }
    }

    enum Shortcut {
        static let analyzedChatSubtitle: LocalizedStringResource = "Analyzed chat input"
        static let addContextOrDraft: LocalizedStringResource = "Add"
        static let skip: LocalizedStringResource = "Skip"
        static let imagesContextChoice: LocalizedStringResource =
            "Add context or a draft?"
        static let imagesContextPrompt: LocalizedStringResource =
            "What do you want to say?"
        static let imagesLegacyContextPrompt: LocalizedStringResource =
            "What do you want to say?"
        static let imageInputSynchronizationError: LocalizedStringResource =
            "The optional input could not be synchronized with this image import."
        static let chatHistoryPersistenceError: LocalizedStringResource =
            "The chat history could not be saved."
        static let textContextChoice: LocalizedStringResource =
            "Add context or a draft?"
        static let textContextPrompt: LocalizedStringResource =
            "What do you want to say?"
        static let textLegacyContextPrompt: LocalizedStringResource =
            "What do you want to say?"
        static let textInputSynchronizationError: LocalizedStringResource =
            "The optional input could not be synchronized with this chat import."
        static let textPersistenceError: LocalizedStringResource =
            "The imported chat text could not be saved."
        static let noSharedText: LocalizedStringResource =
            "No shared or copied message text was provided."
        static let contextTooLong: LocalizedStringResource =
            "Keep context under 500 characters."
        static let imagesInstallationTitle: LocalizedStringResource = "FrameReply Images"
        static let textInstallationTitle: LocalizedStringResource = "FrameReply Text"

        static func noNewMessages(chatTitle: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "shortcut.import.no-new-messages",
                defaultValue: "No new messages found in \(chatTitle).",
                comment: "Shortcut result when all imported chat messages were already present."
            )
        }

        static func reviewRequired(count: Int, chatTitle: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "shortcut.import.review-required",
                defaultValue:
                    "Imported \(count) messages as \(chatTitle). Review it in FrameReply.",
                comment:
                    "Shortcut result. The catalog supplies singular and plural variants for the message count."
            )
        }

        static func addedMessages(count: Int, chatTitle: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "shortcut.import.added-messages",
                defaultValue: "Added \(count) new messages to \(chatTitle).",
                comment:
                    "Shortcut result. The catalog supplies singular and plural variants for the message count."
            )
        }

        static func repliesResult(
            message: String, firstReply: String, secondReply: String
        ) -> LocalizedStringResource {
            LocalizedStringResource(
                "shortcut.replies.result",
                defaultValue:
                    "\(message)\n\nSuggested replies:\n1. \(firstReply)\n2. \(secondReply)",
                comment: "Shortcut result with two verbatim AI-generated reply bodies."
            )
        }

        static func repliesUnavailable(message: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "shortcut.replies.unavailable",
                defaultValue:
                    "\(message) Suggested replies are unavailable; open FrameReply to retry."
            )
        }

        static func errorWithReference(
            message: String, diagnosticID: String
        ) -> LocalizedStringResource {
            LocalizedStringResource(
                "shortcut.error.with-reference",
                defaultValue: "\(message) Reference \(diagnosticID).",
                comment: "Shortcut error followed by a private diagnostic reference."
            )
        }
    }
}
