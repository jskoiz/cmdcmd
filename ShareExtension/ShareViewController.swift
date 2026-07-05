import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let rootView = ShareCaptureView(
            loadInput: { [weak self] in
                await self?.loadInput() ?? SharedCaptureInput()
            },
            finish: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            openSettings: { [weak self] completion in
                self?.openContainingAppSettings(completion: completion)
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    private func loadInput() async -> SharedCaptureInput {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return SharedCaptureInput()
        }

        var input = SharedCaptureInput()

        for item in items {
            for provider in item.attachments ?? [] {
                if let image = await provider.sharedImageCandidate() {
                    input.images.append(image)
                }

                if input.sourceText.isEmpty {
                    input.sourceText = await provider.firstText()
                }
            }
        }

        return input
    }

    private func openContainingAppSettings(completion: @escaping (Bool) -> Void) {
        guard let extensionContext,
              let url = URL(string: "cmdcmd://settings") else {
            completion(false)
            return
        }

        extensionContext.open(url, completionHandler: completion)
    }
}

struct SharedCaptureInput {
    var images: [SharedCaptureImage] = []
    var sourceText: String = ""

    var previewImageData: Data? {
        images.first?.data
    }
}

struct SharedCaptureImage: Equatable {
    var data: Data
    var filename: String
}

private extension NSItemProvider {
    func sharedImageCandidate() async -> SharedCaptureImage? {
        let identifiers = preferredImageTypeIdentifiers()
        for identifier in identifiers where hasItemConformingToTypeIdentifier(identifier) {
            let fallbackName = filename(for: identifier)
            if let data = try? await loadDataRepresentation(forTypeIdentifier: identifier),
               UIImage(data: data) != nil {
                return SharedCaptureImage(data: data, filename: fallbackName)
            }

            if let file = try? await loadFileDataRepresentation(forTypeIdentifier: identifier),
               UIImage(data: file.data) != nil {
                return SharedCaptureImage(data: file.data, filename: file.filename ?? fallbackName)
            }

            if let item = try? await loadItem(forTypeIdentifier: identifier),
               let image = imageCandidate(from: item, fallbackFilename: fallbackName) {
                return image
            }
        }
        return nil
    }

    func preferredImageTypeIdentifiers() -> [String] {
        var identifiers = [
            UTType.png.identifier,
            UTType.jpeg.identifier,
            UTType.image.identifier
        ]

        identifiers.append(
            contentsOf: registeredTypeIdentifiers.filter { identifier in
                guard let type = UTType(identifier) else {
                    return false
                }
                return type.conforms(to: .image)
            }
        )

        var seen = Set<String>()
        return identifiers.filter { seen.insert($0).inserted }
    }

    func filename(for typeIdentifier: String) -> String {
        let suggested = suggestedName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")

        let base = suggested?.isEmpty == false ? suggested! : "shared-screenshot"
        let existingExtension = URL(fileURLWithPath: base).pathExtension
        if let type = UTType(filenameExtension: existingExtension), type.conforms(to: .image) {
            return base
        }

        let preferredExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "png"
        return "\(base).\(preferredExtension)"
    }

    func imageCandidate(from item: NSSecureCoding, fallbackFilename: String) -> SharedCaptureImage? {
        if let data = item as? Data, UIImage(data: data) != nil {
            return SharedCaptureImage(data: data, filename: fallbackFilename)
        }

        if let url = item as? URL {
            return imageCandidate(from: url, fallbackFilename: fallbackFilename)
        }

        if let url = item as? NSURL {
            return imageCandidate(from: url as URL, fallbackFilename: fallbackFilename)
        }

        if let image = item as? UIImage,
           let data = image.pngData() ?? image.jpegData(compressionQuality: 0.92) {
            return SharedCaptureImage(data: data, filename: fallbackFilename)
        }

        return nil
    }

    func imageCandidate(from url: URL, fallbackFilename: String) -> SharedCaptureImage? {
        guard let data = try? Data(contentsOf: url), UIImage(data: data) != nil else {
            return nil
        }

        let filename = url.lastPathComponent.isEmpty ? fallbackFilename : url.lastPathComponent
        return SharedCaptureImage(data: data, filename: filename)
    }

    func firstText() async -> String {
        if hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = try? await loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
           !url.isFileURL {
            return url.absoluteString
        }

        if hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = try? await loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
            return text
        }

        return ""
    }

    func loadDataRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    func loadFileDataRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> (data: Data, filename: String?) {
        try await withCheckedThrowingContinuation { continuation in
            loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    do {
                        let data = try Data(contentsOf: url)
                        let filename = url.lastPathComponent.isEmpty ? nil : url.lastPathComponent
                        continuation.resume(returning: (data, filename))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    func loadItem(forTypeIdentifier typeIdentifier: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let item {
                    continuation.resume(returning: item)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }
}
