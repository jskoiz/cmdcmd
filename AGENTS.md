# cmd+cmd Repository Guidance

## End-state architecture

- `CmdCmd/` and `ShareExtension/` are the iOS product.
- `macos/CmdCmdRelay/` is the only supported relay implementation.
- `site/` is the public setup and privacy site. The canonical public origin is
  `https://www.cmdcmd.click`.
- Prefer the current contract. Do not add compatibility aliases, bridge routes,
  duplicate parsers, or removed alternate relay and delivery paths.

## Repository truth first

Before editing, building, launching, packaging, or taking screenshots, run:

```bash
pwd
git rev-parse --show-toplevel
git branch --show-current
git status -sb
```

Keep edits and validation in the same checkout. If the active checkout contains
unrelated changes, preserve them and use an isolated worktree for separate work.
Never validate one checkout with an app or DerivedData produced from another.

## Verification

- Fast native checks: `./scripts/check.sh --fast`
- Full repository verification: `./scripts/check.sh`
- Reuse `CMDCMD_DERIVED_DATA` or the check script's single default under
  `/tmp/codex-xcode-derived-data/cmdcmd-modernization`; do not create timestamped
  build paths.
- The full check selects one available iOS Simulator. Set
  `CMDCMD_TEST_DESTINATION` to a complete `xcodebuild` destination only when an
  explicit simulator override is needed.
- Do not claim simulator, device, signing, notarization, App Store, TestFlight,
  deployment, or hosted verification unless that exact surface was checked.

## Release boundaries

- The public Mac installer is `https://www.cmdcmd.click/install.sh`; keep one
  static-site distribution contract.
- Packaging success and `codesign --verify` do not prove notarization. A Mac
  release is notarized only after the submitted artifact is accepted, stapled,
  and passes Gatekeeper assessment.
- Never publish or describe a release artifact as signed or notarized without
  verifying the exact distributed archive.
- App Store archives and exports belong under ignored `.asc/` output. Upload and
  App Store submission remain explicit operator actions.
- Do not trigger GitHub-hosted macOS or iOS workflows on the user's personal
  Actions budget without approval for that exact repository, workflow, and ref.

## Signing and secrets

- Never print, paste, log, or commit tokens, certificates, provisioning
  profiles, private keys, or keychain passwords.
- Device signing must be non-interactive. If the configured signing material is
  unavailable, stop instead of opening a macOS password prompt.
- Keep generated archives, exports, DerivedData, live screenshots, and local
  relay state out of Git.

## App Store and TestFlight

- Keep `appstore/metadata.md` limited to submission-facing metadata and review
  instructions.
- Do not add existing TestFlight groups or create a public link. Only Jerry
  Koizumi (`jerry@avmillabs.com`) should be added for TestFlight testing unless
  the user explicitly changes that instruction.

## Git

- Before committing, verify the author is `jskoiz` with
  `20649937+jskoiz@users.noreply.github.com`.
- Commit messages describe only the human-visible change and contain no
  assistant attribution.
- Do not commit, push, merge, publish, deploy, or upload unless the task
  explicitly includes that action.
