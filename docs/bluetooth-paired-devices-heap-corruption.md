# Bluetooth paired-device listing corrupts the heap

## Symptom

VibeRemote dies shortly after launch or while a popup is open. Crash reports show:

- `BUG IN CLIENT OF LIBMALLOC: memory corruption of free block`
- `EXC_BREAKPOINT` in `libsystem_malloc.dylib`
- Often noticed later (for example while creating the menu bar item), after the heap was already damaged

## Cause

Device listing called `IOBluetoothDevice.pairedDevices()` (and used to do it from the 60 Hz loop). On this Mac (macOS 26 / Tahoe), that API has corrupted the heap. Adding a second BLE Logitech mouse made it fail almost immediately.

## What we changed

- Removed `IOBluetooth` / `pairedDevices()` from `BluetoothDeviceCatalog`
- List connected devices from HID + Game Controller only
- Rate-limit remaining device refresh (about 15 s, skip while a menu is tracking)

## Do not

Call `IOBluetoothDevice.pairedDevices()` again, even behind a timer or “only on a button.”
