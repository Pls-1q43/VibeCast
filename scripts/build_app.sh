#!/usr/bin/env bash
# Build a local-signed VibeCast.app release package.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAC="$ROOT/mac"
DIST="$ROOT/dist"
APP="$DIST/VibeCast.app"
ZIP="$DIST/VibeCast-0.1.0-macos.zip"
BUNDLE_ID="com.vibecast.app"
VERSION="0.1.0"
WEB_RES="$MAC/Sources/VibeCast/Resources/web"
APP_ICON="$MAC/Sources/VibeCast/Resources/AppIcon.icns"
STATUS_BAR_ICON="$MAC/Sources/VibeCast/Resources/StatusBarIconTemplate.png"
BACKUP_DIR="$(mktemp -d)"

restore_web_resources() {
  rm -rf "$WEB_RES"
  mkdir -p "$(dirname "$WEB_RES")"
  if [ -d "$BACKUP_DIR/web" ]; then
    ditto "$BACKUP_DIR/web" "$WEB_RES"
    if [ ! -d "$BACKUP_DIR/web/assets 2" ]; then
      rm -rf "$WEB_RES/assets 2"
    fi
  fi
  rm -rf "$BACKUP_DIR"
}
trap restore_web_resources EXIT

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少命令：$1"; exit 1;
  }
}

need_cmd node
need_cmd npm
need_cmd swift
need_cmd ditto

NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
if [ "$NODE_MAJOR" -lt 18 ]; then
  echo "Node.js 版本过低：需要 >= 18，当前 $(node --version)"
  exit 1
fi

if [ -d "$WEB_RES" ]; then
  ditto "$WEB_RES" "$BACKUP_DIR/web"
fi

echo "==> 构建前端资源"
( cd "$ROOT/web" && NODE_OPTIONS="" npm run build ) || {
  echo "前端构建失败，请先在 web/ 执行 npm install"; exit 1;
}

echo "==> 校验前端资源"
[ -f "$WEB_RES/index.html" ] || { echo "缺少 index.html"; exit 1; }
[ -f "$WEB_RES/config.html" ] || { echo "缺少 config.html"; exit 1; }
[ -d "$WEB_RES/assets" ] || { echo "缺少 assets 目录"; exit 1; }
if grep -q "Placeholder. Run" "$WEB_RES/index.html" "$WEB_RES/config.html"; then
  echo "前端资源仍是 placeholder，拒绝打包"
  exit 1
fi

echo "==> Release 构建 Swift 可执行文件"
( cd "$MAC" && swift build -c release )

BIN="$MAC/.build/release/VibeCast"
[ -x "$BIN" ] || { echo "未找到可执行文件 $BIN"; exit 1; }

echo "==> 组装 .app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/VibeCast"

if [ -f "$APP_ICON" ]; then
  cp "$APP_ICON" "$APP/Contents/Resources/AppIcon.icns"
fi

if [ -f "$STATUS_BAR_ICON" ]; then
  cp "$STATUS_BAR_ICON" "$APP/Contents/Resources/StatusBarIconTemplate.png"
fi

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
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>VibeCast</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- 菜单栏 App：不在 Dock 显示 -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> 本地签名"
if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP"
fi
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" "$APP"
else
  echo "未找到 codesign，跳过签名"
fi

echo "==> 生成发布压缩包"
rm -f "$ZIP"
( cd "$DIST" && ditto -c -k --sequesterRsrc --keepParent "VibeCast.app" "$ZIP" )

echo "==> 完成: $APP"
echo "==> 发布包: $ZIP"
echo "    启动: open \"$APP\""
