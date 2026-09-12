# App switcher preview stays one app behind after arrows

## Symptom

Window cards under Command-Tab only change on Tab. Left/Right after the strip is up leave the preview on the previous app. The next Tab then advances, but it is still one app behind the native highlight.

## Cause

The listen-only tap counted Tab against a local MRU index. Native Command-Tab also moves with Left (previous) and Right (next) while Command stays down. Those keys never stepped the index, so the overlay lagged the Dock strip.

## Fix

Queue Tab and Left/Right. Tab can open the session. Arrows only move after it is already live. Apply every stashed step on the main queue so two keys in one turn do not collapse to the last one.

Do not call Accessibility from the tap callback. Do not swallow the keys.
