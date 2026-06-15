//
//  ImageExporter.swift
//  KaleidoSense
//
//  Saves a rendered CGImage to the photo library and prepares a UIImage for
//  the system share sheet.
//

import UIKit
import Photos

enum ExportError: LocalizedError {
    case photoPermissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .photoPermissionDenied: return "Photo Library access is required to save."
        case .saveFailed:            return "The image could not be saved."
        }
    }
}

enum ImageExporter {

    /// Wraps a CGImage as a UIImage for sharing/preview.
    nonisolated static func uiImage(from cgImage: CGImage) -> UIImage {
        UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    /// Requests permission and saves the image to the user's photo library.
    ///
    /// `nonisolated` is essential: the `performChanges` block is executed by
    /// Photos on a background queue. Under the project's MainActor default
    /// isolation an inline closure would be inferred @MainActor and crash with
    /// a libdispatch queue assertion when run off the main thread.
    nonisolated static func saveToPhotos(_ cgImage: CGImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.photoPermissionDenied
        }
        let image = uiImage(from: cgImage)
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}
