# Wallpaper goes black when switching Spaces on a MacBook

Investigated 2026-09-07. Open. Seen on a MacBook, not on this desktop Mac.

## Symptom

Switching desktop Spaces on a MacBook blacks out the wallpaper for a moment. Windows stay. The development Mac (externals, same app) does not show it.

## What we know

Control Box has no Space-change observer. This is not a DockSwipe or Mission Control handler.

**Quit does not stop it.** Command-Q only closes the window; confirm with Activity Monitor that Control Box is gone, and that Launch at Login did not respawn it. After a real quit the flash was still there. So it is not a live overlay, a live CoreBrightness status handler, or a live brightness write.

Quit also does **not** restore Night Shift. `NightShiftCatalog.invalidate()` clears the timer and status handler only. `endControl(restore: true)` runs when **Adjust Night Shift from this curve** is turned off, not on terminate. After quit the Mac can still be on our 24-hour custom schedule with Auto appearance pinned off.

## Remaining hypotheses

1. **Leftover Night Shift / appearance pin.** The hijack survives Quit. On a MacBook built-in, that can leave WindowServer’s desktop-picture layer in a bad state across Space animations. Turning the pane off (which restores) is a different test than quitting.
2. **WindowServer wallpaper compositor on the laptop panel.** Dynamic / HDR / Shuffle wallpaper on Tahoe built-in displays commonly drop to black for a frame on Space switch, with or without Control Box. This desk’s externals use a different path.
3. **Glass overlays or ScreenCaptureKit** (Dock Previews, action HUD) were first-pass suspects. They cannot explain a flash that continues after the process is gone, unless they only *primed* a compositor glitch that then persists until log out.

Unified brightness (`DisplayServicesSetBrightness` on the built-in) only applies with two adjustable displays and while the process is running. Same for a live Night Shift status ping.

## How to isolate

Same swipe every time: three-finger trackpad, watch empty desktop.

1. Activity Monitor: Control Box not running. Launch at Login off.
2. Turn **Adjust Night Shift from this curve** **off**, then Quit. Swipe.
3. System Settings → Appearance back to Auto (or the look you want). Displays → Night Shift off or Sunset to Sunrise. Swipe.
4. Log out / reboot with Control Box still quit. Swipe.
5. If it is still there: try a static wallpaper vs Dynamic / Shuffle.

| Result | Meaning |
|---|---|
| Pane off (restore) fixes it; Quit alone does not | Leftover Night Shift / appearance pin |
| Log out / reboot fixes it, then it returns after Control Box launch | We trigger a WindowServer glitch that survives Quit |
| Still black after reboot with Control Box not launched | Not us. MacBook wallpaper compositor |

## Do not

Add an `activeSpaceDidChange` handler to “fix” wallpaper. Do not treat this as DockSwipe flicker ([dockswipe-progress-snapback.md](dockswipe-progress-snapback.md)). Do not assume Quit restores Night Shift or appearance; only the pane toggle does today.
