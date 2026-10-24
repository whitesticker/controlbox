#!/bin/zsh
# Build ControlCenterLab, wrap it in a minimal .app (so it gets a Dock icon and
# real menu bar extras), and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
app=.build/ControlCenterLab.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/ControlCenterLab "$app/Contents/MacOS/ControlCenterLab"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ControlCenterLab</string>
    <key>CFBundleIdentifier</key><string>com.whitesticker.controlcenterlab</string>
    <key>CFBundleName</key><string>ControlCenterLab</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" >/dev/null
pkill -x ControlCenterLab 2>/dev/null || true
while pgrep -x ControlCenterLab >/dev/null; do sleep 0.1; done
open "$app"
