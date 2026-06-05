# cmd+cmd Relay for macOS

Native macOS companion for cmd+cmd. It receives private iPhone screenshot
uploads, stores them locally, and attaches them to the frontmost Codex Desktop
composer through macOS pasteboard and Accessibility.

## Build

```bash
swift build --package-path macos/CmdCmdRelay -c release
```

For a distributable app bundle:

```bash
./scripts/package_macos.sh
```

Set `DEVELOPER_ID_APPLICATION` to sign the bundle:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Example" ./scripts/package_macos.sh
```

The packaging script writes `dist/cmdcmd-relay/CmdCmdRelay-macOS.zip` plus a
SHA-256 checksum. Notarization still needs the project owner's Apple Developer
credentials and should be run against the exported zip before publishing.

## Security Model

- The relay never reads Codex credentials, sessions, cookies, or private app
  files.
- The relay requires a per-user bearer token for every capture and status call.
- The default listener is `127.0.0.1`; private-network mode is explicit.
- Screenshots and metadata stay under the user's local Application Support
  directory.
- Accessibility is required only so the relay can focus Codex Desktop and paste
  into the visible composer.

