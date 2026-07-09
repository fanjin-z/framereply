//
//  ChatScreenshotImageInput.swift
//  zeptly
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ChatScreenshotImageInput {
    static func isSupportedImage(data: Data, filename: String? = nil, type: UTType? = nil) -> Bool {
        if let type {
            return type.conforms(to: .image)
        }

        if let filename {
            let fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
            if !fileExtension.isEmpty,
                let inferredType = UTType(filenameExtension: fileExtension),
                inferredType.conforms(to: .image)
            {
                return true
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

        return !data.isEmpty
    }
}
