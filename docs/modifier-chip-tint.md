# Modifier chips do not light up on older macOS

## Symptom

In Window Grab and Display Arrangement, the ⌃⇧⌥⌘ chips do not show a selected state on macOS 14/15. Clicking still toggles the chord.

## Cause

`.buttonStyle(.bordered)` plus `.tint(accent)` does not fill the button on those releases the way it does later.

## What we changed

Chips use a plain button with an accent fill and white label when on, gray fill when off.

## Do not

Depend on bordered-button tint for selected state.
