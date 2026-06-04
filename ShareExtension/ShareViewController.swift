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
            cancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CancellationError())
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
                if input.imageData == nil {
                    input.imageData = await provider.firstImageData()
                    if input.filename.isEmpty {
                        input.filename = provider.suggestedName.map { "\($0).png" } ?? "shared-screenshot.png"
                    }
                }

                if input.sourceText.isEmpty {
                    input.sourceText = await provider.firstText()
                }
            }
        }

        return input
    }
}

struct SharedCaptureInput {
    var imageData: Data?
    var filename: String = ""
    var sourceText: String = ""
}

private extension NSItemProvider {
    func firstImageData() async -> Data? {
        let identifiers = [UTType.png.identifier, UTType.jpeg.identifier, UTType.image.identifier]
        for identifier in identifiers where hasItemConformingToTypeIdentifier(identifier) {
            if let data = try? await loadDataRepresentation(forTypeIdentifier: identifier) {
                return data
            }
        }
        return nil
    }

    func firstText() async -> String {
        if hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = try? await loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
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
