# System Monitor menu lags under load; detail submenus leave gaps

## Symptom

1. The System Monitor menu bar extra feels slow to open and to hover between rows, worst when the Mac is low on RAM or CPU.
2. A metric's detail **submenu** changes size or shows an empty band in the middle. The **Top processes** list goes from five rows to four (or from "…" to five rows) after the submenu is already on screen.

## Cause

1. Every 1 s tick set seven `@Published` properties on `SystemMonitor`. All ~15 `NSHostingView`s (dashboard rows and detail submenus) observe it, so all of them were invalidated every second even while the menu was closed. When the main thread was slow, ticks queued one `DispatchQueue.main.async` each and rendered back to back. `DateRow` built a `DateFormatter` per render. The menu bar image was redrawn every tick even when the text was unchanged.
2. `DetailSubmenu` measures its hosting view once in `menuWillOpen`. NSMenu does not re-measure a custom item view afterwards. `TopProcessList` started as one "…" line and then became 0–5 rows, so the height changed after measurement. The ranked list was trimmed to five *before* resolving names, so a process that exited mid-sample dropped a row. The list also called `ProcessMonitor.icon(for:)` (`NSRunningApplication` + `NSWorkspace.icon(forFile:)`) for every row on every render, and sampled with `Thread.sleep` inside `Task.detached` (blocks a cooperative-pool thread). Repeated hovers could stack samples.

## What we changed

- `SystemMonitor` keeps history on its poll queue and coalesces ticks into one main publish of the newest frame. `objectWillChange` fires only while the menu is open (`setPresenting`, called from `menuWillOpen` / `menuDidClose`). On open it publishes the latest frame before rows are measured. The icon reads `tickSnapshot` (a `CurrentValueSubject`, not `@Published`) and redraws only when the formatted text changes. Sensors and battery slow to 10 s / 30 s while closed and refresh on the next tick after open.
- `TopProcessList` always lays out five fixed-height slots. Loading shows "…" in slot 0; an empty result shows "—". Unused slots stay blank at the bottom of the submenu, never in the middle.
- `ProcessMonitor` resolves names down the ranked list until it has five.
- Fewer than five rows was also real data loss, not only timing. libproc from an unprivileged app cannot read root- or system-user processes (about 205 of 624 pids here: WindowServer, kernel_task, mds_stores, XprotectService). CPU now comes from setuid `/bin/ps -Aceo pid=,pcpu=,rss=,comm=` (~100 ms per spawn) and memory from setuid `top`, which both see every process (see [system-monitor-top-processes.md](system-monitor-top-processes.md)). Disk I/O has no setuid tool, so it stays on libproc and ranks over a rolling 10 s window (a 0.5 s window caught 0–3 processes, 2 s about 8, 10 s about 12). The first Disk refresh after opening still uses a 0.5 s window, so it can show fewer rows for about 2 s.
- `TopProcessFeed` (one per detail submenu) samples on a serial utility queue only while that submenu is open, skips a tick while the last sample is still running, caches icons per pid, and keeps the last list across opens.

## Bottom of the menu clipped (Tahoe status-item menus)

After live re-measure landed, the main menu sometimes cut off **Hide from Menu Bar**. A status-item menu that is already open resizes its window when a custom item view's frame changes, but does **not** move the items below it. Reproduced with plain `NSView` items: grow by 60 pt → window +60, the bottom item stays put (gap at the bottom); shrink by 20 pt → window −20, the bottom item sits 15 pt below the window edge. `itemChanged(_:)` and `update()` do nothing. Toggling the resized item's `isHidden` off and on (or re-inserting it, or reassigning its `view`) re-lays out every item. `MenuHostingView.fit()` toggled `isHidden` after any resize while tracking. Obsolete since the dropdown became panels (below): `fit()` now calls `onResize` and the panel follows the content's frame.

## Sensors row jumps between one and two lines

The Sensors row laid CPU, GPU, and each fan out in one `HStack` with no line limit. When the digits got wider ("996 rpm" → "1005 rpm"), a fan value wrapped onto a second line, the row grew, and the live re-measure resized the whole menu every few seconds. `HighlightStat` is now an equal-width column, one line, scaled down (`minimumScaleFactor`) instead of wrapping.

## Switching rows lags with history columns

Moving from one row to another (GPU → Network) took about half a second once detail submenus had a history column. A 40 s `sample` while switching rows showed each open laying out the history chart three times on the main thread: `MenuHostingView.fit()` from `menuWillOpen` (called from NSMenu's submenu timer), `NSHostingView.viewDidMoveToWindow` when the menu re-parents the view, and `NSMenuItemView layout`. Swift Charts rebuilt every mark on each pass: band style is an `AreaMark` plus a `LineMark` per point, so about 720 marks for Network / Disk and over 2,000 for Sensors. Charts was about 3.6 s of the 8 s of main-thread work in that sample.

`HistoryPanel` now draws with one `Canvas` (a fill and a stroke path per series, grid and axis labels drawn in the same pass) and does hover hit-testing with `HistoryPlotMapper`. Offscreen, a fresh panel with three layout passes went from about 67 ms to 17 ms for Sensors and 30 ms to 17 ms for Network; the 17 ms is the rest of the panel and the window, not the chart.

## NSMenu's own submenu delay (dropdown is now panels)

Even with cheap charts, switching rows still felt slow next to iStat Menus. `Prototypes/MenuLagLab` (a menu bar extra with the same seven rows and only random numbers in each submenu) measured about 200 ms from a row highlighting to its submenu opening with plain `NSMenuItem`s, AppKit custom views, and SwiftUI custom views alike, so the delay is NSMenu's, not our content: it opens a submenu from a timer (the profile above shows `menuWillOpen` under `__CFRunLoopDoTimer`), so a diagonal move toward an open submenu does not switch it. There is no public setting for that delay. iStat Menus does not use NSMenu (`BBRMenuKit`: `BBRMenu` is an `NSObject`, `BBRMenuWindow` an `NSWindow`, `BBRMenuItem` an `NSView` with tracking areas, `BBRGlassView` an `NSGlassEffectView`).

The lab's panel mode (borderless panels, rows with their own tracking areas, one prebuilt panel per submenu) measured about 5 ms. Control Box now does the same (`MenuPanel.swift`): `MenuPanelRow` reports the first mouse-entered / mouse-moved, `StatusItemController` orders the row's `DetailSubmenu` panel in and the previous one out, and nothing is re-parented or rebuilt. A global and a local mouse-down monitor, Escape, and a Space switch close it. There is no menu aim, so crossing another row on the way to a submenu switches to that row.

## Do not

- Go back to `NSMenu` for the dashboard or its submenus. The submenu delay is built in.
- Re-parent a submenu's hosting view on each show. Keep one panel per submenu and order it in and out.
- Draw menu charts with Swift Charts. Every layout pass rebuilds every mark, and a submenu open runs several.
- Let a dashboard row's height depend on how wide a live number is. Use `lineLimit(1)` plus a fixed or equal-width column.

- Put `@Published` state on `SystemMonitor` that changes every tick. Use `tickSnapshot` or publish inside `publish(_:)`.
- Let a detail submenu's content change height without `onResize` reaching its panel. Reserve space where you can.
- Sample processes from a SwiftUI `.task`. Panel order-in / order-out does not reliably cancel it.
- Go back to libproc for CPU / memory ranking. It silently drops root processes.
- `waitUntilExit()` before reading a child's stdout. Output past the 64 KiB pipe buffer deadlocks.
