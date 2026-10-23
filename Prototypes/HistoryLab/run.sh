#!/bin/zsh
# Build HistoryLab, wrap it in a minimal .app (so it gets a Dock icon and a
# real menu bar), and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
app=.build/HistoryLab.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/HistoryLab "$app/Contents/MacOS/HistoryLab"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>HistoryLab</string>
    <key>CFBundleIdentifier</key><string>com.whitesticker.historylab</string>
    <key>CFBundleName</key><string>HistoryLab</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" >/dev/null
pkill -x HistoryLab 2>/dev/null || true
while pgrep -x HistoryLab >/dev/null; do sleep 0.1; done
open "$app"
