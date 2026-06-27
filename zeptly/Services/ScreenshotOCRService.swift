//
//  ScreenshotOCRService.swift
//  zeptly
//

import Foundation
import ImageIO
import Vision

nonisolated protocol ScreenshotOCRService: Sendable {
    func recognizeText(in imageData: Data) async throws -> OCRDocument
}

nonisolated struct VisionScreenshotOCRService: ScreenshotOCRService {
    private let minimumConfidence: Float

    init(minimumConfidence: Float = 0.2) {
        self.minimumConfidence = minimumConfidence
    }

    func recognizeText(in imageData: Data) async throws -> OCRDocument {
        let minimumConfidence = minimumConfidence
        return try await Task.detached(priority: .userInitiated) {
            guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
                CGImageSourceGetCount(imageSource) > 0
            else {
                throw ScreenshotOCRError.invalidImage
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(
                data: imageData,
                orientation: imageOrientation(from: imageData),
                options: [:]
            )

            do {
                try handler.perform([request])
            } catch {
                throw ScreenshotOCRError.recognitionFailed
            }

            let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
                guard let candidate = observation.topCandidates(1).first,
                    candidate.confidence >= minimumConfidence
                else {
                    return nil
                }

                let text = candidate.string
                    .split(whereSeparator: \Character.isWhitespace)
                    .joined(separator: " ")
                guard !text.isEmpty else {
                    return nil
                }

                let box = observation.boundingBox
                return OCRLine(
                    text: text,
                    confidence: candidate.confidence,
                    boundingBox: OCRBoundingBox(
                        x: box.origin.x,
                        y: box.origin.y,
                        width: box.size.width,
                        height: box.size.height
                    )
                )
            }

            let orderedLines = OCRDocument.readingOrder(lines)
            guard !orderedLines.isEmpty else {
                throw ScreenshotOCRError.noText
            }

            return OCRDocument(lines: orderedLines)
        }.value
    }
}

nonisolated private func imageOrientation(from data: Data) -> CGImagePropertyOrientation {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let rawOrientation = properties[kCGImagePropertyOrientation] as? NSNumber,
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation.uint32Value)
    else {
        return .up
    }
    return orientation
}
