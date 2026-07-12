<picture>
  <source media="(prefers-color-scheme: dark)" srcset="CmdCmd/Resources/Assets.xcassets/CmdCmdLogoDark.imageset/logo-dark.png">
  <img alt="cmd+cmd" src="CmdCmd/Resources/Assets.xcassets/CmdCmdLogo.imageset/logo.png" width="220">
</picture>

# cmd+cmd

Send iPhone screenshots to Codex Desktop through a private relay on your Mac.

cmd+cmd is an independent companion utility and is not affiliated with OpenAI.

## Install

1. Install [cmd+cmd from the App Store](https://apps.apple.com/app/id6776976333).
2. On the Mac running Codex Desktop, install the native relay:

   ```bash
   curl -fsSL https://www.cmdcmd.click/install.sh | bash
   ```

3. Open cmd+cmd on iPhone, go to Settings, tap `Scan Desktop QR`, and scan the
   QR printed by the installer.
4. Grant Accessibility permission when macOS asks so the relay can attach files
   to the visible Codex Desktop composer.

The installer registers a per-user LaunchAgent so the relay starts at login and
automatically restarts if it exits. Its logs are written to
`~/Library/Logs/cmdcmd-relay.log` and `~/Library/Logs/cmdcmd-relay.err.log`.

The relay uses a private per-user token. Do not expose it on a shared or public
network.

## Repository

- `CmdCmd/`: SwiftUI iOS app and App Intent.
- `ShareExtension/`: iOS Share Extension.
- `macos/CmdCmdRelay/`: native macOS relay.
- `site/`: public setup and privacy site.
- `appstore/`: App Store metadata and screenshot assets.

## Development

Run the complete repository check:

```bash
./scripts/check.sh
```

Use `./scripts/check.sh --fast` while iterating on the native relay. The full
check runs native tests plus the iOS simulator test/build harness with one reused
DerivedData directory.

Build or test only the native relay:

```bash
swift build --package-path macos/CmdCmdRelay
swift test --package-path macos/CmdCmdRelay
```

Open `CmdCmd.xcodeproj` in Xcode for interactive iOS work.

## Security model

- Screenshots travel directly from the iPhone to the paired Mac relay.
- Screenshots and metadata remain under the user's local Application Support
  directory.
- The relay never reads Codex credentials, sessions, cookies, or private app
  files.
- Accessibility is used only to focus Codex Desktop and attach the selected
  screenshot and context sidecar.

See [macos/CmdCmdRelay/README.md](macos/CmdCmdRelay/README.md) for native relay
development and packaging details. The public privacy policy is at
[www.cmdcmd.click/privacy](https://www.cmdcmd.click/privacy).
