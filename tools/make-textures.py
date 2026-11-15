#!/usr/bin/env python3
"""Turns the artist's PNGs in art/ into the textures the game loads.

Writes addon/Tamer/Textures/Icon.tga (128x128) and MinimapIcon.tga (64x64) as
uncompressed 32-bit TGA, the same format as Fireside Tales' textures. Resizing
uses macOS's built-in sips, so this runs on a Mac with no extra installs:

    python3 tools/make-textures.py
"""
import os
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXTURES = os.path.join(ROOT, "addon", "Tamer", "Textures")
JOBS = [("icon.png", "Icon.tga", 128), ("minimap.png", "MinimapIcon.tga", 64)]


def read_png_rgba(path):
    """Decodes an 8-bit RGBA or RGB, non-interlaced PNG into rows of RGBA bytes."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path} isn't a PNG")
    pos, idat = 8, b""
    width = height = color = None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or color not in (2, 6) or interlace:
                sys.exit(f"{path} must be an 8-bit RGB or RGBA PNG without interlacing")
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    channels = 4 if color == 6 else 3
    raw = zlib.decompress(idat)
    stride = width * channels
    rows, prev = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            left = line[i - channels] if i >= channels else 0
            up = prev[i]
            corner = prev[i - channels] if i >= channels else 0
            if kind == 1:
                line[i] = (line[i] + left) & 255
            elif kind == 2:
                line[i] = (line[i] + up) & 255
            elif kind == 3:
                line[i] = (line[i] + (left + up) // 2) & 255
            elif kind == 4:
                p = left + up - corner
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - corner)
                pred = left if pa <= pb and pa <= pc else (up if pb <= pc else corner)
                line[i] = (line[i] + pred) & 255
        prev = line
        if channels == 3:
            line = bytearray(b"".join(bytes(line[i:i + 3]) + b"\xff" for i in range(0, stride, 3)))
        rows.append(line)
    return width, height, rows


# The artist's exports are only 88-99% opaque inside the art, which lets the minimap show
# through the icon. Alpha at or above this counts as solid; the soft edge below it is
# stretched to match.
SOLID = 192


def solidify(rows):
    for row in rows:
        for i in range(3, len(row), 4):
            a = row[i]
            row[i] = 255 if a >= SOLID else round(a * 255 / SOLID)
    return rows


def write_tga(path, width, height, rows):
    # Uncompressed true-color, 32 bits, 8 alpha bits, top-left origin. TGA stores BGRA.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    body = bytearray()
    for row in rows:
        for i in range(0, len(row), 4):
            r, g, b, a = row[i:i + 4]
            body += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(header + body)


def main():
    os.makedirs(TEXTURES, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for source, target, size in JOBS:
            resized = os.path.join(tmp, source)
            subprocess.run(
                ["sips", "-z", str(size), str(size), "-s", "format", "png",
                 os.path.join(ROOT, "art", source), "--out", resized],
                check=True, stdout=subprocess.DEVNULL)
            width, height, rows = read_png_rgba(resized)
            write_tga(os.path.join(TEXTURES, target), width, height, solidify(rows))
            print(f"Wrote addon/Tamer/Textures/{target} ({width}x{height})")


if __name__ == "__main__":
    main()
