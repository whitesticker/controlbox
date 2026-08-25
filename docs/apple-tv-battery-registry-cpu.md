# Apple TV battery walk pegs a CPU core

Hit 2026-08-25. VibeRemote sat near 90% CPU on the main thread with an Apple TV remote attached (or selected).

## Symptom

Activity Monitor shows VibeRemote using most of a core while idle. A `sample` of the process is almost entirely:

`DualSenseMonitor.capture` → `AppleTVRemoteSession.poll` → `AppleTVBatteryReader.percent` → `IOIteratorNext` / `IORegistryEntryCreateCFProperty`.

## Cause

The host polls devices at 120 Hz for DualSense sticks and MX gestures. Apple TV poll used that same tick to read battery.

BLE Battery Service `0x180F` is the intended source, but it often never fills. The fallback walked the entire `IOService` plane looking for Product / SerialNumber / DeviceAddress / BatteryPercent. A 2 s throttle only covered BLE `retrieveConnectedPeripherals`, not the registry walk. A miss (`percent == nil`) kept `batteryAvailable` false, so the walk ran every tick.

## Fix

`percent()` returns a cached BLE or registry value. Registry iteration runs on a background queue at most every 15 s, and only while BLE has no reading. Empty name+address does not walk. BLE refresh is 8 s.

Do not put IORegistry iteration on the 120 Hz poll.

Code: `IRemote/AppleTVBatteryReader.swift`, `IRemote/AppleTVRemoteSession.swift`.
