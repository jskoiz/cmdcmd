import Foundation
import Photos

struct LatestScreenshotCapture {
    var data: Data
    var filename: String
    var metadata: CaptureImageMetadata
}

enum LatestScreenshotProvider {
    static func loadLatestScreenshot() async throws -> LatestScreenshotCapture {
        try await authorizePhotoAccess()

        let screenshotSubtype = Int(PHAssetMediaSubtype.photoScreenshot.rawValue)
        let options = PHFetchOptions()
        options.fetchLimit = 1
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0",
            screenshotSubtype
        )
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]

        let result = PHAsset.fetchAssets(with: .image, options: options)
        guard let asset = result.firstObject else {
            throw LatestScreenshotError.noScreenshotFound
        }

        let data = try await imageData(for: asset)
        return LatestScreenshotCapture(
            data: data,
            filename: originalFilename(for: asset) ?? "latest-screenshot.png",
            metadata: CaptureImageMetadata(
                capturedAt: asset.creationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight
            )
        )
    }

    private static func authorizePhotoAccess() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let requestedStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    continuation.resume(returning: status)
                }
            }
            if requestedStatus == .authorized || requestedStatus == .limited {
                return
            }
            throw LatestScreenshotError.photosAccessDenied
        case .denied, .restricted:
            throw LatestScreenshotError.photosAccessDenied
        @unknown default:
            throw LatestScreenshotError.photosAccessDenied
        }
    }

    private static func imageData(for asset: PHAsset) async throws -> Data {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: LatestScreenshotError.imageDataUnavailable)
                }
            }
        }
    }

    private static func originalFilename(for asset: PHAsset) -> String? {
        PHAssetResource.assetResources(for: asset)
            .first { resource in
                resource.type == .photo || resource.type == .fullSizePhoto
            }?
            .originalFilename
    }
}

enum LatestScreenshotError: LocalizedError {
    case photosAccessDenied
    case noScreenshotFound
    case imageDataUnavailable

    var errorDescription: String? {
        switch self {
        case .photosAccessDenied:
            "Allow Photos access to send the latest screenshot."
        case .noScreenshotFound:
            "No recent screenshot was found in Photos."
        case .imageDataUnavailable:
            "The latest screenshot could not be loaded."
        }
    }
}
