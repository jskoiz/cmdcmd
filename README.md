<picture>
  <source media="(prefers-color-scheme: dark)" srcset="CmdCmd/Resources/Assets.xcassets/CmdCmdLogoDark.imageset/logo-dark.png">
  <img alt="cmd+cmd" src="CmdCmd/Resources/Assets.xcassets/CmdCmdLogo.imageset/logo.png" width="220">
</picture>

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

## Ship-Ready Setup

cmd+cmd is now designed as two user-facing pieces:

- `cmd+cmd` for iPhone, distributed through TestFlight or the App Store.
- `cmd+cmd Relay.app` for Mac, distributed as a signed and notarized download.

The Mac relay installer is the preferred setup path for users. It installs the
signed relay bundle under Application Support, prepares a private-network
endpoint and per-user bearer token, starts the background LaunchAgent, waits for
the relay to become reachable, and prints a terminal QR code. Users scan that
QR inside the iPhone app to link the phone to this Mac.

User install:

```bash
curl -fsSL https://cmd.avmil.xyz/install.sh | bash
```

Phone pairing:

1. Open `cmd+cmd` on iPhone.
2. Go to Settings and tap `Scan Desktop QR`.
3. Scan the QR printed by the Mac installer.
4. Grant macOS Accessibility permission so the relay can paste into Codex
   Desktop.

Release build:

```bash
./scripts/package_macos.sh
```

Set `DEVELOPER_ID_APPLICATION` to sign the Mac app. Notarize the exported zip
before publishing it to the release URL used by `scripts/install-macos.sh`.

## Private Relay

The repo includes two relay implementations:

- `macos/CmdCmdRelay`: the native Mac relay for real users.
- `relay/`: the Node.js developer relay for local testing and protocol work.

Both relays receive the app payload, save the screenshot and metadata to a
local inbox, open the screenshot on the Mac, copy it to the pasteboard, activate
Codex Desktop, and paste the image into the visible composer.

The iOS app polls the relay status URL after upload so it can distinguish a
queued receipt from a Codex Desktop attachment or a delivery failure.

Developer relay quick start:

```bash
cd relay
npm install
cp .env.example .env
npm start
```

Configure cmd+cmd's endpoint as `http://127.0.0.1:8787/v1/captures` for the
iOS Simulator. For a physical phone, prefer the installer QR so the iPhone gets
the Mac's private-network endpoint and matching bearer token.
Do not expose the relay on a shared or public network.

See `relay/README.md` for setup and smoke test instructions.

## Website

The static setup site lives in `site/` and can be deployed as-is:

```bash
cd site
python3 -m http.server 4173
```
