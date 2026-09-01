# Relaunch forces Dark while Night Shift take-over is on

## Symptom

Quit and reopen Control Box. Appearance jumps Light → Dark. Dark stays Dark. There is no Appearance pane in the app.

## Cause

Night Shift take-over turns off Auto appearance so sunset scheduling cannot flip Light/Dark. The pin used `SLSGetAppearanceThemeLegacy` / `AppleInterfaceStyle`, which stay **Dark** while Auto is showing Light. The first capture was persisted and reused on every launch, so `pin` wrote Dark (and turning Auto off revealed that stored theme).

## What we changed

Read **effective** appearance (`NSApp.effectiveAppearance`). Optional **Schedule Light and Dark** (default on, sunset → sunrise) flips the theme on the Night Shift 20 s tick. Custom hours wrap midnight. Off freezes the look on screen. Keep the original Auto flag and restore it when the pane goes off. After disabling Auto, always write the scheduled or frozen Light/Dark so the leftover Dark style cannot win. Do not add a new timer. Do not ask for Core Location.

## Do not

Use `SLSGetAppearanceThemeLegacy` or `AppleInterfaceStyle` as “what the Mac looks like” while Auto is on. Do not persist a Dark pin across launches and apply it on the next start. Do not leave Apple Auto on during the 00:00–23:59 warmth take-over.
