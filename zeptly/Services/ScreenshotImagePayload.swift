import Foundation

nonisolated struct ScreenshotImagePayload: Equatable, Sendable {
    let dataURL: String

    init(data: Data) throws {
        guard data.isEmpty == false else {
            throw ProviderConnectionError.invalidResponse("The screenshot image is empty.")
        }

        let mimeType: String
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            mimeType = "image/png"
        } else if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            mimeType = "image/jpeg"
        } else if data.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            mimeType = "image/gif"
        } else if data.count >= 12,
            String(data: data.prefix(4), encoding: .ascii) == "RIFF",
            String(data: data.dropFirst(8).prefix(4), encoding: .ascii) == "WEBP"
        {
            mimeType = "image/webp"
        } else {
            throw ProviderConnectionError.invalidResponse(
                "The screenshot image format is not supported.")
        }

        dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}
