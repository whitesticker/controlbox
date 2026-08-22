# Ad-hoc signing resets Accessibility and Input Monitoring

## Symptom

Every new build required removing and re-adding VibeRemote in:

- System Settings → Privacy & Security → Accessibility
- System Settings → Privacy & Security → Input Monitoring

## Cause

The Xcode project used `CODE_SIGN_IDENTITY = "-"` (ad-hoc). The designated requirement was a **cdhash**, which changes every rebuild. TCC treats that as a new app.

## What we changed

Debug and Release sign with Apple Development, team `XXA24FWXDW`. The designated requirement is bundle id `com.iremote.app` plus that certificate, so grants survive rebuilds.

After the first switch from ad-hoc to Development, leftover ad-hoc VibeRemote rows in those lists must be removed once.

## Do not

Set `CODE_SIGN_IDENTITY` back to `-` for local builds.
