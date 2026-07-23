import Foundation
import UniformTypeIdentifiers
import XCTest

@testable import FrameReply

final class ChatScreenshotPhotoLoaderTests: XCTestCase {
    func testRejectsEntireSelectionWhenAnyImageIsUnreadable() {
        let valid = ChatScreenshotPhotoLoader.LoadedImage(
            data: pngData,
            contentType: .png
        )
        let invalid = ChatScreenshotPhotoLoader.LoadedImage(
            data: Data("not an image".utf8),
            contentType: .png
        )

        XCTAssertThrowsError(
            try ChatScreenshotPhotoLoader.validatedData(from: [valid, invalid])
        ) { error in
            guard let loaderError = error as? ChatScreenshotPhotoLoaderError,
                case .unreadableImage(let position) = loaderError
            else {
                return XCTFail("Expected unreadableImage")
            }
            XCTAssertEqual(position, 2)
        }
    }

    func testPreservesAllImagesWhenEverySelectionIsReadable() throws {
        let images = [
            ChatScreenshotPhotoLoader.LoadedImage(data: pngData, contentType: .png),
            ChatScreenshotPhotoLoader.LoadedImage(data: pngData, contentType: .image)
        ]

        XCTAssertEqual(
            try ChatScreenshotPhotoLoader.validatedData(from: images),
            [pngData, pngData]
        )
    }

    private var pngData: Data {
        Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
    }
}
