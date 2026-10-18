#!/usr/bin/env python3
"""CourtLife production tattoo stencil generator.

Writes one 1024x1024 RGBA stencil per image-based tattoo design to
CourtLifeUE/SourceArt/Characters/Tattoos/T_Tattoo_<Key>.png, plus a contact
sheet (_preview.png) that composites every stencil on a light and a dark skin
tone.

Encoding (contract, see CLAssets.h FCLTattooDesign and Docs/Art/Characters/TATTOOS.md):
    R = ink coverage (black linework, solid black, stipple/hatch shading)
    G = accent coverage (colour fill: rose petals, crown gold, flame fill...)
    B = 0
    A = max(R, G)
    Background fully transparent (0,0,0,0).

Design keys match courtlife/src/core/catalog.js TATTOO_DESIGNS. 'script' and
'number' are text designs (bDrawsText) and have no stencil.

All art is authored in 1024-unit coordinates, rasterised at 4x (4096^2) with
Pillow and box-downsampled for clean anti-aliased edges. Every random choice
uses a fixed seed, so the output is byte-for-byte reproducible for a given
Pillow/numpy version.

Usage:
    python3 gen_tattoos.py                 # all designs + preview
    python3 gen_tattoos.py rose crown      # only these designs (+ preview of all on disk)
    python3 gen_tattoos.py --no-preview
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFont

N = 1024          # output size
SS = 4            # supersample factor
M = N * SS        # working raster size

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "Tattoos"))

# Image-based design keys (catalog.js order). Text designs: script, number.
DESIGN_KEYS = ["tribal", "band", "rose", "stars", "crown", "geometric",
               "flames", "clock", "praying", "waves"]
DISPLAY_NAMES = {
    "tribal": "Tribal", "band": "Barbed Band", "rose": "Rose", "stars": "Stars",
    "crown": "Crown", "geometric": "Geometric Sleeve", "flames": "Flames",
    "clock": "Clock", "praying": "Cross", "waves": "Waves",
}
WRAP_KEYS = {"band", "geometric"}   # bWrapsLimb: must tile horizontally


def tex_name(key: str) -> str:
    return "T_Tattoo_%s.png" % (key[0].upper() + key[1:])


# --------------------------------------------------------------------------
# Geometry helpers (all in 1024-unit space)
# --------------------------------------------------------------------------

def bez(p0, p1, p2, p3, n=64):
    t = np.linspace(0.0, 1.0, n)[:, None]
    p0, p1, p2, p3 = (np.asarray(p, float) for p in (p0, p1, p2, p3))
    return ((1 - t) ** 3) * p0 + 3 * ((1 - t) ** 2) * t * p1 + 3 * (1 - t) * t * t * p2 + (t ** 3) * p3


def spline(points, closed=False, n_per=40):
    """Catmull-Rom spline through points."""
    P = np.asarray(points, float)
    if closed:
        P = np.vstack([P[-1], P, P[0], P[1]])
    else:
        P = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        t = np.linspace(0, 1, n_per, endpoint=False)[:, None]
        t2, t3 = t * t, t * t * t
        seg = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
        out.append(seg)
    if not closed:
        out.append(P[-2][None, :])
    return np.vstack(out)


def resample(pts, step=1.0, closed=False):
    P = np.asarray(pts, float)
    if closed:
        P = np.vstack([P, P[:1]])
    d = np.hypot(*np.diff(P, axis=0).T)
    s = np.concatenate([[0], np.cumsum(d)])
    total = s[-1]
    if total <= 1e-9:
        return P[:1]
    n = max(2, int(total / step) + 1)
    u = np.linspace(0, total, n)
    if closed:
        u = u[:-1]
    x = np.interp(u, s, P[:, 0])
    y = np.interp(u, s, P[:, 1])
    return np.stack([x, y], 1)


def arclen_t(P):
    d = np.hypot(*np.diff(P, axis=0).T)
    s = np.concatenate([[0], np.cumsum(d)])
    return s / max(s[-1], 1e-9)


def normals(P, closed=False):
    if closed:
        T = np.roll(P, -1, 0) - np.roll(P, 1, 0)
    else:
        T = np.gradient(P, axis=0)
    L = np.hypot(T[:, 0], T[:, 1])[:, None]
    T = T / np.maximum(L, 1e-9)
    return np.stack([-T[:, 1], T[:, 0]], 1)


def signed_area(P):
    x, y = P[:, 0], P[:, 1]
    return 0.5 * np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y)


def outward_normals(P):
    """Outward normals for a closed polygon (y-down image space)."""
    T = np.roll(P, -1, 0) - np.roll(P, 1, 0)
    T /= np.maximum(np.hypot(T[:, 0], T[:, 1])[:, None], 1e-9)
    n = np.stack([T[:, 1], -T[:, 0]], 1)
    return n if signed_area(P) > 0 else -n


def smooth_circ(v, k=9):
    if k <= 1:
        return v
    ker = np.ones(k) / k
    pad = np.concatenate([v[-k:], v, v[:k]])
    return np.convolve(pad, ker, mode="same")[k:-k]


SHADOW_DIR = np.array([0.45, 0.89])  # light from top-left: heavy lines bottom-right


def weighted_widths(P, base, heavy=0.9, shadow=SHADOW_DIR):
    n = outward_normals(P)
    f = np.clip(n @ (shadow / np.linalg.norm(shadow)), 0, 1)
    return smooth_circ(base * (1 + heavy * f ** 1.2), 11)


def taper(t, wmax, peak=0.4, p=0.8, w0=0.0, w1=0.0):
    t = np.asarray(t, float)
    peak = min(max(peak, 1e-6), 1 - 1e-6)
    a = np.where(t < peak, np.sin(0.5 * np.pi * np.clip(t / peak, 0, 1)),
                 np.cos(0.5 * np.pi * np.clip((t - peak) / (1 - peak), 0, 1)))
    a = np.clip(a, 0, 1) ** p
    lo = np.where(t < peak, w0, w1)
    return lo + (wmax - lo) * a


def blade(spine, prof, step=1.0):
    """Closed polygon of a variable-width stroke (pointed where width==0)."""
    P = resample(spine, step)
    t = arclen_t(P)
    w = prof(t) if callable(prof) else np.full(len(P), prof)
    n = normals(P)
    L = P + n * (w[:, None] / 2)
    R = P - n * (w[:, None] / 2)
    return np.vstack([L, R[::-1]])


def mirror(P, cx=512.0):
    P = np.asarray(P, float).copy()
    P[:, 0] = 2 * cx - P[:, 0]
    return P


def circle_pts(c, r, n=360, a0=0.0, a1=2 * math.pi, ry=None):
    a = np.linspace(a0, a1, n, endpoint=(abs(a1 - a0 - 2 * math.pi) > 1e-6))
    ry = r if ry is None else ry
    return np.stack([c[0] + r * np.cos(a), c[1] + ry * np.sin(a)], 1)


def rot(P, ang, c=(0, 0)):
    P = np.asarray(P, float)
    ca, sa = math.cos(ang), math.sin(ang)
    Q = P - c
    return np.stack([Q[:, 0] * ca - Q[:, 1] * sa, Q[:, 0] * sa + Q[:, 1] * ca], 1) + c


def offset_closed(P, d):
    """Naive inward(-)/outward(+) offset of a smooth closed polygon."""
    return P + outward_normals(P) * d


# --------------------------------------------------------------------------
# Canvas: two coverage layers (ink, accent) at 4x, painter's-algorithm ops
# --------------------------------------------------------------------------

class Canvas:
    def __init__(self, wrap=False):
        self.wrap = wrap
        self.off = (0.0, 0.0)   # global translation (1024 units) applied at raster time
        self.ink = Image.new("L", (M, M), 0)
        self.acc = Image.new("L", (M, M), 0)

    # -- low level -------------------------------------------------------
    @staticmethod
    def blank():
        return Image.new("L", (M, M), 0)

    def shifts(self):
        return (-N, 0, N) if self.wrap else (0,)

    def _sc(self, P, dx=0.0):
        P = np.asarray(P, float)
        ox, oy = self.off
        return [((x + dx + ox) * SS, (y + oy) * SS) for x, y in P]

    def poly(self, img, P, fill=255):
        d = ImageDraw.Draw(img)
        for dx in self.shifts():
            d.polygon(self._sc(P, dx), fill=fill)

    def disc(self, img, c, r, fill=255):
        d = ImageDraw.Draw(img)
        for dx in self.shifts():
            x, y = (c[0] + dx + self.off[0]) * SS, (c[1] + self.off[1]) * SS
            rr = r * SS
            d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=fill)

    def stroke(self, img, P, w, fill=255, closed=False, caps=True, step=0.8):
        """Variable width polyline. w: scalar, array (per input point), or f(t)."""
        P0 = np.asarray(P, float)
        if callable(w):
            P = resample(P0, step, closed)
            ww = w(arclen_t(P)) if not closed else w(np.linspace(0, 1, len(P), endpoint=False))
        elif np.ndim(w) == 0:
            P = resample(P0, step, closed)
            ww = np.full(len(P), float(w))
        else:
            # resample widths alongside points
            Pc = np.vstack([P0, P0[:1]]) if closed else P0
            wc = np.concatenate([w, w[:1]]) if closed else np.asarray(w, float)
            d = np.hypot(*np.diff(Pc, axis=0).T)
            s = np.concatenate([[0], np.cumsum(d)])
            n = max(2, int(s[-1] / step) + 1)
            u = np.linspace(0, s[-1], n)
            if closed:
                u = u[:-1]
            P = np.stack([np.interp(u, s, Pc[:, 0]), np.interp(u, s, Pc[:, 1])], 1)
            ww = np.interp(u, s, wc)
        n = normals(P, closed)
        P = P + np.asarray(self.off)
        L = (P + n * (ww[:, None] / 2)) * SS
        R = (P - n * (ww[:, None] / 2)) * SS
        d = ImageDraw.Draw(img)
        cnt = len(P) if closed else len(P) - 1
        for dx in self.shifts():
            o = np.array([dx * SS, 0])
            for i in range(cnt):
                j = (i + 1) % len(P)
                quad = [tuple(L[i] + o), tuple(L[j] + o), tuple(R[j] + o), tuple(R[i] + o)]
                d.polygon(quad, fill=fill)
            # joint/cap discs keep joins solid on curves
            for i in range(len(P)):
                if not caps and not closed and (i == 0 or i == len(P) - 1):
                    continue
                r = ww[i] * SS / 2
                if r < 0.6:
                    continue
                x, y = P[i, 0] * SS + o[0], P[i, 1] * SS
                d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

    def mask_poly(self, P):
        m = self.blank()
        self.poly(m, P)
        return m

    # -- high level ink/accent ops ------------------------------------------
    def ink_poly(self, P):
        self.poly(self.ink, P, 255)

    def ink_erase_poly(self, P):
        self.poly(self.ink, P, 0)

    def acc_poly(self, P, value=255):
        self.poly(self.acc, P, value)

    def acc_erase_poly(self, P):
        self.poly(self.acc, P, 0)

    def ink_stroke(self, P, w, **kw):
        self.stroke(self.ink, P, w, 255, **kw)

    def ink_erase_stroke(self, P, w, **kw):
        self.stroke(self.ink, P, w, 0, **kw)

    def ink_disc(self, c, r):
        self.disc(self.ink, c, r, 255)

    def ink_erase_disc(self, c, r):
        self.disc(self.ink, c, r, 0)

    def ink_layer(self, layer, clip=None):
        if clip is not None:
            layer = ImageChops.multiply(layer, clip)
        self.ink = ImageChops.lighter(self.ink, layer)

    def ink_erase_mask(self, mask):
        self.ink = ImageChops.subtract(self.ink, mask)

    def acc_layer(self, layer, clip=None):
        if clip is not None:
            layer = ImageChops.multiply(layer, clip)
        self.acc = ImageChops.lighter(self.acc, layer)

    def shape(self, P, base=7.0, heavy=0.9, accent=True, erase=True, line=True):
        """Painter's-algorithm filled shape: occludes what is behind it, fills
        accent, and draws a weighted outline (heavier toward bottom-right)."""
        P = resample(P, 1.0, closed=True)
        if erase:
            self.ink_erase_poly(P)
        if accent:
            self.acc_poly(P)
        elif erase:
            self.acc_erase_poly(P)
        if line:
            self.ink_stroke(P, weighted_widths(P, base, heavy), closed=True)
        return P

    # -- shading -------------------------------------------------------------
    def stipple(self, density, bbox, clip=None, spacing=7.0, r=(1.0, 1.9), seed=1, gamma=1.0):
        """Jittered-grid dotwork. density(x, y) -> 0..1 (vectorised, 1024 units).
        bbox in 1024 units. clip: L mask image at working res."""
        rng = np.random.default_rng(seed)
        x0, y0, x1, y1 = bbox
        gx = np.arange(x0, x1, spacing)
        gy = np.arange(y0, y1, spacing * 0.866)
        X, Y = np.meshgrid(gx, gy)
        X = X + (np.arange(len(gy))[:, None] % 2) * spacing * 0.5
        X = X + rng.uniform(-0.42, 0.42, X.shape) * spacing
        Y = Y + rng.uniform(-0.42, 0.42, Y.shape) * spacing
        X, Y = X.ravel(), Y.ravel()
        if self.wrap:
            X = np.mod(X, N)
        D = np.clip(density(X, Y), 0, 1) ** gamma
        keep = rng.random(len(X)) < D
        X, Y, D = X[keep], Y[keep], D[keep]
        R = (r[0] + (r[1] - r[0]) * np.sqrt(D) * rng.uniform(0.75, 1.0, len(D))) * SS
        layer = self.blank()
        d = ImageDraw.Draw(layer)
        for dx in self.shifts():
            for x, y, rr in zip((X + dx + self.off[0]) * SS, (Y + self.off[1]) * SS, R):
                d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=255)
        self.ink_layer(layer, clip)

    def hatch(self, angle_deg, spacing, width, bbox, clip=None, wfn=None):
        """Parallel lines across bbox; width may vary per line via wfn(x,y)."""
        layer = self.blank()
        x0, y0, x1, y1 = bbox
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        rad = math.hypot(x1 - x0, y1 - y0) / 2 + spacing
        a = math.radians(angle_deg)
        dvec = np.array([math.cos(a), math.sin(a)])
        nvec = np.array([-dvec[1], dvec[0]])
        k = -rad
        while k <= rad:
            c = np.array([cx, cy]) + nvec * k
            P = np.stack([c - dvec * rad, c + dvec * rad])
            P = resample(P, 4.0)
            if wfn is not None:
                w = np.clip(wfn(P[:, 0], P[:, 1]), 0, None)
            else:
                w = np.full(len(P), width)
            self.stroke(layer, P, w, caps=False, step=2.0)
            k += spacing
        self.ink_layer(layer, clip)

    # -- output --------------------------------------------------------------
    def finish(self):
        r = np.asarray(self.ink.reduce(SS), np.uint8)
        g = np.asarray(self.acc.reduce(SS), np.uint8)
        a = np.maximum(r, g)
        b = np.zeros_like(r)
        rgba = np.dstack([r, g, b, a])
        rgba[a == 0] = 0
        return Image.fromarray(rgba, "RGBA")


def dens_radial(c, r0, r1, p=1.5):
    """1 inside r0, falling to 0 at r1."""
    def f(x, y):
        d = np.hypot(x - c[0], y - c[1])
        return np.clip((r1 - d) / max(r1 - r0, 1e-6), 0, 1) ** p
    return f


def dens_linear(p0, p1, p=1.5):
    """1 at p0, 0 at p1 (projected)."""
    p0 = np.asarray(p0, float)
    v = np.asarray(p1, float) - p0
    L2 = float(v @ v)

    def f(x, y):
        t = ((x - p0[0]) * v[0] + (y - p0[1]) * v[1]) / L2
        return np.clip(1 - t, 0, 1) ** p
    return f


# --------------------------------------------------------------------------
# Designs
# --------------------------------------------------------------------------

def d_tribal():
    c = Canvas()
    shapes = []
    # central spear with concave sides
    shapes.append(blade([(512, 92), (512, 934)], lambda t: taper(t, 96, peak=0.44, p=1.8)))
    # upper wing: sweeps up and out to a long point
    shapes.append(blade(spline([(506, 470), (560, 360), (650, 262), (760, 192), (900, 140)]),
                        lambda t: taper(t, 96, peak=0.22, p=0.85, w0=14)))
    # spikes hanging off the underside of the wing
    shapes.append(blade(spline([(690, 262), (720, 315), (735, 372)]), lambda t: taper(t, 34, peak=0.12, p=1.0, w0=26)))
    shapes.append(blade(spline([(800, 196), (830, 240), (850, 290)]), lambda t: taper(t, 26, peak=0.12, p=1.0, w0=20)))
    # middle blade pointing outward
    shapes.append(blade(spline([(506, 560), (600, 490), (740, 458), (870, 478), (930, 500)]),
                        lambda t: taper(t, 58, peak=0.30, p=0.85, w0=12)))
    # lower hook curling back in toward the spear
    shapes.append(blade(spline([(506, 640), (620, 648), (745, 700), (812, 790), (790, 870), (720, 900), (650, 880), (620, 840)]),
                        lambda t: taper(t, 82, peak=0.36, p=0.75, w0=12)))
    # barb off the lower hook
    shapes.append(blade(spline([(790, 735), (850, 700), (900, 690)]), lambda t: taper(t, 30, peak=0.15, p=1.0, w0=24)))
    # small inner flick inside the hook
    shapes.append(blade(spline([(600, 735), (660, 760), (700, 800), (705, 840)]), lambda t: taper(t, 30, peak=0.35, p=0.9)))
    for s in shapes:
        c.ink_poly(s)
        c.ink_poly(mirror(s))
    # negative-space slits in the spear
    c.ink_erase_poly(blade([(512, 250), (512, 470)], lambda t: taper(t, 20, peak=0.55, p=1.2)))
    c.ink_erase_poly(blade([(512, 560), (512, 780)], lambda t: taper(t, 16, peak=0.45, p=1.2)))
    return c


def d_band():
    c = Canvas(wrap=True)
    cy = 512.0
    period = 128.0          # half-twist length: 8 crossings per 1024 tile
    amp = 24.0
    ww = 18.0

    def strand(sign, x0, x1):
        x = np.arange(x0, x1 + 0.01, 1.0)
        return np.stack([x, cy + sign * amp * np.sin(np.pi * x / period)], 1)

    def highlight(seg):
        k = len(seg)
        a, b = int(k * 0.15), int(k * 0.85)
        hl = seg[a:b] + np.array([0.0, -ww * 0.2])
        if len(hl) > 4:
            c.ink_erase_stroke(hl, lambda t: taper(t, 3.6, peak=0.5, p=0.6))

    # both strands in full, with highlights on the open (non-crossing) stretches
    for sign in (1, -1):
        c.ink_stroke(strand(sign, -64, N + 64), ww)
    for k in range(8):
        for sign in (1, -1):
            highlight(strand(sign, k * period + 26, (k + 1) * period - 26))
    # at each crossing the strand heading down-right passes in front
    for k in range(8):
        xc = k * period
        sign = 1 if k % 2 == 0 else -1
        seg = strand(sign, xc - 40, xc + 40)
        c.ink_erase_stroke(seg[6:-6], ww + 10, caps=False)
        c.ink_stroke(seg, ww, caps=False)
        highlight(seg)

    # barbs between crossings, 4 per tile
    for j in range(4):
        x = j * 256.0 + 64.0
        for ang, ln in ((60.0, 66.0), (-55.0, 62.0)):
            a = math.radians(ang)
            d = np.array([math.cos(a), math.sin(a)])
            p0 = np.array([x, cy]) - d * ln
            p1 = np.array([x, cy]) + d * ln
            c.ink_erase_poly(blade([p0 - d * 4, p1 + d * 4], lambda t: taper(t, 22, peak=0.5, p=0.3)))
            c.ink_poly(blade([p0, p1], lambda t: taper(t, 13, peak=0.5, p=0.3)))
        # coil wrapped around both strands and the barb roots
        for dxk in (-11.0, 0.0, 11.0):
            coil = bez((x + dxk - 9, cy - 34), (x + dxk + 12, cy - 12), (x + dxk - 12, cy + 12), (x + dxk + 9, cy + 34), 40)
            c.ink_erase_stroke(coil, 16, caps=True)
            c.ink_stroke(coil, 10.0, caps=True)
            c.ink_erase_stroke(coil[10:22] + np.array([-2.5, 0]), 2.2)
    # framing rules
    for y, w in ((cy - 86, 7.0), (cy - 102, 3.0), (cy + 86, 7.0), (cy + 102, 3.0)):
        c.ink_stroke([(-10, y), (N + 10, y)], w, caps=False)
    return c


def d_rose():
    c = Canvas()
    cx, cy = 512.0, 430.0

    # ---- leaves (behind the bloom) ----
    def leaf(base, tip, bulge, flip, seed):
        base, tip = np.asarray(base, float), np.asarray(tip, float)
        v = tip - base
        L = np.linalg.norm(v)
        u = v / L
        n = np.array([-u[1], u[0]])
        ts = np.linspace(0, 1, 60)
        prof = np.sin(np.pi * ts ** 0.85) * bulge
        side1 = base + np.outer(ts, v) + np.outer(prof * 1.0, n)
        side2 = base + np.outer(ts, v) - np.outer(prof * 0.85, n)
        # notch on side1
        P = np.vstack([side1, side2[::-1][1:-1]])
        P = c.shape(P, base=7.5, heavy=0.9, accent=False)
        mask = c.mask_poly(P)
        # vein
        vein = base + np.outer(ts[:52], v) + np.outer(np.sin(np.pi * ts[:52]) * bulge * 0.12, n)
        c.ink_stroke(vein, lambda t: taper(t, 6.0, peak=0.1, p=0.8, w0=6.0))
        # side veins
        for k in range(1, 5):
            t0 = k / 5.6
            p0 = base + v * t0 + n * (np.sin(np.pi * t0) * bulge * 0.12)
            for s in (1, -0.85):
                p1 = p0 + v * 0.13 + n * bulge * 0.55 * s * np.sin(np.pi * (t0 + 0.08))
                c.ink_stroke(bez(p0, p0 + v * 0.05 + n * s * 10, p1 - v * 0.04, p1, 20), lambda t: taper(t, 3.4, peak=0.05, p=1.0, w0=3.4))
        # shade the far half of the leaf with dotwork, dense near the vein
        side = flip

        def dens(x, y):
            q = np.stack([x - base[0], y - base[1]], 1)
            along = q @ u / L
            across = q @ n
            hs = (across * side < 0)
            base_d = np.clip(1 - np.abs(across) / (bulge * 0.95), 0, 1)
            return hs * (0.45 + 0.55 * base_d) * np.clip(np.sin(np.pi * np.clip(along, 0, 1)) * 1.4, 0, 1)
        bb = (min(base[0], tip[0]) - bulge, min(base[1], tip[1]) - bulge, max(base[0], tip[0]) + bulge, max(base[1], tip[1]) + bulge)
        c.stipple(dens, bb, clip=mask, spacing=4.8, r=(1.0, 2.1), seed=seed)

    leaf((470, 620), (130, 745), 95, 1, 21)
    leaf((560, 620), (900, 735), 92, -1, 22)
    leaf((500, 650), (430, 905), 60, -1, 23)

    # ---- bloom ----
    def petal_shade(P, anchor, r0, r1, seed, cap=1.0, spacing=5.5):
        mask = c.mask_poly(P)
        d0 = dens_radial(anchor, r0, r1, p=1.6)
        bb = (P[:, 0].min(), P[:, 1].min(), P[:, 0].max(), P[:, 1].max())
        c.stipple(lambda x, y: d0(x, y) * cap, bb, clip=mask, spacing=spacing, r=(1.0, 2.1), seed=seed)

    # filler behind the bloom so no skin shows between petals; the gaps that
    # stay visible are the deepest shadows, so pack them with dotwork
    fill = c.shape(circle_pts((512, 400), 200, 300, ry=170), base=6.0)
    c.stipple(dens_radial((512, 392), 20, 70, 1.0), (300, 230, 724, 570), clip=c.mask_poly(fill), spacing=3.6, r=(1.4, 2.2), seed=30)
    # back petals (outer silhouette), drawn back to front
    back_l = spline([(330, 430), (270, 330), (300, 230), (390, 185), (470, 215), (500, 300), (470, 420)], closed=True, n_per=30)
    back_r = mirror(back_l)
    back_t = spline([(400, 260), (430, 175), (512, 140), (594, 175), (624, 260), (512, 330)], closed=True, n_per=30)
    for P, anc, sd in ((back_t, (512, 300), 31), (back_l, (470, 400), 32), (back_r, (554, 400), 33)):
        P = c.shape(P, base=6.5)
        petal_shade(P, anc, 10, 150, sd, cap=0.85)
    # rolled lips on back petals (turned-over edge)
    for lip in (spline([(300, 250), (350, 205), (420, 200)]), mirror(spline([(300, 250), (350, 205), (420, 200)])),
                spline([(445, 190), (512, 165), (579, 190)])):
        c.ink_stroke(lip, lambda t: taper(t, 5.0, peak=0.5, p=0.7, w0=1.5, w1=1.5))

    # inner cup / bud spiral
    cup = spline([(420, 340), (440, 270), (512, 240), (584, 270), (604, 340), (512, 380)], closed=True, n_per=30)
    cup = c.shape(cup, base=6.0)
    petal_shade(cup, (512, 330), 0, 120, 34, cap=0.95)
    spiral = []
    for k in range(260):
        t = k / 259.0
        a = -math.pi * 0.5 + t * math.pi * 3.2
        r = 62 * (1 - 0.82 * t)
        spiral.append((512 + r * math.cos(a) * 1.25, 300 + r * math.sin(a) * 0.62))
    spiral = np.array(spiral)
    c.ink_erase_stroke(spiral, 12)
    c.ink_stroke(spiral, lambda t: taper(t, 7.5, peak=0.15, p=0.7, w0=4.0, w1=2.0))

    # side front petals
    side_l = spline([(300, 470), (282, 380), (330, 320), (420, 330), (470, 420), (440, 520), (360, 540)], closed=True, n_per=30)
    side_r = mirror(side_l)
    for P, anc, sd in ((side_l, (450, 360), 35), (side_r, (574, 360), 36)):
        P = c.shape(P, base=7.0)
        petal_shade(P, anc, 5, 130, sd, cap=0.8)
    # front bowl petal with wavy lip
    top = spline([(300, 440), (370, 400), (450, 430), (512, 405), (574, 430), (654, 400), (724, 440)], n_per=40)
    bottom = spline([(724, 440), (712, 530), (650, 615), (512, 658), (374, 615), (312, 530), (300, 440)], n_per=40)
    bowl = np.vstack([top, bottom[1:-1]])
    bowl = c.shape(bowl, base=8.0, heavy=1.0)
    petal_shade(bowl, (512, 425), 10, 120, 37, cap=0.9)
    # fold lines on the bowl
    for fl in (spline([(380, 455), (400, 520), (440, 580)]), mirror(spline([(380, 455), (400, 520), (440, 580)])),
               spline([(512, 430), (505, 520), (512, 600)])):
        c.ink_stroke(fl, lambda t: taper(t, 4.0, peak=0.25, p=0.8))
    # turned lip under the wavy edge
    c.ink_stroke(spline([(330, 445), (380, 425), (450, 452), (512, 430), (574, 452), (644, 425), (694, 445)]),
                 lambda t: taper(t, 3.0, peak=0.5, p=0.5, w0=1.0, w1=1.0))
    return c


def star_pts(c, R, r, rot_deg=-90, n=5):
    pts = []
    for i in range(n * 2):
        a = math.radians(rot_deg) + i * math.pi / n
        rr = R if i % 2 == 0 else r
        pts.append((c[0] + rr * math.cos(a), c[1] + rr * math.sin(a)))
    return np.array(pts)


def d_stars():
    c = Canvas()

    def nautical(cen, R, angle, base_w):
        P = star_pts(cen, R, R * 0.42, angle)
        c.ink_erase_poly(P)
        c.acc_poly(P)
        n = len(P)
        for i in range(0, n, 2):
            tip = P[i]
            right = P[(i + 1) % n]
            c.ink_poly([tuple(cen), tuple(tip), tuple(right)])
        # outline
        Pr = resample(P, 1.0, closed=True)
        c.ink_stroke(Pr, weighted_widths(Pr, base_w, 0.7), closed=True)
        # inner ridge lines from centre to tips (on accent halves)
        for i in range(0, n, 2):
            c.ink_stroke([cen, P[i]], lambda t: taper(t, base_w * 0.55, peak=0.0, p=1.0, w0=base_w * 0.55))

    def outline_star(cen, R, angle, w, seed):
        P = star_pts(cen, R, R * 0.45, angle)
        Pr = resample(P, 1.0, closed=True)
        c.ink_erase_poly(Pr)
        c.acc_erase_poly(Pr)
        mask = c.mask_poly(Pr)
        c.stipple(dens_linear(cen + np.array([R * 0.5, R * 0.6]), cen - np.array([R * 0.6, R * 0.6]), p=1.2),
                  (cen[0] - R, cen[1] - R, cen[0] + R, cen[1] + R), clip=mask, spacing=5.0, r=(0.9, 1.7), seed=seed)
        c.ink_stroke(Pr, weighted_widths(Pr, w, 0.8), closed=True)

    def sparkle(cen, R, w):
        for ang in (0, 90):
            a = math.radians(ang)
            d = np.array([math.cos(a), math.sin(a)])
            c.ink_poly(blade([cen - d * R, cen + d * R], lambda t: taper(t, w, peak=0.5, p=2.2)))
        c.ink_disc(cen, w * 0.28)

    # cascade, big to small, top-left to bottom-right
    outline_star(np.array([770.0, 200.0]), 72, -80, 6.0, 41)
    outline_star(np.array([250.0, 820.0]), 62, -100, 5.5, 42)
    nautical(np.array([430.0, 440.0]), 250, -90, 9.0)
    nautical(np.array([735.0, 715.0]), 138, -76, 7.0)
    sparkle(np.array([880.0, 420.0]), 38, 18)
    sparkle(np.array([165.0, 230.0]), 34, 16)
    sparkle(np.array([560.0, 880.0]), 28, 13)
    # dot trail
    for (x, y, r) in ((640, 190, 6), (610, 150, 4), (880, 560, 5), (190, 640, 6), (150, 560, 4), (420, 860, 5)):
        c.ink_disc((x, y), r)
    return c


def d_crown():
    c = Canvas()
    c.off = (0.0, 86.0)   # authored high; centre the silhouette
    # silhouette of the crown top: tips and valleys joined by concave curves
    tips = [(262, 360), (380, 300), (512, 228), (644, 300), (762, 360)]
    valleys = [(330, 540), (450, 520), (574, 520), (694, 540)]
    base_y = 610.0
    path = [np.array([[270, base_y]])]
    pts = [tips[0]]
    for i in range(4):
        a, v, b = np.array(tips[i], float), np.array(valleys[i], float), np.array(tips[i + 1], float)
        path.append(bez(a, a + (v - a) * 0.15 + np.array([10, 60]), v + np.array([-30, -60]), v, 30))
        path.append(bez(v, v + np.array([30, -60]), b + (v - b) * 0.15 + np.array([-10, 60]), b, 30))
    top = np.vstack([np.array([[270, base_y]]), bez((270, base_y), (268, 500), (262, 420), tips[0], 30)] + path[1:] +
                    [bez(tips[-1], (762, 420), (756, 500), (754, base_y), 30)])
    top = c.shape(top, base=8.0)
    top_mask = c.mask_poly(top)
    # shading: dotwork rising from the valleys and the band
    def dens(x, y):
        d = np.clip((y - 430) / 180.0, 0, 1) ** 1.8 * 0.7
        for v in valleys:
            d = np.maximum(d, dens_radial(v, 0, 85, 1.6)(x, y) * 0.8)
        return d
    c.stipple(dens, (250, 220, 780, 620), clip=top_mask, spacing=5.5, r=(1.0, 2.0), seed=51)
    # centre ridges of each point (bevel line)
    for t, v0 in zip(tips, [(300, 590), (410, 590), (512, 590), (614, 590), (724, 590)]):
        c.ink_stroke(spline([t, ((t[0] + v0[0]) / 2 + 4, (t[1] + v0[1]) / 2), v0]), lambda tt: taper(tt, 4.0, peak=0.1, p=1.0, w0=2.0, w1=1.0))
    # band (slightly curved)
    band_top = bez((250, 600), (380, 640), (644, 640), (774, 600), 80)
    band_bot = bez((774, 712), (644, 752), (380, 752), (250, 712), 80)
    band = np.vstack([band_top, band_bot])
    band = c.shape(band, base=8.0, heavy=1.0)
    band_mask = c.mask_poly(band)
    c.stipple(lambda x, y: np.clip((y - 690) / 50.0, 0, 1) ** 1.3 * 0.9, (240, 600, 790, 760), clip=band_mask, spacing=5.0, r=(1.0, 1.9), seed=52)
    # band rims
    c.ink_stroke(bez((262, 622), (380, 660), (644, 660), (762, 622), 80), 3.5, caps=False)
    c.ink_stroke(bez((262, 692), (380, 732), (644, 732), (762, 692), 80), 3.5, caps=False)
    # gems on band
    def gem_oval(cen, rx, ry):
        P = circle_pts(cen, rx, 200, ry=ry)
        c.ink_poly(P)
        hl = circle_pts((cen[0] - rx * 0.25, cen[1] - ry * 0.25), rx * 0.55, 80, math.pi * 1.05, math.pi * 1.6, ry=ry * 0.55)
        c.ink_erase_stroke(hl, 4.0)
    def gem_diamond(cen, s):
        P = np.array([(cen[0], cen[1] - s), (cen[0] + s * 0.8, cen[1]), (cen[0], cen[1] + s), (cen[0] - s * 0.8, cen[1])])
        c.ink_erase_poly(P)
        c.ink_stroke(resample(P, 1.0, True), 4.5, closed=True)
        c.ink_poly(np.array([(cen[0], cen[1] - s), (cen[0] + s * 0.8, cen[1]), (cen[0], cen[1] + s)]))
    gem_oval((512, 690), 40, 26)
    gem_diamond((390, 680), 22)
    gem_diamond((634, 680), 22)
    for x in (300, 724):
        c.ink_disc((x, 668 if x < 512 else 668), 9)
    # balls on the tips
    for i, t in enumerate(tips):
        r = 26 if i == 2 else 21
        cen = (t[0], t[1] - r + 4)
        c.ink_erase_disc(cen, r + 4)
        c.acc_poly(circle_pts(cen, r, 120))
        c.ink_stroke(circle_pts(cen, r, 200), weighted_widths(circle_pts(cen, r, 200), 6.0), closed=True)
        c.ink_stroke(circle_pts((cen[0] + 3, cen[1] + 2), r * 0.62, 120, math.radians(-20), math.radians(110)), lambda tt: taper(tt, 5, peak=0.5, p=0.6))
        c.ink_erase_stroke(circle_pts((cen[0] - 2, cen[1] - 2), r * 0.55, 60, math.radians(200), math.radians(250)), 3.5)
    # cross on top of centre ball
    top_c = (512, tips[2][1] - 52 - 4)
    cr = np.array([(-10, -64), (10, -64), (10, -40), (30, -40), (30, -22), (10, -22), (10, 6), (-10, 6),
                   (-10, -22), (-30, -22), (-30, -40), (-10, -40)], float) + np.array(top_c) + np.array([0, -4])
    c.shape(cr, base=5.0, heavy=0.8)
    return c


def d_geometric():
    c = Canvas(wrap=True)
    cell = 128.0
    y_top, y_bot = 210.0, 814.0
    cy = 512.0
    # border rules and dot rows
    for y, w in ((y_top, 10.0), (y_top + 22, 3.5), (y_bot, 10.0), (y_bot - 22, 3.5)):
        c.ink_stroke([(-10, y), (N + 10, y)], w, caps=False)
    for k in range(16):
        x = k * 64.0 + 32.0
        c.ink_disc((x, y_top + 44), 5.0)
        c.ink_disc((x, y_bot - 44), 5.0)
    # triangles: top row points down, bottom row points up (offset half cell)
    tri_h = 112.0
    for k in range(8):
        x0 = k * cell
        # top row
        T = np.array([(x0 + 6, y_top + 62), (x0 + cell - 6, y_top + 62), (x0 + cell / 2, y_top + 62 + tri_h)])
        B = np.array([(x0 + cell / 2 + 6, y_bot - 62), (x0 + cell * 1.5 - 6, y_bot - 62), (x0 + cell, y_bot - 62 - tri_h)])
        for tri, solid, sd, apex in ((T, k % 2 == 0, 61 + k, T[2]), (B, k % 2 == 1, 71 + k, B[2])):
            Pr = resample(tri, 1.0, True)
            if solid:
                c.ink_poly(Pr)
                inner = tri + (tri.mean(0) - tri) * 0.55
                c.ink_erase_stroke(resample(inner, 1.0, True), 3.0, closed=True)
            else:
                c.ink_stroke(Pr, 4.0, closed=True)
                mask = c.mask_poly(tri + (tri.mean(0) - tri) * 0.12)
                base_mid = (tri[0] + tri[1]) / 2
                c.stipple(dens_linear(apex, base_mid, p=0.9), (tri[:, 0].min(), tri[:, 1].min(), tri[:, 0].max(), tri[:, 1].max()),
                          clip=mask, spacing=4.0, r=(1.0, 1.8), seed=sd)
    # central chain: circles with 6-petal flower, joined by lozenges
    R = 50.0
    for k in range(8):
        x = k * cell + cell / 2
        circ = circle_pts((x, cy), R, 240)
        c.ink_stroke(circ, 7.0, closed=True)
        c.ink_stroke(circle_pts((x, cy), R - 12, 200), 2.5, closed=True)
        # seed-of-life petals
        for i in range(6):
            a = i * math.pi / 3
            pc = (x + math.cos(a) * 19, cy + math.sin(a) * 19)
            c.ink_stroke(circle_pts(pc, 19, 120), 2.8, closed=True)
        c.ink_disc((x, cy), 5)
        # lozenge between circles
        xl = k * cell
        L = np.array([(xl, cy - 46), (xl + 15, cy), (xl, cy + 46), (xl - 15, cy)])
        c.ink_poly(L)
        c.ink_stroke([(xl - 64 + R + 4, cy), (xl - 15, cy)], 3.0)
        c.ink_stroke([(xl + 15, cy), (xl + 64 - R - 4, cy)], 3.0)
        # small diamonds above/below the chain
        for sgn in (-1, 1):
            yy = cy + sgn * 96
            D = np.array([(xl, yy - 12), (xl + 9, yy), (xl, yy + 12), (xl - 9, yy)])
            c.ink_poly(D)
    # graduated dot rows flanking the chain
    for sgn in (-1, 1):
        for k in range(32):
            x = k * 32.0 + 16.0
            c.ink_disc((x, cy + sgn * 78), 3.2 if k % 2 == 0 else 2.0)
    return c


def d_flames():
    c = Canvas()
    # (base, tip, sway amplitude, base width)
    tongues = [
        ((512, 700), (512, 104), 46, 150),
        ((450, 700), (330, 196), -40, 120),
        ((574, 700), (700, 170), 40, 120),
        ((395, 730), (200, 330), -34, 100),
        ((629, 730), (835, 300), 34, 100),
        ((350, 770), (148, 520), -26, 80),
        ((674, 770), (878, 488), 26, 80),
    ]
    polys, licks = [], []
    for (b, tip, A, w) in tongues:
        b, tip = np.array(b, float), np.array(tip, float)
        v = tip - b
        u = v / np.linalg.norm(v)
        n = np.array([-u[1], u[0]])
        ts = np.linspace(0, 1, 11)
        spine = np.array([b + v * t + n * A * math.sin(2 * math.pi * t * 0.9 + 0.2) * (0.35 + 0.65 * t) for t in ts])
        spine = spline(spine, n_per=16)
        polys.append(blade(spine, lambda t, w=w: w * (1 - t) ** 0.9 * (1 + 0.18 * np.sin(np.pi * t))))
        sl = spine[int(len(spine) * 0.18):int(len(spine) * 0.72)]
        licks.append(sl + n * (-A * 0.25) - u * 6)
    polys.append(circle_pts((512, 755), 225, 360, ry=128))
    # union outline: stroke all boundaries, then erase the union of interiors
    outline_layer = c.blank()
    interior = c.blank()
    for P in polys:
        Pr = resample(P, 1.0, closed=True)
        c.stroke(outline_layer, Pr, weighted_widths(Pr, 15.0, 0.8), closed=True)
        c.poly(interior, P, 255)
    c.ink_layer(outline_layer)
    c.ink_erase_mask(interior)
    c.acc_layer(interior)
    # dotwork darkening toward the tips (accent -> black gradient)
    c.stipple(lambda x, y: np.clip((600 - y) / 380.0, 0, 1) ** 1.2 * 0.97, (120, 90, 910, 640), clip=interior,
              spacing=4.6, r=(1.0, 2.2), seed=91)
    for lk in licks:
        c.ink_stroke(lk, lambda t: taper(t, 6.0, peak=0.45, p=0.7))
    # lower inner licks rising from the base
    for x0, x1, top in ((440, 470, 610), (584, 554, 610), (512, 512, 560)):
        c.ink_stroke(spline([(x0, 840), ((x0 + x1) / 2 + 8, 740), (x1, top)]), lambda t: taper(t, 6.0, peak=0.35, p=0.7))
    # detached flame sparks
    for (x, y, s, ang) in ((290, 130, 46, -22), (745, 105, 40, 20), (905, 250, 30, 32), (120, 300, 30, -32)):
        b = np.array([x, y + s * 0.5])
        a = math.radians(ang - 90)
        d = np.array([math.cos(a), math.sin(a)])
        nn = np.array([-d[1], d[0]])
        sp = spline([b, b + d * s * 0.5 + nn * 7, b + d * s - nn * 3])
        P = blade(sp, lambda t, s=s: s * 0.5 * (1 - t) ** 0.9 * np.sqrt(np.clip(t * 6, 0, 1)))
        c.shape(P, base=5.0, heavy=0.6)
    return c


def roman_glyph(ch, h):
    """Returns list of (pts, width_fn) strokes for I, V, X in a local box
    (x from 0, baseline y=0 at bottom, y negative up)."""
    thick, thin = h * 0.20, h * 0.07
    out = []
    if ch == "I":
        out.append(([(0.0, -h), (0.0, 0.0)], thick))
        out.append(([(-h * 0.18, -h), (h * 0.18, -h)], thin))
        out.append(([(-h * 0.18, 0), (h * 0.18, 0)], thin))
        return out, h * 0.42
    if ch == "V":
        out.append(([(-h * 0.32, -h), (0.0, 0.0)], thick))
        out.append(([(h * 0.32, -h), (0.0, 0.0)], thin))
        out.append(([(-h * 0.48, -h), (-h * 0.16, -h)], thin))
        out.append(([(h * 0.2, -h), (h * 0.44, -h)], thin))
        return out, h * 0.9
    if ch == "X":
        out.append(([(-h * 0.3, -h), (h * 0.3, 0.0)], thick))
        out.append(([(h * 0.3, -h), (-h * 0.3, 0.0)], thin))
        for y in (-h, 0.0):
            out.append(([(-h * 0.46, y), (-h * 0.14, y)], thin))
            out.append(([(h * 0.14, y), (h * 0.46, y)], thin))
        return out, h * 0.95
    raise ValueError(ch)


def d_clock():
    c = Canvas()
    cen = np.array([512.0, 556.0])
    Ro, Rb = 300.0, 260.0
    # bow (ring) and crown stem on top
    bow_c = (512, 175)
    c.ink_stroke(circle_pts(bow_c, 52, 240), 13.0, closed=True)
    stem = np.array([(478, 205), (546, 205), (552, 262), (472, 262)])
    c.shape(stem, base=6.0)
    for x in np.linspace(486, 538, 7):
        c.ink_stroke([(x, 214), (x + (x - 512) * 0.1, 254)], 3.2)
    c.shape(np.array([(490, 258), (534, 258), (540, 268), (484, 268)]), base=5.0)
    # bezel ring (accent) with knurling
    ring_out = circle_pts(cen, Ro, 720)
    c.ink_erase_poly(ring_out)
    c.acc_poly(ring_out)
    c.acc_erase_poly(circle_pts(cen, Rb, 720))
    c.ink_stroke(ring_out, weighted_widths(ring_out, 11.0, 0.9), closed=True)
    c.ink_stroke(circle_pts(cen, Rb, 720), weighted_widths(circle_pts(cen, Rb, 720), 7.0, -0.5), closed=True)
    c.ink_stroke(circle_pts(cen, Ro - 14, 720), 2.5, closed=True)
    ring_mask = c.mask_poly(ring_out)
    face_mask = c.mask_poly(circle_pts(cen, Rb - 4, 720))
    ring_only = ImageChops.subtract(ring_mask, c.mask_poly(circle_pts(cen, Rb + 4, 720)))
    # bezel shadow dotwork (bottom-right)
    c.stipple(lambda x, y: np.clip(((x - cen[0]) * 0.45 + (y - cen[1]) * 0.89) / Ro, 0, 1) ** 1.3 * 0.9,
              (cen[0] - Ro, cen[1] - Ro, cen[0] + Ro, cen[1] + Ro), clip=ring_only, spacing=5.0, r=(1.0, 1.8), seed=101)
    # face: vignette dotwork inside the bezel
    c.stipple(lambda x, y: np.clip((np.hypot(x - cen[0], y - cen[1]) - (Rb - 70)) / 70.0, 0, 1) ** 1.8 * 0.75,
              (cen[0] - Rb, cen[1] - Rb, cen[0] + Rb, cen[1] + Rb), clip=face_mask, spacing=5.0, r=(0.9, 1.6), seed=102)
    # minute ticks
    for i in range(60):
        a = -math.pi / 2 + i * math.pi / 30
        d = np.array([math.cos(a), math.sin(a)])
        if i % 5 == 0:
            c.ink_disc(cen + d * 240, 6.5)
        else:
            c.ink_stroke([cen + d * 236, cen + d * 248], 3.0)
    # roman numerals, oriented radially (base toward the centre)
    numerals = ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
    h = 46.0
    for i, s in enumerate(numerals):
        a = -math.pi / 2 + i * math.pi / 6
        glyphs = [roman_glyph(ch, h) for ch in s]
        total = sum(g[1] for g in glyphs)
        x = -total / 2
        strokes = []
        for g, gw in glyphs:
            for pts, w in g:
                strokes.append((np.array(pts) + np.array([x + gw / 2, 0.0]), w))
            x += gw
        # upright numerals; wide ones sit slightly further in so they clear the ticks
        r_txt = 196.0 - max(0.0, total - 60.0) * 0.35
        pos = cen + np.array([math.cos(a), math.sin(a)]) * r_txt + np.array([0.0, h / 2])
        for pts, w in strokes:
            c.ink_stroke(pts + pos, w, caps=False)
    # hands: hour -> 10, minute -> 2
    def hand(angle, length, wmax, tail):
        d = np.array([math.cos(angle), math.sin(angle)])
        n = np.array([-d[1], d[0]])
        shaft = blade([cen - d * tail, cen + d * length * 0.72], lambda t: taper(t, wmax * 0.45, peak=0.2, p=0.6, w0=wmax * 0.5, w1=wmax * 0.3))
        c.ink_poly(shaft)
        # spade head
        hc = cen + d * length * 0.78
        spade = spline([hc - d * 14, hc + n * wmax * 1.3, hc + d * length * 0.22, hc - n * wmax * 1.3], closed=True, n_per=20)
        c.ink_poly(spade)
        c.ink_erase_poly(spline([hc - d * 2, hc + n * wmax * 0.5 + d * 10, hc + d * length * 0.12, hc - n * wmax * 0.5 + d * 10], closed=True, n_per=16))
        c.ink_poly(blade([hc + d * length * 0.15, cen + d * length], lambda t: taper(t, wmax * 0.35, peak=0.0, p=1.0, w0=wmax * 0.35)))
    hand(math.radians(-150), 150, 18, 30)
    hand(math.radians(-60), 205, 14, 36)
    c.ink_disc(cen, 18)
    c.acc_poly(circle_pts(cen, 9, 60))
    c.ink_erase_disc(cen, 8)
    c.ink_disc(cen, 3.5)
    return c


def d_praying():
    c = Canvas()
    cx = 512.0
    hc = np.array([512.0, 372.0])
    # rays
    for i in range(36):
        a = -math.pi / 2 + i * math.pi / 18
        d = np.array([math.cos(a), math.sin(a)])
        L = 296 if i % 2 == 0 else 245
        if i % 2 == 0:
            P = blade([hc + d * 205, hc + d * L], lambda t: taper(t, 10, peak=0.0, p=1.0, w0=10))
        else:
            P = blade([hc + d * 205, hc + d * L], lambda t: taper(t, 6, peak=0.0, p=1.0, w0=6))
        c.ink_poly(P)
    # halo (accent ring)
    outer = circle_pts(hc, 185, 600)
    inner = circle_pts(hc, 152, 600)
    c.ink_erase_poly(outer)
    c.acc_poly(outer)
    c.acc_erase_poly(inner)
    c.ink_stroke(outer, weighted_widths(outer, 7.0, 0.8), closed=True)
    c.ink_stroke(inner, 4.0, closed=True)
    halo_ring = ImageChops.subtract(c.mask_poly(outer), c.mask_poly(inner))
    c.stipple(lambda x, y: np.clip(((x - hc[0]) * 0.45 + (y - hc[1]) * 0.89) / 185.0, 0, 1) ** 1.4 * 0.8,
              (hc[0] - 190, hc[1] - 190, hc[0] + 190, hc[1] + 190), clip=halo_ring, spacing=4.5, r=(0.9, 1.6), seed=111)
    # beveled latin cross
    hw, top, bot = 46.0, 150.0, 915.0
    ay0, ay1, ax = 312.0, 404.0, 236.0
    outline = np.array([(cx - hw, top), (cx + hw, top), (cx + hw, ay0), (cx + ax, ay0), (cx + ax, ay1), (cx + hw, ay1),
                        (cx + hw, bot), (cx - hw, bot), (cx - hw, ay1), (cx - ax, ay1), (cx - ax, ay0), (cx - hw, ay0)])
    bev = 17.0
    inset = np.array([(cx - hw + bev, top + bev), (cx + hw - bev, top + bev), (cx + hw - bev, ay0 + bev), (cx + ax - bev, ay0 + bev),
                      (cx + ax - bev, ay1 - bev), (cx + hw - bev, ay1 - bev), (cx + hw - bev, bot - bev), (cx - hw + bev, bot - bev),
                      (cx - hw + bev, ay1 - bev), (cx - ax + bev, ay1 - bev), (cx - ax + bev, ay0 + bev), (cx - hw + bev, ay0 + bev)])
    Po = resample(outline, 1.0, True)
    c.ink_erase_poly(Po)
    c.acc_erase_poly(Po)
    # bevel faces: shade those facing bottom-right
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        face = np.array([outline[i], outline[j], inset[j], inset[i]])
        e = outline[j] - outline[i]
        nrm = np.array([e[1], -e[0]]) / (np.linalg.norm(e) + 1e-9)
        if signed_area(outline) < 0:
            nrm = -nrm
        lit = float(nrm @ (SHADOW_DIR / np.linalg.norm(SHADOW_DIR)))
        if lit > 0.2:
            c.ink_poly(face)
        elif lit > -0.2:
            m = c.mask_poly(face)
            c.hatch(45, 6.0, 2.4, (face[:, 0].min(), face[:, 1].min(), face[:, 0].max(), face[:, 1].max()), clip=m)
    # bevel corner lines
    for i in range(n):
        c.ink_stroke([outline[i], inset[i]], 3.0)
    c.ink_stroke(resample(inset, 1.0, True), 3.0, closed=True)
    c.ink_stroke(Po, weighted_widths(Po, 7.5, 0.9), closed=True)
    # wood grain on the face
    face_mask = c.mask_poly(offset_closed(resample(inset, 1.0, True), -4))
    grain = c.blank()
    rng = np.random.default_rng(112)
    for k in range(5):
        x0 = cx - hw + bev + 10 + k * ((2 * (hw - bev) - 20) / 4)
        ys = np.linspace(top, bot, 120)
        xs = x0 + 3.0 * np.sin(ys / 37.0 + k * 1.7) + 2.0 * np.sin(ys / 13.0 + k)
        P = np.stack([xs, ys], 1)
        seg_starts = np.sort(rng.uniform(0, 1, 4))
        t = np.linspace(0, 1, len(P))
        for s0 in seg_starts:
            sel = (t > s0) & (t < s0 + 0.16)
            if sel.sum() > 3:
                c.stroke(grain, P[sel], lambda tt: taper(tt, 2.6, peak=0.5, p=0.8))
    for k in range(4):
        y0 = ay0 + bev + 10 + k * ((ay1 - ay0 - 2 * bev - 20) / 3)
        xs = np.linspace(cx - ax, cx + ax, 120)
        ys = y0 + 2.5 * np.sin(xs / 31.0 + k * 2.1)
        P = np.stack([xs, ys], 1)
        t = np.linspace(0, 1, len(P))
        for s0 in np.sort(rng.uniform(0, 1, 3)):
            sel = (t > s0) & (t < s0 + 0.2) & ((P[:, 0] < cx - hw) | (P[:, 0] > cx + hw))
            if sel.sum() > 3:
                c.stroke(grain, P[sel], lambda tt: taper(tt, 2.4, peak=0.5, p=0.8))
    c.ink_layer(grain, face_mask)
    # face shadow dotwork at the lower shaft
    c.stipple(lambda x, y: np.clip((y - 640) / 260.0, 0, 1) ** 1.5 * 0.6, (cx - hw, 600, cx + hw, bot), clip=face_mask,
              spacing=4.5, r=(0.8, 1.5), seed=113)
    return c


def d_waves():
    c = Canvas()
    cen = np.array([512.0, 512.0])
    Rf = 395.0
    frame = circle_pts(cen, Rf, 900)
    inner_clip = c.mask_poly(circle_pts(cen, Rf - 6, 900))
    # rising sun (accent) behind the waves, with rays
    sun_c = np.array([600.0, 360.0])
    for i in range(16):
        a = math.pi + i * math.pi / 15
        d = np.array([math.cos(a), math.sin(a)])
        c.ink_poly(blade([sun_c + d * 140, sun_c + d * (230 if i % 2 else 290)], lambda t: taper(t, 7, peak=0.0, p=1.0, w0=7)))
    sun = circle_pts(sun_c, 118, 400)
    c.ink_erase_poly(circle_pts(sun_c, 128, 400))
    c.acc_poly(sun)
    c.ink_stroke(sun, weighted_widths(sun, 6.0, 0.8), closed=True)

    def wave(x0, yb, w, R0, lw, seed):
        """One curling wave crest travelling left. x0 = leading edge."""
        sc = np.array([x0 + R0 * 1.05, yb - R0 * 1.35])
        a = np.linspace(0.0, -2.15 * math.pi, 260)
        r = R0 * (1 - 0.70 * (-a / (2.15 * math.pi)) ** 0.9)
        spiral = sc + np.stack([r * np.cos(a), r * np.sin(a)], 1)
        back = bez((x0 + w, yb + 8), (x0 + w * 0.75, yb - R0 * 0.2), sc + np.array([R0 * 1.6, R0 * 0.2]), spiral[0], 50)
        # occluding body: back slope + outer turn of the spiral + down to the base
        outer = spiral[a > -1.15 * math.pi]
        body = np.vstack([back, outer, [(outer[-1][0] - 4, yb + 70), (x0 + w + 4, yb + 70)]])
        c.ink_erase_poly(body)
        c.acc_erase_poly(body)
        mask = c.mask_poly(body)
        # trough dotwork, darkest at the base and inside the curl
        xl, xr = outer[:, 0].min(), x0 + w
        c.stipple(lambda x, y: np.clip((y - (yb - R0 * 0.9)) / (R0 * 1.6), 0, 1) ** 1.6 * 0.75
                  * np.clip((x - xl) / 60.0, 0, 1) * np.clip((xr - x) / 90.0, 0, 1),
                  (x0 - 10, yb - R0 * 2.8, x0 + w + 10, yb + 70), clip=mask, spacing=4.8, r=(0.9, 1.7), seed=seed)
        # crest line: heavy, tapering into the curl
        crest = np.vstack([back, spiral])
        c.ink_stroke(crest, lambda t: taper(t, lw * 1.7, peak=0.45, p=0.7, w0=lw * 0.8, w1=lw * 0.5))
        # echo lines following the back slope into the curl
        for e, f in ((1, 0.74), (2, 0.50)):
            sp2 = sc + (spiral[: int(len(spiral) * 0.55)] - sc) * f
            bk2 = bez((x0 + w * (0.98 - 0.12 * e), yb + 8), (x0 + w * 0.7, yb - R0 * 0.1 * f), sc + np.array([R0 * 1.5 * f, R0 * 0.35]), sp2[0], 40)
            c.ink_stroke(np.vstack([bk2, sp2]), lambda t: taper(t, lw * 0.85, peak=0.5, p=0.8, w0=0.8, w1=0.8))
        # foam claws hanging off the leading lip
        for j in range(5):
            idx = int(len(spiral) * (0.20 + j * 0.055))
            p = spiral[idx]
            d = p - sc
            d /= np.linalg.norm(d)
            nn = np.array([d[1], -d[0]])
            claw = spline([p, p + d * 14 + nn * 4, p + d * 22 - nn * 9], n_per=10)
            c.ink_stroke(claw, lambda tt: taper(tt, lw * 0.95, peak=0.0, p=1.0, w0=lw * 0.95))

    for k, x in enumerate((90, 300, 510, 720)):
        wave(x, 520, 240, 58, 6.0, 121 + k)
    for k, x in enumerate((30, 270, 510, 750)):
        wave(x, 660, 270, 72, 7.0, 131 + k)
    for k, x in enumerate((140, 440, 740)):
        wave(x, 810, 320, 88, 8.0, 141 + k)
    # foreground swell lines
    body = c.blank()
    c.poly(body, np.array([(80, 870), (944, 870), (944, 950), (80, 950)]))
    c.ink_erase_mask(body)
    c.acc = ImageChops.subtract(c.acc, body)
    for i in range(4):
        y = 878 + i * 20
        xs = np.linspace(100, 924, 300)
        ys = y + 5 * np.sin(xs / 38.0 + i * 1.3)
        c.ink_stroke(np.stack([xs, ys], 1), lambda t: taper(t, 5.0, peak=0.5, p=0.6, w0=1.2, w1=1.2))
    c.ink = ImageChops.multiply(c.ink, inner_clip)
    c.acc = ImageChops.multiply(c.acc, inner_clip)
    c.ink_stroke(frame, weighted_widths(frame, 12.0, 0.9), closed=True)
    c.ink_stroke(circle_pts(cen, Rf + 17, 900), 3.0, closed=True)
    return c


DESIGNS = {
    "tribal": d_tribal, "band": d_band, "rose": d_rose, "stars": d_stars,
    "crown": d_crown, "geometric": d_geometric, "flames": d_flames,
    "clock": d_clock, "praying": d_praying, "waves": d_waves,
}


# --------------------------------------------------------------------------
# Preview
# --------------------------------------------------------------------------

SKIN_LIGHT = (232, 196, 164)
SKIN_DARK = (92, 58, 40)
INK = (22, 24, 30)
ACCENT = (190, 30, 40)


def composite(stencil: Image.Image, skin, size, ink_opacity=0.92):
    a = np.asarray(stencil.convert("RGBA"), np.float32) / 255.0
    R, G = a[..., 0:1], a[..., 1:2]
    base = np.ones(a.shape[:2] + (3,), np.float32) * (np.array(skin, np.float32) / 255.0)
    acc = np.array(ACCENT, np.float32) / 255.0
    ink = np.array(INK, np.float32) / 255.0
    col = base * (1 - G * 0.9) + acc * (G * 0.9)
    col = col * (1 - R * ink_opacity) + ink * (R * ink_opacity)
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
    return img.resize((size, size), Image.LANCZOS)


def load_font(sz, bold=True):
    for p in ("/usr/share/fonts/opentype/inter/Inter-Bold.otf" if bold else "/usr/share/fonts/opentype/inter/Inter-Regular.otf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def make_preview(path):
    tile = 300
    pad = 16
    label_h = 44
    cols = 5
    rows = 2
    cw = tile * 2 + pad
    ch = tile + label_h
    W = cols * cw + (cols + 1) * pad
    H = 70 + rows * ch + (rows + 1) * pad
    sheet = Image.new("RGB", (W, H), (30, 31, 36))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 18), "CourtLife tattoo stencils  -  ink black + red accent on light / dark skin  (wrap designs rolled 50%: seam at centre)",
           font=load_font(22), fill=(235, 235, 240))
    f = load_font(20)
    fs = load_font(15, bold=False)
    for i, key in enumerate(DESIGN_KEYS):
        p = os.path.join(OUT_DIR, tex_name(key))
        if not os.path.exists(p):
            continue
        st = Image.open(p)
        if key in WRAP_KEYS:
            arr = np.roll(np.asarray(st), N // 2, axis=1)
            st = Image.fromarray(arr, "RGBA")
        cx = pad + (i % cols) * (cw + pad)
        cy = 70 + pad + (i // cols) * (ch + pad)
        sheet.paste(composite(st, SKIN_LIGHT, tile), (cx, cy))
        sheet.paste(composite(st, SKIN_DARK, tile), (cx + tile + pad, cy))
        d.text((cx, cy + tile + 8), DISPLAY_NAMES[key], font=f, fill=(240, 240, 240))
        d.text((cx + tile + pad, cy + tile + 11), tex_name(key) + ("  (wraps)" if key in WRAP_KEYS else ""), font=fs, fill=(160, 160, 170))
    sheet.save(path, optimize=True)


def main(argv):
    preview = "--no-preview" not in argv
    keys = [a for a in argv if not a.startswith("--")] or DESIGN_KEYS
    os.makedirs(OUT_DIR, exist_ok=True)
    for key in keys:
        if key not in DESIGNS:
            raise SystemExit("unknown design key: %s" % key)
        img = DESIGNS[key]().finish()
        out = os.path.join(OUT_DIR, tex_name(key))
        img.save(out, optimize=True)
        print("wrote", os.path.relpath(out, os.path.join(HERE, "..", "..", "..")))
    if preview:
        make_preview(os.path.join(OUT_DIR, "_preview.png"))
        print("wrote preview")


if __name__ == "__main__":
    main(sys.argv[1:])
