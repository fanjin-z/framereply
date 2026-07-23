//
//  ChatScreenshotPhotoLoader.swift
//  FrameReply
//

import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum ChatScreenshotPhotoLoaderError: LocalizedError {
    case noReadableImages
    case unreadableImage(position: Int)

    var errorDescription: String? {
        switch self {
        case .noReadableImages:
            String(localized: AppStrings.Errors.Import.unreadableImage)
        case .unreadableImage:
            String(localized: AppStrings.Errors.Import.unreadableImage)
        }
    }
}

enum ChatScreenshotPhotoLoader {
    struct LoadedImage {
        let data: Data?
        let contentType: UTType?
    }

    static func loadData(from items: [PhotosPickerItem]) async throws -> [Data] {
        var loadedImages: [LoadedImage] = []
        for item in items {
            loadedImages.append(
                LoadedImage(
                    data: try await item.loadTransferable(type: Data.self),
                    contentType: item.supportedContentTypes.first
                )
            )
        }
        return try validatedData(from: loadedImages)
    }

    static func validatedData(from images: [LoadedImage]) throws -> [Data] {
        guard !images.isEmpty else {
            throw ChatScreenshotPhotoLoaderError.noReadableImages
        }

        return try images.enumerated().map { index, image in
            guard let data = image.data,
                ChatScreenshotImageInput.isSupportedImage(
                    data: data,
                    type: image.contentType
                )
            else {
                throw ChatScreenshotPhotoLoaderError.unreadableImage(position: index + 1)
            }
            return data
        }
    }
}
