#!/usr/bin/env python3
"""Generate VERBAL's app icon at every size Android and Devpost need.

Pure stdlib (zlib + struct) so it runs anywhere without Pillow.

The mark is the mascot, exactly as it appears in the app: a solid black ball
with two white eyes, and the spectrum coming out from behind it mid-sentence.
Centred, generous margin, so it still reads at 48px in a launcher.

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
    """Return raw RGB rows: the mascot, centred on black, mid-sentence.

    The same geometry as lib/shared/presence.dart: a solid black ball with
    two white eyes, and the spectrum coming out from behind its edge.
    """
    cx = cy = size / 2
    r = size * 0.31
    reach = r * 1.42                   # the light, part way out
    body_lit = (0x30, 0x30, 0x35)
    body_dark = (0x14, 0x14, 0x17)

    tilt = -0.25
    eye_h = r * 0.30
    eye_w = r * 0.14
    gap = r * 0.24
    eyes = [(-gap, 0.0), (gap, -r * 0.06)]
    cx_eyes, oy = cx + r * 0.30, cy - r * 0.30

    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            px, py = x + 0.5, y + 0.5
            dx, dy = px - cx, py - cy
            d = math.hypot(dx, dy)

            if d <= r:
                lift = max(0.0, 1 - math.hypot(dx + r * 0.55, dy + r * 0.65) / (r * 1.3))
                colour = _mix(body_dark, body_lit, lift)
                if d > r - size * 0.004:
                    colour = _mix(colour, INK, 0.5 * max(0.0, -dy / r))
                for (ex, ey) in eyes:
                    mx, my = px - (cx_eyes + ex), py - (oy + ey)
                    ux = mx * math.cos(-tilt) - my * math.sin(-tilt)
                    uy = mx * math.sin(-tilt) + my * math.cos(-tilt)
                    half = eye_h / 2 - eye_w / 2
                    uy_c = max(-half, min(half, uy))
                    if math.hypot(ux, uy - uy_c) <= eye_w / 2:
                        colour = INK
            else:
                colour = BG
                # Soft edge on the light, like the blur in the app.
                edge = (d - reach) / (r * 0.22)
                strength = 1.0 if edge < 0 else math.exp(-edge * edge * 2.0)
                colour = _mix(colour, _spectrum_at(math.atan2(dy, dx)), 0.92 * strength)

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
