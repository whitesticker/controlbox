# Displays pane: extra row, slider does not drive that monitor

Hit 2026-08-24 on Apple silicon with several USB-C / DisplayPort externals. DDC/CI itself was fine. The pane listed **N+1** rows and a named slider did nothing.

## Symptom

- `NSScreen` count is N, Displays shows N+1 (or more).
- A named monitor’s brightness slider is dead, or it moves a different panel.
- A leftover row may still be adjustable; that row is the real DDC pipe for the “dead” screen.

HDMI on some Apple silicon Macs still cannot do DDC. That is a different connection limit.

## Cause

On Apple silicon, I2C/DDC is `DCPAVServiceProxy` under **`dcpextN`**. Product name, vendor, model, and serial live on the sibling **`dispextN`** `IOMobileFramebufferShim` (`DisplayAttributes`), not on the AV proxy.

Walking parents from the proxy and then searching descendants for `DisplayAttributes` is safe only until `dcpextN`. One more hop is `AppleT602xIO` (or the equivalent I/O node), whose descendants include **every** `dispext`. `IORegistryEntrySearchCFProperty` with recursive iterate returns the **first** framebuffer, so every DDC service can inherit one monitor’s EDID.

Match used vendor + product (+ serial when present): unique models failed to match, leftover DDC was appended as an extra row, and twins of the stolen identity still “worked.”

## Fix

DDC matching and Apple-silicon I2C now follow **MonitorControl** (`Arm64DDC.swift`, MIT). Credit is on the Displays page. License text is `Packages/IRemoteControl/NOTICE-MonitorControl`.

What we took from them:

- Depth-first IORegistry walk: last `AppleCLCD2` / `IOMobileFramebufferShim` identity, then the next `DCPAVServiceProxy` on that port
- Score each (Core Graphics display, IORegistry service) and greedily take from highest score, unique display ID + service location
- `Location == External` before creating an AV service
- Dummy skip: AOC `28E850`, name containing `dummy`, virtual + vendor `0xF0F0`
- VESA DDC checksums, retries, settle delays, one I2C lock
- Contrast is VCP `0x12` (brightness stays `0x10`)

Do not walk past `dcpext` and recursively search `DisplayAttributes`. Do not treat leftover DDC services as extra monitors. FineTune is GPL; do not copy it.

Iterator order on this Mac interleaves framebuffer then that port’s proxy. That is why MonitorControl’s last-framebuffer rule works here. An ioreg dump that looks like sibling subtrees is not the same as `IORegistryEntryCreateIterator` order.

Code: `Packages/IRemoteControl/Sources/IRemoteControl/Arm64DDC.swift`, `DisplayBrightness.swift`.
