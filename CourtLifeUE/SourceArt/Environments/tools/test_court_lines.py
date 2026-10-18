#!/usr/bin/env python3
"""Checks that the generated line masks put every marking at regulation size.

Run:  python3 -m unittest test_court_lines   (from this folder)
      python3 test_court_lines.py

The mapping is re-derived here from the documented contract rather than
imported, so a mapping bug in gen_courts.py cannot hide itself:
    40 px/ft, 2048 px square, court x = 0 at column 1024, baseline at row 84.

For each marking we average a perpendicular profile of the mask over many
sample points along the line, then check that
  * the profile's centroid sits on the line's centreline (within 1.5 px), and
  * the mask is clear 0.3 ft either side of the line (no stray paint), and
  * the line is actually painted along its length (coverage fraction).
Lines follow the NBA convention: the 2 in line sits inside the dimension it
marks (outer edge on 23.75 ft, 22 ft, 8 ft, 19 ft, 6 ft), except the
restricted area (inner edge on 4 ft) and the half-court line (centred).
"""
import math
import os
import subprocess
import sys
import unittest

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
TEX_DIR = os.path.join(os.path.dirname(HERE), "Textures")

PX_PER_FT = 40.0
SIZE = 2048
COL_X0 = 1024.0   # column of court x = 0
ROW_D0 = 84.0     # row of the baseline (d = 0)
W = 2.0 / 12.0    # line width (ft)
RIM = (0.0, 5.25)
TOL_FT = 1.5 / PX_PER_FT

VENUES = {
    # name: (mask file, min painted fraction along a line)
    "park": ("T_ParkCourt_Lines.png", 0.70),
    "gym": ("T_GymFloor_Lines.png", 0.90),
}


def ensure_textures():
    missing = [v for v, (f, _) in VENUES.items() if not os.path.exists(os.path.join(TEX_DIR, f))]
    if missing:
        subprocess.check_call([sys.executable, os.path.join(HERE, "gen_courts.py")] + missing)


def load(fname):
    with Image.open(os.path.join(TEX_DIR, fname)) as im:
        a = np.asarray(im.convert("L"), np.float32) / 255.0
    assert a.shape == (SIZE, SIZE), a.shape
    return a


def sample(mask, x, d):
    """Nearest-pixel sample at court position (x ft, d ft from baseline)."""
    u = np.floor(COL_X0 + np.asarray(x) * PX_PER_FT).astype(int)
    v = np.floor(ROW_D0 + np.asarray(d) * PX_PER_FT).astype(int)
    return mask[np.clip(v, 0, SIZE - 1), np.clip(u, 0, SIZE - 1)]


class LineGeometry:
    """Mixin: tests run for each venue's mask."""
    fname = None
    min_cov = None

    @classmethod
    def setUpClass(cls):
        ensure_textures()
        cls.mask = load(cls.fname)

    # -- helpers ------------------------------------------------------------
    def check_profile(self, name, offsets, points_fn, expected):
        """points_fn(offsets_ft, along_index) -> (x, d) arrays.

        `offsets` is a 1-D array of perpendicular positions (ft); the profile
        is averaged over all along-line samples.
        """
        prof = np.zeros_like(offsets)
        centre_hits = []
        n_along = 0
        on_line = np.abs(offsets - expected) <= W / 2
        for xs, ds in points_fn(offsets):
            vals = sample(self.mask, xs, ds)
            prof += vals
            centre_hits.append(vals[on_line].max() > 0.5)
            n_along += 1
        prof /= n_along
        centroid = float((prof * offsets).sum() / prof.sum())
        self.assertAlmostEqual(centroid, expected, delta=TOL_FT,
                               msg="%s centroid %.3f ft, expected %.3f ft" % (name, centroid, expected))
        for side in (-0.3, 0.3):
            i = int(np.argmin(np.abs(offsets - (expected + side))))
            self.assertLess(prof[i], 0.08, "%s: paint found %.2f ft off the line" % (name, side))
        frac = float(np.mean(centre_hits))
        self.assertGreaterEqual(frac, self.min_cov, "%s painted along only %.0f%%" % (name, frac * 100))

    @staticmethod
    def radial(center, angles_deg):
        cx, cd = center

        def fn(radii):
            for a in np.radians(angles_deg):
                yield cx + radii * math.cos(a), cd + radii * math.sin(a)
        return fn

    @staticmethod
    def across_x(d_values):
        def fn(xs):
            for d in d_values:
                yield xs, np.full_like(xs, d)
        return fn

    @staticmethod
    def across_d(x_values):
        def fn(ds):
            for x in x_values:
                yield np.full_like(ds, x), ds
        return fn

    def offsets(self, centre, half=0.75):
        return np.arange(centre - half, centre + half, 0.5 / PX_PER_FT)

    # -- regulation markings ------------------------------------------------
    def test_three_point_arc_23_75(self):
        exp = 23.75 - W / 2
        self.check_profile("3pt arc", self.offsets(exp), self.radial(RIM, np.linspace(30, 150, 241)), exp)

    def test_three_point_arc_top_of_key(self):
        # Directly in front of the rim: line at d = 5.25 + 23.75 = 29 ft.
        self.assertGreater(sample(self.mask, 0.0, RIM[1] + 23.75 - W / 2), 0.0)
        exp = RIM[1] + 23.75 - W / 2
        self.check_profile("arc apex", self.offsets(exp), self.across_d(np.linspace(-1.0, 1.0, 81)), exp)

    def test_corner_threes_22(self):
        exp = 22.0 - W / 2
        ds = np.linspace(0.5, 13.5, 261)
        self.check_profile("right corner", self.offsets(exp), self.across_x(ds), exp)
        self.check_profile("left corner", self.offsets(-exp), self.across_x(ds), -exp)

    def test_corner_meets_arc(self):
        meet = RIM[1] + math.sqrt(23.75 ** 2 - 22.0 ** 2)  # 14.198 ft from baseline
        x = 22.0 - W / 2
        self.assertGreater(sample(self.mask, x, meet - 0.4) + sample(self.mask, -x, meet - 0.4), 0.0)
        # Beyond the meeting point the straight line must stop.
        for d in (16.0, 18.0, 20.0):
            self.assertLess(sample(self.mask, x, d), 0.05)
            self.assertLess(sample(self.mask, -x, d), 0.05)

    def test_free_throw_line_19(self):
        exp = 19.0 - W / 2
        self.check_profile("FT line", self.offsets(exp, 0.6), self.across_d(np.linspace(-5, 5, 201)), exp)

    def test_key_edges_8(self):
        exp = 8.0 - W / 2
        ds = np.concatenate([np.linspace(0.6, 6.6, 121), np.linspace(15.0, 18.4, 69)])
        self.check_profile("key right", self.offsets(exp, 0.6), self.across_x(ds), exp)
        self.check_profile("key left", self.offsets(-exp, 0.6), self.across_x(ds), -exp)

    def test_free_throw_circle_6(self):
        exp = 6.0 - W / 2
        self.check_profile("FT circle", self.offsets(exp), self.radial((0.0, 19.0), np.linspace(15, 165, 241)), exp)

    def test_restricted_area_4(self):
        exp = 4.0 + W / 2
        self.check_profile("restricted", self.offsets(exp, 0.6), self.radial(RIM, np.linspace(10, 170, 241)), exp)

    def test_center_circle_6(self):
        exp = 6.0 - W / 2
        self.check_profile("centre circle", self.offsets(exp), self.radial((0.0, 47.0), np.linspace(195, 345, 241)), exp)

    def test_half_court_line_47(self):
        xs = np.concatenate([np.linspace(-24, -7, 200), np.linspace(7, 24, 200)])
        self.check_profile("half court", self.offsets(47.0, 0.6), self.across_d(xs), 47.0)

    def test_boundary(self):
        self.check_profile("baseline", self.offsets(W / 2, 0.6), self.across_d(np.linspace(-24, 24, 300)), W / 2)
        ds = np.linspace(1, 46, 300)
        self.check_profile("sideline R", self.offsets(25 - W / 2, 0.6), self.across_x(ds), 25 - W / 2)
        self.check_profile("sideline L", self.offsets(-25 + W / 2, 0.6), self.across_x(ds), -25 + W / 2)

    def test_open_floor_is_clean(self):
        # Spots that must have no paint: rim centre, mid-lane, inside the arc, back court.
        for x, d in [(0, 5.25), (0, 12), (-12, 12), (12, 25), (0, 38), (-18, 40), (15, 3)]:
            self.assertLess(sample(self.mask, x, d), 0.05, "paint at (%s, %s)" % (x, d))


class ParkLines(LineGeometry, unittest.TestCase):
    fname, min_cov = VENUES["park"]


class GymLines(LineGeometry, unittest.TestCase):
    fname, min_cov = VENUES["gym"]


class Mapping(unittest.TestCase):
    def test_generator_mapping_matches_contract(self):
        sys.path.insert(0, HERE)
        import gen_courts as g
        self.assertEqual(g.PX_PER_FT, PX_PER_FT)
        self.assertEqual(g.TEX, SIZE)
        self.assertEqual(g.CENTER_U, COL_X0)
        self.assertEqual(g.OFFSET_V, ROW_D0)
        self.assertEqual(g.court_to_px(0, 5.25), (1024.0, 294.0))

    def test_textures_exist_and_sized(self):
        ensure_textures()
        for f in ["T_ParkCourt_BaseColor", "T_ParkCourt_Lines", "T_ParkCourt_Roughness",
                  "T_GymFloor_BaseColor", "T_GymFloor_Lines", "T_GymFloor_Roughness"]:
            path = os.path.join(TEX_DIR, f + ".png")
            self.assertTrue(os.path.exists(path), path)
            with Image.open(path) as im:
                self.assertEqual(im.size, (SIZE, SIZE))

    def test_lines_visible_in_basecolor(self):
        ensure_textures()
        for f in ["T_ParkCourt_BaseColor.png", "T_GymFloor_BaseColor.png"]:
            with Image.open(os.path.join(TEX_DIR, f)) as im:
                img = np.asarray(im.convert("L"), np.float32)
            xs = np.linspace(-5, 5, 101)
            on = sample(img, xs, np.full_like(xs, 19 - W / 2)).mean()
            off = sample(img, xs, np.full_like(xs, 19.6)).mean()
            self.assertGreater(on, off + 40, f)


if __name__ == "__main__":
    unittest.main()
