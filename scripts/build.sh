#!/bin/bash
# Build Nest.app without a full Xcode installation.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ swift build (release)"
swift build -c release

BIN=$(swift build -c release --show-bin-path)
APP_DIR="build/Nest.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN/Nest" "$APP_DIR/Contents/MacOS/Nest"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Nest</string>
    <key>CFBundleIdentifier</key><string>com.nest.menubar</string>
    <key>CFBundleName</key><string>Nest</string>
    <key>CFBundleDisplayName</key><string>Nest</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST

codesign --force -s - "$APP_DIR" 2>/dev/null || true

echo "✅ Built $APP_DIR"
