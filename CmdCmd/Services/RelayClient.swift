import Foundation
import OSLog

private let relayClientLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.jskoiz.CmdCmd",
    category: "RelayClient"
)

enum RelayClientError: LocalizedError {
    case missingEndpoint
    case invalidEndpoint
    case unauthorized
    case rejected(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            "Add a relay endpoint first."
        case .invalidEndpoint:
            "The relay endpoint is not a valid URL."
        case .unauthorized:
            "Relay token was rejected. Refresh the Desktop relay, scan the new QR in Settings, then try again."
        case .rejected(let code, let message):
            "Relay rejected the capture with HTTP \(code): \(message)"
        case .invalidResponse(let message):
            "Relay returned an unreadable response: \(message)"
        }
    }
}

struct RelaySendResult: Decodable {
    var status: String
    var captureId: UUID
    var imagePath: String
    var metadataPath: String
    var statusUrl: String
}

struct RelayDeliveryStatus: Decodable {
    var captureId: UUID
    var status: String
    var message: String
    var deliveryLane: String?

    var isTerminal: Bool {
        status == "delivered" || status == "failed"
    }
}

enum RelayReadiness: Equatable {
    case ready
    case failed(String)

    var message: String {
        switch self {
        case .ready:
            "Relay and token are ready."
        case .failed(let message):
            message
        }
    }

    var failureMessage: String? {
        if case .failed(let message) = self {
            return message
        }
        return nil
    }
}

struct RelayClient {
    static let defaultSendRequestTimeoutSeconds: TimeInterval = 15
    static let defaultStatusRequestTimeoutSeconds: TimeInterval = 5

    var settings: RelaySettings
    var sendRequestTimeoutSeconds = defaultSendRequestTimeoutSeconds
    var statusRequestTimeoutSeconds = defaultStatusRequestTimeoutSeconds

    func checkReadiness(timeoutInterval: TimeInterval = 5) async -> RelayReadiness {
        let trimmedEndpoint = settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else {
            return .failed(RelayClientError.missingEndpoint.localizedDescription)
        }

        guard let healthURL = healthURL(for: trimmedEndpoint) else {
            return .failed(RelayClientError.invalidEndpoint.localizedDescription)
        }

        var healthRequest = URLRequest(url: healthURL)
        healthRequest.timeoutInterval = timeoutInterval
        do {
            let (_, response) = try await URLSession.shared.data(for: healthRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failed("Relay responded without an HTTP status.")
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                return .failed("Relay health check returned HTTP \(httpResponse.statusCode).")
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain,
               nsError.code == NSURLErrorNotConnectedToInternet {
                return .failed(CaptureFailurePresentation.relayReachabilityMessage(endpoint: trimmedEndpoint))
            }

            return .failed(error.localizedDescription)
        }

        return await checkAuthorization(timeoutInterval: timeoutInterval)
    }

    func send(_ payload: CaptureUploadPayload) async throws -> RelaySendResult {
        let startedAt = Date()
        let request = try uploadRequest(for: payload)
        guard let url = request.url else {
            throw RelayClientError.invalidEndpoint
        }
        let scheme = url.scheme ?? "unknown"

        relayClientLogger.info(
            "request building captureId=\(payload.captureId.uuidString, privacy: .public) host=\(url.host() ?? "none", privacy: .public) scheme=\(scheme, privacy: .public)"
        )
        relayClientLogger.info(
            "request body encoded captureId=\(payload.captureId.uuidString, privacy: .public) bodyBytes=\(request.httpBody?.count ?? 0, privacy: .public) imageBase64Chars=\(payload.imageBase64.count, privacy: .public) recognizedTextChars=\(payload.recognizedText.count, privacy: .public)"
        )

        let data: Data
        let response: URLResponse
        do {
            relayClientLogger.info("request started captureId=\(payload.captureId.uuidString, privacy: .public)")
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            relayClientLogger.error(
                "request failed captureId=\(payload.captureId.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public) durationMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
            )
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            relayClientLogger.error(
                "request completed without http response captureId=\(payload.captureId.uuidString, privacy: .public) responseBytes=\(data.count, privacy: .public) durationMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
            )
            throw RelayClientError.invalidResponse("Missing HTTP response")
        }

        relayClientLogger.info(
            "response received captureId=\(payload.captureId.uuidString, privacy: .public) statusCode=\(httpResponse.statusCode, privacy: .public) responseBytes=\(data.count, privacy: .public) durationMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
        )
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            relayClientLogger.error(
                "response rejected captureId=\(payload.captureId.uuidString, privacy: .public) statusCode=\(httpResponse.statusCode, privacy: .public) message=\(message, privacy: .public)"
            )
            if httpResponse.statusCode == 401 {
                throw RelayClientError.unauthorized
            }
            throw RelayClientError.rejected(httpResponse.statusCode, message)
        }

        do {
            let result = try JSONDecoder().decode(RelaySendResult.self, from: data)
            relayClientLogger.info(
                "response decoded captureId=\(payload.captureId.uuidString, privacy: .public) relayStatus=\(result.status, privacy: .public) statusUrl=\(result.statusUrl, privacy: .public)"
            )
            return result
        } catch {
            relayClientLogger.error(
                "response decode failed captureId=\(payload.captureId.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw RelayClientError.invalidResponse(error.localizedDescription)
        }
    }

    func waitForDeliveryStatus(
        after sendResult: RelaySendResult,
        // Must cover the relay's worst legitimate path: helper compilation
        // (up to 30s) plus the paste step (10s), with a little headroom.
        timeoutSeconds: TimeInterval = 45,
        pollIntervalNanoseconds: UInt64 = 1_000_000_000
    ) async throws -> RelayDeliveryStatus? {
        guard let statusURL = URL(string: sendResult.statusUrl, relativeTo: try endpointURL(for: sendResult.captureId))?.absoluteURL else {
            throw RelayClientError.invalidResponse("Invalid relay status URL")
        }

        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastStatus: RelayDeliveryStatus?
        while true {
            try Task.checkCancellation()
            let timeBeforeNextPoll = deadline.timeIntervalSinceNow
            guard timeBeforeNextPoll > 0 else {
                return lastStatus
            }

            let maximumNanosecondInterval = Double(UInt64.max) / 1_000_000_000
            let remainingNanoseconds = if timeBeforeNextPoll >= maximumNanosecondInterval {
                UInt64.max
            } else {
                UInt64(ceil(timeBeforeNextPoll * 1_000_000_000))
            }
            let sleepNanoseconds = min(pollIntervalNanoseconds, remainingNanoseconds)
            if sleepNanoseconds > 0 {
                try await Task.sleep(nanoseconds: sleepNanoseconds)
            }

            let remainingTime = deadline.timeIntervalSinceNow
            guard remainingTime > 0 else {
                return lastStatus
            }

            let status = try await deliveryStatus(
                from: statusURL,
                captureId: sendResult.captureId,
                remainingTime: remainingTime
            )
            lastStatus = status
            if status.isTerminal {
                return status
            }
        }
    }

    func uploadRequest(for payload: CaptureUploadPayload) throws -> URLRequest {
        var request = authorizedRequest(url: try endpointURL(for: payload.captureId))
        request.httpMethod = "POST"
        request.timeoutInterval = max(
            0.001,
            sendRequestTimeoutSeconds.isFinite
                ? sendRequestTimeoutSeconds
                : Self.defaultSendRequestTimeoutSeconds
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)
        return request
    }

    func deliveryStatusRequest(from url: URL, remainingTime: TimeInterval) -> URLRequest {
        var request = authorizedRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = max(0.001, min(statusRequestTimeoutSeconds, remainingTime))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func deliveryStatus(
        from url: URL,
        captureId: UUID,
        remainingTime: TimeInterval
    ) async throws -> RelayDeliveryStatus {
        let startedAt = Date()
        let request = deliveryStatusRequest(from: url, remainingTime: remainingTime)

        relayClientLogger.info("status request started captureId=\(captureId.uuidString, privacy: .public)")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            relayClientLogger.error(
                "status request failed captureId=\(captureId.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public) durationMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
            )
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayClientError.invalidResponse("Missing HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            relayClientLogger.error(
                "status request rejected captureId=\(captureId.uuidString, privacy: .public) statusCode=\(httpResponse.statusCode, privacy: .public) message=\(message, privacy: .public)"
            )
            if httpResponse.statusCode == 401 {
                throw RelayClientError.unauthorized
            }
            throw RelayClientError.rejected(httpResponse.statusCode, message)
        }

        do {
            let status = try JSONDecoder().decode(RelayDeliveryStatus.self, from: data)
            relayClientLogger.info(
                "status response decoded captureId=\(captureId.uuidString, privacy: .public) relayStatus=\(status.status, privacy: .public) durationMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
            )
            return status
        } catch {
            relayClientLogger.error(
                "status response decode failed captureId=\(captureId.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw RelayClientError.invalidResponse(error.localizedDescription)
        }
    }

    private func endpointURL(for captureId: UUID) throws -> URL {
        let trimmedEndpoint = settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else {
            relayClientLogger.error("send aborted missing endpoint captureId=\(captureId.uuidString, privacy: .public)")
            throw RelayClientError.missingEndpoint
        }

        guard let url = URL(string: trimmedEndpoint), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            relayClientLogger.error("send aborted invalid endpoint captureId=\(captureId.uuidString, privacy: .public)")
            throw RelayClientError.invalidEndpoint
        }

        return url
    }

    private func healthURL(for endpoint: String) -> URL? {
        guard var components = URLComponents(string: endpoint),
              let scheme = components.scheme,
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return nil
        }

        components.path = "/healthz"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func checkAuthorization(timeoutInterval: TimeInterval) async -> RelayReadiness {
        guard let endpoint = URLComponents(string: settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = endpoint.scheme,
              ["http", "https"].contains(scheme),
              endpoint.host != nil else {
            return .failed(RelayClientError.invalidEndpoint.localizedDescription)
        }

        var components = endpoint
        components.path = "/v1/captures/00000000-0000-0000-0000-000000000000/status"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            return .failed(RelayClientError.invalidEndpoint.localizedDescription)
        }

        var request = authorizedRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failed("Relay responded without an HTTP status.")
            }

            switch httpResponse.statusCode {
            case 200, 404:
                return .ready
            case 401:
                return .failed(RelayClientError.unauthorized.localizedDescription)
            default:
                return .failed("Relay token check returned HTTP \(httpResponse.statusCode).")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("cmd+cmd/1", forHTTPHeaderField: "User-Agent")

        let token = settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        relayClientLogger.info(
            "authorized request prepared host=\(url.host() ?? "none", privacy: .public) tokenSuffix=\(tokenSuffix(token), privacy: .public)"
        )

        return request
    }
}
