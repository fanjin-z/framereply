import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ScreenshotImageNormalizer {
    static let maximumImageCount = 8
    static let maximumPixelEdge = 3_072
    static let maximumBytesPerImage = 5 * 1_024 * 1_024
    static let maximumTotalBytes = 20 * 1_024 * 1_024

    private static let maximumSourcePixelEdge = 20_000
    private static let maximumSourcePixelCount = 80_000_000

    static func normalize(_ images: [Data]) throws -> [Data] {
        guard images.isEmpty == false else {
            throw ScreenshotImportError.noImage
        }
        guard images.count <= maximumImageCount else {
            throw ScreenshotImportError.tooManyImages
        }

        var normalized: [Data] = []
        var totalBytes = 0
        for image in images {
            let output = try normalize(image)
            totalBytes += output.count
            guard totalBytes <= maximumTotalBytes else {
                throw ScreenshotImportError.imagePayloadTooLarge
            }
            normalized.append(output)
        }
        return normalized
    }

    static func normalize(_ data: Data) throws -> Data {
        guard data.isEmpty == false,
            let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ),
            CGImageSourceGetCount(source) == 1,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0,
            height > 0,
            width <= maximumSourcePixelEdge,
            height <= maximumSourcePixelEdge,
            width <= maximumSourcePixelCount / height
        else {
            throw ScreenshotImportError.unsupportedImage
        }

        let attempts: [(edge: Int, quality: Double)] = [
            (maximumPixelEdge, 0.85),
            (2_560, 0.76),
            (2_048, 0.68),
            (1_536, 0.60)
        ]
        for attempt in attempts {
            guard let image = thumbnail(from: source, maximumEdge: attempt.edge) else {
                continue
            }
            let output = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    output,
                    UTType.jpeg.identifier as CFString,
                    1,
                    nil
                )
            else {
                continue
            }
            CGImageDestinationAddImage(
                destination,
                image,
                [kCGImageDestinationLossyCompressionQuality: attempt.quality] as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else {
                continue
            }
            let result = output as Data
            if result.count <= maximumBytesPerImage {
                return result
            }
        }

        throw ScreenshotImportError.imagePayloadTooLarge
    }

    private static func thumbnail(from source: CGImageSource, maximumEdge: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumEdge,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary
        )
    }
}
