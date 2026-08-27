<p align="center">
  <img src="docs/screenshots/hero.png" alt="Control Box" width="960">
</p>

<p align="center">
  <strong>Control Box</strong> maps unusual input devices to pointer, keys, and system gestures on your Mac.<br>
  DualSense, Siri Remote, and MX Master — at the same time, if you want.
</p>

<p align="center">
  <img src="docs/screenshots/app-icon.png" alt="Control Box icon" width="96">
</p>

Use a **PS5 DualSense** from the couch, an **Apple TV Siri Remote** as a trackpad, or an **MX Master 3 / 3S / 4** with hold-to-swipe gestures. Each device has its own mappings and its own **Control this Mac** switch.

Control Box stays on your Mac. Nothing is uploaded.

## Supported now

| Device | What you get |
|---|---|
| **DualSense / DualSense Edge** | Buttons, sticks, rumble. Touchpad **1-finger** and **2-finger** are separate Gestures. Sticks can be pointer or scroll; L2/R2 can switch tabs with analog travel. |
| **Siri Remote (A2540)** | Clickpad pointer, click-wheel scroll, face buttons, live calibration. |
| **MX Master 3 / 3S** | Extra buttons + thumb **Gesture** (tap = click, hold + move = swipe). Hold Control to move a window; Control+Shift to resize. |
| **MX Master 4** | Extra buttons + **Haptic** pad (same gesture engine, isolated HID++ reader). Same window grab as 3 / 3S. |

Several of these can stay attached at once. Wheel invert and scroll speed are shared across mice (one system scroll tap). Pointer mappings stay per device.

macOS 14+ and **Accessibility** are required. **Input Monitoring** is required for MX wheel speed.

## Install

```bash
brew install --cask whitesticker/controlbox/controlbox
```

Open **Control Box**, then enable it in **System Settings → Privacy & Security → Accessibility** (and Input Monitoring if you use an MX Master). Relaunch if macOS asks. If you previously granted those to the old app identity, grant them again for Control Box.

The first launch of an ad-hoc Homebrew build may need **Right-click → Open**.

## Build from source

```bash
xcodebuild -project ControlBox.xcodeproj -scheme ControlBox -configuration Release \
  -derivedDataPath .derived build
open .derived/Build/Products/Release/ControlBox.app
```

Debug builds are signed with the Apple Development identity so Accessibility and Input Monitoring persist across rebuilds.

## Privacy

Control Box does not send input data to a server. Bluetooth is used only to list devices (it never calls `IOBluetoothDevice.pairedDevices()`). Accessibility is used only to post the keyboard, pointer, and scroll events you mapped.

## Roadmap

Tracked in [docs/roadmap.md](docs/roadmap.md):

- DualSense and Siri Remote **microphone**
- Stronger **gesture** hold / swipe on-screen cue (media skip / play / mute already show an action HUD)
- The extra **MX Master 4** button we do not capture yet
- **MX keyboard** support
- More accurate **calibration** layouts
- Smoother **MX4 haptic** swipes (3S already feels better)
- First-run **onboarding**
- Menu bar icon: a **circle**, matching the app icon (not a game-controller glyph)
- **Background** (Allow in the Background) — request is in the Permissions pane; confirm after login
- **Per-app mouse profiles** — different Control mappings when the frontmost app changes

Generic mouse, Xbox, and other TV remotes are later. New hardware should land as a device family, not another special case in the host.

## Docs for contributors

Start at [docs/README.md](docs/README.md) and [AGENTS.md](AGENTS.md).
