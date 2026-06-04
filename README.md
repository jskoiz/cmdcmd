# cmd+cmd

cmd+cmd is a small iPhone companion for sending screenshots plus context to a Codex-side relay.

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
existing app payload and saves the screenshot and metadata to a local inbox. The
relay can then deliver through one of two explicit lanes:

- `app-server`: durable background delivery through the supported Codex
  app-server protocol.
- `desktop-appshot`: open the phone screenshot on the Mac and trigger Codex
  Desktop's own Appshot helper path so the attachment lands through the visible
  composer flow.

The iOS app polls the relay status URL after upload so it can distinguish a
queued receipt from thread delivery or a triggered Desktop Appshot.

Quick start:

```bash
cd relay
npm install
cp .env.example .env
npm start
```

Configure cmd+cmd's endpoint as `http://127.0.0.1:8787/v1/captures` for the
iOS Simulator, or use a trusted private network URL for a physical phone.
Do not expose Codex app-server directly on a shared or public network.

See `relay/README.md` for setup, dry-run smoke tests, and real Codex smoke test
instructions.
