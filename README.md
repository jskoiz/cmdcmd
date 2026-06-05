# cmd+cmd

cmd+cmd is a small iPhone companion for sending screenshots plus context into
Codex Desktop through the visible Appshot flow.

It includes:

- A SwiftUI iOS app for endpoint setup, manual screenshot sending, and history.
- A Share Extension so screenshots can be sent from the system share sheet.
- An App Intent so Shortcuts can pass an image/file input from Back Tap, Action Button, or a custom shortcut.
- On-device OCR with Vision before upload.

The app sends JSON to the configured relay endpoint:

```json
{
  "schemaVersion": 1,
  "source": "shortcut",
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
