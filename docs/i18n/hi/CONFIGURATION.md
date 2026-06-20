# Target app configuration

VibeCast target profiles से activation, focus, writing और sending control करता है।

```text
~/Library/Application Support/VibeCast/targets.json
```

Configuration page में apps enable करें, running app से Bundle ID चुनें या manually भरें, save करें और हर target test करें।

मुख्य fields: `displayName`, `bundleId`, `focusMode`, `writeMode`, `allowSelectAllReplace`, `sendMode`, `maxTextLength`.

Document pages के लिए `allowSelectAllReplace=false` रखें। New target tune करते समय पहले `sendMode=none` चुनें और write range confirm करें।
