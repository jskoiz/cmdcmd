import Foundation
import OSLog

private let relayClientLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.jskoiz.CodexShot",
    category: "RelayClient"
)

enum RelayClientError: LocalizedError {
    case missingEndpoint
    case invalidEndpoint
    case rejected(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            "Add a relay endpoint first."
        case .invalidEndpoint:
            "The relay endpoint is not a valid URL."
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

struct RelayClient {
    var settings: RelaySettings

    func send(_ payload: CaptureUploadPayload) async throws -> RelaySendResult {
        let startedAt = Date()
        let url = try endpointURL(for: payload.captureId)
        let scheme = url.scheme ?? "unknown"

        relayClientLogger.info(
            "request building captureId=\(payload.captureId.uuidString, privacy: .public) host=\(url.host() ?? "none", privacy: .public) scheme=\(scheme, privacy: .public)"
        )
        var request = authorizedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)
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
        timeoutSeconds: TimeInterval = 60,
        pollIntervalNanoseconds: UInt64 = 1_000_000_000
    ) async throws -> RelayDeliveryStatus? {
        guard let statusURL = URL(string: sendResult.statusUrl, relativeTo: try endpointURL(for: sendResult.captureId))?.absoluteURL else {
            throw RelayClientError.invalidResponse("Invalid relay status URL")
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastStatus: RelayDeliveryStatus?
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)

            let status = try await deliveryStatus(from: statusURL, captureId: sendResult.captureId)
            lastStatus = status
            if status.isTerminal {
                return status
            }
        }

        return lastStatus
    }

    private func deliveryStatus(from url: URL, captureId: UUID) async throws -> RelayDeliveryStatus {
        let startedAt = Date()
        var request = authorizedRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("cmd+cmd/1", forHTTPHeaderField: "User-Agent")

        let token = settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }
}

private func elapsedMilliseconds(since date: Date) -> Int {
    Int(Date().timeIntervalSince(date) * 1000)
}
