# Process tap is exclusive

Per-app volume uses Apple’s process tap (`CATapDescription` + `mutedWhenTapped`). That mute belongs to **one** client.

If FineTune, SoundSource, Audio Hijack, Loopback, or Background Music is already tapping an app, VibeRemote’s slider can create a second tap and get silence or no change. System output still works. Closing the other mixer returns the stream.

Sound lists those apps when they are running. Quit the other mixer; do not try to share a tap.
