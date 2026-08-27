# MacBook per-app volume is 100% or nothing

## Symptom

On a MacBook’s built-in speakers, an app slider is full volume or silent. Intermediate values do nothing. External DACs often work.

## Cause

The mixer wrapped the speakers in a non-stacked aggregate, silenced that aggregate’s output, and played back through DefaultOutput. Built-in speakers often become exclusive to the aggregate, so silencing it mutes the hardware. At 100% the tap is not created (`needsTap` is false), so native audio plays.

## What we changed

Tap-only private aggregate (no speaker subdevice). Capture the tap, play through HALOutput aimed at the real output device, Float32 at the tap sample rate, and apply gain in the render callback.

## Do not

Put the built-in speakers in the aggregate just to clock the tap, or silence that device’s output while also using it for playback.
