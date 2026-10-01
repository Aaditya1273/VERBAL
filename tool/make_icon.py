#!/usr/bin/env python3
"""Generate VERBAL's app icon at every size Android and Devpost need.

Pure stdlib (zlib + struct) so it runs anywhere without Pillow.

The mark is the mascot: a white ball with two eyes and a halo of colour on a
black ground — the same character the user talks to every session. It is
large and off-centre so it still reads at 48px in a launcher.

    python3 tool/make_icon.py
"""

import math
import struct
import zlib
from pathlib import Path

# Brand tokens, matching lib/app/theme.dart.
BG = (0x09, 0x09, 0x0B)       # VerbalTokens.darkBg — the ground
INK = (0xF5, 0xF5, 0xF7)      # the ball

# The halo's spectrum, matching the mascot in lib/shared/presence.dart.
SPECTRUM = [
    (0xFF, 0x8E, 0x8E), (0xFF, 0xC9, 0x8A), (0xBD, 0xF2, 0xA1),
    (0x8A, 0xDF, 0xFF), (0xB7, 0x9C, 0xFF), (0xFF, 0x9B, 0xD8),
]


def _spectrum_at(angle: float):
    """Colour of the halo at an angle (radians), blended around the ring."""
    n = len(SPECTRUM)
    pos = (angle / (2 * math.pi)) % 1.0 * n
    i = int(pos)
    f = pos - i
    a, b = SPECTRUM[i % n], SPECTRUM[(i + 1) % n]
    return tuple(a[k] + (b[k] - a[k]) * f for k in range(3))


def _mix(base, top, alpha):
    return tuple(base[k] + (top[k] - base[k]) * alpha for k in range(3))


def render(size: int) -> bytes:
    """Return raw RGB rows: the mascot, large and off-centre, on black.

    The ball sits low-left and bleeds past the edge, the way a character
    leans into a doorway; the eyes look up and to the right, into the light.
    """
    cx, cy = size * 0.46, size * 0.58
    r = size * 0.44
    halo_r = r * 1.14
    halo_w = r * 0.30

    tilt = -0.25
    eye_h = r * 0.40
    eye_w = r * 0.15
    gap = r * 0.26
    ox, oy = cx + r * 0.22, cy - r * 0.22
    eyes = [(-gap / 2, 0.0), (gap / 2, -r * 0.05)]

    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            px, py = x + 0.5, y + 0.5
            dx, dy = px - cx, py - cy
            d = math.hypot(dx, dy)
            colour = BG

            band = abs(d - halo_r) / halo_w
            if band < 2.4:
                strength = math.exp(-band * band * 1.4) * 0.7
                colour = _mix(colour, _spectrum_at(math.atan2(dy, dx)), strength)

            if d <= r:
                # Shade toward the bottom-right so it reads as a ball.
                shade = max(0.0, (dx + dy) / (2 * r))
                colour = _mix(INK, BG, 0.22 * shade * shade)
                mx, my = px - ox, py - oy
                ux = mx * math.cos(-tilt) - my * math.sin(-tilt)
                uy = mx * math.sin(-tilt) + my * math.cos(-tilt)
                for (ex, ey) in eyes:
                    lx, ly = ux - ex, uy - ey
                    half = eye_h / 2 - eye_w / 2
                    ly_c = max(-half, min(half, ly))
                    if math.hypot(lx, ly - ly_c) <= eye_w / 2:
                        colour = BG

            rows += bytes(int(max(0, min(255, c))) for c in colour)
    return bytes(rows)


def write_png(path: Path, size: int) -> None:
    raw = render(size)

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(
            ">I", zlib.crc32(body) & 0xFFFFFFFF
        )

    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)  # 8-bit RGB
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
    print(f"  {path}  ({size}x{size}, {len(png) // 1024} KB)")


def main() -> None:
    root = Path(__file__).resolve().parent.parent

    print("Android launcher icons:")
    android = {
        "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192,
    }
    for density, size in android.items():
        write_png(
            root / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png",
            size,
        )

    print("\nStore / Devpost assets:")
    write_png(root / "assets/icon/verbal_icon_1024.png", 1024)
    write_png(root / "assets/icon/verbal_icon_512.png", 512)

    print("\nDone. The 1024 is the one Devpost asks for.")


if __name__ == "__main__":
    main()
