# Capability Boundaries and Best Practices

VibeCast mirrors text produced by the phone keyboard into selected Mac apps. These practices keep the experience fast and controlled.

## Input Method and Browser

- The page focuses a text box; the keyboard provides the voice button.
- IME composition behavior can vary by keyboard and Android version.
- Foreground phone use is the most reliable WebSocket scenario.

## macOS and Target Apps

- Accessibility permission powers activation, focus, writing, and sending.
- Electron, WebView, and rich editors vary in Accessibility support.
- Use the Test button as the source of truth for each target.
- Re-test after target apps change shortcuts or UI structure.

## Notion

- Notion AI input: `clipboard_replace` can work well after confirming focus.
- Document blocks: use preserve-last-focus, cursor insert, or sync-only.
- Keep select-all replacement disabled for ordinary pages.

## Privacy

VibeCast handles text, not audio; the page does not request microphone permission; diagnostics are redacted.
