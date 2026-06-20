# Troubleshooting

## Phone page नहीं खोलता

Check करें कि Mac और phone एक reachable network में हैं, VibeCast चल रहा है, और आप fresh token address इस्तेमाल कर रहे हैं।

## Page connect नहीं हो रहा

URL में `token=...` होना चाहिए। Token regenerate किया है तो new address खोलें।

## Accessibility authorized नहीं

System Settings → Privacy & Security → Accessibility में VibeCast enable करें। पहले से enabled हो तो toggle करें और VibeCast relaunch करें।

## Sync या focus fail

Phone पर Refocus दबाएं, configuration page में target retest करें, Electron/WebView के लिए `clipboard_replace` try करें। Range confirm होने तक `allowSelectAllReplace=false` रखें।

## Send fail

Status Synced होने तक wait करें और confirm करें कि `sendShortcut` target app के send behavior से match करता है।
