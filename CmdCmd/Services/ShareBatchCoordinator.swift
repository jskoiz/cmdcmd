import Foundation
import Observation

enum ShareBatchPhase: Equatable {
    case loading
    case sending(current: Int, total: Int)
    case sent(Int)
    case pending(String)
    case failed(String)

    var canRetry: Bool {
        if case .failed = self {
            return true
        }
        return false
    }

    var canClose: Bool {
        switch self {
        case .sent, .pending, .failed:
            true
        case .loading, .sending:
            false
        }
    }

    var feedbackMessage: String? {
        switch self {
        case .pending(let message), .failed(let message):
            message
        case .loading, .sending, .sent:
            nil
        }
    }
}

@MainActor
@Observable
final class ShareBatchCoordinator {
    typealias InputLoader = @MainActor @Sendable () async throws -> SharedCaptureInput
    typealias Submitter = @MainActor @Sendable (
        _ image: SharedCaptureImage,
        _ sourceText: String,
        _ index: Int,
        _ total: Int
    ) async throws -> CaptureRecord

    private(set) var input = SharedCaptureInput()
    private(set) var phase: ShareBatchPhase = .loading

    private let loadInput: InputLoader
    private let submit: Submitter
    private let endpointFailure: @MainActor () -> String?
    private let finish: @MainActor () -> Void
    private let loadTimeoutNanoseconds: UInt64
    private let successDelayNanoseconds: UInt64
    private var activeTask: Task<Void, Never>?
    private var nextUnsentIndex = 0
    private var pendingAcceptedCount = 0
    private var pendingStatusMessage = ""
    private var needsReload = true

    init(
        loadTimeoutNanoseconds: UInt64 = 10_000_000_000,
        successDelayNanoseconds: UInt64 = 1_200_000_000,
        loadInput: @escaping InputLoader,
        submit: @escaping Submitter,
        endpointFailure: @escaping @MainActor () -> String?,
        finish: @escaping @MainActor () -> Void
    ) {
        self.loadTimeoutNanoseconds = loadTimeoutNanoseconds
        self.successDelayNanoseconds = successDelayNanoseconds
        self.loadInput = loadInput
        self.submit = submit
        self.endpointFailure = endpointFailure
        self.finish = finish
    }

    func start() {
        runSingleFlight()
    }

    func retry() {
        guard phase.canRetry else {
            return
        }
        runSingleFlight()
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
    }

    func waitUntilIdle() async {
        let task = activeTask
        await task?.value
    }

    private func runSingleFlight() {
        guard activeTask == nil else {
            return
        }

        activeTask = Task { [weak self] in
            await self?.run()
        }
    }

    private func run() async {
        defer { activeTask = nil }

        do {
            if needsReload {
                phase = .loading
                input = try await loadInputWithDeadline()
                try Task.checkCancellation()
                guard !input.images.isEmpty else {
                    needsReload = true
                    phase = .failed("No image was shared.")
                    return
                }
                needsReload = false
                nextUnsentIndex = 0
                pendingAcceptedCount = 0
                pendingStatusMessage = ""
            }

            if let endpointFailure = endpointFailure() {
                phase = .failed(endpointFailure)
                return
            }

            try await sendRemainingImages()
        } catch is CancellationError {
            return
        } catch ShareBatchError.loadTimedOut {
            needsReload = true
            phase = .failed("Couldn't load the shared image. Close and try sharing again.")
        } catch {
            needsReload = input.images.isEmpty
            phase = .failed(error.localizedDescription)
        }
    }

    private func loadInputWithDeadline() async throws -> SharedCaptureInput {
        let race = ShareInputDeadlineRace()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)

                let loaderTask = Task { @MainActor [loadInput] in
                    do {
                        race.resolve(.success(try await loadInput()))
                    } catch {
                        race.resolve(.failure(error))
                    }
                }
                let timeoutTask = Task.detached { [loadTimeoutNanoseconds] in
                    do {
                        try await Task.sleep(nanoseconds: loadTimeoutNanoseconds)
                        race.resolve(.failure(ShareBatchError.loadTimedOut))
                    } catch {
                        // The loader or caller completed the race first.
                    }
                }

                race.installTasks(loader: loaderTask, timeout: timeoutTask)
            }
        } onCancel: {
            race.resolve(.failure(CancellationError()))
        }
    }

    private func sendRemainingImages() async throws {
        let total = input.images.count
        while nextUnsentIndex < total {
            try Task.checkCancellation()
            let index = nextUnsentIndex
            phase = .sending(current: index + 1, total: total)
            let record = try await submit(input.images[index], input.sourceText, index, total)

            switch record.status {
            case .sent:
                nextUnsentIndex += 1
            case .sending:
                nextUnsentIndex += 1
                pendingAcceptedCount += 1
                pendingStatusMessage = record.statusMessage
            case .needsEndpoint, .failed:
                phase = .failed(failureMessage(for: record, sentCount: nextUnsentIndex, total: total))
                return
            }
        }

        if pendingAcceptedCount > 0 {
            phase = .pending(pendingMessage(total: total))
            return
        }

        phase = .sent(total)
        try await Task.sleep(nanoseconds: successDelayNanoseconds)
        try Task.checkCancellation()
        if case .sent = phase {
            finish()
        }
    }

    private func pendingMessage(total: Int) -> String {
        guard total > 1 else {
            return pendingStatusMessage
        }

        let itemLabel = pendingAcceptedCount == 1 ? "item" : "items"
        return "Accepted \(total) of \(total). Delivery confirmation is pending for \(pendingAcceptedCount) \(itemLabel)."
    }

    private func failureMessage(for record: CaptureRecord, sentCount: Int, total: Int) -> String {
        guard total > 1 else {
            return record.statusMessage
        }
        return "Sent \(sentCount) of \(total). \(record.statusMessage)"
    }

    static func currentEndpointFailure() -> String? {
        let endpoint = CaptureRepository.loadSettings().endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpoint.isEmpty {
            return RelayClientError.missingEndpoint.localizedDescription
        }

        guard let components = URLComponents(string: endpoint),
              let scheme = components.scheme,
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return RelayClientError.invalidEndpoint.localizedDescription
        }
        return nil
    }
}

private final class ShareInputDeadlineRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SharedCaptureInput, Error>?
    private var result: Result<SharedCaptureInput, Error>?
    private var loaderTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func install(_ continuation: CheckedContinuation<SharedCaptureInput, Error>) {
        let completedResult = lock.withLock { () -> Result<SharedCaptureInput, Error>? in
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

    func installTasks(loader: Task<Void, Never>, timeout: Task<Void, Never>) {
        let shouldCancel = lock.withLock { () -> Bool in
            if result != nil {
                return true
            }
            loaderTask = loader
            timeoutTask = timeout
            return false
        }

        if shouldCancel {
            loader.cancel()
            timeout.cancel()
        }
    }

    func resolve(_ result: Result<SharedCaptureInput, Error>) {
        let state = lock.withLock {
            guard self.result == nil else {
                return (
                    continuation: Optional<CheckedContinuation<SharedCaptureInput, Error>>.none,
                    loader: Optional<Task<Void, Never>>.none,
                    timeout: Optional<Task<Void, Never>>.none
                )
            }

            self.result = result
            let state = (continuation, loaderTask, timeoutTask)
            continuation = nil
            loaderTask = nil
            timeoutTask = nil
            return state
        }

        state.loader?.cancel()
        state.timeout?.cancel()
        state.continuation?.resume(with: result)
    }
}

private enum ShareBatchError: LocalizedError {
    case loadTimedOut

    var errorDescription: String? {
        switch self {
        case .loadTimedOut:
            "The shared image took too long to load."
        }
    }
}
