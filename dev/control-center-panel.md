# Control Center panel (the Control Box menu bar extra)

## Problem

The Control Box ring extra was a two-item SwiftUI `MenuBarExtra` (Open Control Box, Quit). Brightness, Sound, and Caffeinate each had their own optional extra, built three different ways (`NSMenu` with hosted slider rows, and a plain duration `NSMenu`), and Night Shift or a saved display arrangement had no menu bar control at all.

## What shipped

The ring opens a macOS Control Center–style panel (`ControlBox/ControlCenter/`):

- **Grid.** Four columns, dense first-fit in the user's order (`ControlCenterGrid`). Caffeinate and Arrangement are 2×1, Night Shift and Sleep Now are 1×1 icon buttons (name in the tooltip), Display and Sound are full-width system sliders. A later small control backfills the gap a large one left.
- **Detail views.** Clicking a 2×1 or slider control anywhere except the slider crossfades the panel into that control's detail view (Caffeinate durations, per-display sliders, output + per-app volume, saved arrangements for the connected displays). Caffeinate's body click starts / stops with the last-used duration instead; its detail opens from the hover chevron. Back chevron returns.
- **Display slider** moves every adjustable panel, keeping each one's share of the brightest (mix captured at drag start, `ControlCenterBrightness`), or drives the linked slider when One slider for all displays is on.
- **Footer.** Edit Controls… (opens the Control Center pane), Open Control Box, Quit.
- **Module extras.** Display / Sound / Caffeinate keep their Show in Menu Bar toggles (same `AppSettings` keys, nothing migrates, bound to `MenuBarExtra(isInserted:)`). Each icon opens that module's detail view. No right-click menu; turn an extra off from its pane.
- **Editing.** The Control Center pane (App section) shows the live panel in edit mode: drag a control to reorder (others reflow live), drag it out or hover → − to hide, drag a row from Available to add. Order is `controlbox.controlCenter.order`.

Content look and sizes were tuned in `Prototypes/ControlCenterLab` (run `run.sh`) and copied as constants into `ControlCenterDesign`: fill surfaces, per-feature tint for active buttons, 320 pt width, 66 pt rows, crossfade, icon footer. Retune in the lab first, then copy the values. The window chrome (corners, glass, shadow) is the system's.

## System MenuBarExtra window, not a custom panel

Every extra is a SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`: the system owns the glass window, closing on outside click / Space switch, and its size follows the content (it snaps rather than animates on a detail swap). A custom borderless glass `NSPanel` was tried first and dropped: as the key window it drew a square box around the rounded glass ([glass-panel-square-box.md](glass-panel-square-box.md)).

Content `onAppear` / `onDisappear` fire on every open / close: catalogs refresh on appear, Sound re-reads every 1.5 s in a `.task` while open, and the panel resets to the grid on disappear.

Opening the window activates Control Box (`NSApp.isActive`) until it closes. `DualSenseMonitor.hostIsFocused` ignores activation whose key window is at `.popUpMenu` level or above, so **Allow while Control Box is focused** off does not stop devices while Control Center is open.

## openWindow

`WindowActions.openMain` is set when the main window first appears, and `WindowActions.showMain()` falls back to performing the Window menu's ⌘0 **Control Box** command (a SwiftUI `Commands` button with its own `openWindow`). Use `showMain()`, not `openMain?(…)` directly, for new callers.
