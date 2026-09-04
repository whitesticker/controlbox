# Live Space swipe pops back, or only moves one desktop

## Symptom

Hold-to-swipe on the MX gesture button / haptic pad (or DualSense 1-finger / 2-finger) follows two desktops, then on release either rubber-bands to the start or keeps only one Space.

## Cause

Live DockSwipe posts absolute progress. `1.0` is one desktop centered. On `.ended`, macOS commits **at most one** Space and rubber-bands the rest — even when field `124` is `2.0`. Snapping release to the nearest integer therefore still lands one desktop over.

A last-sample reverse (slowing down, lift noise) also turned `.ended` into `.cancelled`, which always returns to the start. Default exit speed was `lastDelta * 100`, which could fling past the page you were on.

## What we changed

Live horizontal follow (`locksFullPages`) ends the current session at `±1` as soon as a full page is centered, then starts a new 0…1 session for the rest of the hold. Release still rounds the leftover page (halfway commits). Vertical Mission Control stays one page.

Do not cancel because the last tick reversed. Live release uses a modest directional speed, not `lastDelta * 100`.

`DockSwipe.play(±1.5)` still ends as posted (discrete Apple TV / MX buttons). DualSense `playOneSpace` already lands at `±1.0`.

## Do not

Expect one DockSwipe session to commit two Spaces. Do not go back to `abs(origin) >= 0.28` as the live commit, or to reversing `.ended` when `lastDelta` disagrees with the offset sign.
