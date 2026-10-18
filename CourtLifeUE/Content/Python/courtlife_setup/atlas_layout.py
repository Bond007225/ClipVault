"""Tattoo atlas UV layout for CourtLife.

Pure Python (no ``unreal`` import) so it can be unit-tested anywhere and
imported by ``setup_project.py`` inside the Unreal Editor.

Contract (see Docs/Team/ONBOARDING.md, CLAssets.h, CLCustomizationComponent.cpp):
  * ``UCLCosmeticsCatalog.TattooRegions`` has one ``FCLTattooRegion`` per
    ``ECLTattooSlot`` value, in enum order.
  * ``FCLTattooRegion.UV`` is a box in 0..1 atlas UV space. Inside a region,
    U (X) wraps AROUND the limb (U = Min.X is the front of the limb) and
    V (Y) runs DOWN the limb (V = Min.Y is the joint nearest the torso).
  * ``FCLTattooRegion.Aspect`` = limb circumference / limb length, so
    ``RepaintTattoos`` keeps designs square regardless of the region's pixel
    shape.

Proportions are for the 6'6" (78 in) reference body. Every region is laid
out at the same texel density (``PX_PER_CM``) so pixel aspect ~= Aspect and
ink looks equally sharp on every limb. Left/right pairs are identical in size.

Atlas map (2048 x 2048, origin top-left, units = px)::

    +--------------+--------------+------------------+
    | LeftUpperArm | RightUpperArm| Neck             |
    |              |              +--------+         |
    |              |              |LeftHand| (free)  |
    +-----------+  +-----------+  +--------+         |
    |LeftForearm|  |RightForarm|  |RightHnd|         |
    |           |  |           |  +--------+         |
    +-----------+--+-----------+-------------------- +
    | LeftCalf     | RightCalf    | (reserved for     |
    |              |              |  future slots)    |
    +--------------+--------------+------------------+
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, asdict
from typing import Dict, List, Tuple

ATLAS_SIZE = 2048          # UCLCosmeticsCatalog.TattooAtlasSize default
EDGE_MARGIN_PX = 16        # gap between any region and the atlas border
GUTTER_PX = 32             # gap between neighbouring regions (>= 16 required)
MIN_PADDING_PX = 16        # hard minimum enforced by validate()
PX_PER_CM = 17             # uniform texel density for every region

# ECLTattooSlot order (Public/CLTypes.h). Never reorder: index == enum value.
SLOT_ORDER: Tuple[str, ...] = (
    "Neck",
    "LeftUpperArm",
    "RightUpperArm",
    "LeftForearm",
    "RightForearm",
    "LeftHand",
    "RightHand",
    "LeftCalf",
    "RightCalf",
)

# Realistic limb measurements for the 6'6" reference body, in centimetres:
# (average circumference, length of the tattooable band).
#   Neck      : ~40 cm around, ~12.5 cm from collar line to jaw.
#   Upper arm : ~35 cm around the biceps, ~37 cm shoulder to elbow.
#   Forearm   : ~27 cm average (30 cm below elbow tapering to 18 cm wrist),
#               ~30 cm elbow to wrist.
#   Hand      : ~23 cm around the palm/knuckles, ~20 cm wrist to fingertip.
#   Calf      : ~34 cm average (40 cm calf tapering to 23 cm ankle),
#               ~45 cm knee to ankle.
LIMB_CM: Dict[str, Tuple[float, float]] = {
    "Neck": (40.0, 12.5),
    "UpperArm": (35.0, 37.0),
    "Forearm": (27.0, 30.0),
    "Hand": (23.0, 20.0),
    "Calf": (34.0, 45.0),
}


def limb_of(slot: str) -> str:
    """Strip the Left/Right prefix: 'LeftForearm' -> 'Forearm'."""
    for prefix in ("Left", "Right"):
        if slot.startswith(prefix):
            return slot[len(prefix):]
    return slot


@dataclass(frozen=True)
class Region:
    slot: str
    index: int
    x: int            # pixel rect, top-left origin
    y: int
    w: int
    h: int
    aspect: float     # circumference / length (physical)
    circumference_cm: float
    length_cm: float

    @property
    def uv_min(self) -> Tuple[float, float]:
        return (self.x / ATLAS_SIZE, self.y / ATLAS_SIZE)

    @property
    def uv_max(self) -> Tuple[float, float]:
        return ((self.x + self.w) / ATLAS_SIZE, (self.y + self.h) / ATLAS_SIZE)

    @property
    def pixel_aspect(self) -> float:
        return self.w / self.h

    @property
    def px_per_cm(self) -> float:
        return self.h / self.length_cm

    def to_dict(self) -> dict:
        d = asdict(self)
        d["uv_min"] = list(self.uv_min)
        d["uv_max"] = list(self.uv_max)
        d["pixel_aspect"] = round(self.pixel_aspect, 4)
        d["px_per_cm"] = round(self.px_per_cm, 3)
        return d


def _size_px(limb: str) -> Tuple[int, int]:
    circ, length = LIMB_CM[limb]
    return int(round(circ * PX_PER_CM)), int(round(length * PX_PER_CM))


def build_layout() -> List[Region]:
    """Return the 9 regions in ECLTattooSlot order."""
    m, g = EDGE_MARGIN_PX, GUTTER_PX
    ua_w, ua_h = _size_px("UpperArm")
    fa_w, fa_h = _size_px("Forearm")
    nk_w, nk_h = _size_px("Neck")
    hd_w, hd_h = _size_px("Hand")
    cf_w, cf_h = _size_px("Calf")

    # Column 1 = left arm, column 2 = right arm (upper arm over forearm).
    col1_x = m
    col2_x = col1_x + ua_w + g
    fa_y = m + ua_h + g
    # Column 3: neck on top, hands stacked below it.
    col3_x = col2_x + ua_w + g
    lh_y = m + nk_h + g
    rh_y = lh_y + hd_h + g
    # Bottom band: calves.
    arms_bottom = fa_y + fa_h
    calf_y = arms_bottom + g

    rects = {
        "Neck": (col3_x, m, nk_w, nk_h),
        "LeftUpperArm": (col1_x, m, ua_w, ua_h),
        "RightUpperArm": (col2_x, m, ua_w, ua_h),
        "LeftForearm": (col1_x, fa_y, fa_w, fa_h),
        "RightForearm": (col2_x, fa_y, fa_w, fa_h),
        "LeftHand": (col3_x, lh_y, hd_w, hd_h),
        "RightHand": (col3_x, rh_y, hd_w, hd_h),
        "LeftCalf": (m, calf_y, cf_w, cf_h),
        "RightCalf": (m + cf_w + g, calf_y, cf_w, cf_h),
    }

    regions = []
    for i, slot in enumerate(SLOT_ORDER):
        circ, length = LIMB_CM[limb_of(slot)]
        x, y, w, h = rects[slot]
        regions.append(Region(slot, i, x, y, w, h, round(circ / length, 4), circ, length))
    return regions


def _gap(a: Region, b: Region) -> int:
    """Pixel gap between two rects (negative = overlap)."""
    dx = max(b.x - (a.x + a.w), a.x - (b.x + b.w))
    dy = max(b.y - (a.y + a.h), a.y - (b.y + b.h))
    # If they overlap on one axis, the separation is the other axis' gap.
    if dx < 0 and dy < 0:
        return max(dx, dy)  # overlapping: report the (negative) overlap
    return max(dx, dy)


def validate(regions: List[Region] | None = None, min_padding: int = MIN_PADDING_PX,
             aspect_tolerance: float = 0.03) -> List[str]:
    """Return a list of problems; an empty list means the layout is valid.

    Checks: slot count and enum order, positive size, in-bounds with margin,
    no overlaps, >= ``min_padding`` px between every pair of regions, mirrored
    left/right pairs, and pixel aspect within ``aspect_tolerance`` of Aspect.
    """
    regions = build_layout() if regions is None else regions
    errors: List[str] = []
    names = [r.slot for r in regions]
    if tuple(names) != SLOT_ORDER:
        errors.append(f"slot order {names} != ECLTattooSlot order {list(SLOT_ORDER)}")
    for i, r in enumerate(regions):
        if r.index != i:
            errors.append(f"{r.slot}: index {r.index} != position {i}")
        if r.w <= 0 or r.h <= 0:
            errors.append(f"{r.slot}: non-positive size {r.w}x{r.h}")
        if r.x < min_padding or r.y < min_padding or \
                r.x + r.w > ATLAS_SIZE - min_padding or r.y + r.h > ATLAS_SIZE - min_padding:
            errors.append(f"{r.slot}: out of bounds or closer than {min_padding}px to the atlas edge")
        (u0, v0), (u1, v1) = r.uv_min, r.uv_max
        if not (0.0 <= u0 < u1 <= 1.0 and 0.0 <= v0 < v1 <= 1.0):
            errors.append(f"{r.slot}: UV rect {r.uv_min}-{r.uv_max} not inside 0..1")
        if r.aspect <= 0:
            errors.append(f"{r.slot}: aspect must be > 0")
        elif abs(r.pixel_aspect - r.aspect) / r.aspect > aspect_tolerance:
            errors.append(f"{r.slot}: pixel aspect {r.pixel_aspect:.3f} differs from Aspect {r.aspect:.3f}")
    for i in range(len(regions)):
        for j in range(i + 1, len(regions)):
            gap = _gap(regions[i], regions[j])
            if gap < 0:
                errors.append(f"{regions[i].slot} overlaps {regions[j].slot}")
            elif gap < min_padding:
                errors.append(f"{regions[i].slot} and {regions[j].slot} only {gap}px apart (< {min_padding})")
    by_name = {r.slot: r for r in regions}
    for slot in SLOT_ORDER:
        if slot.startswith("Left"):
            other = by_name.get("Right" + slot[4:])
            mine = by_name.get(slot)
            if mine and other and (mine.w, mine.h, mine.aspect) != (other.w, other.h, other.aspect):
                errors.append(f"{slot} and its Right mirror differ in size or aspect")
    return errors


def to_json_dict(regions: List[Region] | None = None) -> dict:
    regions = build_layout() if regions is None else regions
    return {
        "atlas_size": ATLAS_SIZE,
        "edge_margin_px": EDGE_MARGIN_PX,
        "gutter_px": GUTTER_PX,
        "px_per_cm": PX_PER_CM,
        "uv_convention": "U wraps around the limb (Min.X = front), V runs down the limb (Min.Y = joint nearest torso); origin top-left",
        "slot_order": list(SLOT_ORDER),
        "regions": [r.to_dict() for r in regions],
    }


HERE = os.path.dirname(os.path.abspath(__file__))
JSON_PATH = os.path.join(HERE, "tattoo_atlas_layout.json")


def export_json(path: str = JSON_PATH) -> str:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(to_json_dict(), f, indent=2)
        f.write("\n")
    return path


def render_preview(path: str, scale: float = 0.5) -> str:
    """Render a labelled PNG of the layout (needs Pillow; not used in Unreal)."""
    from PIL import Image, ImageDraw, ImageFont

    size = int(ATLAS_SIZE * scale)
    img = Image.new("RGB", (size, size), (34, 36, 40))
    draw = ImageDraw.Draw(img)

    def font(px: int, bold: bool = False):
        name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
        for base in ("/usr/share/fonts/truetype/dejavu/", ""):
            try:
                return ImageFont.truetype(base + name, px)
            except OSError:
                continue
        return ImageFont.load_default()

    # 256 px grid in atlas space.
    for k in range(0, ATLAS_SIZE + 1, 256):
        p = int(k * scale)
        draw.line([(p, 0), (p, size)], fill=(50, 53, 58))
        draw.line([(0, p), (size, p)], fill=(50, 53, 58))

    colors = {
        "Neck": (214, 120, 70), "UpperArm": (70, 140, 214), "Forearm": (90, 185, 120),
        "Hand": (200, 170, 70), "Calf": (165, 105, 200),
    }
    f_title, f_body, f_small = font(26, True), font(17), font(14)
    for r in build_layout():
        x0, y0 = int(r.x * scale), int(r.y * scale)
        x1, y1 = int((r.x + r.w) * scale) - 1, int((r.y + r.h) * scale) - 1
        base = colors[limb_of(r.slot)]
        fill = tuple(int(c * 0.45) for c in base)
        draw.rectangle([x0, y0, x1, y1], fill=fill, outline=base, width=3)
        # Front-of-limb seam marker (U = Min.X) and "down the limb" arrow.
        draw.line([(x0 + 6, y0 + 8), (x0 + 6, y1 - 8)], fill=base, width=2)
        draw.polygon([(x0 + 1, y1 - 16), (x0 + 11, y1 - 16), (x0 + 6, y1 - 6)], fill=base)
        cx = (x0 + x1) // 2
        lines = [
            (f"{r.index}  {r.slot}", f_title, (255, 255, 255)),
            (f"{r.w} x {r.h} px   aspect {r.aspect:.2f}", f_body, (230, 230, 230)),
            (f"UV ({r.uv_min[0]:.4f}, {r.uv_min[1]:.4f})", f_small, (205, 205, 205)),
            (f"  -> ({r.uv_max[0]:.4f}, {r.uv_max[1]:.4f})", f_small, (205, 205, 205)),
        ]
        # Shrink the label block until it fits inside the region.
        for shrink in (1.0, 0.85, 0.72, 0.6):
            fitted = [(t, font(max(10, int(fo.size * shrink)), fo is f_title), c) for t, fo, c in lines]
            if max(draw.textlength(t, font=fo) for t, fo, _ in fitted) <= (x1 - x0) - 24:
                break
        lines = fitted
        heights = [draw.textbbox((0, 0), t, font=fo)[3] + 6 for t, fo, _ in lines]
        ty = (y0 + y1) // 2 - sum(heights) // 2
        for (text, fo, col), lh in zip(lines, heights):
            tw = draw.textlength(text, font=fo)
            draw.text((cx - tw / 2, ty), text, font=fo, fill=col)
            ty += lh

    # Free space labels.
    free = font(18)
    draw.text((int(1720 * scale), int(700 * scale)), "free", font=free, fill=(120, 124, 130))
    draw.text((int(1300 * scale), int(1560 * scale)), "reserved for future slots\n(e.g. Chest, Back)",
              font=free, fill=(120, 124, 130))
    footer = (f"CourtLife tattoo atlas  {ATLAS_SIZE}x{ATLAS_SIZE}   {PX_PER_CM} px/cm   "
              f"gutter {GUTTER_PX}px  margin {EDGE_MARGIN_PX}px   | = front seam (U=min), "
              f"arrow = down the limb (V)")
    draw.text((8, size - 22), footer, font=f_small, fill=(170, 170, 170))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return path


if __name__ == "__main__":
    problems = validate()
    for line in problems:
        print("ERROR:", line)
    print("json:", export_json())
    repo_docs = os.path.normpath(os.path.join(HERE, "..", "..", "..", "Docs", "TechArt", "tattoo_atlas_layout.png"))
    try:
        print("png:", render_preview(repo_docs))
    except ImportError:
        print("Pillow not installed; skipped preview PNG")
    raise SystemExit(1 if problems else 0)
