#!/bin/zsh
# Build MenuLagLab, wrap it in a minimal menu-bar-only .app, and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
app=.build/MenuLagLab.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/MenuLagLab "$app/Contents/MacOS/MenuLagLab"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MenuLagLab</string>
    <key>CFBundleIdentifier</key><string>com.whitesticker.menulaglab</string>
    <key>CFBundleName</key><string>MenuLagLab</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" >/dev/null
pkill -x MenuLagLab 2>/dev/null || true
while pgrep -x MenuLagLab >/dev/null; do sleep 0.1; done
open "$app"
