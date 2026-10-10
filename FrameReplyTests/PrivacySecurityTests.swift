import ImageIO
import SwiftData
import UIKit
import UniformTypeIdentifiers
import XCTest

@testable import FrameReply

final class PrivacySecurityTests: XCTestCase {
    func testProviderDisclosuresUseProviderSpecificPrivacyPolicies() {
        for (provider, host) in [
            (ProviderPlatform.openRouter, "openrouter.ai"),
            (.miniMaxInternational, "platform.minimax.io"),
            (.miniMaxChina, "platform.minimaxi.com")
        ] {
            let url = ProviderDataConsentDisclosure(provider: provider).privacyPolicyURL
            XCTAssertEqual(url.host, host)
        }
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

        let consent = ManagedAIConsent(
            version: String(repeating: "a", count: 64),
            recipients: [.init(id: "example", name: "Example AI")])
        store.grantConsent(for: .frameReplyAI)
        XCTAssertFalse(store.hasValidConsent(for: consent))
        store.grantConsent(consent)
        XCTAssertTrue(
            ProviderDataConsentStore(userDefaults: defaults).hasValidConsent(for: consent))
        let revised = ManagedAIConsent(
            version: String(repeating: "b", count: 64), recipients: consent.recipients)
        XCTAssertFalse(store.hasValidConsent(for: revised))
        let otherRecipient = ManagedAIConsent(
            version: consent.version,
            recipients: [.init(id: "different", name: "Different AI")])
        XCTAssertFalse(store.hasValidConsent(for: otherRecipient))
        store.revokeConsent(for: .frameReplyAI)
        XCTAssertNil(store.managedConsent)
        XCTAssertFalse(store.hasValidConsent(for: consent))
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
