# cmd+cmd App Store Metadata

## App Information

Name: cmd+cmd
Subtitle: Screenshots to Codex
Category: Developer Tools
Content Rights: This app does not contain, show, or access third-party content unless the user chooses a screenshot.

## URLs

Marketing URL: https://cmd.avmil.xyz/
Support URL: https://cmd.avmil.xyz/
Privacy Policy URL: https://cmd.avmil.xyz/privacy

## Promotional Text

Send iPhone screenshots to Codex Desktop through your paired Mac.

## Description

cmd+cmd sends screenshots from iPhone to Codex Desktop.

Pair with the Mac relay, choose a screenshot, and send. Share Sheet, Shortcuts, and Back Tap are supported. OCR text can be included.

cmd+cmd is independent and is not affiliated with OpenAI.

## Keywords

codex,screenshot,shortcut,back tap,ocr,mac,relay,developer

## What's New

Initial App Store release.

## App Review Notes

cmd+cmd is an independent companion utility for Codex Desktop. It is not affiliated with OpenAI.

The app sends user-selected screenshots to a Mac relay controlled by the user. Screenshots do not pass through cmd+cmd servers.

Reviewer setup:

1. On a Mac, run `curl -fsSL https://cmd.avmil.xyz/install.sh | bash -s -- --review-mode`.
2. Open cmd+cmd on iPhone.
3. In Settings, tap Scan Desktop QR and scan the QR shown in Terminal.
4. Choose or share a screenshot, then send it.
5. The Mac opens a local Review Inbox page with the received screenshot.

Review mode does not require Codex Desktop, an OpenAI account, or macOS Accessibility permission.

Normal user mode uses the same installer without `--review-mode` and sends to Codex Desktop. The relay download is Developer ID signed and notarized.

## TestFlight

Do not add existing tester groups.
Do not create a public link.
Only Jerry Koizumi (`jerry@avmillabs.com`) should be added for TestFlight testing.

## App Privacy

Tracking: No
Data Linked to User: None
Data Used to Track User: None
Data Collected by Developer: None

The app uses Photos for screenshots the user chooses, Camera for pairing QR codes, and Local Network to reach the user's paired Mac relay.
