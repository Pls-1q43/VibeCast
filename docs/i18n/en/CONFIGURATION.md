# Target App Configuration

VibeCast uses target profiles to control activation, focus, writing, and sending.

The profile file lives at:

```text
~/Library/Application Support/VibeCast/targets.json
```

Use the menu bar configuration page for normal editing.

## Setup Flow

1. Open the configuration page.
2. Enable the apps you want to show on the phone.
3. Choose a running app to fill its Bundle ID, or enter it manually.
4. Add custom apps when needed.
5. Save and click Test for each target.
6. When send behavior is uncertain, choose `sendMode=none` first.

## Key Fields

| Field | Purpose |
|---|---|
| `displayName` | Name shown on the phone card |
| `bundleId` | macOS app Bundle ID |
| `focusMode` | Shortcut, preserve last focus, Accessibility lookup, or custom |
| `writeMode` | `auto`, `axvalue`, `clipboard_replace`, or `clipboard_insert` |
| `syncMode` | `mirror` writes the full draft; `editor` only replaces text inserted in this input round |
| `allowSelectAllReplace` | Allows Cmd+A replacement when explicitly safe |
| `sendMode` | Key, custom shortcut, accessibility button, or sync-only |
| `maxTextLength` | Maximum text length for one snapshot |

## Best Practices

- Test every target before daily use.
- Keep `allowSelectAllReplace=false` for ordinary document pages.
- Use `syncMode=editor` for Obsidian or ordinary Notion document blocks.
- Prefer `sendMode=none` while tuning a new target.
- Re-test after target apps update their UI or shortcuts.
