# Ad-hoc signing resets Accessibility and Input Monitoring

## Symptom

Every new build required removing and re-adding Control Box in:

- System Settings → Privacy & Security → Accessibility
- System Settings → Privacy & Security → Input Monitoring

## Cause

The Xcode project used `CODE_SIGN_IDENTITY = "-"` (ad-hoc). The designated requirement was a **cdhash**, which changes every rebuild. TCC treats that as a new app.

## What we changed

Debug and Release sign with Apple Development, team `XXA24FWXDW`. The designated requirement is bundle id `com.whitesticker.controlbox` plus that certificate, so grants survive rebuilds.

The app used to be `com.iremote.app`. That bundle id change is a new app to TCC: grant Accessibility, Input Monitoring, and Background again, then remove leftover rows from the old identity.

After the first switch from ad-hoc to Development, leftover ad-hoc Control Box rows in those lists must be removed once.

## Do not

Set `CODE_SIGN_IDENTITY` back to `-` for local builds.
