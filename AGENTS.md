# VibeRemote agent notes

VibeRemote is a local Mac app that maps unusual input devices (DualSense, Apple TV remote, Logitech MX Master) to pointer, keys, and system gestures.

## Current status (2026-08-22)

- Active test device: **MX Master 4 only**. Leave MX Master 3 / 3S disconnected until MX4 is stable.
- Device kinds are split (`logitechMXMaster3`, `logitechMXMaster3S`, `logitechMXMaster4`). Only MX Master 4 opens HID++. 3 and 3S are classified only.
- Pointer, wheel, extra buttons, and haptic hold-to-swipe work on BLE MX4. How that stack is supposed to feel is `docs/mx-master-4-pointer-and-haptic.md`.
- Pointer speed and haptic gesture speed are **separate sliders**. DPI is sensor resolution only (smoother tracking). Both speeds divide out DPI so 1000 DPI is the reference feel.
- Haptic: tap = click action; hold 100ms then move = swipe. Left/right and up are live DockSwipe. Down (App Exposé) is a discrete system action.
- **Gestures is haptic-pad only.** Click-as-gesture on Back / Forward / etc. is parked (laser XY is not the pad; direction and follow never settled). Do not HID++-divert left/right/middle to invent a second pad.
- Do **not** change HID++ / MX reader code until the user says they have this status and want implementation.

## Device rule

Treat these as **different devices**, not one “MX Master”:

| Device | HID++ collection | Gesture / extra-button notes |
|---|---|---|
| MX Master 3 | confirm before coding | Do not assume Master 4 CIDs |
| MX Master 3S | often usage page `0xFF43` | Thumb / gesture CID often `0x00C3` |
| MX Master 4 | BLE: vendor report `0x11` on the mouse device (page `0xFF43`), not a separate `0xFF00` collection. Bolt receiver `C548` is not the mouse. | Haptic is HID button 7 (`0x40` on report `0x02`). CID `0x01A0` is HID++ when that pipe exists. |

Focus on **MX Master 4 first**. Do not reopen 3S attach, dual-mouse attach, or “open every Logitech interface” while MX4 is the target.

Separate reader code per model will help: matching, divert flags, and button CIDs differ. Shared code should stay at “send a HID++ report” / “list HID devices”, not “one reader for all MX mice.”

## Hard constraints

- Never call `IOBluetoothDevice.pairedDevices()`. It has corrupted the heap on this Mac (`libmalloc` / `EXC_BREAKPOINT`).
- Never `IOHIDManagerOpen` with `kIOHIDOptionsTypeSeizeDevice` on Logitech mouse or HID++ managers.
- Do not open the standard Logitech mouse collection (usage page `0x01` usage `0x02`) just to watch buttons. That can steal the system pointer.
- Reprog Controls V4 `setCidReporting` flags are value + valid pairs, not “0x01 divert / 0x02 persist / 0x04 raw XY”. Solaar hold-only gestures use **`0x33`** (divert+valid + rawXY+valid). Persist is `0x04`/`0x08`. Force raw XY is `0x40`/`0x80`. Packet is CID, flags, remap, and optional high flags. Analytics reporting is high-byte `0x03`. Do not send persist or force-raw-XY. Clear with `0x22`, not `0`. The Master 4 haptic pad also needs Force Sensing `0x19C0` threshold `0x15A3`; press events often arrive as analytics, not diverted-buttons.
- Debug builds must stay signed with the Apple Development identity (`DEVELOPMENT_TEAM = XXA24FWXDW`) so Accessibility and Input Monitoring persist across rebuilds. Do not switch back to ad-hoc (`CODE_SIGN_IDENTITY = "-"`).
- Never upload or publish without explicit approval.

## Docs

Problem write-ups live in `docs/` (one issue type per file). Open work is `docs/todo.md`. Update those when a new failure mode or fix item shows up.
