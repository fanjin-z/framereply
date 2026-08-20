import ImageIO
import SwiftData
import UIKit
import UniformTypeIdentifiers
import XCTest

@testable import FrameReply

final class PrivacySecurityTests: XCTestCase {
    func testProviderDisclosuresIdentifyRecipientsDestinationsAndPolicies() {
        let china = ProviderDataConsentDisclosure(provider: .miniMaxChina)
        XCTAssertEqual(
            china.permissionTitle,
            "Share chat content with \(ProviderPlatform.miniMaxChina.displayName)?"
        )
        for phrase in [
            ProviderPlatform.miniMaxChina.displayName,
            "saved personal context",
            "third-party AI provider",
            "analyze chats and create replies"
        ] {
            XCTAssertTrue(china.permissionMessage.contains(phrase), phrase)
        }

        let openRouter = ProviderDataConsentDisclosure(provider: .openRouter)
        for phrase in ["OpenRouter", "Alibaba Cloud International", "Qwen3.7 Plus"] {
            XCTAssertTrue(openRouter.destinationDescription.contains(phrase), phrase)
        }
        XCTAssertFalse(openRouter.summary.localizedCaseInsensitiveContains("zero retention"))
        XCTAssertEqual(openRouter.privacyPolicyURL.host, "openrouter.ai")

        let international = ProviderDataConsentDisclosure(provider: .miniMaxInternational)
        XCTAssertTrue(international.destinationDescription.contains("MiniMax International"))
        XCTAssertTrue(china.destinationDescription.contains("mainland China"))
        XCTAssertEqual(international.privacyPolicyURL.host, "platform.minimax.io")
        XCTAssertEqual(china.privacyPolicyURL.host, "platform.minimaxi.com")
    }

    @MainActor
    func testProviderConsentIsVersionedWithdrawableAndRegionScoped() throws {
        let suiteName = "PrivacySecurityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ProviderDataConsentStore(userDefaults: defaults)

        XCTAssertFalse(store.hasValidConsent(for: .openAI))
        store.grantConsent(for: .openAI)
        XCTAssertTrue(store.hasValidConsent(for: .openAI))
        store.revokeConsent(for: .openAI)
        XCTAssertFalse(store.hasValidConsent(for: .openAI))

        store.grantConsent(for: .miniMaxInternational)
        XCTAssertTrue(store.hasValidConsent(for: .miniMaxInternational))
        XCTAssertFalse(store.hasValidConsent(for: .miniMaxChina))
    }

    func testEndpointAllowlistRequiresHTTPSAndExactHost() throws {
        XCTAssertNoThrow(
            try ProviderNetworkSession.validateHTTPS(
                URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!),
                allowedHost: "api.openai.com"
            )
        )
        XCTAssertThrowsError(
            try ProviderNetworkSession.validateHTTPS(
                URLRequest(url: URL(string: "http://api.openai.com/v1/responses")!),
                allowedHost: "api.openai.com"
            )
        )
        for host in ["api.minimax.io", "api.minimaxi.com"] {
            XCTAssertNoThrow(
                try ProviderNetworkSession.validateHTTPS(
                    URLRequest(url: URL(string: "https://\(host)/v1/chat/completions")!),
                    allowedHost: host
                ))
            XCTAssertThrowsError(
                try ProviderNetworkSession.validateHTTPS(
                    URLRequest(
                        url: URL(string: "https://\(host).attacker.example/v1/chat/completions")!),
                    allowedHost: host
                ))
        }
        XCTAssertThrowsError(
            try ProviderNetworkSession.validateHTTPS(
                URLRequest(
                    url: URL(string: "https://api.openai.com.attacker.example/v1/responses")!),
                allowedHost: "api.openai.com"
            )
        )
    }

    @MainActor
    func testImageNormalizerRejectsInvalidInputsAndProducesBoundedMetadataFreeOutput() throws {
        XCTAssertThrowsError(try ScreenshotImageNormalizer.normalize(Data([0x00, 0x01]))) {
            XCTAssertEqual(($0 as? ScreenshotImportError)?.code, "unsupported_image")
        }
        XCTAssertThrowsError(
            try ScreenshotImageNormalizer.normalize(
                Array(
                    repeating: Data([0x00]), count: ScreenshotImageNormalizer.maximumImageCount + 1)
            )
        ) {
            XCTAssertEqual(($0 as? ScreenshotImportError)?.code, "too_many_images")
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4_000, height: 1_000))
        let source = renderer.jpegData(withCompressionQuality: 1) { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4_000, height: 1_000))
        }

        let output = try ScreenshotImageNormalizer.normalize(source)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        )
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)

        XCTAssertLessThanOrEqual(max(width, height), ScreenshotImageNormalizer.maximumPixelEdge)
        XCTAssertLessThanOrEqual(output.count, ScreenshotImageNormalizer.maximumBytesPerImage)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(properties[kCGImagePropertyIPTCDictionary])
    }

    @MainActor
    func testDeleteAllUserDataClearsPersistedContent() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = ChatRepository(container: container)
        context.insert(
            ChatRecord(
                id: "private-chat", title: "Synthetic User", previewText: "Synthetic preview")
        )
        context.insert(
            ChatMessageRecord(
                chatID: "private-chat",
                senderKind: "user",
                text: "Synthetic private message",
                timeLabel: "10:00",
                sortIndex: 0
            )
        )
        try repository.addPersonalInfoFact(text: "Synthetic personal fact")
        try repository.setPersonalInfoLearningEnabled(false)
        try PersonaRepository(container: container).seedPersonasIfNeeded()
        try context.save()

        try FrameReplyDataStore.deleteAllUserData(in: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<ChatRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ChatMessageRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PersonaRecord>()).isEmpty)
        XCTAssertTrue(try repository.personalInfoFacts().isEmpty)
        XCTAssertTrue(try repository.personalInfoLearningEnabled())
    }
}
