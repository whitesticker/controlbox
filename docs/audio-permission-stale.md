# Permissions still asks after System Audio Recording is granted

## Symptom

Permissions (and Sound) keep offering **Screen & System Audio Recording** after Control Box is already allowed under System Audio Recording. The prompt also asks for Screen Recording, which per-app volume does not need.

## Cause

`hasCaptureAccess` treated unknown audio TCC as “whatever `CGPreflightScreenCaptureAccess()` says.” System Audio Recording (`kTCCServiceAudioCapture`) is a different grant from Screen Recording. An audio-only allow leaves screen preflight false, so the row stays **Not allowed**. Request also called `CGRequestScreenCaptureAccess()`, which is the screen prompt.

## What we changed

Trust `kTCCServiceAudioCapture` first. Treat a Screen Recording grant as sufficient (macOS 26 covers taps that way) but do not require it. Request audio TCC only. Open the Screen & System Audio Recording settings pane (that is where Apple put the audio-only list). Remember a process tap that actually started.

## Do not

Call `CGRequestScreenCaptureAccess()` for Sound. Do not hide the row as allowed only when Screen Recording is on.
