import ImageIO
import SwiftData
import UIKit
import UniformTypeIdentifiers
import XCTest

@testable import FrameReply

final class PrivacySecurityTests: XCTestCase {
    func testProviderPermissionCopyNamesRecipientDataAndPurpose() {
        let disclosure = ProviderDataConsentDisclosure(provider: .zhipuChina)

        XCTAssertEqual(
            disclosure.permissionTitle,
            "Share chat content with \(ProviderPlatform.zhipuChina.displayName)?"
        )
        XCTAssertTrue(
            disclosure.permissionMessage.contains(ProviderPlatform.zhipuChina.displayName)
        )
        XCTAssertTrue(disclosure.permissionMessage.contains("messages, images, names, and drafts"))
        XCTAssertTrue(disclosure.permissionMessage.contains("third-party AI provider"))
        XCTAssertTrue(disclosure.permissionMessage.contains("analyze chats and create replies"))
    }

    @MainActor
    func testProviderConsentIsVersionedAndCanBeWithdrawn() throws {
        let suiteName = "PrivacySecurityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ProviderDataConsentStore(userDefaults: defaults)

        XCTAssertFalse(store.hasValidConsent(for: .openAI))
        store.grantConsent(for: .openAI)
        XCTAssertTrue(store.hasValidConsent(for: .openAI))
        store.revokeConsent(for: .openAI)
        XCTAssertFalse(store.hasValidConsent(for: .openAI))
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
        XCTAssertThrowsError(
            try ProviderNetworkSession.validateHTTPS(
                URLRequest(
                    url: URL(string: "https://api.openai.com.attacker.example/v1/responses")!),
                allowedHost: "api.openai.com"
            )
        )
    }

    func testImageNormalizerRejectsInvalidAndExcessInputs() throws {
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
    }

    @MainActor
    func testImageNormalizerBoundsDimensionsAndStripsMetadata() throws {
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
        try PersonaRepository(container: container).seedPersonasIfNeeded()
        try context.save()

        try FrameReplyDataStore.deleteAllUserData(in: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<ChatRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ChatMessageRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PersonaRecord>()).isEmpty)
    }
}
