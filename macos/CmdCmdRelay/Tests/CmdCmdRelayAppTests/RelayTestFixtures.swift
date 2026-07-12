import Foundation
@testable import CmdCmdRelayApp

enum RelayTestFixtures {
    static func payloadObject(captureId: String = UUID().uuidString) -> [String: Any] {
        [
            "schemaVersion": 2,
            "captureId": captureId,
            "createdAt": "2026-07-12T12:00:00Z",
            "source": "mainApp",
            "sourceDetail": "test",
            "screenshotContext": [
                "capturedAt": "2026-07-12T11:59:59Z",
                "preparedAt": "2026-07-12T12:00:00Z",
                "timeZoneIdentifier": "Pacific/Honolulu",
                "source": "mainApp",
                "sourceDetail": "test",
                "imageFilename": "capture.png",
                "imageMimeType": "image/png",
                "pixelWidth": 1,
                "pixelHeight": 1,
                "originalImageBytes": 4,
                "uploadImageBytes": 4,
                "ocrEnabled": false,
                "ocrLineCount": 0,
                "ocrCharacterCount": 0,
                "ocrTimedOut": false,
                "visibleApp": NSNull()
            ],
            "context": "test context",
            "recognizedText": "",
            "imageFilename": "capture.png",
            "imageMimeType": "image/png",
            "imageBase64": Data([0x89, 0x50, 0x4e, 0x47]).base64EncodedString()
        ]
    }

    static func payloadData(captureId: String = UUID().uuidString) throws -> Data {
        try JSONSerialization.data(withJSONObject: payloadObject(captureId: captureId))
    }

    static func capture(captureId: String = UUID().uuidString) throws -> CapturePayload {
        try CapturePayload.decode(from: payloadData(captureId: captureId))
    }

    static func settings(
        port: Int = 0,
        inboxDirectory: String,
        deliveryMode: RelayDeliveryMode = .codex
    ) -> RelaySettings {
        RelaySettings(
            token: "relay-test-token",
            host: "127.0.0.1",
            port: port,
            inboxDirectory: inboxDirectory,
            codexBundleIdentifier: "com.openai.codex",
            deliveryMode: deliveryMode,
            pasteDelayMilliseconds: 0
        )
    }
}
