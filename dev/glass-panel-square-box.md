# Square box around glass menu panels

## Symptom

On macOS 26, a borderless glass menu panel shows a faint square outline and a tinted square at each corner, behind the rounded glass. Seen on the old custom Control Center panel and on System Monitor's dropdown / submenus.

## Cause

The panel is the **key window**. macOS 26 draws a rectangular rim over the whole window when a borderless window that contains glass is key: `NSGlassEffectView` and SwiftUI `glassEffect` both do it, a masked `NSVisualEffectView` does not. Not key, the same window is clean. The window shadow is not the cause: turning it off or invalidating it does not help. Reproduce by capturing your own window with `CGWindowListCreateImage` (one-pixel corners have alpha only while key).

Both panels made themselves key so Escape and SwiftUI hover work without activating Control Box.

## Fix

Override the private `NSWindow` hooks `_hasActiveAppearance` (return `false`) and `_hasActiveControls` (return `true`) on the panel class. SwiftUI's own `MenuBarExtraWindow` overrides exactly these (found by listing its methods with `class_copyMethodList`); with them the window stays key (Escape, hover) and the corners are clean. `MenuPanel` does this.

Control Center moved to SwiftUI `MenuBarExtra` (`.menuBarExtraStyle(.window)`), whose window already has it. See [control-center-panel.md](control-center-panel.md).

## Do not

Try to fix it with the window shadow (`hasShadow`, `invalidateShadow`), a container view, `fullSizeContentView`, or SwiftUI `glassEffect` instead of `NSGlassEffectView`: none of them change the key-state rim.
