# VibeRemote agent notes

VibeRemote is a local Mac app that maps unusual input devices (DualSense, Apple TV remote, Logitech MX Master) to pointer, keys, and system gestures.

## Current status (2026-08-22)

- Active test device: **MX Master 3S** (BLE `0xB034`). Leave MX Master 4 disconnected. Master 3 is still later.
- Device kinds stay split for the sidebar (3 vs 3S vs 4). HID modules are **3/3S together** (`MXMaster3Support`) and **4** (`MXMaster4Support`). Shared code is the HID++ pipe and hold-to-swipe engine.
- 3S HID++ is nested on the mouse device (page `0xFF43`, report `0x11`). Gesture is thumb CID `0x00C3`. See `docs/mx-master-3s-hid.md`.
- MX4 pointer / haptic stack is unchanged when that mouse is the active model. How MX4 should feel is `docs/mx-master-4-pointer-and-haptic.md`.
- Pointer speed and gesture speed are **separate sliders**. DPI is sensor resolution only. Both speeds divide out DPI so 1000 DPI is the reference feel.
- 3S: tap gesture button = click action; hold 100ms then move = swipe. Same ControlEngine path as MX4 haptic (owner `.mxHaptic`).
- **Gestures is the 3S gesture button / MX4 haptic pad only.** Click-as-gesture on Back / Forward / etc. is still parked.
- Do not attach Bolt receiver `C548`. Do not open both 3S and 4 at once.

## Device rule

Treat these as **different devices**, not one “MX Master”:

| Device | HID++ collection | Gesture / extra-button notes |
|---|---|---|
| MX Master 3 | Unifying `0x4082`, BLE `0xB023`. Same HID module as 3S. | Gesture CID `0x00C3`. No 3 on this Mac; inferred from Solaar/logiops. |
| MX Master 3S | BLE `0xB034`, Bolt `0xB043`. Nested `0xFF43` / report `0x11`. | Same CIDs as Master 3. Thumb gesture `0x00C3`. |
| MX Master 4 | BLE: vendor report `0x11` on the mouse device (page `0xFF43`), not a separate `0xFF00` collection. Bolt receiver `C548` is not the mouse. | Haptic is HID button 7 (`0x40` on report `0x02`). CID `0x01A0` is HID++ when that pipe exists. |

Focus on **MX Master 3S** while that mouse is the only Logitech device attached. Do not reopen dual-mouse attach or “open every Logitech interface.”

Keep 3/3S and 4 as separate HID modules. Shared code should stay at “send a HID++ report” / “list HID devices” / hold-to-swipe, not one matcher for every Logitech interface.

## Hard constraints

- Never call `IOBluetoothDevice.pairedDevices()`. It has corrupted the heap on this Mac (`libmalloc` / `EXC_BREAKPOINT`).
- Never `IOHIDManagerOpen` with `kIOHIDOptionsTypeSeizeDevice` on Logitech mouse or HID++ managers.
- Do not open the standard Logitech mouse collection (usage page `0x01` usage `0x02`) just to watch buttons. That can steal the system pointer.
- Reprog Controls V4 `setCidReporting` flags are value + valid pairs, not “0x01 divert / 0x02 persist / 0x04 raw XY”. Solaar hold-only gestures use **`0x33`** (divert+valid + rawXY+valid). Persist is `0x04`/`0x08`. Force raw XY is `0x40`/`0x80`. Packet is CID, flags, remap, and optional high flags. Analytics reporting is high-byte `0x03`. Do not send persist or force-raw-XY. Clear with `0x22`, not `0`. The Master 4 haptic pad also needs Force Sensing `0x19C0` threshold `0x15A3`; press events often arrive as analytics, not diverted-buttons.
- Debug builds must stay signed with the Apple Development identity (`DEVELOPMENT_TEAM = XXA24FWXDW`) so Accessibility and Input Monitoring persist across rebuilds. Do not switch back to ad-hoc (`CODE_SIGN_IDENTITY = "-"`).
- Never upload or publish without explicit approval.

## Docs

Start at `docs/README.md`. MX4 feel and architecture: `docs/mx-master-4-pointer-and-haptic.md`. Why Gestures is haptic-only: `docs/haptic-vs-back-gesture.md`. Open work: `docs/todo.md`. One issue type per file. Update those when a new failure mode or fix item shows up.
