import Foundation
import UIKit
import Vision

struct AvatarArtifact: Equatable, Sendable {
    static let algorithmRevision = 1

    let imageData: Data
    let perceptualHash: UInt64
    let featurePrintData: Data
    let quality: Double
    let revision: Int
}

struct StoredAvatarFingerprint: Equatable, Sendable {
    let chatID: String
    let perceptualHash: UInt64
    let featurePrintData: Data
    let quality: Double
    let revision: Int
}

struct AvatarSimilarity: Equatable, Sendable {
    let chatID: String
    let hashDistance: Int
    let featureDistance: Float

    var passesAbsoluteThresholds: Bool {
        hashDistance <= 6 && featureDistance <= 1.0
    }
}

enum AvatarIdentityService {
    private static let outputSize = CGSize(width: 128, height: 128)
    private static let maximumStoredBytes = 40_000

    static func extract(from screenshotData: Data, bounds: NormalizedAvatarBounds?)
        -> AvatarArtifact?
    {
        guard let bounds, let screenshot = UIImage(data: screenshotData),
            validates(bounds, imageSize: screenshot.size)
        else {
            return nil
        }

        let imageSize = screenshot.size
        var crop = CGRect(
            x: bounds.x * imageSize.width,
            y: bounds.y * imageSize.height,
            width: bounds.width * imageSize.width,
            height: bounds.height * imageSize.height
        )
        let inset = min(crop.width, crop.height) * 0.06
        crop = crop.insetBy(dx: inset, dy: inset)
        guard crop.width >= 16, crop.height >= 16 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let normalized = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            let scale = max(outputSize.width / crop.width, outputSize.height / crop.height)
            screenshot.draw(
                in: CGRect(
                    x: -crop.minX * scale,
                    y: -crop.minY * scale,
                    width: imageSize.width * scale,
                    height: imageSize.height * scale
                )
            )
        }

        guard let cgImage = normalized.cgImage,
            let luma = grayscalePixels(cgImage, size: 32),
            let hash = perceptualHash(luma),
            let featurePrint = featurePrint(for: cgImage),
            let archived = try? NSKeyedArchiver.archivedData(
                withRootObject: featurePrint,
                requiringSecureCoding: true
            )
        else {
            return nil
        }

        let quality = informationQuality(luma)
        guard quality >= 0.08 else { return nil }

        var jpeg = normalized.jpegData(compressionQuality: 0.82)
        if let data = jpeg, data.count > maximumStoredBytes {
            jpeg = normalized.jpegData(compressionQuality: 0.62)
        }
        guard let jpeg, jpeg.count <= maximumStoredBytes else { return nil }

        return AvatarArtifact(
            imageData: jpeg,
            perceptualHash: hash,
            featurePrintData: archived,
            quality: quality,
            revision: AvatarArtifact.algorithmRevision
        )
    }

    static func similarities(
        artifact: AvatarArtifact?,
        candidates: [StoredAvatarFingerprint]
    ) -> [AvatarSimilarity] {
        guard let artifact,
            let current = unarchiveFeaturePrint(artifact.featurePrintData)
        else {
            return []
        }

        return candidates.compactMap { candidate in
            guard candidate.revision == artifact.revision,
                candidate.quality >= 0.08,
                let stored = unarchiveFeaturePrint(candidate.featurePrintData)
            else {
                return nil
            }

            var distance: Float = 0
            guard (try? current.computeDistance(&distance, to: stored)) != nil else {
                return nil
            }
            return AvatarSimilarity(
                chatID: candidate.chatID,
                hashDistance: (artifact.perceptualHash ^ candidate.perceptualHash).nonzeroBitCount,
                featureDistance: distance
            )
        }
        .sorted {
            if $0.featureDistance == $1.featureDistance {
                return $0.hashDistance < $1.hashDistance
            }
            return $0.featureDistance < $1.featureDistance
        }
    }

    static func uniqueStrongMatch(in similarities: [AvatarSimilarity]) -> String? {
        guard let best = similarities.first, best.passesAbsoluteThresholds else { return nil }
        let duplicateHashCount = similarities.filter {
            $0.hashDistance == best.hashDistance && $0.featureDistance <= 1.0
        }.count
        guard duplicateHashCount == 1 else { return nil }

        guard similarities.count > 1 else { return best.chatID }
        let runnerUp = similarities[1]
        guard best.featureDistance <= runnerUp.featureDistance * 0.65 else { return nil }
        return best.chatID
    }

    private static func validates(_ bounds: NormalizedAvatarBounds, imageSize: CGSize) -> Bool {
        let values = [bounds.x, bounds.y, bounds.width, bounds.height]
        guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
            bounds.x + bounds.width <= 1,
            bounds.y + bounds.height <= 0.35,
            (0.025...0.24).contains(bounds.width),
            (0.025...0.24).contains(bounds.height)
        else {
            return false
        }
        let aspect = (bounds.width * imageSize.width) / (bounds.height * imageSize.height)
        return (0.65...1.35).contains(aspect)
    }

    private static func featurePrint(for image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        #if targetEnvironment(simulator)
            if let devicesByStage = try? request.supportedComputeStageDevices {
                for (stage, devices) in devicesByStage {
                    let cpu = devices.first { device in
                        if case .cpu = device {
                            return true
                        }
                        return false
                    }
                    if let cpu {
                        request.setComputeDevice(cpu, for: stage)
                    }
                }
            }
        #endif
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results?.first as? VNFeaturePrintObservation
    }

    private static func unarchiveFeaturePrint(_ data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    private static func grayscalePixels(_ image: CGImage, size: Int) -> [Double]? {
        var bytes = [UInt8](repeating: 0, count: size * size)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: size,
                    height: size,
                    bitsPerComponent: 8,
                    bytesPerRow: size,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard rendered else { return nil }
        return bytes.map { Double($0) }
    }

    private static func informationQuality(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return min(1, sqrt(variance) / 64)
    }

    /// A compact DCT perceptual hash; intended for near-duplicate image matching only.
    private static func perceptualHash(_ pixels: [Double]) -> UInt64? {
        guard pixels.count == 32 * 32 else { return nil }
        var coefficients = [Double]()
        coefficients.reserveCapacity(64)

        for v in 0..<8 {
            for u in 0..<8 {
                var sum = 0.0
                for y in 0..<32 {
                    let yCos = cos((Double(2 * y + 1) * Double(v) * .pi) / 64)
                    for x in 0..<32 {
                        let xCos = cos((Double(2 * x + 1) * Double(u) * .pi) / 64)
                        sum += pixels[y * 32 + x] * xCos * yCos
                    }
                }
                let uScale = u == 0 ? 1 / sqrt(2.0) : 1
                let vScale = v == 0 ? 1 / sqrt(2.0) : 1
                coefficients.append(0.25 * uScale * vScale * sum)
            }
        }

        let sorted = coefficients.dropFirst().sorted()
        guard let median = sorted.isEmpty ? nil : sorted[sorted.count / 2] else { return nil }
        return coefficients.enumerated().reduce(into: UInt64(0)) { result, item in
            if item.element > median {
                result |= UInt64(1) << UInt64(item.offset)
            }
        }
    }
}
