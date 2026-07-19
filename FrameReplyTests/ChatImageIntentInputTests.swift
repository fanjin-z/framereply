import AppIntents
import Foundation
import UniformTypeIdentifiers
import XCTest

@testable import FrameReply

final class ChatImageIntentInputTests: XCTestCase {
    func testAcceptsOneAndEightImagesPreservingDataAndOrder() throws {
        let single = pngData(marker: 1)
        XCTAssertEqual(
            try ChatImageIntentInput.validatedData(from: [imageFile(data: single)]),
            [single]
        )

        let data = (1...8).map { pngData(marker: UInt8($0)) }
        XCTAssertEqual(
            try ChatImageIntentInput.validatedData(from: data.map(imageFile(data:))),
            data
        )
    }

    func testRejectsZeroAndNineImages() {
        XCTAssertThrowsError(try ChatImageIntentInput.validatedData(from: [])) { error in
            XCTAssertEqual(error as? ChatImageIntentInputError, .noImages)
        }
        let files = (1...9).map { imageFile(data: pngData(marker: UInt8($0))) }
        XCTAssertThrowsError(try ChatImageIntentInput.validatedData(from: files)) { error in
            XCTAssertEqual(
                error as? ChatImageIntentInputError,
                .tooManyImages(maximum: ChatImageIntentInput.maximumImageCount)
            )
        }
    }

    func testRejectsEmptyUnsupportedAndUnreadableImages() {
        let invalidFiles: [(IntentFile, Int)] = [
            (imageFile(data: Data()), 1),
            (
                IntentFile(
                    data: Data("not an image".utf8), filename: "chat.txt", type: .plainText),
                1
            ),
            (IntentFile(data: Data([1, 2, 3]), filename: "chat.png", type: .png), 1)
        ]

        for (file, position) in invalidFiles {
            XCTAssertThrowsError(try ChatImageIntentInput.validatedData(from: [file])) { error in
                XCTAssertEqual(
                    error as? ChatImageIntentInputError,
                    .invalidImage(position: position)
                )
            }
        }
    }

    private func imageFile(data: Data) -> IntentFile {
        IntentFile(data: data, filename: "chat.png", type: .png)
    }

    private func pngData(marker: UInt8) -> Data {
        var data = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
        data.append(marker)
        return data
    }
}
