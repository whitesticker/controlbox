# System Monitor history submenu covers the main menu

## Symptom

History was a third-level submenu, opened by hovering the graph at the top of a detail submenu. With the System Monitor extra near the right edge of the screen, the detail submenu opened to the left of the main menu, and history then opened back to the right, on top of the main menu. Pressing ⌘⇧ (to take a screenshot) closed history while the main menu and detail submenu stayed open.

## Cause

`NSMenu` opens a submenu to the right of its parent whenever it fits on screen, and to the left only when it does not. It does not avoid its own ancestors, so the third level landed on the first. A modifier press makes the menu re-hit-test the pointer; the pointer was over history, which was over a main-menu row, so the main menu took the highlight and closed history.

Checked with a test menu at the right edge: setting `userInterfaceLayoutDirection = .rightToLeft` on the detail and history menus (in `willHighlight`, in `menuWillOpen`, or before `popUp`) does not change the side. Width is the only input.

## Fix

First, no third level: one NSMenu submenu held the stats plus a history column (`DetailWithHistory`). That fixed the overlap, but either column could be the taller one (CPU's stats, GPU's history), leaving an empty block under the shorter.

Now the dropdown and its submenus are panels, not NSMenu (see [system-monitor-menu-lag-and-gaps.md](system-monitor-menu-lag-and-gaps.md)), so placement is ours. `DetailSubmenu` owns two panels: the stats panel next to the dropdown and the history panel (`HistoryColumn`) beyond it on the outer side, tops aligned, each sized to its own content. History opens when the pointer enters the stats panel (`MenuPanel.onPointerEnter`), stays while the pointer moves into it, and closes when the pointer is back on a dropdown row; its feeds run only while it is shown. `show` picks the side away from the screen edge the dropdown is near, using the combined width, and falls back to the other side when both do not fit. A left-opening panel that re-measures keeps its right edge, so it never grows over the dropdown.

## Layout

- Sensors has one history panel that charts the stats-panel section under the pointer (`HistoryFocus`): **Power** (SMC `PSTR` system total, watts, y axis from 0), **Fans**, or one temperature group (that group's hottest sensor, the same figure as the group header's "max"). The charted section keeps a faint highlight. Moving off a section (dividers, padding, the history panel) keeps the last pick. There is no all-groups chart any more; the pane preview's picker lists the same sections under **Sensors** (only ones with recorded data). A single group is one series, so candles apply. Candles and bars fall back to lines past two series, where bins on the same date pile on each other.
- In/out pairs are blue for in (download, read) and red for out (upload, write), in the history chart and on the dashboard rows (`DashColors`).
- Styles are Candles (default), Bars, and Line. Candles and bars bin by the per-range bar length. A candle's wick is the bin's low to high and its body the first to last sample (`HistoryPoint.open` / `close`); rising bins are hollow, falling bins filled. Metrics with more than two series (sensor groups) draw lines instead, because candles on the same bins pile on each other.
- `HistoryStore` keeps min/avg/max at 1 s for 5 min, 20 s for 1 h, and 5 min for 24 h, in memory only, fed from the System Monitor tick. Temperatures are the hottest sensor per `SensorGroup`, recorded only on ticks that read the SMC.
- User options are System Monitor → History. Layout values are `HistoryDesign`, edited in the hidden Design lab (Option-click the History preview). `Prototypes/HistoryLab` is the standalone prototype it came from.

## Do not

- Do not move history back to a cascading third-level submenu.
- Do not rely on `NSMenu.userInterfaceLayoutDirection` to pick a submenu's side.
- Do not open history in a timer-driven custom window: clicks in a window outside the menu end menu tracking.

## Sensors: one row per category

The Sensors stats panel used to list every sensor (a 7-column tile grid per temperature group, 420 pt wide), and hovering a section charted it. It is now one row per category with one value: Power (system watts), Fans (fastest), and each temperature group (hottest sensor, heat-colored, with the sensor count). The history panel opens only when a row is hovered, not when the pointer enters the panel (`DetailSubmenu(focus:)` wires `HistoryFocus.onHover` to `showHistory`). It charts that category and lists every sensor of it under the chart in a 3-column grid (`SensorsHistoryDetail`, the `HistoryColumn` footer). The charted row stays highlighted while the history panel is open (`HistoryFocus.isActive`).
