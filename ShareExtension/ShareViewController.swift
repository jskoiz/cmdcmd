import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let rootView = ShareCaptureView(
            loadInput: { [weak self] in
                try await self?.loadInput() ?? SharedCaptureInput()
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

    private func loadInput() async throws -> SharedCaptureInput {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return SharedCaptureInput()
        }

        var input = SharedCaptureInput()

        for item in items {
            for provider in item.attachments ?? [] {
                try Task.checkCancellation()
                if let image = try await provider.sharedImageCandidate() {
                    input.images.append(image)
                }

                if input.sourceText.isEmpty {
                    input.sourceText = try await provider.firstText()
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

private extension NSItemProvider {
    func sharedImageCandidate() async throws -> SharedCaptureImage? {
        let identifiers = preferredImageTypeIdentifiers()
        for identifier in identifiers where hasItemConformingToTypeIdentifier(identifier) {
            try Task.checkCancellation()
            let fallbackName = filename(for: identifier)
            do {
                let data = try await cancellableDataRepresentation(forTypeIdentifier: identifier)
                if UIImage(data: data) != nil {
                    return SharedCaptureImage(data: data, filename: fallbackName)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Try the provider's next representation.
            }

            do {
                let file = try await cancellableFileDataRepresentation(forTypeIdentifier: identifier)
                if UIImage(data: file.data) != nil {
                    return SharedCaptureImage(data: file.data, filename: file.filename ?? fallbackName)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Try the provider's next representation.
            }

            do {
                let item = try await cancellableItem(forTypeIdentifier: identifier)
                if let image = imageCandidate(from: item, fallbackFilename: fallbackName) {
                    return image
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Try the provider's next registered image type.
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
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url), UIImage(data: data) != nil else {
            return nil
        }

        let filename = url.lastPathComponent.isEmpty ? fallbackFilename : url.lastPathComponent
        return SharedCaptureImage(data: data, filename: filename)
    }

    func firstText() async throws -> String {
        try Task.checkCancellation()
        if hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            do {
                let url = try await cancellableURL()
                if !url.isFileURL {
                    return url.absoluteString
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Fall through to plain text.
            }
        }

        if hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            do {
                return try await cancellableString()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return ""
            }
        }

        return ""
    }

    func cancellableDataRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        let cancellation = ProgressCancellationController()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let progress = loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    }
                }
                cancellation.install(progress)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func cancellableFileDataRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> (data: Data, filename: String?) {
        let cancellation = ProgressCancellationController()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let progress = loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
                        defer {
                            if accessedSecurityScope {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
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
                cancellation.install(progress)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func cancellableItem(forTypeIdentifier typeIdentifier: String) async throws -> NSSecureCoding {
        let race = ItemLoadRace()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
                loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                    if let error {
                        race.resolve(.failure(error))
                    } else if let item {
                        race.resolve(.success(item))
                    } else {
                        race.resolve(.failure(CocoaError(.fileReadUnknown)))
                    }
                }
            }
        } onCancel: {
            race.resolve(.failure(CancellationError()))
        }
    }

    func cancellableURL() async throws -> URL {
        let cancellation = ProgressCancellationController()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let progress = loadObject(ofClass: URL.self) { item, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let item {
                        continuation.resume(returning: item)
                    } else {
                        continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    }
                }
                cancellation.install(progress)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func cancellableString() async throws -> String {
        let cancellation = ProgressCancellationController()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let progress = loadObject(ofClass: String.self) { item, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let item {
                        continuation.resume(returning: item)
                    } else {
                        continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    }
                }
                cancellation.install(progress)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}

private final class ItemLoadRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NSSecureCoding, Error>?
    private var result: Result<NSSecureCoding, Error>?

    func install(_ continuation: CheckedContinuation<NSSecureCoding, Error>) {
        let completedResult = lock.withLock { () -> Result<NSSecureCoding, Error>? in
            if let result {
                return result
            }
            self.continuation = continuation
            return nil
        }

        if let completedResult {
            continuation.resume(with: completedResult)
        }
    }

    func resolve(_ result: Result<NSSecureCoding, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<NSSecureCoding, Error>? in
            guard self.result == nil else {
                return nil
            }
            self.result = result
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}

private final class ProgressCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var progress: Progress?
    private var cancelled = false

    func install(_ progress: Progress) {
        let shouldCancel = lock.withLock { () -> Bool in
            if cancelled {
                return true
            }
            self.progress = progress
            return false
        }
        if shouldCancel {
            progress.cancel()
        }
    }

    func cancel() {
        let progress = lock.withLock { () -> Progress? in
            guard !cancelled else {
                return nil
            }
            cancelled = true
            return self.progress
        }
        progress?.cancel()
    }
}
