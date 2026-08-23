# Media gesture left/right does not skip tracks

## Symptom

Haptic preset **Media controls**: tap play/pause and up/down volume work. Hold + move **left / right** does not go to previous / next track.

## Cause

After live DockSwipe landed, horizontal motion only called `applySpace`. That returns immediately unless left/right are Spaces. Media prev/next are discrete key presses, not a live desktop swipe.

On release, `processGesture` only fires the **click** slot (play/pause). A left/right classification never became a media skip.

App navigation next/previous app had the same hole.

## What we changed

Once `HoldGesture`’s 100ms arm delay has passed and the axis is horizontal, a clear move (`x <= -40` or `x >= 40`) fires `set.left` / `set.right` once per hold when those actions are discrete (media skip, app switch, browser back/forward). Spaces still use live DockSwipe.

## Do not

Route media skip through DockSwipe. Do not fire prev/next on release of a tap.
