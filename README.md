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

