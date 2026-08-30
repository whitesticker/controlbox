# Sound sliders freeze the MacBook on Sequoia

## Symptom

On a MacBook running **macOS Sequoia**, moving a volume slider on Sound makes the whole system hitch. It starts on the first adjust and does not stop. Tahoe with the same binary does not do this.

## Cause

Sequoia 15.x `coreaudiod` publishes process-tap and process-object IDs before they are resolvable. HAL reads then return `kAudioHardwareBadObjectError` (`!obj`) for tens of milliseconds. Tahoe fixed the timing; 15.x did not get the backport.

Sound refreshes every 1.5s and treated a failed or empty process list as “every app quit,” and a flickering default-output UID as “device changed.” That destroyed the tap and created a new one. The new tap was unpublished, the next poll failed the same way, and `coreaudiod` stayed in a create/destroy storm. Whole-machine lag until the taps were gone.

A GCD IOProc writing speaker buffers would stall any macOS. It does not explain Sequoia-only.

## What we changed

If the process-object list read fails, leave live taps alone. Only drop a session after three successful lists in a row without that app. Only recreate for an output-UID change after three stable mismatches. Retry `kAudioTapPropertyFormat` on `!obj`. Do not call `TCCAccessRequest` from tap setup.

Capture stays off the speaker IOProc (tap-only aggregate + HALOutput). That is separate from this Sequoia race.

## Do not

Tear down taps because one HAL read returned empty or `!obj`. Do not recreate a tap on every Sound-page timer tick.
