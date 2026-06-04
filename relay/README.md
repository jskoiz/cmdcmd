# cmd+cmd Relay

This private relay receives the JSON payload posted by the cmd+cmd iOS app,
saves the screenshot into a local inbox, and sends the note, OCR text, and local
image into Codex through the supported `codex app-server` protocol. The relay
uses a native `localImage` input, so Codex receives the screenshot as an image
attachment rather than only as a file path in prompt text.

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

## Real Codex Test

With `CODEXSHOT_DRY_RUN` unset, the relay starts `codex app-server`, starts or
resumes a Codex thread, and passes the screenshot through its `localImage` input.
This is the same app-server protocol used by rich Codex clients, rather than the
background SDK/CLI lane.

This is not the private macOS Appshots hotkey path. Appshots are created inside
the Codex Desktop renderer and attached locally by the app. The relay uses the
documented app-server turn API, so its source of truth is the relay log entry
containing the `threadId`, `turnId`, and final turn status.

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

## Required App Settings

In cmd+cmd Settings:

- Endpoint URL: `http://127.0.0.1:8787/v1/captures` for simulator, or the
  trusted private URL for a physical phone.
- Bearer token: the exact value of `CODEXSHOT_RELAY_TOKEN`.
- Thread hint: optional Codex thread id to resume.
