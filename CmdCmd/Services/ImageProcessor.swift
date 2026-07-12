import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct PreparedImage: Equatable {
    var data: Data
    var mimeType: String
    var filename: String
    var pixelWidth: Int
    var pixelHeight: Int
    var thumbnailData: Data?
}

enum ImagePreparationError: LocalizedError {
    case invalidImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "The selected file is not a readable image."
        case .encodingFailed:
            "The selected image could not be prepared for upload."
        }
    }
}

enum ImageProcessor {
    private static let maxRawBytes = 7_500_000
    private static let maxUploadDimension = 1_800
    private static let maxThumbnailDimension = 420

    static func prepare(data: Data, filename: String) throws -> PreparedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let sourceTypeIdentifier = CGImageSourceGetType(source) as String?,
              let sourceType = UTType(sourceTypeIdentifier),
              sourceType.conforms(to: .image),
              let sourceDimensions = dimensions(of: source) else {
            throw ImagePreparationError.invalidImage
        }

        let canonicalType = canonicalType(for: sourceType)
        let requiresTranscoding = canonicalType == nil || data.count > maxRawBytes

        let uploadData: Data
        let uploadType: UTType
        let uploadDimensions: (width: Int, height: Int)
        let uploadImage: CGImage?

        if !requiresTranscoding, let canonicalType {
            uploadData = data
            uploadType = canonicalType
            uploadDimensions = sourceDimensions
            uploadImage = nil
        } else {
            let boundedUpload = try boundedUpload(from: source)
            uploadType = boundedUpload.type
            uploadData = boundedUpload.data
            uploadDimensions = (boundedUpload.image.width, boundedUpload.image.height)
            uploadImage = boundedUpload.image
        }

        let thumbnailImage = uploadImage.flatMap { image in
            downsampledImage(from: image, maxPixelSize: maxThumbnailDimension)
        } ?? downsampledImage(from: source, maxPixelSize: maxThumbnailDimension)
        let thumbnailData = thumbnailImage.flatMap { image in
            try? encodedData(for: image, type: .jpeg, compressionQuality: 0.72)
        }

        return PreparedImage(
            data: uploadData,
            mimeType: mimeType(for: uploadType),
            filename: canonicalFilename(filename, type: uploadType),
            pixelWidth: uploadDimensions.width,
            pixelHeight: uploadDimensions.height,
            thumbnailData: thumbnailData
        )
    }

    private static func canonicalType(for type: UTType) -> UTType? {
        if type.conforms(to: .png) {
            return .png
        }
        if type.conforms(to: .jpeg) {
            return .jpeg
        }
        return nil
    }

    private static func dimensions(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0 else {
            return nil
        }

        return (width, height)
    }

    private static func downsampledImage(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func boundedUpload(
        from source: CGImageSource
    ) throws -> (data: Data, type: UTType, image: CGImage) {
        var maxPixelSize = maxUploadDimension

        while maxPixelSize > 0 {
            guard let image = downsampledImage(from: source, maxPixelSize: maxPixelSize) else {
                throw ImagePreparationError.invalidImage
            }

            let type: UTType = hasAlpha(image) ? .png : .jpeg
            let data = try encodedData(for: image, type: type)
            if data.count <= maxRawBytes {
                return (data, type, image)
            }

            let currentDimension = max(image.width, image.height)
            guard currentDimension > 1 else {
                throw ImagePreparationError.encodingFailed
            }

            let byteRatio = Double(maxRawBytes) / Double(data.count)
            let proportionalDimension = Int(
                Double(currentDimension) * sqrt(byteRatio) * 0.9
            )
            maxPixelSize = max(
                min(proportionalDimension, currentDimension - 1, maxPixelSize - 1),
                1
            )
        }

        throw ImagePreparationError.encodingFailed
    }

    private static func downsampledImage(from image: CGImage, maxPixelSize: Int) -> CGImage? {
        let maxDimension = max(image.width, image.height)
        guard maxDimension > maxPixelSize else {
            return image
        }

        let scale = CGFloat(maxPixelSize) / CGFloat(maxDimension)
        let size = CGSize(
            width: max(CGFloat(image.width) * scale, 1),
            height: max(CGFloat(image.height) * scale, 1)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !hasAlpha(image)
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in
                UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
            }
            .cgImage
    }

    private static func encodedData(
        for image: CGImage,
        type: UTType,
        compressionQuality: CGFloat = 0.82
    ) throws -> Data {
        let uiImage = UIImage(cgImage: image)
        let data: Data?
        if type == .png {
            data = uiImage.pngData()
        } else {
            data = uiImage.jpegData(compressionQuality: compressionQuality)
        }

        guard let data else {
            throw ImagePreparationError.encodingFailed
        }
        return data
    }

    private static func canonicalFilename(_ filename: String, type: UTType) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(fileURLWithPath: trimmed.isEmpty ? "screenshot" : trimmed)
        let stem = url.deletingPathExtension().lastPathComponent
        let safeStem = stem.isEmpty ? "screenshot" : stem
        let fileExtension = type == .jpeg ? "jpg" : "png"
        return "\(safeStem).\(fileExtension)"
    }

    private static func mimeType(for type: UTType) -> String {
        type == .jpeg ? "image/jpeg" : "image/png"
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            false
        case .premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly:
            true
        @unknown default:
            true
        }
    }
}
