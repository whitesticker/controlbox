# Mac panes gated on MX Master

## Symptom

**Window Grab** and **Pointer & Scroll** show a placeholder until an MX Master is added. Window grab also does not run without a controlling MX.

## Cause

The panes and `applyWindowGrab` / `applyMouseScrollTap` required `hasMXMaster` / `sharedMXScrollRecord` (an MX with Control this Mac). Settings lived only on MX profiles, so there was nothing to persist without a mouse.

## What we changed

Mac-level `MacMouseSettings` (UserDefaults). Both panes stay enabled. Window grab and the scroll tap run whenever Accessibility is on. Pointer speed also applies to USB/Bluetooth mice via HID, not only MX HID++.

## Do not

Hide those Mac panes again when no MX is attached. Window grab is not an MX-only injection path.
