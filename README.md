<p align="center"><img src="Resources/icon-preview.png" width="160"></p>

# MSI Light

A native macOS app for the Mystic Light LEDs on the MSI MPG 274URDFW E16M. MSI only ships lighting software for Windows; this talks to the monitor directly over its USB-B upstream cable.

## Install

Requires Xcode Command Line Tools (`xcode-select --install`) and macOS 15 or later.

```bash
git clone https://github.com/<you>/msi-light.git
cd msi-light
./scripts/build.sh --install
```

The monitor's USB-B upstream cable must be connected to the Mac. Display cables alone do not carry the lighting channel.

## How it works

The monitor enumerates as a USB HID device (`VID 0x1462`, `PID 0x3FA4`). Lighting lives in feature report `0x72`, a 168-byte packet:

| Bytes | Contents |
|---|---|
| 0 | Report ID `0x72` |
| 1–11 | Group 0 header: mode, R, G, B, speed, brightness, then 5 fixed bytes |
| 12–22 | Group 1 header, same layout |
| 23–25 | Group 0 LED (one LED) |
| 95–160 | Group 1 LEDs (22 × RGB) |
| 167 | Trailer `0x82` |

Mode bytes: `0x00` off, `0x01` static, `0x02` breathing, `0x05` flashing, `0x1A` rainbow, `0x21` MSI's factory ambient effect.

The layout comes from [msigd](https://github.com/couriersud/msigd), which documents the same report for earlier MSI monitors. It was confirmed on this model by reading the factory state back before writing anything.

## Safety

- The app only ever sends report `0x72`, built from the factory packet in `MSIDevice.swift`. It never touches OSD settings.
- Writes are coalesced to at most 8 per second. Effects run on the monitor's own controller rather than being streamed from the Mac.
- **Restore Factory Lighting** writes back the exact packet the monitor shipped with.

## Rebuilding the icon

```bash
swift scripts/make-icon.swift
```

MSI and the MSI logo are trademarks of Micro-Star International. This is a personal project, not affiliated with MSI.
