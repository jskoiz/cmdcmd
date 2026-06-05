# cmd+cmd Node Relay

This developer relay receives the JSON payload posted by the cmd+cmd iOS app,
saves the screenshot into a local inbox, opens it on the Mac, and uses the
relay's native desktop helper to paste the image plus OCR/context text into the
visible Codex composer.
The relay has one delivery path: Codex Desktop attachment.

For end-user distribution, prefer the native Mac app in `macos/CmdCmdRelay`.
This Node relay remains useful for protocol tests and fast local development.

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

- Replace `CMDCMD_RELAY_TOKEN` with a long random value.
- Keep `CMDCMD_HOST=127.0.0.1` for simulator-only testing, or bind to a
  trusted private interface for a physical phone.
- Keep `CMDCMD_APPSHOT_OPEN_VIEWER=true` when the screenshot should open in
  Preview before the relay helper attaches it to Codex Desktop.
- Keep `CMDCMD_APPSHOT_CLOSE_VIEWER=true` when the Preview thumbnail should
  close automatically after the attach.

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
CMDCMD_RELAY_URL=http://127.0.0.1:8787/v1/captures npm run smoke:post
```

The script posts `fixtures/sample-payload.json` with the bearer token from
`.env` and prints the relay response. This exercises the real Codex Desktop
paste path and may bring Preview and Codex Desktop to the foreground.

## Codex Desktop Delivery

Default settings:

```text
CMDCMD_APPSHOT_OPEN_VIEWER=true
CMDCMD_APPSHOT_VIEWER_BUNDLE=com.apple.Preview
CMDCMD_APPSHOT_CLOSE_VIEWER=true
CMDCMD_APPSHOT_CODEX_BUNDLE=com.openai.codex
```

When a capture arrives, the relay saves the image, opens it in the configured
Mac viewer, waits briefly for that window to become available, then runs the
native desktop helper. The helper copies the image to the pasteboard, activates
Codex Desktop, focuses the frontmost visible composer, pastes the image, then
pastes a text block containing structured screenshot context, optional phone
context, and OCR text when present. The screenshot context includes capture and
preparation times, image dimensions and byte sizes, OCR duration/confidence, and
an inferred visible app when OCR evidence is strong enough. If viewer cleanup is
enabled, it closes the matching Preview window after the attach. The capture
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
CMDCMD_APPSHOT_OPEN_DELAY_MS=750
CMDCMD_APPSHOT_OPEN_TIMEOUT_MS=5000
CMDCMD_APPSHOT_PASTE_DELAY_MS=400
CMDCMD_APPSHOT_PASTE_TIMEOUT_MS=10000
```

macOS may require Accessibility permission for the relay's native desktop
helper, or for `node` when the helper is launched by the relay.

## Required App Settings

In cmd+cmd Settings:

- Endpoint URL: `http://127.0.0.1:8787/v1/captures` for simulator, or the
  trusted private URL for a physical phone.
- Bearer token: the exact value of `CMDCMD_RELAY_TOKEN`.
- Default context and OCR settings: optional context that is sent with each
  screenshot. OCR-enabled captures also send timing, confidence, line count, and
  visible-app inference metadata.
