# इंस्टॉल और उपयोग

VibeCast एक macOS menu bar app और Mac द्वारा host किए गए phone web page से बना है।

## आवश्यकताएं

macOS 13+, Xcode Command Line Tools और Swift 5.9+, Node.js 18+, Android Chrome, Mac और phone के बीच reachable local network, और macOS Accessibility permission।

## Build

```bash
cd web && npm install && cd ..
bash scripts/build_app.sh
open dist/VibeCast.app
```

npm preload issue हो तो `NODE_OPTIONS=""` इस्तेमाल करें।

## पहली बार

VibeCast launch करें, Accessibility permission दें, menu bar से configuration page खोलें, targets enable करें, Bundle IDs bind करें और writing test करें। Token वाला access address copy करके Android Chrome में खोलें।

## Daily use

Phone पर target card tap करें, Android keyboard का voice button इस्तेमाल करें, draft review करें और Send दबाएं। Final revision Mac पर mirror होने के बाद VibeCast send करता है।
