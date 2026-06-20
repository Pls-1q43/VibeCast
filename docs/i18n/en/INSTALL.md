# Install and Use

VibeCast ships as a macOS menu bar app plus a phone web page hosted by the Mac.

## Requirements

- macOS 13 Ventura or newer
- Xcode Command Line Tools, Swift 5.9+
- Node.js 18+
- Android Chrome
- A local network where the Mac and phone can reach each other
- macOS Accessibility permission

## Build

```bash
cd web && npm install && cd ..
bash scripts/build_app.sh
open dist/VibeCast.app
```

If npm is affected by a local preload environment, run builds with `NODE_OPTIONS=""`.

## First Run

1. Launch `dist/VibeCast.app`.
2. Grant Accessibility permission in System Settings.
3. Open the menu bar item and choose “Open Configuration Page…”.
4. Enable targets, bind Bundle IDs, and test writing.
5. Copy the access address with token and open it in Android Chrome.
6. Add the page to the home screen if you want an app-like entry point.

## Daily Use

1. Open the VibeCast page on your phone.
2. Tap a target card.
3. Let VibeCast focus the matching Mac app.
4. Use your Android keyboard’s voice button.
5. Review or edit the draft on the phone.
6. Tap Send; VibeCast sends after the final text revision is mirrored.

## Verify

```bash
cd web
NODE_OPTIONS="" npm test
NODE_OPTIONS="" npm run build

cd ../mac
swift test
```
