#!/usr/bin/env python3
"""Validates the CourtLife tattoo stencils written by gen_tattoos.py.

Checks, per image-based design:
  * file exists, PNG, RGBA, 1024x1024 (power of two)
  * B == 0 everywhere, A == max(R, G) (so A >= max(R, G)), and fully
    transparent pixels carry no colour
  * coverage is non-empty and sensible (ink present; accent present where the
    design uses it)
  * margins: placed designs keep a clear border on all four sides; limb-wrapping
    designs (band, geometric) keep a clear border top and bottom only
  * wrapping designs tile seamlessly: the seam (right column -> left column)
    differs no more than ordinary neighbouring columns inside the image
Also checks that every key in courtlife/src/core/catalog.js TATTOO_DESIGNS is
either a stencil here or a known text design, so build codes keep working.

Exit code 0 when everything passes.
"""
from __future__ import annotations

import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
TATTOO_DIR = os.path.normpath(os.path.join(HERE, "..", "Tattoos"))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
CATALOG = os.path.join(REPO, "courtlife", "src", "core", "catalog.js")

SIZE = 1024
MARGIN = 40                     # px of empty border required
STENCILS = ["tribal", "band", "rose", "stars", "crown", "geometric",
            "flames", "clock", "praying", "waves"]
TEXT_DESIGNS = {"script", "number"}
WRAP = {"band", "geometric"}
USES_ACCENT = {"rose", "stars", "crown", "flames", "clock", "praying", "waves"}

failures: list[str] = []


def check(cond, msg):
    if not cond:
        failures.append(msg)
    return cond


def tex_name(key):
    return "T_Tattoo_%s.png" % (key[0].upper() + key[1:])


def catalog_keys():
    src = open(CATALOG, encoding="utf-8").read()
    m = re.search(r"TATTOO_DESIGNS\s*=\s*\{(.*?)\}", src, re.S)
    if not m:
        return None
    return re.findall(r"^\s*(\w+)\s*:", m.group(1), re.M)


def main():
    keys = catalog_keys()
    if check(keys is not None, "could not parse TATTOO_DESIGNS in %s" % CATALOG):
        for k in keys:
            check(k in STENCILS or k in TEXT_DESIGNS, "catalog key '%s' has no stencil and is not a text design" % k)
        for k in STENCILS:
            check(k in keys, "stencil '%s' is not a catalog key" % k)
    for k in TEXT_DESIGNS:
        check(not os.path.exists(os.path.join(TATTOO_DIR, tex_name(k))), "text design '%s' should not have a stencil" % k)

    print("%-10s %8s %8s %6s %6s %6s %6s  %s" % ("design", "ink%", "accent%", "top", "bot", "left", "right", "seam"))
    for key in STENCILS:
        path = os.path.join(TATTOO_DIR, tex_name(key))
        if not check(os.path.exists(path), "%s: missing %s" % (key, path)):
            continue
        im = Image.open(path)
        check(im.format == "PNG", "%s: not a PNG" % key)
        check(im.mode == "RGBA", "%s: mode %s, expected RGBA" % (key, im.mode))
        check(im.size == (SIZE, SIZE), "%s: size %s, expected %dx%d" % (key, im.size, SIZE, SIZE))
        a = np.asarray(im.convert("RGBA")).astype(np.int32)
        R, G, B, A = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
        check(B.max() == 0, "%s: B channel not zero (max %d)" % (key, B.max()))
        check(np.all(A >= np.maximum(R, G)), "%s: A < max(R,G) somewhere" % key)
        check(np.all(A == np.maximum(R, G)), "%s: A != max(R,G) somewhere" % key)
        check(np.all(a[A == 0][:, :3] == 0), "%s: transparent pixels carry colour" % key)
        ink = (R > 127).mean() * 100
        acc = (G > 127).mean() * 100
        check(ink > 1.0, "%s: ink coverage too low (%.2f%%)" % (key, ink))
        check(ink < 60.0, "%s: ink coverage implausibly high (%.2f%%)" % (key, ink))
        if key in USES_ACCENT:
            check(acc > 0.5, "%s: accent coverage too low (%.2f%%)" % (key, acc))
        # margins = empty rows/cols from each edge
        rows = np.where(A.max(1) > 0)[0]
        cols = np.where(A.max(0) > 0)[0]
        top, bot = int(rows.min()), int(SIZE - 1 - rows.max())
        left, right = int(cols.min()), int(SIZE - 1 - cols.max())
        check(top >= MARGIN and bot >= MARGIN, "%s: vertical margin %d/%d < %d" % (key, top, bot, MARGIN))
        seam_txt = "-"
        if key in WRAP:
            # must reach both edges and the seam must be as smooth as the interior
            check(left == 0 and right == 0, "%s: wrap design does not reach both edges" % key)
            f = a.astype(np.float64)
            interior = np.abs(np.diff(f[:, :, :], axis=1)).mean(axis=(0, 2))   # per column pair
            seam = np.abs(f[:, -1] - f[:, 0]).mean()
            limit = np.percentile(interior, 99)
            # exact-content check: the edge columns' coverage profiles match their
            # neighbours across the seam as closely as interior neighbours do
            seam_txt = "%.3f (interior p99 %.3f)" % (seam, limit)
            check(seam <= limit + 1e-9, "%s: seam diff %.3f exceeds interior p99 %.3f" % (key, seam, limit))
            # rolled image must look identical in structure: compare coverage of the
            # left and right edge columns
            cov_l, cov_r = (A[:, 0] > 0).sum(), (A[:, -1] > 0).sum()
            check(abs(cov_l - cov_r) <= max(8, 0.1 * max(cov_l, cov_r)),
                  "%s: edge column coverage mismatch %d vs %d" % (key, cov_l, cov_r))
        else:
            check(left >= MARGIN and right >= MARGIN, "%s: horizontal margin %d/%d < %d" % (key, left, right, MARGIN))
            # roughly centred: bbox centre within 6% of the canvas centre
            cx = (cols.min() + cols.max()) / 2
            cy = (rows.min() + rows.max()) / 2
            check(abs(cx - SIZE / 2) < 0.06 * SIZE and abs(cy - SIZE / 2) < 0.06 * SIZE,
                  "%s: not centred (bbox centre %.0f,%.0f)" % (key, cx, cy))
        print("%-10s %8.2f %8.2f %6d %6d %6d %6d  %s" % (key, ink, acc, top, bot, left, right, seam_txt))

    if failures:
        print("\nFAILED (%d):" % len(failures))
        for f in failures:
            print("  -", f)
        return 1
    print("\nAll tattoo stencil checks passed (%d stencils)." % len(STENCILS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
