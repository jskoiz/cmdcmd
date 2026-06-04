# cmd+cmd Relay

This private relay receives the JSON payload posted by the cmd+cmd iOS app,
saves the screenshot into a local inbox, and delivers it through one configured
lane.

- `CODEXSHOT_DELIVERY_MODE=app-server` sends the note, OCR text, and local
  image into Codex through the supported `codex app-server` protocol.
- `CODEXSHOT_DELIVERY_MODE=desktop-appshot` opens the phone screenshot on the
  Mac and triggers Codex Desktop's Appshot helper so Codex Desktop creates the
  actual composer attachment.

Remote connections are useful for controlling a trusted Codex host from another
device, but the phone app should not talk to the Codex remote-control layer or
the Codex app-server directly. Keep this relay as the only HTTP endpoint exposed
to cmd+cmd.

## Setup

```bash
cd relay
npm install
cp .env.example .env
```

Edit `.env`:

- Replace `CODEXSHOT_RELAY_TOKEN` with a long random value.
- Keep `CODEXSHOT_DELIVERY_MODE=app-server` for durable background thread
  delivery, or set `CODEXSHOT_DELIVERY_MODE=desktop-appshot` for the
  Appshot-style visible composer flow.
- Set `CODEXSHOT_CODEX_CWD` to the project Codex should work from.
- Set `CODEXSHOT_CODEX_THREAD_ID` when captures should resume a specific
  active Codex thread by default.
- Keep `CODEXSHOT_HOST=127.0.0.1` unless you are binding behind a trusted
  private network interface.

Start the relay:

```bash
npm start
```

Set cmd+cmd's endpoint to:

```text
http://127.0.0.1:8787/v1/captures
```

On a physical iPhone, use a private path such as Tailscale, VPN, or Cloudflare
Tunnel and set the app endpoint to that private URL. Do not expose Codex
app-server transports on a shared or public network.

## Local Smoke Test

Use the built-in dry-run mode when you only want to prove the HTTP contract and
image storage path without starting Codex:

```bash
CODEXSHOT_DRY_RUN=1 npm start
```

In another terminal:

```bash
CODEXSHOT_RELAY_URL=http://127.0.0.1:8787/v1/captures npm run smoke:post
```

The script posts `fixtures/sample-payload.json` with the bearer token from
`.env` and prints the relay response.

## App-Server Delivery

With `CODEXSHOT_DRY_RUN` unset, the relay starts `codex app-server`, starts or
resumes a Codex thread, and passes the screenshot through its `localImage` input.
This is the same app-server protocol used by rich Codex clients, rather than the
background SDK/CLI lane.

If `threadHint` is present in the app payload, the relay calls
`thread/resume`. If the payload omits it, the relay falls back to
`CODEXSHOT_CODEX_THREAD_ID` or `CODEX_THREAD_ID`. If no thread id is available,
it calls `thread/start`. The relay then sends the capture with `turn/start`, or
`turn/steer` if the resumed thread reports an active in-progress turn. The
capture response is an immediate `202 Accepted` receipt with the stored image
path, metadata sidecar path, and `statusUrl`. The Codex turn continues in the
background. Poll `GET /v1/captures/{captureId}/status` with the same bearer token
to read `accepted`, `delivering`, `delivered`, or `failed` state, including the
`threadId`, `turnId`, completion, and error details when available.

By default the relay uses `/Applications/Codex.app/Contents/Resources/codex` on
macOS when present, so launchd jobs do not depend on shell `PATH`. Override this
with `CODEXSHOT_CODEX_BIN` if needed.

## Desktop Appshot Delivery

Use this mode when the product goal is "send this iPhone screenshot into the
visible Codex Desktop composer" instead of only writing to a background thread.

```text
CODEXSHOT_DELIVERY_MODE=desktop-appshot
CODEXSHOT_APPSHOT_HELPER=/Users/jk/Documents/Codex/2026-06-04/are-you-able-to-inspect-the/outputs/codex-active-appshot
CODEXSHOT_APPSHOT_OPEN_VIEWER=true
CODEXSHOT_APPSHOT_VIEWER_BUNDLE=com.apple.Preview
```

When a capture arrives, the relay saves the image, opens it in the configured
Mac viewer, waits briefly for that window to become available, and invokes the
helper. The helper still owns the Appshot interaction: it primes Codex Desktop's
active-chat gate, restores the target app, and presses the configured Appshot
hotkey. The relay reports `Queued for Desktop Appshot`, `Triggering Desktop
Appshot`, `Triggered Desktop Appshot from phone screenshot`, or a failure back
to the phone through the normal status endpoint.

Useful optional settings:

```text
CODEXSHOT_APPSHOT_HOTKEY=DoubleCommand
CODEXSHOT_APPSHOT_TARGET_BUNDLE=com.apple.Preview
CODEXSHOT_APPSHOT_OPEN_DELAY_MS=750
CODEXSHOT_APPSHOT_HELPER_TIMEOUT_MS=30000
CODEXSHOT_APPSHOT_CODEX_DELAY=0.85
CODEXSHOT_APPSHOT_RESTORE_DELAY=0.25
CODEXSHOT_APPSHOT_HOLD_DELAY=0.12
```

macOS may require Accessibility permission for the helper process.

## Required App Settings

In cmd+cmd Settings:

- Endpoint URL: `http://127.0.0.1:8787/v1/captures` for simulator, or the
  trusted private URL for a physical phone.
- Bearer token: the exact value of `CODEXSHOT_RELAY_TOKEN`.
- Thread hint: optional Codex thread id to resume.
