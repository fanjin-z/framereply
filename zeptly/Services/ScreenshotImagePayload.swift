import Foundation

nonisolated struct ScreenshotImagePayload: Equatable, Sendable {
    let dataURL: String

    init(data: Data) throws {
        guard data.isEmpty == false else {
            throw ProviderConnectionError.invalidResponse("The screenshot image is empty.")
        }
        guard data.count <= ScreenshotImageNormalizer.maximumBytesPerImage else {
            throw ProviderConnectionError.invalidResponse("The screenshot image is too large.")
        }

        let mimeType: String
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            mimeType = "image/png"
        } else if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            mimeType = "image/jpeg"
        } else {
            throw ProviderConnectionError.invalidResponse(
                "The screenshot image must be normalized to PNG or JPEG before upload.")
        }

        dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}
