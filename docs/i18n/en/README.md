# VibeCast

Turn your phone into a remote voice-to-text input panel for macOS, designed for Vibe Coding.

[中文](../../../README.md) · [English](README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md) · [Español](../es/README.md) · [हिन्दी](../hi/README.md) · [العربية](../ar/README.md)

VibeCast lets your phone capture text through the keyboard you already use, then mirrors that text into Codex, WorkBuddy, Notion, Obsidian, CodeBuddy, or any configured Mac app. Speech recognition stays with the phone keyboard; VibeCast moves text quickly, locally, and deliberately.

## Highlights

- Phone-first voice input through a mobile browser.
- Real-time text mirroring to macOS target apps.
- Independent drafts for every target.
- Two-stage send confirmation.
- Configurable Bundle ID, focus, write, and send behavior.
- Local-first privacy: no microphone permission, no audio handling, redacted diagnostics.
- Product, design, code, and marketing: All by Codex. Thanks to OpenAI.

## Compared with Continuity Microphone

Compared with iPhone/Mac Continuity Microphone, VibeCast solves:

1. Continuity Microphone connections can be unstable.
2. iPhone cannot be used for other tasks while Continuity Microphone is active.
3. It cannot quickly switch between target apps on the Mac.
4. It still requires activating Mac-side dictation first, so your hands cannot fully leave the keyboard.
5. Continuity Microphone does not support Android phones.

## Quick Start Guide

1. Start VibeCast on your Mac; the VibeCast icon appears in the menu bar.
2. Choose Copy Access URL.
3. Open that URL in a phone browser on the same Wi-Fi.
4. On the phone page, choose Codex, Notion, or any configured target.
5. Use your phone keyboard or voice input; text appears in real time in the corresponding Mac app.
6. Tap Send; VibeCast confirms the final text is synced before sending in the target app.

## Docs

- [Install and Use](INSTALL.md)
- [Target App Configuration](CONFIGURATION.md)
- [Architecture](ARCHITECTURE.md)
- [Security and Privacy](SECURITY.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Capability Boundaries and Best Practices](KNOWN_LIMITS.md)
- [Uninstall](UNINSTALL.md)

## License

VibeCast is released under the [MIT License](../../../LICENSE).
