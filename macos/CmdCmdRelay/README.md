# cmd+cmd Relay for macOS

The native relay is the only supported cmd+cmd relay. It receives authenticated
iPhone screenshot uploads, stores them locally, and attaches them to the visible
Codex Desktop composer through macOS pasteboard and Accessibility APIs. The
installed bundle runs headlessly; setup, pairing, logs, and QR display stay in
Terminal.

## Install

```bash
curl -fsSL https://www.cmdcmd.click/install.sh | bash
```

The installer prepares the private endpoint and token, starts the relay, waits
for it to become healthy, and prints the pairing QR.

## Develop

From the repository root:

```bash
swift test --package-path macos/CmdCmdRelay
./scripts/check.sh --fast
```

The full `./scripts/check.sh` command also verifies the iOS app and Share
Extension.

## Package locally

```bash
./scripts/package_macos.sh
```

Set `DEVELOPER_ID_APPLICATION` to create a Developer ID-signed bundle:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Example" ./scripts/package_macos.sh
```

The script writes `dist/cmdcmd-relay/CmdCmdRelay-macOS.zip` and its SHA-256
checksum. Without an explicit identity, the current script produces an ad-hoc
local build, not a release artifact. Packaging or signature verification alone
does not prove notarization; only describe an artifact as notarized after Apple
accepts it, the ticket is stapled, and Gatekeeper accepts that exact bundle.

## Security model

- Every capture and status request requires the per-user bearer token.
- The relay never reads Codex credentials, sessions, cookies, or private app
  files.
- Screenshots and metadata stay in the user's Application Support directory.
- Accessibility is used only to focus Codex Desktop and attach files to its
  visible composer.
