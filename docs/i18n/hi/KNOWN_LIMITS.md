# Capability boundaries और best practices

VibeCast phone keyboard से बने text को selected Mac apps में mirror करता है।

- Voice button Android keyboard देता है।
- IME composition keyboard और Android version के हिसाब से बदल सकता है।
- Phone foreground में हो तो WebSocket सबसे stable रहता है।
- Accessibility permission activation, focus, writing और sending का आधार है।
- Electron, WebView और rich editors को Test button से verify करें।

Notion AI input में focus confirm करने के बाद `clipboard_replace` अच्छा काम कर सकता है। Document blocks में preserve-last-focus, cursor insert या sync-only बेहतर हैं।
