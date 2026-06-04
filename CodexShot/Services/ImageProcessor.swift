import Foundation
import UIKit
import UniformTypeIdentifiers

enum ImageProcessor {
    static func mimeType(for data: Data, filename: String = "screenshot.png") -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }

        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }

        if filename.lowercased().hasSuffix(".jpg") || filename.lowercased().hasSuffix(".jpeg") {
            return "image/jpeg"
        }

        return "image/png"
    }

    static func normalizedUploadData(from data: Data) -> Data {
        let maxRawBytes = 7_500_000
        guard data.count > maxRawBytes, let image = UIImage(data: data) else {
            return data
        }

        let maxDimension: CGFloat = 1800
        let scale = min(maxDimension / max(image.size.width, image.size.height), 1)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.jpegData(withCompressionQuality: 0.82) { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    static func thumbnailData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else {
            return nil
        }

        let maxDimension: CGFloat = 420
        let scale = min(maxDimension / max(image.size.width, image.size.height), 1)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.jpegData(withCompressionQuality: 0.72) { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

