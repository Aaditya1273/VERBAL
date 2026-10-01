#!/usr/bin/env python3
"""Generate VERBAL's app icon at every size Android and Devpost need.

Pure stdlib (zlib + struct) so it runs anywhere without Pillow.

The mark is the mascot: one black ball, two white marks, a halo of colour on
a black ground — the same thing the user talks to every session. Generous
margin so it stays legible at 48px in a launcher.

    python3 tool/make_icon.py
"""

import math
import struct
import zlib
from pathlib import Path

# Brand tokens, matching lib/app/theme.dart.
BG = (0x09, 0x09, 0x0B)       # VerbalTokens.darkBg — the ground
BODY = (0x14, 0x14, 0x16)     # the ball, a shade above the ground
INK = (0xF5, 0xF5, 0xF7)      # the two marks

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
    return tuple(int(base[k] + (top[k] - base[k]) * alpha) for k in range(3))


def render(size: int) -> bytes:
    """Return raw RGB rows for a size x size icon: the mascot on its ground."""
    cx = cy = size / 2
    r = size * 0.30                 # the ball
    halo_r = r * 1.22               # centre line of the halo ring
    halo_w = r * 0.42               # half-width of the ring before the blur

    # The two marks, in the ball's own frame (top-right, tilted).
    tilt = -0.32
    mark_h = r * 0.36
    mark_w = r * 0.14
    marks = [(-r * 0.22, 0.0), (r * 0.22, -r * 0.06)]
    ox, oy = cx + r * 0.30, cy - r * 0.30

    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            px, py = x + 0.5, y + 0.5
            dx, dy = px - cx, py - cy
            d = math.hypot(dx, dy)
            colour = BG

            # Halo: a soft ring of spectrum, strongest on its centre line.
            band = abs(d - halo_r) / halo_w
            if band < 2.2:
                strength = math.exp(-band * band * 1.6) * 0.75
                colour = _mix(colour, _spectrum_at(math.atan2(dy, dx)), strength)

            # Ball, lit faintly from the top-left.
            if d <= r:
                lit = max(0.0, 1 - math.hypot(dx + r * 0.5, dy + r * 0.6) / (r * 1.1))
                colour = _mix(BODY, INK, 0.22 * lit)
                # Rim light along the top edge.
                if d > r - size * 0.004:
                    rim = max(0.0, -dy / r)
                    colour = _mix(colour, INK, 0.5 * rim)
                # Marks: rotate the pixel into the marks' frame.
                mx, my = px - ox, py - oy
                ux = mx * math.cos(-tilt) - my * math.sin(-tilt)
                uy = mx * math.sin(-tilt) + my * math.cos(-tilt)
                for (mxc, myc) in marks:
                    lx, ly = ux - mxc, uy - myc
                    half = mark_h / 2 - mark_w / 2
                    ly_c = max(-half, min(half, ly))
                    if math.hypot(lx, ly - ly_c) <= mark_w / 2:
                        colour = INK

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
