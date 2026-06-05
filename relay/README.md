# cmd+cmd Relay

This private relay receives the JSON payload posted by the cmd+cmd iOS app,
saves the screenshot into a local inbox, and uses the relay's native desktop
helper to paste the image plus OCR/context text into the visible Codex
composer.
The relay has one delivery path: Codex Desktop attachment.

Remote connections are useful for controlling a trusted Codex host from another
device. Keep this relay as the only HTTP endpoint exposed to cmd+cmd, and keep
it behind a private network, VPN, tunnel, or localhost binding.

## Setup

```bash
cd relay
npm install
cp .env.example .env
```

Edit `.env`:

- Replace `CODEXSHOT_RELAY_TOKEN` with a long random value.
- Keep `CODEXSHOT_HOST=127.0.0.1` for simulator-only testing, or bind to a
  trusted private interface for a physical phone.
- Keep `CODEXSHOT_APPSHOT_OPEN_VIEWER=false` for normal use so the screenshot
  never opens in Preview.
- Set `CODEXSHOT_APPSHOT_OPEN_VIEWER=true` only when debugging viewer behavior.
  The relay opens Preview hidden/in the background, then closes the matching
  screenshot window and quits Preview if no other windows remain.

Start the relay:

```bash
npm start
```

Set cmd+cmd's endpoint to:

```text
http://127.0.0.1:8787/v1/captures
```

On a physical iPhone, use a private path such as Tailscale, VPN, or Cloudflare
Tunnel and set the app endpoint to that private URL.

## Local Smoke Test

With the relay running and `.env` configured:

```bash
CODEXSHOT_RELAY_URL=http://127.0.0.1:8787/v1/captures npm run smoke:post
```

The script posts `fixtures/sample-payload.json` with the bearer token from
`.env` and prints the relay response. This exercises the real Codex Desktop
paste path and may bring Codex Desktop to the foreground.

## Codex Desktop Delivery

Default settings:

```text
CODEXSHOT_APPSHOT_OPEN_VIEWER=false
CODEXSHOT_APPSHOT_VIEWER_BUNDLE=com.apple.Preview
CODEXSHOT_APPSHOT_CLOSE_VIEWER=true
CODEXSHOT_APPSHOT_CODEX_BUNDLE=com.openai.codex
```

When a capture arrives, the relay saves the image and runs the native desktop
helper. The helper copies the image to the pasteboard, activates Codex Desktop,
focuses the frontmost visible composer, pastes the image, then pastes a text
block containing the phone context and OCR text when present. If the optional
viewer path is enabled, the relay opens Preview hidden/in the background before
the paste; if viewer cleanup is enabled, it closes the matching Preview window
after the attach and quits Preview when no other windows remain. The capture
response is an immediate
`202 Accepted` receipt with the stored image path, metadata sidecar path, and
`statusUrl`.

Poll `GET /v1/captures/{captureId}/status` with the same bearer token to read
`accepted`, `delivering`, `delivered`, or `failed` state. The phone displays the
relay messages, including:

- `Queued for the frontmost Codex chat`
- `Attaching to the frontmost Codex chat`
- `Attached phone screenshot in the frontmost Codex chat`
- `Codex Desktop attach failed: ...`

Useful optional settings:

```text
CODEXSHOT_APPSHOT_OPEN_DELAY_MS=750
CODEXSHOT_APPSHOT_OPEN_TIMEOUT_MS=5000
CODEXSHOT_APPSHOT_PASTE_DELAY_MS=400
CODEXSHOT_APPSHOT_PASTE_TIMEOUT_MS=10000
```

macOS may require Accessibility permission for the relay's native desktop
helper, or for `node` when the helper is launched by the relay.

## Required App Settings

In cmd+cmd Settings:

- Endpoint URL: `http://127.0.0.1:8787/v1/captures` for simulator, or the
  trusted private URL for a physical phone.
- Bearer token: the exact value of `CODEXSHOT_RELAY_TOKEN`.
- Default context and OCR settings: optional context that is sent with each
  screenshot.
