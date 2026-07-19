//
//  ChatScreenshotPhotoLoader.swift
//  FrameReply
//

import Foundation
import PhotosUI
import SwiftUI

enum ChatScreenshotPhotoLoaderError: LocalizedError {
    case noReadableImages

    var errorDescription: String? {
        switch self {
        case .noReadableImages:
            "The selected screenshot could not be read. Choose a still PNG, JPEG, or HEIC image."
        }
    }
}

enum ChatScreenshotPhotoLoader {
    static func loadData(from items: [PhotosPickerItem]) async throws -> [Data] {
        var imageDataList: [Data] = []
        for item in items {
            guard let data = try await item.loadTransferable(type: Data.self),
                ChatScreenshotImageInput.isSupportedImage(
                    data: data,
                    type: item.supportedContentTypes.first
                )
            else {
                continue
            }
            imageDataList.append(data)
        }

        guard !imageDataList.isEmpty else {
            throw ChatScreenshotPhotoLoaderError.noReadableImages
        }
        return imageDataList
    }
}
