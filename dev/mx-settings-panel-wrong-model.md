# MX Master 4 settings drove the connected 3S

## Symptom

MX Master 3S input worked, but key mapping and gesture settings were edited on the remembered **MX Master 4** device panel.

## Cause

One HID++ reader serves the live mouse. Device refresh treated every `isMXMaster` row as that mouse, and `captureMXMaster` applied whichever MX profile was selected. The saved MX4 selection stayed selected after 4 was unplugged, so 3S hardware used the MX4 profile.

## Fix

Settings are per physical mouse (BLE address / serial), not per model family. Glue HID++ and apply mappings only when the selected record is that device. A second 3S, a Master 3, and an MX4 each keep their own profiles.
