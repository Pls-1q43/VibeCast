# Troubleshooting

## Phone Cannot Open the Page

- Confirm the Mac and phone can reach each other on the local network.
- Check that the VibeCast menu bar service is running.
- Copy a fresh access address with token.
- Check firewall or router rules.

## Page Is Not Connected

- Confirm `token=...` is present in the URL.
- Refresh after regenerating the pairing token.
- Relaunch VibeCast if the Mac slept or changed networks.

## Accessibility Not Authorized

Open System Settings → Privacy & Security → Accessibility and enable VibeCast. If it is already enabled, toggle it off and on, then relaunch VibeCast.

## Sync or Focus Fails

1. Tap Refocus on the phone.
2. Test the target again in the configuration page.
3. For Electron/WebView inputs, try `clipboard_replace`.
4. Keep `allowSelectAllReplace=false` until the write range is confirmed.

## Send Fails

- Wait for the status to become Synced.
- Confirm the target app is still active or can be reactivated.
- Verify `sendShortcut` matches the app’s send behavior.
- Use `sendMode=none` for sync-only workflows.
