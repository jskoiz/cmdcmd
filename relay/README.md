# cmd+cmd Node Relay

This developer relay receives the JSON payload posted by the cmd+cmd iOS app,
saves the screenshot into a local inbox, and uses the relay's native desktop
helper to attach the screenshot plus a `.txt` context sidecar to the visible
Codex Desktop composer.
The relay has one delivery path: Codex Desktop attachments.

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
attachment path and may bring Codex Desktop to the foreground.

## Codex Desktop Delivery

Default settings:

```text
CMDCMD_DESKTOP_CODEX_BUNDLE=com.openai.codex
```

When a capture arrives, the relay saves the image and runs the native desktop
helper. The helper activates Codex Desktop, focuses the visible composer,
attaches the screenshot, writes structured screenshot context/OCR to a `.txt`
sidecar, and attaches that text file. It does not open Preview or a temporary
screenshot window, and it does not paste the context inline into the composer.
The screenshot context includes capture and preparation times, image dimensions
and byte sizes, OCR duration/confidence, and an inferred visible app when OCR
evidence is strong enough. The capture response is an immediate
`202 Accepted` receipt with the stored image path, metadata sidecar path, and
`statusUrl`.

Poll `GET /v1/captures/{captureId}/status` with the same bearer token to read
`accepted`, `delivering`, `delivered`, or `failed` state. The phone displays the
relay messages, including:

- `Screenshot queued for Codex`
- `Sending screenshot to Codex`
- `Screenshot sent to Codex`
- `Could not send screenshot: ...`

Useful optional settings:

```text
CMDCMD_DESKTOP_PASTE_DELAY_MS=400
CMDCMD_DESKTOP_PASTE_TIMEOUT_MS=10000
```

`CMDCMD_DESKTOP_PASTE_DELAY_MS` is the delay after Codex Desktop is activated
and before the helper focuses the composer and attaches files.

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
