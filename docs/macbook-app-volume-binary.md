# MacBook per-app volume is 100% or nothing

## Symptom

On a MacBook’s built-in speakers, an app slider is full volume or silent. Intermediate values do nothing. Permissions are already granted. External DACs often worked with earlier mixer paths.

## Cause

`mutedWhenTapped` only helps if the tap is actually read and the gained samples are played back on the same device.

A non-stacked aggregate that includes the speakers can take those speakers over. Silencing that aggregate’s output then mutes the hardware. Playing the tap through DefaultOutput / HALOutput cannot reach the seized device, so anything below 100% is silence (`needsTap` is false at 100%, so native audio still plays).

A later tap-only aggregate avoided the seizure, but it has no speaker clock. The IOProc sees empty buffers, mute still engages, and HALOutput plays the empty pipe. Same binary result.

## What we changed

Stacked private aggregate (`kAudioAggregateDeviceIsStackedKey`) with the real output as clock / main subdevice plus the process tap. Apply gain in the aggregate IOProc and write that to the aggregate output. Do not silence the speakers, and do not play back through a second output unit.

## Do not

Put the built-in speakers in a **non-stacked** aggregate and silence that output. Do not use a tap-only aggregate plus HALOutput / DefaultOutput as the MacBook playback path.
