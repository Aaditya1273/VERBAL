#!/usr/bin/env python3
"""Generate VERBAL's app icon at every size Android and Devpost need.

Pure stdlib (zlib + struct) so it runs anywhere without Pillow.

The mark is the waveform already used on the practice screen: VERBAL is a
voice-first product, and the bars are the one shape a user sees every session.
Deep teal ground, warm off-white bars, generous margin so it stays legible at
48px in a launcher.

    python3 tool/make_icon.py
"""

import struct
import zlib
from pathlib import Path

# Brand tokens, matching lib/app/theme.dart.
ACCENT = (0x17, 0x5E, 0x54)   # VerbalTokens.accentLight
INK = (0xF7, 0xF6, 0xF3)      # VerbalTokens.lightBg — the bars

# Bar heights as a fraction of the canvas. Asymmetric on purpose: a symmetric
# waveform reads as a logo, an uneven one reads as speech.
BARS = [0.30, 0.56, 0.86, 0.46, 0.68, 0.24]


def render(size: int) -> bytes:
    """Return raw RGB rows for a size x size icon."""
    px = [[ACCENT for _ in range(size)] for _ in range(size)]

    margin = size * 0.22
    usable = size - 2 * margin
    slot = usable / len(BARS)
    bar_w = slot * 0.46
    radius = bar_w / 2
    mid = size / 2

    for i, height in enumerate(BARS):
        cx = margin + slot * (i + 0.5)
        half = (usable * height) / 2

        x0, x1 = cx - bar_w / 2, cx + bar_w / 2
        y0, y1 = mid - half, mid + half

        for y in range(max(0, int(y0 - 1)), min(size, int(y1 + 2))):
            for x in range(max(0, int(x0 - 1)), min(size, int(x1 + 2))):
                # Rounded caps: inside the straight body, or within the end cap.
                px_x, px_y = x + 0.5, y + 0.5
                inside_body = x0 <= px_x <= x1 and (y0 + radius) <= px_y <= (y1 - radius)
                near_top = ((px_x - cx) ** 2 + (px_y - (y0 + radius)) ** 2) <= radius ** 2
                near_bot = ((px_x - cx) ** 2 + (px_y - (y1 - radius)) ** 2) <= radius ** 2
                if inside_body or near_top or near_bot:
                    px[y][x] = INK

    rows = bytearray()
    for row in px:
        rows.append(0)  # PNG filter type 0 for each scanline
        for r, g, b in row:
            rows += bytes((r, g, b))
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
