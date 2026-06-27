//
//  ChatScreenshotOCR.swift
//  zeptly
//

import Foundation

nonisolated struct OCRBoundingBox: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

nonisolated struct OCRLine: Codable, Equatable, Sendable {
    let text: String
    let confidence: Float
    let boundingBox: OCRBoundingBox
}

nonisolated struct OCRDocument: Codable, Equatable, Sendable {
    let lines: [OCRLine]

    var modelText: String {
        lines.enumerated().map { index, line in
            let box = line.boundingBox
            return "[\(index)] x=\(format(box.x)) y=\(format(box.y)) w=\(format(box.width)) h=\(format(box.height)) confidence=\(format(Double(line.confidence))) text=\(line.text)"
        }.joined(separator: "\n")
    }

    static func readingOrder(_ lines: [OCRLine]) -> [OCRLine] {
        lines.sorted { lhs, rhs in
            let lhsRow = Int(lhs.boundingBox.y * 100)
            let rhsRow = Int(rhs.boundingBox.y * 100)
            if lhsRow != rhsRow {
                return lhsRow > rhsRow
            }
            return lhs.boundingBox.x < rhs.boundingBox.x
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

nonisolated enum ScreenshotOCRError: LocalizedError, Equatable {
    case invalidImage
    case noText
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "The screenshot could not be decoded as an image."
        case .noText:
            "No readable chat text was found in the screenshot."
        case .recognitionFailed:
            "The screenshot text could not be recognized."
        }
    }
}
