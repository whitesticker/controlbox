# MacBook per-app volume is 100% or nothing

## Symptom

On a MacBook’s built-in speakers, an app slider is full volume or silent. Intermediate values do nothing. Permissions are already granted. External DACs often worked with earlier mixer paths.

## Cause

`mutedWhenTapped` only helps if the tap is actually read and the gained samples are played back on the same device.

A non-stacked aggregate that includes the speakers can take those speakers over. Silencing that aggregate’s output then mutes the hardware. Playing the tap through DefaultOutput / HALOutput cannot reach the seized device, so anything below 100% is silence (`needsTap` is false at 100%, so native audio still plays).

A later tap-only aggregate avoided the seizure, but it has no speaker clock. The IOProc sees empty buffers, mute still engages, and HALOutput plays the empty pipe. Same binary result.

## What we changed

Tap-only private aggregate (clock from the output UID, no speaker subdevice). Capture the tap on the HAL thread, play through HALOutput aimed at the real output at that device’s sample rate, apply gain there. A stacked aggregate is only a fallback, and then output streams are disabled so the IOProc never drives the speakers.

Writing gained samples onto a stacked speaker IOProc stopped the “100% or silence” symptom but froze Sequoia MacBooks (see [macbook-app-volume-system-lag.md](macbook-app-volume-system-lag.md)).

## Do not

Put the built-in speakers in a **non-stacked** aggregate and silence that output. Do not write speaker buffers from a GCD IOProc. Do not pump `CFRunLoopRunInMode` while creating a tap.
