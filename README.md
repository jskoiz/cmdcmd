# CodexShot

CodexShot is a small iPhone companion for sending screenshots plus context to a Codex-side relay.

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
  "threadHint": "optional Codex thread hint",
  "imageMimeType": "image/png",
  "imageBase64": "..."
}
```

The relay endpoint is intentionally configurable because Codex does not expose a documented public active-thread attachment API.

## Private Relay

The repo includes a private relay implementation in `relay/`. It receives the
existing app payload, saves the screenshot and metadata to a local inbox, then
uses the supported `codex app-server` protocol to start or resume a Codex thread
with the note, OCR text, and a native local image attachment.

The relay does not spoof the Codex Desktop Appshots hotkey path. Appshots are a
Desktop renderer feature; this relay uses the supported app-server turn lane and
logs the resulting `threadId`, `turnId`, and final status. The iOS app polls the
relay status URL after upload so it can distinguish a queued receipt from Codex
turn completion.

Quick start:

```bash
cd relay
npm install
cp .env.example .env
npm start
```

Configure CodexShot's endpoint as `http://127.0.0.1:8787/v1/captures` for the
iOS Simulator, or use a trusted private network URL for a physical phone.
Do not expose Codex app-server directly on a shared or public network.

See `relay/README.md` for setup, dry-run smoke tests, and real Codex smoke test
instructions.
