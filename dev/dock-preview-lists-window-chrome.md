# Dock preview lists inspectors as windows

## Symptom

Hovering a Dock icon (Calendar on another Space in the report) shows extra cards for window chrome — event inspectors, mini month widgets, palettes — not just the real windows.

## Cause

Accessibility lists `AXDialog` / `AXFloatingWindow` (and untitled window roles) next to `AXStandardWindow`. Other-Space frames also come from off-screen CG windows. Those helper surfaces sit inside or overlap the real window, but the list treated each as its own card. Nested CG extras were only compared to AX frames, so when AX missed the host, every layer-0 surface became a card.

## What we changed

After listing AX windows, drop nested non-standard surfaces (inspectors, palettes, mini widgets). Off-screen CG extras are largest-first and skipped when they sit inside an already-kept frame. `AXStandardWindow` stays even if another Space’s window of the same app shares display coordinates. Transparent CG windows are ignored.

## Do not

Drop a real `AXStandardWindow` only because its frame is inside another window of the same app — other Spaces reuse the same display rect.
