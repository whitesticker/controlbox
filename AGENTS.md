# Control Box agent notes

Control Box is a local Mac app that maps unusual input devices (DualSense, Apple TV remote, Logitech MX Master) to pointer, keys, and system gestures.

## Current status (2026-08-22)

- Multi-device is live: DualSense, Apple TV remote, MX Master 3/3S, and MX Master 4 can stay attached at once. Each device has its own **Control this Mac** toggle.
- Device I/O lives in family sessions (`DeviceFamilySession`): `DualSenseSession`, `AppleTVRemoteSession` (generation `AppleTVA2540`), MX 3/3S and MX 4 readers. The host (`DualSenseMonitor`) is records, engines, and the poll loop. Add a family; do not add `captureXbox()` on the host.
- HID modules stay split: **3/3S together** (`MXMaster3Support`) and **4** (`MXMaster4Support`). Each family has its own HID++ reader (product IDs only). Shared code is the HID++ pipe and hold-to-swipe engine.
- 3S HID++ is nested on the mouse device (page `0xFF43`, report `0x11`). Gesture is thumb CID `0x00C3`. See `docs/mx-master-3s-hid.md`.
- MX4 pointer / haptic stack is unchanged. How MX4 should feel is `docs/mx-master-4-pointer-and-haptic.md`.
- Pointer speed and gesture speed are **separate sliders**. DPI is sensor resolution only. Both speeds divide out DPI so 1000 DPI is the reference feel.
- 3S: tap gesture button = click action; hold 100ms then move = swipe. Same ControlEngine path as MX4 haptic (owner `.mxHaptic`).
- DualSense touchpad: **1-finger** and **2-finger** are separate Gestures owners (`touchpadOneFinger` / `touchpadTwoFinger`). Same `HoldGesture` path as MX. Physical click stays `touchpadClick`. Finger count can promote to 2-finger during the 100ms arm window, then locks.
- DualSense L2/R2 mapped to Previous/Next tab use analog travel (mid = one tab, full hold = repeat). L1/R1 stay digital. Other devices unchanged.
- Factory defaults match the live desk: DualSense L1/R1 desktops, L2/R2 tabs, D-pad Mission Control / Desktop / app switch, Square click, 1-finger media, left stick pointer / right stick scroll; Apple TV Back = Return; MX pointer 21%, natural scroll off, Mode shift = Right Option; MX4 haptic 61% and 4000 DPI.
- MX **Window grab**: hold Control and move to drag a window from anywhere; hold Control+Shift and move to resize with the top-left anchored. MX with Control this Mac only.
- **MX Gestures is the 3S gesture button / MX4 haptic pad only.** Click-as-gesture on Back / Forward / etc. is still parked. DualSense finger rows are allowed.
- Do not attach Bolt receiver `C548`. Do not seize HID. Do not open the standard mouse collection just to watch buttons. Do not go back to one matcher for every Logitech interface.

## Device rule

Treat these as **different devices**, not one “MX Master”:

| Device | HID++ collection | Gesture / extra-button notes |
|---|---|---|
| MX Master 3 | Unifying `0x4082`, BLE `0xB023`. Same HID module as 3S. | Gesture CID `0x00C3`. No 3 on this Mac; inferred from Solaar/logiops. |
| MX Master 3S | BLE `0xB034`, Bolt `0xB043`. Nested `0xFF43` / report `0x11`. | Same CIDs as Master 3. Thumb gesture `0x00C3`. |
| MX Master 4 | BLE: vendor report `0x11` on the mouse device (page `0xFF43`), not a separate `0xFF00` collection. Bolt receiver `C548` is not the mouse. | Haptic is HID button 7 (`0x40` on report `0x02`). CID `0x01A0` is HID++ when that pipe exists. |

3S + 4 at once is allowed through **two isolated readers**, not one manager that opens every Logitech collection. Keep 3/3S and 4 as separate HID modules. Shared code should stay at “send a HID++ report” / “list HID devices” / hold-to-swipe.

## Hard constraints

- Never call `IOBluetoothDevice.pairedDevices()`. It has corrupted the heap on this Mac (`libmalloc` / `EXC_BREAKPOINT`).
- Never `IOHIDManagerOpen` with `kIOHIDOptionsTypeSeizeDevice` on Logitech mouse or HID++ managers.
- Do not open the standard Logitech mouse collection (usage page `0x01` usage `0x02`) just to watch buttons. That can steal the system pointer.
- Reprog Controls V4 `setCidReporting` flags are value + valid pairs, not “0x01 divert / 0x02 persist / 0x04 raw XY”. Solaar hold-only gestures use **`0x33`** (divert+valid + rawXY+valid). Persist is `0x04`/`0x08`. Force raw XY is `0x40`/`0x80`. Packet is CID, flags, remap, and optional high flags. Analytics reporting is high-byte `0x03`. Do not send persist or force-raw-XY. Clear with `0x22`, not `0`. The Master 4 haptic pad also needs Force Sensing `0x19C0` threshold `0x15A3`; press events often arrive as analytics, not diverted-buttons.
- Debug builds must stay signed with the Apple Development identity (`DEVELOPMENT_TEAM = XXA24FWXDW`) so Accessibility and Input Monitoring persist across rebuilds. Do not switch back to ad-hoc (`CODE_SIGN_IDENTITY = "-"`).
- Never upload or publish without explicit approval.

## Docs

Start at `docs/README.md`. MX4 feel and architecture: `docs/mx-master-4-pointer-and-haptic.md`. Why Gestures is haptic-only: `docs/haptic-vs-back-gesture.md`. Open work: `docs/todo.md`. One issue type per file. Update those when a new failure mode or fix item shows up.
