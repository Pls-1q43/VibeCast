#!/usr/bin/env bash
# Build a local-signed VibeCast.app release package.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAC="$ROOT/mac"
DIST="$ROOT/dist"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vibecast-app.XXXXXX")"
APP="$STAGING_DIR/VibeCast.app"
DIST_APP="$DIST/VibeCast.app"
BUNDLE_ID="${BUNDLE_ID:-com.vibecast.app}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$VERSION}"
SWIFT_ARCHS="${SWIFT_ARCHS:-arm64 x86_64}"
APPCAST_URL="${APPCAST_URL:-https://pls-1q43.github.io/VibeCast/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-IqzH3LOJYajczC0ywxHO2dd+P8rVjAZKru+JZ4H1oLM=}"
REQUIRE_SIGNED_DRIVER="${REQUIRE_SIGNED_DRIVER:-0}"
ZIP="$DIST/VibeCast-$VERSION-macos.zip"
WEB_RES="$MAC/Sources/VibeCast/Resources/web"
APP_ICON="$MAC/Sources/VibeCast/Resources/AppIcon.icns"
STATUS_BAR_ICON="$MAC/Sources/VibeCast/Resources/StatusBarIconTemplate.png"
DRIVER_SRC="$ROOT/driver/VibeCastVirtualMic"
DRIVER_BUNDLE="$STAGING_DIR/VibeCastVirtualMic.driver"
BACKUP_DIR="$(mktemp -d)"

restore_web_resources() {
  rm -rf "$WEB_RES"
  mkdir -p "$(dirname "$WEB_RES")"
  if [ -d "$BACKUP_DIR/web" ]; then
    mv "$BACKUP_DIR/web" "$WEB_RES"
    rm -rf "$WEB_RES/assets 2" "$WEB_RES/target-icons 2"
  fi
  rm -rf "$BACKUP_DIR"
  rm -rf "$STAGING_DIR"
}
trap restore_web_resources EXIT

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少命令：$1"; exit 1;
  }
}

clean_bundle_metadata() {
  local bundle="$1"
  if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$bundle"
    find "$bundle" -exec xattr -c {} \; 2>/dev/null || true
  fi
  if command -v dot_clean >/dev/null 2>&1; then
    dot_clean -m "$bundle" 2>/dev/null || true
  fi
  if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$bundle"
    find "$bundle" -exec xattr -c {} \; 2>/dev/null || true
    # Some File Provider backed folders can reattach these across the bundle;
    # remove them last because strict codesign treats them as detritus.
    xattr -d com.apple.FinderInfo "$bundle" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$bundle" 2>/dev/null || true
    find "$bundle" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
    find "$bundle" -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; 2>/dev/null || true
    xattr -cr "$bundle"
    find "$bundle" -exec xattr -c {} \; 2>/dev/null || true
  fi
}

verify_bundle_signature() {
  local bundle="$1"
  if codesign --verify --deep --strict --verbose=2 "$bundle"; then
    return 0
  fi
  clean_bundle_metadata "$bundle"
  codesign --verify --deep --strict --verbose=2 "$bundle"
}

verify_zip_bundle() {
  local zip="$1"
  local verify_dir
  verify_dir="$(mktemp -d "${TMPDIR:-/tmp}/vibecast-verify.XXXXXX")"
  ditto -x -k "$zip" "$verify_dir"
  if verify_bundle_signature "$verify_dir/VibeCast.app"; then
    rm -rf "$verify_dir"
    return 0
  fi
  rm -rf "$verify_dir"
  return 1
}

verify_binary_archs() {
  local binary="$1"
  local missing=0
  if ! command -v lipo >/dev/null 2>&1; then
    echo "缺少命令：lipo"
    return 1
  fi
  for arch in $SWIFT_ARCHS; do
    if ! lipo "$binary" -verify_arch "$arch" >/dev/null 2>&1; then
      echo "二进制缺少架构：$arch ($binary)"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || return 1
  echo "    架构: $(lipo -archs "$binary")"
}

verify_driver_signing_policy() {
  local driver="$1"
  local signature
  signature="$(codesign -dv --verbose=4 "$driver" 2>&1 || true)"
  if grep -q "Signature=adhoc" <<<"$signature"; then
    echo "警告：VibeCastVirtualMic.driver 当前为 ad-hoc 签名；SIP 开启的 macOS 不会加载这种 HAL 虚拟麦克风。"
    echo "      发布包请设置 CODESIGN_IDENTITY='Developer ID Application: ...' 并完成公证。"
    if [ "$REQUIRE_SIGNED_DRIVER" = "1" ]; then
      echo "REQUIRE_SIGNED_DRIVER=1，拒绝生成不可发布的虚拟麦克风包。"
      return 1
    fi
  fi
}

need_cmd node
need_cmd npm
need_cmd swift
need_cmd clang
need_cmd ditto
need_cmd lipo

SWIFT_BUILD_ARGS=(-c release)
for arch in $SWIFT_ARCHS; do
  SWIFT_BUILD_ARGS+=(--arch "$arch")
done

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

echo "==> Release 构建 Swift 可执行文件 ($SWIFT_ARCHS)"
( cd "$MAC" && swift build "${SWIFT_BUILD_ARGS[@]}" )

BIN_DIR="$(cd "$MAC" && swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path | tail -n 1)"
BIN="$BIN_DIR/VibeCast"
[ -x "$BIN" ] || { echo "未找到可执行文件 $BIN"; exit 1; }
verify_binary_archs "$BIN"

echo "==> 构建 VibeCast 专属虚拟麦克风驱动"
[ -f "$DRIVER_SRC/VibeCastVirtualMic.c" ] || { echo "缺少虚拟麦克风驱动源码"; exit 1; }
[ -f "$DRIVER_SRC/Info.plist" ] || { echo "缺少虚拟麦克风 Info.plist"; exit 1; }
rm -rf "$DRIVER_BUNDLE"
mkdir -p "$DRIVER_BUNDLE/Contents/MacOS"
cp "$DRIVER_SRC/Info.plist" "$DRIVER_BUNDLE/Contents/Info.plist"
DRIVER_ARCH_ARGS=()
for arch in $SWIFT_ARCHS; do
  DRIVER_ARCH_ARGS+=(-arch "$arch")
done
clang "${DRIVER_ARCH_ARGS[@]}" -dynamiclib -install_name "@rpath/VibeCastVirtualMic" \
  -framework CoreAudio -framework CoreFoundation \
  -o "$DRIVER_BUNDLE/Contents/MacOS/VibeCastVirtualMic" \
  "$DRIVER_SRC/VibeCastVirtualMic.c"
verify_binary_archs "$DRIVER_BUNDLE/Contents/MacOS/VibeCastVirtualMic"

echo "==> 组装 .app bundle"
rm -rf "$APP" "$DIST_APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN" "$APP/Contents/MacOS/VibeCast"
verify_binary_archs "$APP/Contents/MacOS/VibeCast"

if [ -f "$APP_ICON" ]; then
  cp "$APP_ICON" "$APP/Contents/Resources/AppIcon.icns"
fi

if [ -f "$STATUS_BAR_ICON" ]; then
  cp "$STATUS_BAR_ICON" "$APP/Contents/Resources/StatusBarIconTemplate.png"
fi

ditto --norsrc "$DRIVER_BUNDLE" "$APP/Contents/Resources/VibeCastVirtualMic.driver"

# SwiftPM 资源 bundle（含前端 web/）
RES_BUNDLE="$BIN_DIR/VibeCast_VibeCast.bundle"
if [ -d "$RES_BUNDLE" ]; then
  cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
fi

SPARKLE_FRAMEWORK=""
for candidate in "$BIN_DIR/Sparkle.framework" "$BIN_DIR/Frameworks/Sparkle.framework"; do
  if [ -d "$candidate" ]; then
    SPARKLE_FRAMEWORK="$candidate"
    break
  fi
done
if [ -z "$SPARKLE_FRAMEWORK" ]; then
  SPARKLE_FRAMEWORK="$(find "$MAC/.build" -path "*/Sparkle.framework" -type d | head -n 1)"
fi
if [ -z "$SPARKLE_FRAMEWORK" ]; then
  echo "未找到 Sparkle.framework，请确认 SwiftPM 已解析 Sparkle 依赖"
  exit 1
fi
ditto --norsrc "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

if command -v install_name_tool >/dev/null 2>&1; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/VibeCast" 2>/dev/null || true
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>VibeCast</string>
  <key>CFBundleDisplayName</key><string>VibeCast</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>VibeCast</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- 菜单栏 App：不在 Dock 显示 -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>SUFeedURL</key><string>$APPCAST_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_ED_KEY</string>
</dict>
</plist>
PLIST

echo "==> 本地签名"
clean_bundle_metadata "$APP"
if command -v codesign >/dev/null 2>&1; then
  CODESIGN_ARGS=(--force --sign "${CODESIGN_IDENTITY:--}")
  if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    CODESIGN_ARGS+=(--options runtime --timestamp)
  fi

  SPARKLE_BUNDLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  for nested in \
    "$SPARKLE_BUNDLE/XPCServices/Downloader.xpc" \
    "$SPARKLE_BUNDLE/XPCServices/Installer.xpc" \
    "$SPARKLE_BUNDLE/Updater.app" \
    "$SPARKLE_BUNDLE/Autoupdate" \
    "$APP/Contents/Frameworks/Sparkle.framework" \
    "$APP/Contents/Resources/VibeCastVirtualMic.driver"
  do
    if [ -e "$nested" ]; then
      codesign "${CODESIGN_ARGS[@]}" "$nested"
    fi
  done
  verify_driver_signing_policy "$APP/Contents/Resources/VibeCastVirtualMic.driver"

  APP_CODESIGN_ARGS=("${CODESIGN_ARGS[@]}")
  if [ -z "${CODESIGN_IDENTITY:-}" ]; then
    # Ad-hoc signing normally falls back to a cdhash-only designated requirement,
    # which makes macOS TCC treat every rebuild as a different Accessibility client.
    # Pin a stable local requirement to the bundle identifier so local updates do
    # not repeatedly invalidate the user's Accessibility grant.
    APP_CODESIGN_ARGS+=(--requirements "=designated => identifier \"$BUNDLE_ID\"")
  fi
  codesign "${APP_CODESIGN_ARGS[@]}" "$APP"
  verify_bundle_signature "$APP"
else
  echo "未找到 codesign，跳过签名"
fi

echo "==> 生成发布压缩包"
rm -f "$ZIP"
( cd "$STAGING_DIR" && ditto -c -k --sequesterRsrc --keepParent "VibeCast.app" "$ZIP" )
if command -v codesign >/dev/null 2>&1; then
  verify_zip_bundle "$ZIP"
fi
rm -rf "$DIST_APP"
ditto --norsrc --noextattr --noqtn --noacl "$APP" "$DIST_APP"
clean_bundle_metadata "$DIST_APP"
if command -v codesign >/dev/null 2>&1; then
  if ! verify_bundle_signature "$DIST_APP"; then
    echo "警告：$DIST_APP 位于可能会附加扩展属性的目录，严格签名校验未通过；发布 zip 已单独校验。"
  fi
fi

echo "==> 完成: $DIST_APP"
echo "==> 发布包: $ZIP"
echo "    启动: open \"$DIST_APP\""
