# DualSense Bluetooth microphone (macOS)

Parked 2026-08-24. Probe only — **not in the app**. Come back here before wiring capture into VibeRemote.

## Symptom / goal

Sony does not expose DualSense speaker or mic as a Core Audio device over Bluetooth on macOS. `system_profiler SPAudioDataType`, ffmpeg AVFoundation, and `AudioInputProbe` never show a DualSense input. The UI copy in `MicrophoneStatusView` was right about that.

The pad **does** send microphone audio over the HID interrupt channel: Opus inside Bluetooth input report `0x31`. A standalone tool can enable that path, decode, and write a WAV. Quality on this Mac is still poor because macOS delivers only about half the mic frames.

USB DualSense is a normal UAC1 audio device on other platforms; the 3.5 mm jack over USB on this Mac is still untested. That is the likely high-quality path. This note is the Bluetooth HID path only.

Hardware used: DualSense `054C:0CE6`, Bluetooth HID ACL, address `4C:B9:9B:BE:62:A4` (desk pad). No USB DualSense was attached.

## Why Core Audio is empty

Bluetooth advertisement is HID + PnP only. No A2DP, HFP, or other audio UUID. Class of Device is gamepad, audio service bit clear. Mainline Linux `hid-playstation.c` says the same: Bluetooth audio is not supported in the kernel driver.

Over USB the pad is a composite HID + USB Audio Class device. Over Bluetooth, speaker, jack, mic, and HD haptics all ride Sony’s proprietary HID reports.

## Protocol (what actually worked)

Wire format matches [dualsense-neo SPEC.md](https://github.com/forgerpl/dualsense-neo/blob/main/SPEC.md) (2026-07). Do not use DualShock 4 SBC-in-`0x14` as a guide.

### Reports on this firmware

HID descriptor on this pad (Bluetooth, usage page `0x01` usage `0x05`):

- Input `0x31` — 78 bytes (gamepad **or** mic; same ID).
- Output `0x32`–`0x39` — 142…547 bytes (audio/haptics ladder).
- `maxIn=78`, `maxOut=547`.

Mic data does **not** arrive on a large input report. It is a second variant of `0x31`.

### Enable capture

1. Output `0x31` (78 B, CRC-32 over HIDP seed `0xA2` + body except last 4, stored LE). Unmute only:
   - `valid_flag0`: mic volume enable `0x40` + audio control `0x80`. **Do not** set rumble (`0x01`) or haptics select (`0x02`).
   - `valid_flag1`: mute LED + power-save enable.
   - `mic_volume`: `0x24` (max is `0x40`; `0x40` clipped hard).
   - `power_save_control`: `0` (clear `MIC_MUTE` bit 4).
2. Output `0x32` (142 B) with one sized sub-packet:
   - header `0x11 | 0x80`, length `1`, payload `0x03` (mic bit 0 + one field bit).
   - This is the **mic-only** mask. It does **not** start the speaker/haptics family (`0xFE` / `0xFF`).

Then input `0x31` reports interleave. Mic variant: bit 1 of byte 1 set (`(byte[1] >> 1) & 1 == 1`). Typical gamepad `b1` is `x1`, mic is `x2` (high nibble is a 4-bit sequence).

Opus: 48 kHz **mono**, 480 samples (10 ms), **71 bytes at offset 3**. Trailing 4 bytes of the 78-byte report are CRC. Decode with libopus. Every good frame decoded to exactly 480 samples (`decodeErr=0` on this Mac).

Output CRC: IEEE CRC-32, seed byte `0xA2` prepended, hash everything except the last 4, write LE. Same as `PS_OUTPUT_CRC32_SEED` in `hid-playstation.c`.

`IOHIDDeviceSetReport` for DualSense on this Mac wants the **report ID in the buffer** and as the report-ID argument (same as HID++).

### Disable (after capture)

Send `0x32` / `0x11` mask **`0x02`** (same length-1 packet, mic bit cleared). Do **not** send mask `0xFE`: that is the working **audio/haptics family** and keeps the grip coils awake. Do **not** send sub-packet `0x12` (haptics PCM), including zeros — starting that stream clicks the coils.

If the pad is still buzzing, HID stop is best-effort. The audio DSP **latches**. Power-cycle the controller (hold PS until lights die).

## Grip buzz (what we hit)

| Send | Effect |
|---|---|
| `0x11` mask `0xFF` (mic + `0xFE` family) | Mic on; speaker/haptics engine on. Coils can keep running after the tool exits. |
| `0x11` mask `0xFE` as “mic off” | Stops mic, **leaves haptics family on**. |
| `0x12` 64 B haptic PCM (even silence) | Drives the actuators. |
| `0x31` `valid_flag0` rumble + `valid_flag2` `COMPATIBLE_VIBRATION2` | Arms classic/HD rumble. Unmute used this once; buzz returned. |
| Mic-only `0x03`, unmute without rumble bits | Capture still worked; much less buzz. Residual latch still possible; power-cycle clears it. |

`Int16.abs(Int16.min)` traps (`EXC_BREAKPOINT`). Peak/magnitude must special-case `.min`. Nested HID callbacks + exclusive access on a class `pcm` buffer also trapped; copy reports in the callback and decode later.

## Quality on this Mac (measured)

Pad rate (Linux / dualsense-neo): ~99 mic reports/s plus ~464 gamepad reports/s.

This Mac, second userspace `IOHIDDevice` client (VibeRemote also attached via Game Controller + `DualSenseHIDBatteryReader`):

- ~70 HID input reports/s total.
- ~47 mic frames/s after enable.
- 30 s wall clock → ~13 s of concatenated PCM.
- Keep-alive `0x03` at 10 Hz did **not** raise the mic rate.

So the limiter is Apple’s HID / Game Controller stack, not our timer. Concatenating frames skips time (choppy, slightly fast). Opus PLC from the 4-bit sequence nibble in `byte[1]` fills 1–3 missing frames between received packets; it cannot invent the rest. A 10 s run: 470 real + 235 PLC → 7.0 s of audio.

First capture used `mic_volume=0x40`: peak 32767, heavy clip. Later `0x18` / `0x24`: peak a few thousand, hiss if you then apply large makeup gain.

The DualSense built-in capsule is small and noisy. 71-byte / 10 ms Opus is a thin codec. DSP will not turn this into a headset mic while half the frames never arrive.

## Probe tool

Not linked into VibeRemote. Needs Homebrew `opus`, Input Monitoring for the process that runs it (Terminal / Cursor).

```text
swiftc -Onone tools/dualsense-mic.swift \
  -import-objc-header tools/dualsense-mic-bridging.h \
  -lopus -L/opt/homebrew/lib -I/opt/homebrew/include \
  -Xcc -I/opt/homebrew/include \
  -framework IOKit -framework CoreFoundation \
  -o /tmp/dualsense-mic

/tmp/dualsense-mic 10 /tmp/dualsense-mic.wav   # seconds, output wav
/tmp/dualsense-mic stop                          # rumble off + mic mask 0x02 (best-effort)
```

Do not commit WAVs (desk voice). Local dumps were `/tmp/dualsense-mic.wav` and `tools/dualsense-mic.wav`.

Vendor match: `054C:0CE6` (DualSense) and `054C:0DF2` (Edge). Open without seize.

## App code (untouched)

`MicrophoneStatusView` still says Bluetooth is HID-only. `AudioInputProbe` lists Core Audio inputs. `DualSenseHIDBatteryReader` already listens to `0x31` for battery (same reports; mic variants would look like garbage battery if parsed). Do not parse mic `0x31` as gamepad/battery.

## Next (when this comes back)

1. **USB** — plug the pad, see if Core Audio gets a DualSense input. If yes, that is the product mic path.
2. **Bluetooth frame rate** — dedicated HID thread, or taking the pad away from Game Controller for a probe, to see if macOS will deliver ~100 mic/s. Seizing DualSense HID will fight VibeRemote; do not seize Logitech.
3. **Product** — if BT stays at ~47/s, do not ship it as a speech mic. Optional: meter-only, or USB-only.
4. **Apple TV remote mic** is a different HID (seize audio interface + `0xAF`). Do not mix with this DualSense path.

## Do not

- Treat DualSense BT as A2DP/HFP.
- Copy DS4 SBC report IDs (`0x14`–`0x19`).
- Send `0xFE` / `0xFF` / `0x12` unless you are deliberately driving speaker or coils.
- Set rumble/haptics valid flags on the unmute `0x31`.
- Call `IOBluetoothDevice.pairedDevices()`.
- `abs(Int16.min)`.
- Decode Opus on the HID callback thread while mutating the same Swift array (exclusivity trap).

## References

- [forgerpl/dualsense-neo SPEC.md](https://github.com/forgerpl/dualsense-neo/blob/main/SPEC.md) — framing, `0x11` masks, mic layout, 45 kHz DAC note (output; mic in is 48 kHz).
- [awalol/DS5Dongle](https://github.com/awalol/DS5Dongle) — mic enable is bit 0 of the `0x11` control mask.
- Linux `drivers/hid/hid-playstation.c` — `0x31` SetStateData struct, CRC seeds `0xA2` output / `0xA3` feature.
- Sony support: built-in DualSense mic/speaker not compatible with Mac; headset jack needs USB.
