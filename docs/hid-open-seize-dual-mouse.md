# Opening or seizing every Logitech HID interface

## Symptom

With MX Master 4 and MX Master 3S both connected, the app crashed on launch or became unusable. One mouse at a time was more likely to stay up.

## Cause

`LogitechMXMasterReader` matched all Logitech vendor collections and:

- Opened every matching HID++ / mouse / consumer interface at once
- Sometimes called `IOHIDManagerOpen(..., kIOHIDOptionsTypeSeizeDevice)`, which seizes **all** matching devices
- Attached and tore down interfaces from HID callbacks that can run off the main thread
- Wrote into report buffers and freed them while the kernel could still write

Two physical mice multiply the number of HID collections (mouse, consumer, vendor, Bolt/BLE). That is what blew up, not “Bluetooth cannot have two mice.”

## What we think happened (3S + 4 together)

1. Two mice → many Logitech HID interfaces.
2. One manager opened or seized all of them.
3. HID++ probe/divert ran on more than one device, sometimes off the main thread.
4. Heap corruption (`libmalloc`) and/or both mice left in a bad firmware state.

The 3S also uses HID++ usage page `0xFF43` (Master 4 uses `0xFF00`). One shared matcher that opens “any Logitech vendor page” is the wrong shape for two models.

## Do not

- Seize Logitech HID managers
- Open the standard mouse collection (`0x01` / `0x02`) to watch buttons
- Attach every matching interface; talk to one target device at a time
