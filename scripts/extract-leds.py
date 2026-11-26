"""Split an MSI rear product photo into a base image and an LED mask.

Usage: python3 scripts/extract-leds.py rear.png Resources/<model>-rear.png Resources/<model>-rear-leds.png preview.png
Needs Pillow and NumPy. The photo must have a transparent background (MSI's gallery images do).
LED pixels are found by saturation: the shell is white or black, the LEDs are colored.
"""
import sys, numpy as np
from PIL import Image
src, out_base, out_leds, out_preview = sys.argv[1:5]
im = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32) / 255
rgb, a = im[..., :3], im[..., 3]
mx, mn = rgb.max(-1), rgb.min(-1)
sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
# LED pixels: saturated and reasonably bright
led = np.clip((sat - 0.20) / 0.25, 0, 1) * np.clip((mx - 0.10) / 0.45, 0, 1) * a
ys, xs = np.nonzero(led > 0.05)
print("LED bbox x", xs.min(), xs.max(), "y", ys.min(), ys.max(), "pixels", len(xs))
# Base: replace LED pixels with the dark grille they sit on
dark = np.full_like(rgb, 0.07)
base_rgb = rgb * (1 - led[..., None]) + dark * led[..., None]
# Neutralize leftover tint (reflections) inside the LED panel
ys0, xs0 = np.nonzero(led > 0.05)
box = (slice(ys0.min(), ys0.max() + 1), slice(xs0.min(), xs0.max() + 1))
lum = base_rgb[box].mean(-1, keepdims=True)
bs = base_rgb[box]; bmx, bmn = bs.max(-1), bs.min(-1)
bsat = np.where(bmx > 0, (bmx - bmn) / np.maximum(bmx, 1e-6), 0)[..., None]
w = np.clip(bsat / 0.12, 0, 1)
base_rgb[box] = bs * (1 - w) + np.minimum(lum, 0.12) * w
# Crop to visible content
ya, xa = np.nonzero(a > 0.02)
y0, y1, x0, x1 = ya.min(), ya.max() + 1, xa.min(), xa.max() + 1
print("crop", x0, y0, x1, y1)
base = np.dstack([base_rgb, a])[y0:y1, x0:x1]
Image.fromarray((base * 255).astype(np.uint8), "RGBA").save(out_base)
# LED mask: white with alpha = LED intensity (brightness of the original dot)
inten = led * np.clip(mx / 0.85, 0, 1)
mask = np.dstack([np.ones_like(inten)] * 3 + [inten])[y0:y1, x0:x1]
Image.fromarray((mask * 255).astype(np.uint8), "RGBA").save(out_leds)
# Preview: LEDs tinted orange over base, on black
bg = np.zeros_like(base[..., :3])
comp = bg * (1 - base[..., 3:]) + base[..., :3] * base[..., 3:]
tint = np.array([1.0, 0.43, 0.0])
m = mask[..., 3:]
comp = comp * (1 - m) + tint * m
Image.fromarray((np.clip(comp, 0, 1) * 255).astype(np.uint8), "RGB").save(out_preview)
