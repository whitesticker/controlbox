# Clicks stop working from every device

Seen 2026-10-05. Not a Control Box bug.

## Symptom

Clicks from every mouse and the trackpad stopped working (drags or nothing), not only on devices Control Box manages. Rebooting fixed it.

## Cause

A Magic Mouse was resting on a box with its button pressed. WindowServer keeps the global button state down while any sender holds a button, so every other device's clicks look like part of a held drag.

## Check first

Before debugging Control Box injection, look for any pointing device that could be physically held down (Magic Mouse, a second mouse, a pad trigger mapped to click) and lift or switch it off. Quitting Control Box clears its own synthetic buttons; if clicks are still dead after quit, it is another sender.
