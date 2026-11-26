# How MSI Mystic talks to the monitor

MSI monitors with on-screen settings over USB expose a USB HID device on the upstream (USB-B) cable, vendor ID `0x1462`, product ID `0x3FA4`. Lighting is a HID feature report. MSI Mystic reads it with `IOHIDDeviceGetReport` and writes it with `IOHIDDeviceSetReport`. No driver or kernel extension is involved.

## Lighting report

MSI uses two layouts:

| Report ID | Size | LEDs per group | Used by |
|---|---|---|---|
| `0x72` | 168 bytes | 24 | MPG273CQR, MAG274 series, MPG 274URDFW and newer |
| `0x71` | 78 bytes | 9 | Older MAG models |

Both share one structure:

| Bytes | Contents |
|---|---|
| 0 | Report ID |
| 1–11 | Group 0 header: mode, red, green, blue, speed, brightness, then 5 bytes left as the monitor returned them |
| 12–22 | Group 1 header, same layout |
| 23 onward | One red, green, blue triplet per LED, group 0 then group 1 |

| Mode | Byte |
|---|---|
| Off | `0x00` |
| Steady | `0x01` |
| Breathe | `0x02` |
| Flash | `0x05` |
| Rainbow | `0x1A` |
| Ambient (MSI's factory effect) | `0x21` |

Ambient ignores the stored color, so a color change only shows once the mode is something else.

## How the app adapts to a model

1. It finds any device with the MSI USB ID and reads its product name, for example `MSI Monitor MPG 274URDFW E16M`.
2. It requests report `0x72`, then `0x71`, and uses whichever the monitor answers.
3. Every write starts from a reference packet that came from the monitor: the factory packet for known models, or a snapshot taken the first time an unknown model connects (stored in `~/Library/Application Support/MSI Mystic`).
4. It writes color only to the LED slots that are populated in that reference. On the MPG 274URDFW that is one slot in group 0 and 22 in group 1, which drive its 44 LEDs in pairs.

## Safety

- The only report the app writes is the lighting report, built on a packet the monitor returned.
- It never sends OSD or picture commands. [msigd](https://github.com/couriersud/msigd) documents that the firmware does not validate those, and that some can disable a monitor's USB until it's power-cycled.
- Writes are coalesced to at most about 8 per second.
- Color-cycling effects run on the monitor's own controller.
- Untested models ask before the first write.

## Adding a monitor

Model-specific data is optional and lives in `MonitorModel.lookup` in `Sources/LightController.swift`:

- `productPage`: link shown in the footer.
- `factory`: the lighting packet read from a new unit, so Restore Factory Lighting works.
- `rearPhoto`: a rear product photo plus LED mask, so the preview lights the real LED pattern. MSI's gallery images already have transparent backgrounds. Split one with:

  ```bash
  python3 scripts/extract-leds.py rear.png Resources/<model>-rear.png Resources/<model>-rear-leds.png preview.png
  ```

  It needs Pillow and NumPy. Models without a photo get a generic monitor drawing.
- `verified: true`, once lighting has been confirmed on real hardware.

Run `./scripts/test.sh` before and after changes. The tests check the factory packet against `Tests/fixtures/mpg274urdfw-factory.bin` and that the packets the app builds stay byte-identical.

## Other brands

No cross-vendor standard is in use yet. Each brand has its own protocol, and OpenRGB supports them one vendor at a time; it added an Acer monitor controller in version 0.9. Microsoft's HID LampArray, the standard behind Windows Dynamic Lighting, would make this uniform, but the MPG 274URDFW's USB descriptor exposes no LampArray collection, only MSI's vendor report.
