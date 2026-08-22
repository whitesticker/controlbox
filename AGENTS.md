# VibeRemote agent notes

VibeRemote is a local Mac app that maps unusual input devices (DualSense, Apple TV remote, Logitech MX Master) to pointer, keys, and system gestures.

## Current status (2026-08-22)

- Active test device: **MX Master 4 only**. Leave MX Master 3 / 3S disconnected until MX4 is stable.
- The app still treats every MX Master as one `logitechMXMaster` kind and one `LogitechMXMasterReader`. That is a known design problem, not the next code change until the user says to proceed.
- Pointer and wheel can work through normal HID + a listen-only event tap. Extra buttons and haptic hold-to-swipe go through Logitech **HID++**. Getting one working has repeatedly broken the other.
- Do **not** change HID++ / MX reader code until the user says they have this status and want implementation.

## Device rule

Treat these as **different devices**, not one “MX Master”:

| Device | HID++ collection | Gesture / extra-button notes |
|---|---|---|
| MX Master 3 | confirm before coding | Do not assume Master 4 CIDs |
| MX Master 3S | often usage page `0xFF43` | Thumb / gesture CID often `0x00C3` |
| MX Master 4 | usage page `0xFF00` | Haptic / gesture CID `0x01A0` |

Focus on **MX Master 4 first**. Do not reopen 3S attach, dual-mouse attach, or “open every Logitech interface” while MX4 is the target.

Separate reader code per model will help: matching, divert flags, and button CIDs differ. Shared code should stay at “send a HID++ report” / “list HID devices”, not “one reader for all MX mice.”

## Hard constraints

- Never call `IOBluetoothDevice.pairedDevices()`. It has corrupted the heap on this Mac (`libmalloc` / `EXC_BREAKPOINT`).
- Never `IOHIDManagerOpen` with `kIOHIDOptionsTypeSeizeDevice` on Logitech mouse or HID++ managers.
- Do not open the standard Logitech mouse collection (usage page `0x01` usage `0x02`) just to watch buttons. That can steal the system pointer.
- Do not send HID++ divert flags that include persist or force-raw-XY (`0x02`, `0x08`, `0x10` in the usual Solaar layout, or the old `0x33` arm). Those have left the Master 4 pointer dead until a power cycle.
- Debug builds must stay signed with the Apple Development identity (`DEVELOPMENT_TEAM = XXA24FWXDW`) so Accessibility and Input Monitoring persist across rebuilds. Do not switch back to ad-hoc (`CODE_SIGN_IDENTITY = "-"`).
- Never upload or publish without explicit approval.

## Docs

Problem write-ups live in `docs/` (one issue type per file). Open work is `docs/todo.md`. Update those when a new failure mode or fix item shows up.
