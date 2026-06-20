# VibeCast

अपने फ़ोन को macOS के लिए रिमोट voice-to-text input panel बनाएं, खास तौर पर Vibe Coding के लिए।

[中文](../../../README.md) · [English](../en/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md) · [Español](../es/README.md) · [हिन्दी](README.md) · [العربية](../ar/README.md)

VibeCast आपके फ़ोन कीबोर्ड से बने टेक्स्ट को Codex, WorkBuddy, Notion, CodeBuddy या किसी भी configured Mac app में real time mirror करता है। Speech recognition फ़ोन keyboard में रहता है; VibeCast text को local, fast और controlled तरीके से ले जाता है।

## मुख्य बातें

- फ़ोन browser से input panel।
- macOS target apps में real-time text mirroring।
- हर target के लिए अलग draft।
- final sync confirm होने के बाद two-stage send।
- Bundle ID, focus, write और send behavior configurable।
- microphone permission नहीं, audio handling नहीं, redacted diagnostics।
- Product, design, code, marketing: All by Codex. Thanks to OpenAI.

## Continuity Microphone की तुलना में

iPhone/Mac Continuity Microphone की तुलना में VibeCast ये समस्याएँ हल करता है:

1. Continuity Microphone connection अस्थिर हो सकता है।
2. Continuity Microphone चालू होने पर iPhone पर दूसरे काम करना मुश्किल होता है।
3. Mac पर target app जल्दी switch नहीं किया जा सकता।
4. पहले Mac-side dictation चालू करना पड़ता है, इसलिए हाथ keyboard से पूरी तरह दूर नहीं जा सकते।
5. Continuity Microphone Android phones support नहीं करता।

## Quick Start Guide

1. Mac पर VibeCast शुरू करें; menu bar में VibeCast icon दिखेगा।
2. Copy Access URL चुनें।
3. उसी Wi-Fi पर जुड़े फ़ोन browser में वह URL खोलें।
4. फ़ोन page पर Codex, Notion या कोई configured target चुनें।
5. फ़ोन keyboard या voice input इस्तेमाल करें; text संबंधित Mac app में real time दिखाई देगा।
6. Send दबाएँ; VibeCast final text sync confirm करके target app में send action चलाता है।

## Docs

[Install](INSTALL.md) · [Configuration](CONFIGURATION.md) · [Architecture](ARCHITECTURE.md) · [Security](SECURITY.md) · [Troubleshooting](TROUBLESHOOTING.md) · [Best Practices](KNOWN_LIMITS.md) · [Uninstall](UNINSTALL.md)

## License

MIT License के अंतर्गत जारी।
