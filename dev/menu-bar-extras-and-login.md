# Launch at Login, Hide Dock, and extra menu bar icons

## Launch at Login

Permissions has a **Launch at Login** toggle (`SMAppService.mainApp.register` / `unregister`). It is optional; Accessibility and Input Monitoring are still the required grants. If macOS leaves the item on **Allow in the Background**, the pane links to Login Items.

## Hide Dock and Command-Q

**Hide Dock icon** uses `NSApp.setActivationPolicy(.accessory)`. Command-Q is **Close Window**, not Quit. **Quit Control Box** is only on the Control Box menu bar extra. Logout still quits the app. Do not cancel `applicationShouldTerminate` or shutdown will hang.

## Brightness, Sound, and Caffeinate extras

Each pane (and the Control Center pane) has **Show in menu bar**, off until turned on. Each is a SwiftUI `MenuBarExtra` (window style) that opens that module's Control Center **detail view** (see [control-center-panel.md](control-center-panel.md)). Turning it off does not quit. Catalogs live on the app delegate so sliders keep working after the window closes.

Caffeinate’s detail view has the countdown, an on/off switch, duration chips, and **Sleep Now**, which stops the active assertion and calls `IOPMSleepSystem`. The cup icon is hollow when idle and hollow-with-coffee plus steam while keeping the Mac awake.

Brightness writes the built-in panel immediately. External DDC writes are coalesced on a background queue. Listing displays does DDC reads off the main thread so the pane slider does not hitch.

## Do not

Set `LSUIElement` in Info.plist (Dock hide is a runtime toggle). Make the module extras the only place for their controls: Control Center keeps Display, Sound, and Caffeinate whether or not their own icons are on.
