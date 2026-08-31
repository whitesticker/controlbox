# Only the haptic pad runs gestures

## Current rule

**Gestures is haptic-pad only.** Profiles do not offer Gestures on Back, Forward, Smart Shift, Mode / DPI, middle, left, or right. Those stay ordinary click bindings.

Click-as-gesture is parked. Hardware and failed attempts: [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md).

## Why other buttons cannot share the pad path

The profile can store a `GestureSet` per button, but only the haptic pad has press + XY on the same report (`0x02` bit `0x40` + 12-bit X/Y). Extra buttons are clicks. Hold-Back-and-move uses the desk laser, which is a different sensor.

Diverting left/right/middle over HID++ (`0x0050` / `0x0051` / `0x0052`) can steal the system pointer.

## How the app enforces haptic-only

| Layer | What it does |
|---|---|
| Profiles UI | Gestures appears only on the Haptic picker. Footer: haptic is the only Gestures button. |
| `MappingProfile.setBinding` | Non-haptic `.gestures` is coerced to browser Back / Forward or `.none`. |
| `setGestureSet` / `gestureSet(for:)` | No-op / nil unless the button is `.mxHaptic`. |
| `mxGestureOwners` | `{.mxHaptic}` or empty. Never Back, etc. |
| Load | `restrictGesturesToHapticPad()` on every saved MX profile. |
| Reader | `setGestureOwners` intersects with `{.mxHaptic}`. |
| Engine | `processGesture` runs `HoldGesture` only when `gestureOwner == .mxHaptic` and that binding is Gestures. |

Default MX bindings: haptic = Gestures (window navigation), Back = browser back, Forward = browser forward.

## Earlier bug (UI-only Gestures)

Before the park, Profiles said “Assign Gestures to any button.” Setting Back to Gestures did not start a hold-to-swipe session. Only the haptic pad ran.

Causes that still matter if anyone reopens this:

- The reader started sessions from the haptic pad only.
- A Back CID in `gestureCIDs` still called `applyHapticEdge`, which labeled the owner as haptic and then ended when the pad bit was up.
- After HID++ attach, Back/Forward CGEvents were ignored (`!ready`), so a missed HID++ edge never started a session.
- Form pickers for Preset / Click / directions reused the same identity, so editing Back also rewrote Haptic. Haptic pickers now use `.id` per button/slot; keep that if Gestures stays on haptic only.

## Do not

HID++-divert the standard click CIDs to make left/right/middle into gesture buttons. Do not put Gestures back on those pickers until laser follow is actually solved.
