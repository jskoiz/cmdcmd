# cmd+cmd

cmd+cmd is a small iPhone companion for sending screenshots plus context into
Codex Desktop through the visible Appshot flow.

It includes:

- A SwiftUI iOS app for endpoint setup, manual screenshot sending, and history.
- A Share Extension so screenshots can be sent from the system share sheet.
- An App Intent so Shortcuts can pass an image/file input from Back Tap, Action Button, or a custom shortcut.
- On-device OCR with Vision before upload, including OCR timing and confidence
  context.

The app sends JSON to the configured relay endpoint:

```json
{
  "schemaVersion": 2,
  "source": "shortcut",
  "screenshotContext": {
    "capturedAt": "2026-06-04T12:00:00.000Z",
    "preparedAt": "2026-06-04T12:00:01.000Z",
    "timeZoneIdentifier": "Pacific/Honolulu",
    "source": "shortcut",
    "sourceDetail": "Latest Screenshot",
    "imageFilename": "IMG_0001.PNG",
    "imageMimeType": "image/png",
    "pixelWidth": 1290,
    "pixelHeight": 2796,
    "originalImageBytes": 2400000,
    "uploadImageBytes": 1100000,
    "ocrEnabled": true,
    "ocrDurationMs": 842,
    "ocrLineCount": 24,
    "ocrCharacterCount": 560,
    "ocrTimedOut": false,
    "ocrAverageConfidence": 0.82,
    "visibleApp": {
      "name": "Photos",
      "confidence": "high",
      "evidence": ["Library", "Collections", "Syncing Paused"]
    }
  },
  "context": "user supplied note",
  "recognizedText": "OCR text",
  "imageMimeType": "image/png",
  "imageBase64": "..."
}
```

## Private Relay

The repo includes a private relay implementation in `relay/`. It receives the
app payload, saves the screenshot and metadata to a local inbox, opens the
screenshot on the Mac, copies it to the pasteboard, activates Codex Desktop,
and pastes the image into the visible composer.

The iOS app polls the relay status URL after upload so it can distinguish a
queued receipt from a Codex Desktop attachment or a delivery failure.

Quick start:

```bash
cd relay
npm install
cp .env.example .env
npm start
```

Configure cmd+cmd's endpoint as `http://127.0.0.1:8787/v1/captures` for the
iOS Simulator, or use a trusted private network URL for a physical phone.
Do not expose the relay on a shared or public network.

See `relay/README.md` for setup and smoke test instructions.
