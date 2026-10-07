import XCTest

@testable import FrameReply

@MainActor
final class ChatHistoryTranslationTests: XCTestCase {
    func testHiddenTranslationIsReusedOnlyForTheSameMessageTextAndTarget() throws {
        let translation = ChatHistoryTranslation()
        let messageID = UUID()
        let key = ChatHistoryTranslation.Key(
            messageID: messageID, sourceText: "Bonjour", targetLanguageIdentifier: "en"
        )
        let request = try XCTUnwrap(translation.begin(key))
        translation.finish(request, text: "Hello")
        translation.hide(key)

        XCTAssertNil(translation.states[key])
        XCTAssertNil(translation.begin(key))
        XCTAssertEqual(translation.states[key], .translated("Hello"))

        let otherKeys = [
            ChatHistoryTranslation.Key(
                messageID: messageID, sourceText: "Bonsoir", targetLanguageIdentifier: "en"),
            ChatHistoryTranslation.Key(
                messageID: messageID, sourceText: "Bonjour", targetLanguageIdentifier: "zh-Hans"),
            ChatHistoryTranslation.Key(
                messageID: UUID(), sourceText: "Bonjour", targetLanguageIdentifier: "en")
        ]
        for otherKey in otherKeys {
            XCTAssertNotNil(translation.begin(otherKey))
        }
    }

    func testCancelledRequestCannotOverwriteOrCancelItsReplacement() throws {
        let translation = ChatHistoryTranslation()
        let key = ChatHistoryTranslation.Key(
            messageID: UUID(), sourceText: "Bonjour", targetLanguageIdentifier: "en"
        )
        let oldRequest = try XCTUnwrap(translation.begin(key))
        XCTAssertNil(translation.begin(key))
        translation.cancel(oldRequest)
        let newRequest = try XCTUnwrap(translation.begin(key))

        translation.finish(oldRequest, text: "Stale translation")
        translation.fail(oldRequest, reason: .failed)
        translation.cancel(oldRequest)
        XCTAssertTrue(translation.isTranslating(newRequest))

        translation.finish(newRequest, text: "Hello")
        translation.hide(key)
        translation.finish(oldRequest, text: "Stale translation")
        XCTAssertNil(translation.states[key])
        XCTAssertNil(translation.begin(key))
        XCTAssertEqual(translation.states[key], .translated("Hello"))
    }

    func testFailureCanBeRetriedWithoutCachingAnEmptyResult() throws {
        let translation = ChatHistoryTranslation()
        let key = ChatHistoryTranslation.Key(
            messageID: UUID(), sourceText: "Bonjour", targetLanguageIdentifier: "en"
        )
        let firstRequest = try XCTUnwrap(translation.begin(key))
        translation.fail(firstRequest, reason: .unsupportedLanguage)
        XCTAssertEqual(translation.states[key], .failed(.unsupportedLanguage))

        let retry = try XCTUnwrap(translation.begin(key))
        translation.finish(retry, text: " \n ")
        XCTAssertEqual(translation.states[key], .failed(.failed))
        let finalRequest = try XCTUnwrap(translation.begin(key))
        translation.finish(finalRequest, text: "Hello")
        XCTAssertEqual(translation.states[key], .translated("Hello"))
    }
}
