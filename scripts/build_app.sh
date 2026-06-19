#!/usr/bin/env bash
# 打包 VibeCast.app（菜单栏 App）。先确保已构建前端：cd web && npm run build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAC="$ROOT/mac"
DIST="$ROOT/dist"
APP="$DIST/VibeCast.app"
BUNDLE_ID="com.vibecast.app"

echo "==> 构建前端（若已构建可忽略告警）"
if [ ! -f "$MAC/Sources/VibeCast/Resources/web/assets" ] 2>/dev/null; then :; fi
( cd "$ROOT/web" && NODE_OPTIONS="" npm run build ) || {
  echo "前端构建失败，请先在 web/ 执行 npm install"; exit 1;
}

echo "==> Release 构建 Swift 可执行文件"
( cd "$MAC" && swift build -c release )

BIN="$MAC/.build/release/VibeCast"
[ -x "$BIN" ] || { echo "未找到可执行文件 $BIN"; exit 1; }

echo "==> 组装 .app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/VibeCast"

# SwiftPM 资源 bundle（含前端 web/）
RES_BUNDLE="$MAC/.build/release/VibeCast_VibeCast.bundle"
if [ -d "$RES_BUNDLE" ]; then
  cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>VibeCast</string>
  <key>CFBundleDisplayName</key><string>VibeCast</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>VibeCast</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- 菜单栏 App：不在 Dock 显示 -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 本地临时签名（ad-hoc），使辅助功能授权可记住该 App。
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "（ad-hoc 签名跳过/失败，可手动签名）"

echo "==> 完成: $APP"
echo "    启动: open \"$APP\""
