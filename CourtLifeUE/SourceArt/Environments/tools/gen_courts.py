#!/usr/bin/env python3
"""Procedural half-court textures for CourtLife (park court + indoor gym).

Usage:
    python3 gen_courts.py            # both venues
    python3 gen_courts.py park       # one venue
    python3 gen_courts.py --preview  # also render perspective previews

Requires Python 3, Pillow, numpy. Every random source uses a fixed seed, so
the output is byte-for-byte reproducible on the same library versions.

Texture mapping (all maps, 2048 x 2048, 40 px per ft)
------------------------------------------------------
The half court is 50 ft wide x 47 ft deep (baseline to half-court line), i.e.
2000 x 1880 px. It is centred in a 2048 square with a 24 px (0.6 ft) apron on
the left/right and an 84 px (2.1 ft) apron above/below:

    column u -> court x (ft) = (u + 0.5 - 1024) / 40      (x = 0 on the rim line)
    row    v -> depth d (ft) = (v + 0.5 - 84) / 40         (d = 0 on the baseline)

    baseline      : row 84            (top of image)
    rim centre    : d = 5.25 ft  -> pixel (1024, 294)
    half-court    : d = 47 ft    -> row 1964
    sidelines     : x = +/-25 ft -> columns 24 and 2024

Core court space (CLShooting.h) has the rim at the origin and z toward half
court, so core z = d - 5.25 and core x = image x. In Unreal (CLCourt) +X is
toward half court (rows increasing) and +Y = core -x (columns decreasing).

To map the 50 x 47 ft blockout floor's 0..1 UVs onto just the court region:
    U_tex = (24 + U * 2000) / 2048 ,  V_tex = (84 + V * 1880) / 2048
(see Content/Python/environments/court_dims.py: TEX_UV_SCALE / TEX_UV_OFFSET).

Line convention (2 in = 1/6 ft wide lines)
-----------------------------------------
Lines lie inside the dimension they mark (NBA convention):
  * sidelines / baseline: outer edge on the court boundary.
  * key: outer edges at x = +/-8 ft, free-throw line far edge at d = 19 ft.
  * three-point arc: outer edge at 23.75 ft from rim centre; corner lines
    outer edge at x = +/-22 ft, from the baseline until they meet the arc.
  * free-throw circle and centre circle: outer edge at 6 ft radius.
  * restricted area: inner edge at 4 ft radius from rim centre.
  * half-court line: centred on d = 47 ft.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

# ---------------------------------------------------------------- mapping ---
PX_PER_FT = 40
TEX = 2048
COURT_W_FT = 50.0
COURT_D_FT = 47.0
OFFSET_U = (TEX - int(COURT_W_FT * PX_PER_FT)) // 2  # 24
OFFSET_V = (TEX - int(COURT_D_FT * PX_PER_FT)) // 2  # 84
CENTER_U = OFFSET_U + int(COURT_W_FT / 2 * PX_PER_FT)  # 1024

# ------------------------------------------------------------ regulation ---
LINE_W = 2.0 / 12.0
RIM_D = 5.25
BACKBOARD_D = 4.0
KEY_HALF_W = 8.0
FT_LINE_D = 19.0
FT_CIRCLE_R = 6.0
RESTRICTED_R = 4.0
THREE_R = 23.75
CORNER_X = 22.0
HALF_D = 47.0
CENTER_R = 6.0
LANE_MARKS_D = (7.0, 8.0, 11.0, 14.0)  # near edge of lane-space marks from baseline

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Textures")


def px_to_court(u, v):
    return (u + 0.5 - CENTER_U) / PX_PER_FT, (v + 0.5 - OFFSET_V) / PX_PER_FT


def court_to_px(x, d):
    """Continuous pixel coordinate (pixel centres at +0.5)."""
    return x * PX_PER_FT + CENTER_U, d * PX_PER_FT + OFFSET_V


def grid():
    u = np.arange(TEX, dtype=np.float32)
    x, d = px_to_court(u, u)
    return np.meshgrid(x, d)  # X[v,u], D[v,u]


# ------------------------------------------------------------------ lines ---
def _band(t, lo, hi):
    """Anti-aliased coverage of [lo, hi] along coordinate t (ft)."""
    return np.clip(np.minimum(t - lo, hi - t) * PX_PER_FT + 0.5, 0.0, 1.0)


def line_mask(X, D):
    """Clean regulation line coverage in 0..1."""
    w = LINE_W
    m = np.zeros_like(X)
    ax = np.abs(X)
    in_court_d = _band(D, 0.0, HALF_D + w / 2)

    # Boundary.
    m = np.maximum(m, _band(D, 0.0, w) * _band(X, -25.0, 25.0))
    m = np.maximum(m, _band(ax, 25.0 - w, 25.0) * in_court_d)
    m = np.maximum(m, _band(D, HALF_D - w / 2, HALF_D + w / 2) * _band(X, -25.0, 25.0))

    # Centre circle (our half).
    rc = np.hypot(X, D - HALF_D)
    m = np.maximum(m, _band(rc, CENTER_R - w, CENTER_R) * (D <= HALF_D))

    # Key.
    m = np.maximum(m, _band(ax, KEY_HALF_W - w, KEY_HALF_W) * _band(D, 0.0, FT_LINE_D))
    m = np.maximum(m, _band(D, FT_LINE_D - w, FT_LINE_D) * _band(X, -KEY_HALF_W, KEY_HALF_W))

    # Lane-space marks: 6 in outward, 2 in wide (first one a 1 ft "block").
    for i, md in enumerate(LANE_MARKS_D):
        depth = 1.0 if i == 0 else w
        m = np.maximum(m, _band(ax, KEY_HALF_W, KEY_HALF_W + 0.5) * _band(D, md, md + depth))

    # Free-throw circle: solid outside the key, dashed inside it.
    rf = np.hypot(X, D - FT_LINE_D)
    ring = _band(rf, FT_CIRCLE_R - w, FT_CIRCLE_R)
    outside = D >= FT_LINE_D
    ang = np.arctan2(D - FT_LINE_D, X)  # -pi..0 inside the key
    arc_len = (ang + math.pi) * FT_CIRCLE_R  # 0 .. 6*pi ft along the inner half
    dash = (np.mod(arc_len, 1.25) < 0.75)
    m = np.maximum(m, ring * np.where(outside, 1.0, dash * (D < FT_LINE_D - w)))

    # Restricted area: inner edge 4 ft from rim, straight legs back to backboard.
    rr = np.hypot(X, D - RIM_D)
    m = np.maximum(m, _band(rr, RESTRICTED_R, RESTRICTED_R + w) * (D >= RIM_D))
    m = np.maximum(m, _band(ax, RESTRICTED_R, RESTRICTED_R + w) * _band(D, BACKBOARD_D, RIM_D))

    # Three-point line.
    m = np.maximum(m, _band(rr, THREE_R - w, THREE_R) * (ax <= CORNER_X) * (D >= RIM_D))
    meet = RIM_D + np.sqrt(np.maximum(THREE_R ** 2 - X ** 2, 0.0))
    m = np.maximum(m, _band(ax, CORNER_X - w, CORNER_X) * _band(D, 0.0, 0.0 + 99) * (D <= meet))
    return m.astype(np.float32)


def key_mask(X, D):
    """Painted area inside the lane (inside the lane lines)."""
    return (_band(np.abs(X), -1, KEY_HALF_W - LINE_W) * _band(D, LINE_W, FT_LINE_D - LINE_W)).astype(np.float32)


def court_mask(X, D):
    return (_band(np.abs(X), -1, 25.0) * _band(D, 0.0, HALF_D)).astype(np.float32)


# ------------------------------------------------------------------ noise ---
def value_noise(rng, cell_x, cell_y=None, octaves=4, persistence=0.5, shape=(TEX, TEX)):
    """Multi-octave bicubic value noise in roughly 0..1; cells in pixels."""
    cell_y = cell_x if cell_y is None else cell_y
    H, W = shape
    out = np.zeros(shape, np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cx = max(1.0, cell_x / 2 ** o)
        cy = max(1.0, cell_y / 2 ** o)
        gw, gh = int(math.ceil(W / cx)) + 3, int(math.ceil(H / cy)) + 3
        g = rng.random((gh, gw)).astype(np.float32)
        big = np.asarray(Image.fromarray(g, "F").resize((int(gw * cx), int(gh * cy)), Image.BICUBIC))
        oy = int(rng.integers(0, max(1, big.shape[0] - H)))
        ox = int(rng.integers(0, max(1, big.shape[1] - W)))
        out += amp * big[oy:oy + H, ox:ox + W]
        total += amp
        amp *= persistence
    return np.clip(out / total, 0.0, 1.0)


def stretch(a, lo, hi):
    return np.clip((a - lo) / (hi - lo), 0.0, 1.0)


def blur(a, radius):
    """Separable gaussian blur (sigma = radius px) in numpy, edge-clamped."""
    r = max(1, int(math.ceil(radius * 3)))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / radius) ** 2).astype(np.float32)
    k /= k.sum()
    a = a.astype(np.float32)
    p = np.pad(a, ((0, 0), (r, r)), mode="edge")
    a = sum(k[i] * p[:, i:i + a.shape[1]] for i in range(2 * r + 1))
    p = np.pad(a, ((r, r), (0, 0)), mode="edge")
    return sum(k[i] * p[i:i + a.shape[0], :] for i in range(2 * r + 1))


def blobs(X, D, spots):
    """Sum of anisotropic gaussians: (x, d, sx, sd, weight) in ft."""
    acc = np.zeros_like(X)
    for x, d, sx, sd, wgt in spots:
        acc += wgt * np.exp(-(((X - x) / sx) ** 2 + ((D - d) / sd) ** 2))
    return acc


def to_u8(a):
    return np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8)


def save_rgb(path, rgb):
    Image.fromarray(to_u8(rgb), "RGB").save(path, optimize=True)


def save_l(path, a):
    Image.fromarray(to_u8(a), "L").save(path, optimize=True)


def lerp(a, b, t):
    """a + (b - a) * t; a 2-D weight broadcasts over RGB when a or b is colour."""
    is_rgb = any(np.ndim(z) >= 1 and np.shape(z)[-1] == 3 for z in (a, b))
    if is_rgb and np.ndim(t) == 2:
        t = t[..., None]
    return a + (b - a) * t


def rgb(*c):
    return np.array(c, np.float32) / 255.0


# ------------------------------------------------------------------- park ---
def crack_path(rng, x, y, ang, steps, wiggle=0.16, revert=0.0):
    """Mostly-straight random walk with micro jitter (pixel coordinates).
    `revert` pulls the heading back toward the start angle (straight cracks)."""
    pts = [(x, y)]
    ang0 = ang
    for _ in range(steps):
        ang += rng.normal(0, wiggle) - revert * (ang - ang0)
        seg = rng.uniform(7, 16)
        x += math.cos(ang) * seg
        y += math.sin(ang) * seg
        pts.append((x + rng.normal(0, 1.2), y + rng.normal(0, 1.2)))
    return pts, ang


def draw_cracks(rng, n, length_ft, width_px, branch_p=0.25, paths=None):
    """Crack network rasterised into a 0..1 mask. Appends main paths to `paths`."""
    img = Image.new("L", (TEX, TEX), 0)
    dr = ImageDraw.Draw(img)

    def walk(x, y, ang, steps, wpx, depth):
        pts, _ = crack_path(rng, x, y, ang, steps)
        for i in range(len(pts) - 1):
            ww = max(1, int(round(wpx * rng.uniform(0.6, 1.25))))
            dr.line([pts[i], pts[i + 1]], fill=int(rng.uniform(170, 255)), width=ww)
            if depth < 2 and rng.random() < branch_p / 8:
                walk(pts[i + 1][0], pts[i + 1][1], ang + rng.choice([-1, 1]) * rng.uniform(0.5, 1.2),
                     int(steps * rng.uniform(0.1, 0.35)), max(1, wpx - 1), depth + 1)
        return pts

    for _ in range(n):
        x, y = rng.uniform(0, TEX), rng.uniform(0, TEX)
        steps = int(length_ft * PX_PER_FT / 11 * rng.uniform(0.5, 1.4))
        pts = walk(x, y, rng.uniform(0, 2 * math.pi), steps, width_px, 0)
        if paths is not None:
            paths.append(pts)
    return np.asarray(img, np.float32) / 255.0


def alligator(rng, X, D, cx, cd, radius):
    """Fatigue ('alligator') cracking: Voronoi cell edges inside a soft disc."""
    pts = rng.uniform(-radius, radius, (90, 2)) + np.array([cx, cd])
    sel = (np.abs(X - cx) < radius * 1.2) & (np.abs(D - cd) < radius * 1.2)
    out = np.zeros_like(X)
    xs, ds = X[sel], D[sel]
    dist = np.sqrt((xs[:, None] - pts[None, :, 0]) ** 2 + (ds[:, None] - pts[None, :, 1]) ** 2)
    part = np.partition(dist, 1, axis=1)
    edge = np.clip(1.0 - (part[:, 1] - part[:, 0]) * PX_PER_FT / 1.6, 0, 1)
    fall = np.clip(1.2 - np.hypot(xs - cx, ds - cd) / radius, 0, 1)
    out[sel] = edge * fall
    return out


def make_park(seed=1971):
    rng = np.random.default_rng(seed)
    X, D = grid()
    lines_clean = line_mask(X, D)
    key = key_mask(X, D)
    court = court_mask(X, D)

    # --- traffic: where feet and the ball wear the coating off ---
    traffic = blobs(X, D, [
        (0, 6.5, 5, 4, 1.0),      # under the rim
        (0, 20, 4, 3, 0.6),       # free-throw line
        (0, 27, 6, 3, 0.45),      # top of the arc
        (-15, 20, 5, 5, 0.35), (15, 20, 5, 5, 0.4),    # wings
        (-20, 4, 3, 5, 0.3), (20, 4, 3, 5, 0.25),      # corners
        (-6, 9, 3, 4, 0.4), (6, 9, 3, 4, 0.4),         # blocks
    ])
    traffic = np.clip(traffic, 0, 1.2)

    n_low = value_noise(rng, 420, octaves=3)
    n_mid = value_noise(rng, 90, octaves=4)
    n_hi = value_noise(rng, 14, octaves=3)
    n_stone = value_noise(rng, 3.0, octaves=1)
    n_stone2 = value_noise(rng, 1.6, octaves=1)
    n_fine = rng.random((TEX, TEX)).astype(np.float32)

    # Coating wear. `thin` = acrylic worn thin (asphalt darkens through),
    # `worn` = coating gone, raw aggregate exposed. Edges break up on grain.
    wear_field = traffic * 0.62 + n_mid * 0.7 + n_hi * 0.22 - 0.68
    thin = stretch(wear_field, -0.10, 0.18)
    worn = stretch(wear_field + (n_stone - 0.5) * 0.06, 0.15, 0.30)

    # --- asphalt: grey binder with clustered light/dark aggregate ---
    asphalt = rgb(66, 64, 61) * (0.85 + 0.28 * n_mid[..., None])
    light_stone = stretch(n_stone, 0.66, 0.80) * (0.5 + 0.5 * n_stone2)
    dark_pit = stretch(0.30 - n_stone, 0.0, 0.10)
    asphalt = asphalt + (light_stone * 0.20 - dark_pit * 0.07 + (n_stone2 - 0.5) * 0.04)[..., None]
    asphalt = asphalt * rgb(255, 250, 242)

    # --- acrylic colour coat: green playing area, terracotta key + apron ---
    green = rgb(66, 106, 82)
    green_bleached = rgb(112, 134, 112)
    red = rgb(148, 74, 60)
    red_bleached = rgb(164, 112, 96)
    sun = stretch(n_low, 0.15, 0.85) * 0.85 + 0.1     # uneven sun bleaching
    area = np.clip(key + (1 - court), 0, 1)
    coat = lerp(lerp(green, green_bleached, sun), lerp(red, red_bleached, sun), area)
    coat = coat * (0.93 + 0.12 * n_mid[..., None] + 0.05 * (n_hi[..., None] - 0.5))
    # Acrylic is a sand-filled coat: fine grain plus faint roller/squeegee passes.
    squeegee = value_noise(rng, 2.0, 120, octaves=2) - 0.5
    coat = coat + ((n_stone2 - 0.5) * 0.05 + squeegee * 0.025)[..., None]
    # Resurfaced patch: a newer, slightly bluer green rolled over a repair.
    ragged = (n_hi - 0.5) * 1.6 + (n_stone - 0.5) * 0.3
    patch = np.clip(np.minimum(np.minimum(X - 9.5, 16.5 - X), np.minimum(D - 29.0, 35.5 - D)) * 3 + ragged, 0, 1)
    patch = blur(patch, 1.2)
    patch_rim = np.clip(patch * (1 - patch) * 4, 0, 1)
    coat = lerp(coat, rgb(72, 114, 88) * (0.95 + 0.1 * n_hi[..., None]), patch * 0.85 * (1 - area))
    coat = coat * (1 - 0.10 * patch_rim)[..., None]
    coat = lerp(coat, coat * 0.66 + asphalt * 0.34, thin * 0.85 * (1 - patch))

    color = lerp(coat, asphalt, worn)

    # --- painted lines: faded, chipped at the edges, a few bigger flakes ---
    chips = stretch(value_noise(rng, 18, octaves=3) + traffic * 0.10 + (n_stone - 0.5) * 0.25, 0.66, 0.78)
    edge_rough = (n_stone2 - 0.5) * 0.9           # ragged edges
    lines = np.clip(lines_clean * 1.25 + edge_rough * (lines_clean * (1 - lines_clean) * 4) - 0.12, 0, 1)
    lines = lines * (1.0 - chips * 0.9) * (1.0 - worn * 0.4) * (0.80 + 0.20 * stretch(n_mid, 0.2, 0.8))
    line_col = lerp(rgb(232, 230, 220), rgb(206, 200, 186), stretch(n_low, 0.3, 0.8))
    color = lerp(color, line_col, lines * 0.95)
    color = lerp(color, color * 0.75 + asphalt * 0.25, (lines * thin * 0.5))  # dirt in the paint

    # --- cracks ---
    long_paths = []
    cracks = draw_cracks(rng, 7, 18, 2, paths=long_paths)
    cracks = np.maximum(cracks, draw_cracks(rng, 18, 3.5, 1) * 0.7)
    # Transverse expansion cracks right across the court (the classic park look).
    img = Image.new("L", (TEX, TEX), 0)
    dr = ImageDraw.Draw(img)
    seal_paths = []
    for d0 in (33.0, 12.0):
        y = court_to_px(0, d0)[1]
        pts, _ = crack_path(rng, -10, y, rng.normal(0, 0.02), 200, wiggle=0.08, revert=0.25)
        dr.line(pts, fill=255, width=2)
        seal_paths.append(pts)
    cracks = np.maximum(cracks, np.asarray(img, np.float32) / 255.0)
    fat = alligator(rng, X, D, -11.0, 31.5, 3.0)
    fat = np.maximum(fat, alligator(rng, X, D, 18.0, 5.0, 2.0))
    cracks = np.maximum(cracks, fat * 0.55)
    cracks = blur(cracks, 0.6)
    # Crack sealer: black tar painted over the transverse cracks + two long ones.
    simg = Image.new("L", (TEX, TEX), 0)
    sd = ImageDraw.Draw(simg)
    for pts in seal_paths + long_paths[:1]:
        for i in range(len(pts) - 1):
            sd.line([pts[i], pts[i + 1]], fill=255, width=int(rng.uniform(10, 16)))
    sealer = blur(np.asarray(simg, np.float32) / 255.0, 2.5)
    sealer = stretch(sealer + (n_hi - 0.5) * 0.5, 0.35, 0.55)
    halo = blur(cracks, 4.0)
    grime_pre = n_mid * 0.5
    crack_col = rgb(40, 37, 34) * (0.9 + 0.2 * n_hi[..., None])
    color = color * (1 - 0.12 * stretch(halo, 0.03, 0.3))[..., None]     # dirt along cracks
    color = lerp(color, crack_col, np.clip(cracks, 0, 1) * 0.85)
    seal_col = rgb(44, 44, 46) * (0.9 + 0.25 * n_hi[..., None]) + 0.04 * grime_pre[..., None]
    color = lerp(color, seal_col, sealer * 0.85)

    # --- grime: edges, water stains, gum, scuffs ---
    edge_dist = np.minimum(25.0 - np.abs(X), D)
    edge_grime = np.exp(-np.clip(edge_dist + 2.0, 0, None) / 2.0) * (0.6 + 0.6 * n_mid)
    puddle = stretch(n_low * 0.7 + value_noise(rng, 160, octaves=3) * 0.6 - 0.58, 0.0, 0.2)
    puddle_ring = np.clip(puddle * (1 - puddle) * 4, 0, 1) * stretch(n_hi, 0.3, 0.7)
    grime = np.clip(edge_grime * 0.5 + puddle * 0.2 + puddle_ring * 0.12 + stretch(n_mid, 0.4, 0.8) * 0.18
                    + stretch(value_noise(rng, 40, octaves=3), 0.55, 0.8) * 0.12, 0, 1)
    dirt = rgb(74, 66, 54)
    color = lerp(color, color * 0.55 + dirt * 0.45, grime)

    gimg = Image.new("L", (TEX, TEX), 0)
    gd = ImageDraw.Draw(gimg)
    for _ in range(180):  # gum + old stains
        x, y = rng.uniform(0, TEX), rng.uniform(0, TEX)
        r = rng.uniform(1.5, 4.0)
        gd.ellipse([x - r, y - r * rng.uniform(0.7, 1.0), x + r, y + r], fill=int(rng.uniform(110, 230)))
    for _ in range(260):  # ball and sneaker scuffs in traffic areas
        x = rng.normal(0, 9); d = abs(rng.normal(14, 8))
        px, py = court_to_px(x, d)
        a = rng.uniform(0, math.pi)
        L = rng.uniform(8, 28)
        gd.line([px, py, px + math.cos(a) * L, py + math.sin(a) * L], fill=int(rng.uniform(25, 70)),
                width=int(rng.integers(3, 7)))
    gum = blur(np.asarray(gimg, np.float32) / 255.0, 1.0)
    color = lerp(color, rgb(34, 32, 32), gum * 0.7)

    # Final grade: dusty haze, sane albedo range.
    lum = color.mean(axis=2, keepdims=True)
    color = lerp(color, lum, np.full((TEX, TEX), 0.10, np.float32)) * 0.97 + rgb(10, 9, 7)
    color = np.clip(color, 0.03, 0.85)

    # --- roughness ---
    rough = 0.76 + 0.08 * n_mid - 0.07 * stretch(traffic, 0.3, 1.0)   # polished by feet
    rough = lerp(rough, 0.92 + 0.05 * n_stone, worn)                      # raw asphalt
    rough = lerp(rough, 0.64 + 0.05 * n_hi, lines * 0.9)                  # paint
    rough = lerp(rough, 0.97, np.clip(cracks, 0, 1))
    rough = lerp(rough, 0.45 + 0.10 * n_hi, sealer)                       # tar sealer is glossy
    rough = lerp(rough, 0.90, grime * 0.5)
    rough = lerp(rough, 0.55, gum * 0.5)
    rough += (n_fine - 0.5) * 0.03

    return color, lines, np.clip(rough, 0, 1)


# -------------------------------------------------------------------- gym ---
BOARD_W_PX = 2.25 / 12.0 * PX_PER_FT  # 2 1/4 in strips = 7.5 px


def make_gym(seed=2026, team=(24, 52, 128)):
    rng = np.random.default_rng(seed)
    X, D = grid()
    lines_clean = line_mask(X, D)
    key = key_mask(X, D)
    court = court_mask(X, D)
    H = W = TEX

    u = np.arange(W, dtype=np.float32)
    v = np.arange(H, dtype=np.float32)
    board = np.floor(u / BOARD_W_PX).astype(np.int32)  # per column
    n_boards = int(board.max()) + 1

    # Each board column is a chain of strips with random lengths (2-9 ft) and
    # staggered end joints; give every strip its own tone and grain phase.
    strip_id = np.zeros((H, W), np.int32)
    joint = np.zeros((H, W), np.float32)
    next_id = 0
    tone_list = []
    for b in range(n_boards):
        cols = np.where(board == b)[0]
        y = -rng.uniform(0, 9 * PX_PER_FT)
        ids = np.zeros(H, np.int32)
        jrow = np.zeros(H, np.float32)
        while y < H:
            L = rng.uniform(2.0, 9.0) * PX_PER_FT
            y0, y1 = int(max(0, y)), int(min(H, y + L))
            ids[y0:y1] = next_id
            if 0 <= int(y1) < H:
                jrow[int(y1)] = 1.0
            next_id += 1
            y += L
        strip_id[:, cols] = ids[:, None]
        joint[:, cols] = jrow[:, None]
    # Strip tone: mostly honey maple, some paler, some darker amber.
    t = rng.normal(0, 1, next_id).astype(np.float32)
    amber = (rng.random(next_id) < 0.06).astype(np.float32)
    pale = (rng.random(next_id) < 0.12).astype(np.float32)
    strip_tone = np.clip(t * 0.028 - amber * 0.06 + pale * 0.035, -0.15, 0.1)
    strip_hue = rng.normal(0, 1, next_id).astype(np.float32) * 0.012
    tone = strip_tone[strip_id]
    hue = strip_hue[strip_id]

    # Grain: streaks stretched along the board, wobbled by low-frequency noise.
    g1 = value_noise(rng, 2.2, 260, octaves=3, persistence=0.6)
    g2 = value_noise(rng, 1.0, 90, octaves=2, persistence=0.5)
    flecks = value_noise(rng, 3, 40, octaves=2)
    # Fine growth-ring lines: sine of a wobbly phase field, sharpened.
    phase = u[None, :] * 0.9 + value_noise(rng, 30, 400, octaves=3) * 40.0 + strip_id * 1.7
    rings = np.abs(np.sin(phase)) ** 6
    grain = (g1 - 0.5) * 0.10 + (g2 - 0.5) * 0.06 - rings * 0.05
    mineral = stretch(flecks, 0.78, 0.92) * 0.10   # dark mineral streaks in maple

    base = rgb(218, 180, 132)
    wood = base * (1 + tone[..., None] + grain[..., None]) - mineral[..., None] * rgb(120, 110, 100)
    wood = wood + np.stack([hue, hue * 0.4, -hue], -1)

    # Seams between strips (side) and end joints.
    side = ((u % BOARD_W_PX) < 1.0).astype(np.float32)[None, :]
    seam = np.clip(side * 0.55 + joint * 0.6, 0, 1)
    wood = wood * (1 - 0.18 * seam[..., None])

    # Finish: amber polyurethane, slightly darker in the low-frequency field
    # (different coats / refinishing passes).
    n_low = value_noise(rng, 500, octaves=3)
    n_mid = value_noise(rng, 70, octaves=3)
    finish = 0.97 + 0.09 * (n_low - 0.5) + 0.03 * (n_mid - 0.5)
    wood = wood * finish[..., None] * rgb(255, 246, 232)

    # Painted key + out-of-bounds border in the team colour, grain showing through.
    lum = wood.mean(axis=2, keepdims=True)
    team_c = rgb(*team)
    painted = team_c * (0.84 + 1.3 * (lum - lum.mean())) * (0.93 + 0.08 * n_mid[..., None] + 0.06 * n_low[..., None])
    painted = painted * (1 - 0.15 * seam[..., None])
    paint_area = np.clip(key + (1 - court), 0, 1)
    color = lerp(wood, painted, paint_area)

    # Traffic: finish worn/dulled and very slight greying where play happens.
    traffic = np.clip(blobs(X, D, [
        (0, 7, 6, 5, 1.0), (0, 19, 5, 5, 0.7), (0, 27, 8, 4, 0.5),
        (-15, 20, 6, 6, 0.45), (15, 20, 6, 6, 0.45), (-21, 4, 4, 6, 0.3), (21, 4, 4, 6, 0.3),
    ]), 0, 1)

    # Shoe scuff marks (black rubber) - short arcs in traffic areas.
    simg = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(simg)
    for _ in range(320):
        x = rng.normal(0, 10); d = abs(rng.normal(15, 10))
        px, py = court_to_px(x, d)
        r = rng.uniform(10, 30)
        a0 = rng.uniform(0, 360)
        sd.arc([px - r, py - r, px + r, py + r], a0, a0 + rng.uniform(8, 30),
               fill=int(rng.uniform(40, 140)), width=int(rng.integers(2, 4)))
    scuff = blur(np.asarray(simg, np.float32) / 255.0, 0.6)
    color = lerp(color, rgb(40, 34, 30), blur(scuff, 0.8) * 0.3)
    color = color * (1 - 0.05 * traffic[..., None])

    # Painted lines: crisp white, faint wear in traffic.
    lw = 1.0 - stretch(value_noise(rng, 5, octaves=2) + traffic * 0.2, 0.70, 0.9) * 0.35
    lines = lines_clean * lw
    line_col = rgb(242, 240, 232) * (0.97 + 0.04 * n_mid[..., None])
    color = lerp(color, line_col, lines)
    color = np.clip(color, 0.03, 0.9)

    # Roughness: glossy poly finish with sheen variation.
    rough = 0.24 + 0.05 * n_low + 0.03 * n_mid + 0.10 * traffic
    rough = rough + 0.06 * seam + 0.02 * (g2 - 0.5)
    rough = lerp(rough, 0.30 + 0.03 * n_mid, paint_area * 0.8)
    rough = lerp(rough, 0.32, lines)
    rough = lerp(rough, 0.55, scuff * 0.6)
    return color, lines, np.clip(rough, 0, 1), paint_area


# ---------------------------------------------------------------- preview ---
def _solve_homography(src, dst):
    """Coefficients mapping dst (output) -> src (input) for Image.PERSPECTIVE."""
    A, b = [], []
    for (xs, ys), (xd, yd) in zip(src, dst):
        A.append([xd, yd, 1, 0, 0, 0, -xs * xd, -xs * yd]); b.append(xs)
        A.append([0, 0, 0, xd, yd, 1, -ys * xd, -ys * yd]); b.append(ys)
    return np.linalg.solve(np.array(A, float), np.array(b, float))


def render_preview(base_path, out_path, cam=(0.0, 44.0, 8.0), target=(0.0, 7.0, 4.0),
                   size=(1600, 900), hfov=90.0, sky=(150, 175, 200), ground=(70, 72, 60)):
    """Pinhole view of the floor texture from the gameplay camera.

    World: x across the court (ft), d from baseline (ft), h up (ft). The
    default camera sits ~17 ft behind a shooter at the top of the arc (CLBallerCharacter
    boom = 17 ft, +4 ft socket) looking at the rim.
    """
    ss = 2
    Wo, Ho = size[0] * ss, size[1] * ss
    c = np.array(cam, float)
    f = np.array(target, float) - c
    f /= np.linalg.norm(f)
    up = np.array([0, 0, 1.0])
    r = np.cross(f, up); r /= np.linalg.norm(r)
    upc = np.cross(r, f)
    fpx = (Wo / 2) / math.tan(math.radians(hfov / 2))

    def project(p):
        q = np.array(p, float) - c
        zc = q @ f
        return (Wo / 2 + fpx * (q @ r) / zc, Ho / 2 - fpx * (q @ upc) / zc)

    pts = [(-25, 0, 0), (25, 0, 0), (25, 40, 0), (-25, 40, 0)]
    src = [court_to_px(p[0], p[1]) for p in pts]
    dst = [project(p) for p in pts]
    coeffs = _solve_homography(src, dst)

    tex = Image.open(base_path).convert("RGB")
    warped = tex.transform((Wo, Ho), Image.PERSPECTIVE, tuple(coeffs), Image.BILINEAR,
                           fillcolor=ground)
    # Paint above the horizon (rays that never hit the floor).
    out = np.asarray(warped).copy()
    ys = np.arange(Ho)
    xs = np.arange(Wo)
    XX, YY = np.meshgrid(xs, ys)
    dirs = (f[None, None, :] + ((XX - Wo / 2) / fpx)[..., None] * r[None, None, :]
            - ((YY - Ho / 2) / fpx)[..., None] * upc[None, None, :])
    tfloor = -c[2] / np.where(dirs[..., 2] < -1e-6, dirs[..., 2], -1e-6)
    hitd = c[1] + tfloor * dirs[..., 1]
    hitx = c[0] + tfloor * dirs[..., 0]
    off_tex = (dirs[..., 2] >= -1e-4) | (hitd < -2.1) | (np.abs(hitx) > 25.6) | (hitd > 49.1)
    out[(dirs[..., 2] >= -1e-4)] = sky
    out[off_tex & (dirs[..., 2] < -1e-4)] = ground
    img = Image.fromarray(out)
    dr = ImageDraw.Draw(img)

    # Pole, backboard and rim for scale (front face 4 ft from baseline).
    pole_top, pole_bot = project((0, -3.5, 12.0)), project((0, -3.5, 0.0))
    dr.line([pole_bot, pole_top], fill=(60, 60, 64), width=18)
    dr.line([project((0, -3.5, 11.5)), project((0, 3.75, 11.5))], fill=(60, 60, 64), width=14)
    bb = [project((-3, 4.0, 9.5)), project((3, 4.0, 9.5)), project((3, 4.0, 13.0)), project((-3, 4.0, 13.0))]
    dr.polygon(bb, fill=(235, 235, 235), outline=(40, 40, 40))
    sq = [project((-1, 4.0, 10.0)), project((1, 4.0, 10.0)), project((1, 4.0, 11.5)), project((-1, 4.0, 11.5))]
    dr.line(sq + [sq[0]], fill=(200, 60, 40), width=6)
    rim = [project((0.75 * math.cos(a), 5.25 + 0.75 * math.sin(a), 10.0)) for a in np.linspace(0, 2 * math.pi, 40)]
    dr.line(rim, fill=(220, 90, 30), width=7)
    img = img.resize(size, Image.LANCZOS)
    img.save(out_path)


# ------------------------------------------------------------------- main ---
def build(venue, preview=False):
    os.makedirs(OUT_DIR, exist_ok=True)
    if venue == "park":
        color, lines, rough = make_park()
        prefix = "T_ParkCourt"
    elif venue == "gym":
        color, lines, rough, paint = make_gym()
        prefix = "T_GymFloor"
        save_l(os.path.join(OUT_DIR, prefix + "_PaintMask.png"), paint)
    else:
        raise SystemExit("unknown venue " + venue)
    base = os.path.join(OUT_DIR, prefix + "_BaseColor.png")
    save_rgb(base, color)
    save_l(os.path.join(OUT_DIR, prefix + "_Lines.png"), lines)
    save_l(os.path.join(OUT_DIR, prefix + "_Roughness.png"), rough)
    print("wrote", prefix)
    if preview:
        if venue == "park":
            render_preview(base, os.path.join(ROOT, "_preview_park.png"),
                           sky=(150, 178, 205), ground=(58, 70, 44))
        else:
            render_preview(base, os.path.join(ROOT, "_preview_gym.png"),
                           sky=(120, 118, 112), ground=(52, 54, 62))
        print("wrote preview", venue)


def main(argv):
    preview = "--preview" in argv
    venues = [a for a in argv if not a.startswith("-")] or ["park", "gym"]
    for v in venues:
        build(v, preview)


if __name__ == "__main__":
    main(sys.argv[1:])
