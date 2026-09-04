# Dock preview lists inspectors as windows

## Symptom

Hovering Calendar (GitHub issue 16; reproduced on the MacBook) shows extra cards for window chrome — event inspectors, mini month widgets, palettes — not just the real windows. All cards were **Other Space**. 0.1.31 (nested-only prune) did not fix it.

## Cause

Accessibility does not list Calendar windows that live on another Space (`kAXWindowsAttribute` is empty on the desk Mac). Off-screen CG surfaces fill in: the main window (~1100×930), a ~300×300 mini month *inside* it, and an event inspector that often sits *beside* the host rather than inside it. Those inspector frames can still be `AXStandardWindow` when AX can see them, so a nested-only filter kept them.

## What we changed

0.1.32: per display, drop any non-minimized surface smaller than 35% of the largest window of that app. Also drop nested / heavily overlapping chrome, popovers, sheets, and `AXUnknown`. Other-Space cards always show quit (no card hover required). Close / minimize stay on this Space.

## Do not

Use a nested-only filter. Calendar’s inspector is a sibling window. Do not require `AXStandardWindow` exemption — chrome can report that subrole. Do not debug this against Calendar on the desk Mac; the report was the MacBook. Do not drop a real second window that is ≥ 35% of the largest on that display.
