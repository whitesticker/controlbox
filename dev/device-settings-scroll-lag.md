# Device settings page is laggy to scroll

## Symptom

On a MacBook, two-finger scroll on a device **sidebar** page stutters. It happens even when that device is disconnected.

## Cause

The page was one grouped `Form` cell wrapping every profile tile, gesture pad, and mapping picker. AppKit has to composite that whole row during trackpad scroll. Vibrancy (`.thinMaterial`), card shadows, and spinning Easy-Switch `ProgressView`s (three of them while hosts are Pending) made it worse.

Live HID snapshots on `@Observable` DualSenseMonitor could also rebuild the Form, but that is not required for the hitch: a disconnected DualSense or MX page is already heavy.

## What we changed

Give Analog, Profiles, and each mapping group their own Form rows so the list can scroll smaller cells. Use opaque fills instead of materials. Drop card shadows. Easy-Switch Pending is a static ellipsis, not a spinner.

Publish DualSense / MX / Apple TV snapshots to SwiftUI only when settings-relevant fields change, unless Calibration is open. IMU stays off until Calibration is open. Control ingest still uses the local poll snapshot.

## Do not

Put every mapping back into one Profiles card. Do not put `ProgressView` on idle Easy-Switch tiles. Do not turn DualSense IMU on just because the device page is selected.
