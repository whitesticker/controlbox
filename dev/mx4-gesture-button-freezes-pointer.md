# MX4 Gesture button freeze

Shipped in 0.1.44.

## Symptom

Diverting MX4 **gesture button** `0x00C3` as a Gestures owner and pinning the pointer looked like a hung app. Click-only divert (`0x03`) restored Click but killed swipe. Mixing firmware XY with report `0x02` laser XY felt like dropped frames.

## Cause

The haptic-pad path calls `CGAssociateMouseAndMouseCursorPosition(0)` and swallows `mouseMoved`. That is wrong for `0x00C3`. OpenLogi only uses `rawXYEvent` for that CID. Mixing it with report `0x02` laser XY double-feeds the swipe and leaves the OS cursor moving, which feels like hitching. A missed HID++ up while pinned leaves the pointer dead until the mouse is power-cycled.

OpenLogi’s OS-hook (cursor travel, no HID++ divert) is for Middle / Back / Forward in gesture mode. It is **not** how the dedicated gesture button works. Logitech products stay on HID++.

## What we changed

Match OpenLogi for the **gesture button** (and Mode shift when it owns Gestures):

| Control | Divert | Motion | Pointer |
|---|---|---|---|
| Gesture button `0x00C3` | `0x33` if it owns Gestures | HID++ `rawXYEvent` only | No pin. Swallow `mouseMoved` only while firmware XY arrived in the last 80ms. |
| Haptic button `0x01A0` | `0x33` + analytics | HID++ XY + report `0x02` while held | Pin. Drop the first raw-XY sample (contact jump). |

Do not start a non-haptic hold from CG other-mouse button 7. Non-Logitech mice are another day.

## Do not

Pin the pointer for MX4 `0x00C3`. Do not feed report `0x02` laser XY into that swipe. Do not replace Logitech gesture-button divert with an OS-hook.
