#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP_DIR="$ROOT/发票管家.app"
DATA_DIR="$ROOT/发票整理"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BINARY="$MACOS/发票管家"
ICON_SOURCE="$ROOT/content_ops/mac/InvoicePilotIcon.icns"
ICON_TARGET="$RESOURCES/InvoicePilotIcon.icns"

case "$DATA_DIR" in
  "$APP_DIR"|"$APP_DIR"/*)
    echo "拒绝构建：数据目录不能放在发票管家.app 内。"
    exit 1
    ;;
esac

echo "覆盖安装：只更新 $APP_DIR，不会删除 $DATA_DIR"
mkdir -p "$MACOS" "$RESOURCES"

swiftc \
  -target arm64-apple-macosx26.0 \
  -parse-as-library \
  "$ROOT/content_ops/mac/InvoicePilotApp.swift" \
  -o "$BINARY"

if [ -f "$ICON_SOURCE" ]; then
  cp "$ICON_SOURCE" "$ICON_TARGET"
fi

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>发票管家</string>
  <key>CFBundleIdentifier</key>
  <string>com.local.invoicepilot</string>
  <key>CFBundleIconFile</key>
  <string>InvoicePilotIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>发票管家</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.14</string>
  <key>CFBundleVersion</key>
  <string>20260520.10</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

chmod +x "$BINARY"
echo "$APP_DIR"
