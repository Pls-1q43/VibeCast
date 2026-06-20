# Security and Privacy

VibeCast focuses on local text flow. Speech recognition happens inside the Android keyboard; VibeCast receives only the text that the keyboard writes into the page.

## Privacy Model

- The web page uses a standard `<textarea>`.
- The page does not request microphone permission.
- VibeCast does not receive, transmit, or store audio.
- The Mac does not send user text to external services.
- Diagnostics record events, targets, revisions, lengths, and short hashes, not full text or tokens.

## Pairing Token

- The Mac generates a token on first launch.
- The copied phone URL includes `token=...`.
- The phone stores the token in localStorage.
- Regenerating the token invalidates old URLs.

Treat the token URL as a local control entry point and keep it on trusted devices.

## Local Network Boundary

VibeCast listens on port `8787` for devices that can reach the Mac. Visibility depends on your router and firewall. Use trusted networks, avoid port forwarding, and regenerate the token if an address is exposed.

## Write Guards

Before writing or sending, VibeCast verifies the selected target, Bundle ID, process, session, focus binding, revision, rate, and text size. Clipboard replacement is allowed only when the target profile explicitly permits select-all replacement.
