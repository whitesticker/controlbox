# App switcher has no window cards

## Symptom

Command-Tab (and Next / Previous application) only shows app icons. There is no way to pick a specific window, including minimized ones or windows on another Space.

## What we changed

A toggle on the **Dock Previews** pane, off until it is on. While the application switcher is up, the highlighted app’s windows use the same list and stills as Dock hover.

Cards are thumbnails only: no title under the still, no close / minimize / quit HUD. Click a card to focus that window and dismiss the switcher. Apps with no windows show nothing extra. Card click is the plain `DockPreview.focus`; Dock Previews → Card click (Switch to Space / When already in front) does not apply here.

## App switcher select

Dock Previews → **App switcher select** → **Switch to Space** (off by default). The controller remembers the app highlighted by the last Tab / arrow step. When Command is released on an open strip (not Escape), `AppSwitcherSelect.perform(app)` runs 50 ms later so Apple’s own activation lands first: if that app has a window visible on any current Space, nothing; otherwise the most recent non-minimized window (fullscreen preferred) goes to `WindowSpaces.reveal`, which slides that window’s display — this one or another — and no-ops if Apple already moved it. No windows listed → reveal by pid. All minimized → native restore only. The tap is shared with the previews, so it stays up when either toggle is on; `publish` only fires cards when previews are on. Earlier this was tied to clicking a switcher card and deferred to Command-up — nobody clicks those cards, so that path was dropped.

**Which app was picked.** Our MRU list is only a guess at the Dock's strip order (the Dock's order is its own activation history; ours is seeded from launch order plus `didActivateApplication`), so `apps[index]` can name the wrong app — with previews off nobody sees it, and the Space switch then does nothing. The Dock exposes the strip over Accessibility: `AXApplication(Dock)` → `AXList` with subrole `AXProcessSwitcherList` → `AXButton` per app, `AXFocused` on the highlighted one, title = app name. `dockHighlightedApp()` reads that (a) synchronously in the tap callback on the Command-up `flagsChanged`, while the strip is still up, and (b) 70 ms after each Tab / arrow step to correct the cards if the guess was wrong. The Dock's answer wins over the MRU guess. A quick Command-Tab can land Tab and the release in one flush; those steps are now stepped (without publishing) before the session ends so a pick exists. Verified with a synthetic Command-Tab to App Store fullscreen on a non-current Space of another display: that display slid to it.

Fullscreen apps did not switch at first. Picking a fullscreen app in Command-Tab makes macOS slide to its fullscreen Space on its own; our swipe landed mid-animation (~130 ms in, before the current-Space read had flipped) and cancelled or overshot it. `WindowSpaces.switchTo` now checks `SLSManagedDisplayIsAnimating` before every swipe and waits for the slide to finish, then re-snapshots — usually the Space is current by then and it no-ops. `AppSwitcherSelect` also asks `WindowSpaces.fullscreenSpaceIsCurrent` instead of trusting CG on-screen for fullscreen windows.

The listen-only tap watches Command, Tab, Left, Right, Shift, and Escape. Left/Right only move the preview after the strip is already up. Accessibility and ScreenCaptureKit run on the main queue after the key is stashed. No idle pointer poll. Placement is always on the main display, vertically centered between the native switcher strip and the top of the display. Preview size is its own slider, up to 300%. See [app-switcher-preview-arrow-keys.md](app-switcher-preview-arrow-keys.md).

## Do not

Call Accessibility from the `CGEvent` tap callback. Do not add the Dock-card title line or HUD to this overlay. Do not swallow Command-Tab.
