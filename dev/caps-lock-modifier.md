# Caps Lock toggles caps instead of acting as a modifier

## Symptom

Control Box chords only know ⌃ ⌥ ⇧ ⌘. Caps Lock still flips the caps lock state, so it cannot stand in for those keys on Window Management or Display Arrangement.

## What we changed

A **Caps Lock** Mac pane, off until the toggle is on. A modifier selector on that pane chooses which keys Caps Lock acts as (default Control). While it is on, a `defaultTap` swallows keycode 57 so Caps Lock does not toggle. Physical hold comes from keyboard HID usage `0x39` (listen-only, no seize), with the Caps Lock `CGEvent` path as fallback.

`ModifierChords.live()` strips lock-state Caps Lock from the current event, then ORs in the mapped modifiers while `CapsLockModifier.isHeld`. Saved chords still use `normalized()`. Window Management, Display Arrangement, Organize, and Dock-click “no modifiers” all compare against `live()`.

This is Control Box–only — other apps do not see Caps Lock or a Hyper key. If system Caps Lock is already on when the pane turns on, one pass-through tap turns it off so typing is not stuck in caps. The catalog lives on the app delegate so the tap survives window close.

## Do not

Call Accessibility from the Caps Lock tap callback. Do not remap Caps Lock to ⌃⌥⇧⌘ for the whole Mac. Do not treat lock-state `maskAlphaShift` as held. Do not seize the keyboard HID manager. Do not add an idle poll for hold state.
