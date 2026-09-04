# Dock preview lists inspectors as windows

## Symptom

Hovering Calendar (and similar apps) on another Space shows extra cards for window chrome — event inspectors, mini month widgets, palettes — not just the real windows.

## Cause

Accessibility does not list Calendar windows that live on another Space (`kAXWindowsAttribute` is empty). Off-screen CG surfaces fill in: the main window, a ~300×300 mini month inside it, and an event inspector that often sits *beside* the host rather than inside it. Those inspector frames are still `AXStandardWindow` when AX can see them, so a nested-only filter kept them. 0.1.31 nested-only prune was not enough.

## What we changed

Per display, drop any non-minimized surface smaller than 35% of the largest window of that app. Also drop nested / heavily overlapping chrome, popovers, sheets, and `AXUnknown`. Other-Space cards show quit without waiting for a card hover.

## Do not

Use a nested-only filter. Calendar’s inspector is a sibling window. Do not require `AXStandardWindow` exemption — chrome can report that subrole.
