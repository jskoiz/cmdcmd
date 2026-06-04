import Foundation

enum RelayClientError: LocalizedError {
    case missingEndpoint
    case invalidEndpoint
    case rejected(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            "Add a relay endpoint first."
        case .invalidEndpoint:
            "The relay endpoint is not a valid URL."
        case .rejected(let code, let message):
            "Relay rejected the capture with HTTP \(code): \(message)"
        }
    }
}

struct RelayClient {
    var settings: RelaySettings

    func send(_ payload: CaptureUploadPayload) async throws {
        let trimmedEndpoint = settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else {
            throw RelayClientError.missingEndpoint
        }

        guard let url = URL(string: trimmedEndpoint), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            throw RelayClientError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexShot/1", forHTTPHeaderField: "User-Agent")

        let token = settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw RelayClientError.rejected(httpResponse.statusCode, message)
        }
    }
}

