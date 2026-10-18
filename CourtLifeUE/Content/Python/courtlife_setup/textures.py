"""Tiny dependency-free texture writer (no ``unreal`` import).

``setup_project`` uses it to write placeholder default textures (a solid
color mask, a transparent tattoo atlas) that are then imported into Unreal,
because a TextureSampleParameter2D must reference a texture to compile.
"""

from __future__ import annotations

import struct
from typing import Iterable, Tuple

RGBA = Tuple[int, int, int, int]


def tga_bytes(width: int, height: int, pixels: Iterable[RGBA]) -> bytes:
    """Uncompressed 32-bit BGRA TGA, top-left origin. ``pixels`` row-major RGBA."""
    if not (0 < width < 65536 and 0 < height < 65536):
        raise ValueError("bad TGA size")
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,      # id length
        0,      # no color map
        2,      # uncompressed true-color
        0, 0, 0,  # color map spec
        0, 0,   # x/y origin
        width, height,
        32,     # bits per pixel
        0x28,   # 8 alpha bits + top-left origin
    )
    body = bytearray()
    count = 0
    for r, g, b, a in pixels:
        for c in (r, g, b, a):
            if not 0 <= c <= 255:
                raise ValueError("channel out of range")
        body += bytes((b, g, r, a))
        count += 1
    if count != width * height:
        raise ValueError(f"expected {width * height} pixels, got {count}")
    return header + bytes(body)


def write_solid_tga(path: str, rgba: RGBA, size: int = 4) -> str:
    with open(path, "wb") as f:
        f.write(tga_bytes(size, size, [rgba] * (size * size)))
    return path
