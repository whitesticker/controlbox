# VibeRemote

Control your Mac from the couch with a **PS5 DualSense** or **Apple TV Siri Remote**.

VibeRemote maps buttons, clickpad, touchpad, and analog sticks to pointer, clicks, keys, and media keys. Hold Select for right-click, tap twice for double-click, and optionally rumble the DualSense on every press.

macOS 14+ is required. Accessibility permission is required to inject input.

## Install with Homebrew

```bash
brew tap whitesticker/viberemote
brew install --cask viberemote
```

Then open **VibeRemote**, enable it in **System Settings → Privacy & Security → Accessibility**, and relaunch if macOS asks.

The first launch of an ad-hoc signed build may need **Right-click → Open**.

## Build from source

```bash
xcodebuild -project IRemote.xcodeproj -scheme IRemote -configuration Release -derivedDataPath .derived build
open .derived/Build/Products/Release/VibeRemote.app
```

## Privacy

VibeRemote stays on your Mac. It does not send controller data to a server. Bluetooth is used only to list paired devices. Accessibility is used only to post keyboard, pointer, and scroll events you mapped.
