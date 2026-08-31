# App switcher has no window cards

## Symptom

Command-Tab (and Next / Previous application) only shows app icons. There is no way to pick a specific window, including minimized ones or windows on another Space.

## What we changed

A toggle on the **Dock Previews** pane, off until it is on. While the application switcher is up, the highlighted app’s windows use the same list and stills as Dock hover.

Cards are thumbnails only: no title under the still, no close / minimize / quit HUD. Click a card to focus that window and dismiss the switcher. Apps with no windows show nothing extra.

The listen-only tap watches Command, Tab, Shift, and Escape. Accessibility and ScreenCaptureKit run on the main queue after the key is stashed. No idle pointer poll. Placement is always on the main display, vertically centered between the native switcher strip and the top of the display. Preview size is its own slider, up to 300%.

## Do not

Call Accessibility from the `CGEvent` tap callback. Do not add the Dock-card title line or HUD to this overlay. Do not swallow Command-Tab.
