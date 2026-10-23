# System Monitor menu bar icon is user-chosen

## What it is

The System Monitor status item used to show only ↑/↓ network speed. The pane's **Menu Bar Icon** section now picks what it shows. It has two rows: **In menu bar** (ordered, drawn like the menu bar) and **Available**. Drag a tile between the rows, or within the top row to reorder. The tiles' right-click menus do the same without dragging. Default is Network only, so existing installs look the same.

Items (`MenuBarItem`): Network (↑/↓), Disk activity (R/W), CPU %, CPU temp, GPU %, GPU temp, Memory pressure, Disk used (boot volume, captioned SSD if internal), Power (SMC `PSTR`, else battery watts), Battery %, Fan (first fan's rpm). Single items are a small caption over a value (iStat Menus style); the two rate items are two marked lines. Every number uses one font (9 pt semibold); labels (captions and the ↑/↓, R/W marks) are 10 pt, one size above the numbers. A faint 1 pt divider separates items. Stored as raw values in `com.local.top.menuBarItems`.

## How it draws

`MenuBarIconRenderer` draws every chosen item into one template `NSImage`, so the menu bar's light/dark appearance still applies. `StatusItemController` combines `SystemMonitor.tickSnapshot` with `PreferencesStore.$menuBarItems` and redraws only when the formatted text changes. The pane's tiles use the same renderer, with live values while the extra is on and example values while it is off.

Temperatures, fan, and power come from the snapshot's sensor sample, which refreshes every 10 s while the menu is closed (3 s open). Battery is every 30 s closed. No new loop.

## Do not

- Size an item from its current text. Each item is drawn at the width of its widest value (`widestText`), because `NSStatusItem` shifts its neighbours whenever its width changes. See [system-monitor-arrow-jitter.md](system-monitor-arrow-jitter.md).
- Split the items into several status items. One image keeps one click target and one dropdown.
