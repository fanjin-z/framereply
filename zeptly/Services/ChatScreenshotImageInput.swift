//
//  ChatScreenshotImageInput.swift
//  zeptly
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ChatScreenshotImageInput {
    static func isSupportedImage(data: Data, filename: String? = nil, type: UTType? = nil) -> Bool {
        guard !data.isEmpty else {
            return false
        }

        if let type, !type.conforms(to: .image) {
            return false
        }

        if type == nil, let filename {
            let fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
            if !fileExtension.isEmpty,
                let inferredType = UTType(filenameExtension: fileExtension),
                !inferredType.conforms(to: .image)
            {
                return false
            }
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }

        if let typeIdentifier = CGImageSourceGetType(source) as String?,
            let sourceType = UTType(typeIdentifier),
            sourceType.conforms(to: .image)
        {
            return true
        }

        if CGImageSourceGetCount(source) > 0 {
            return true
        }

        return false
    }
}
