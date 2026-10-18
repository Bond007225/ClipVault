#!/usr/bin/env python3
"""Unit tests for court_dims.py (no Unreal needed).

Run from this folder:  python3 -m unittest test_court_dims
"""
import math
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import court_dims as d  # noqa: E402

UE_ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))


def parts_by_name():
    return {p["name"]: p for p in d.half_court_parts()}


def extent(part, axis):
    """(min, max) along court-local axis 0/1/2 for unrotated parts."""
    c, s = part["location_ft"][axis], part["size_ft"][axis]
    return c - s / 2.0, c + s / 2.0


class Regulation(unittest.TestCase):
    def test_units(self):
        self.assertEqual(d.UU_PER_FT, 30.48)
        self.assertAlmostEqual(d.ft_to_uu(10), 304.8)

    def test_matches_core_constants(self):
        """Cross-check against the C++ core so the art never drifts from gameplay."""
        with open(os.path.join(UE_ROOT, "Source", "CourtLife", "Core", "CLShooting.h")) as f:
            src = f.read()

        def const(name):
            return float(re.search(r"%s\s*=\s*(-?[\d.]+)f?" % name, src).group(1))
        self.assertEqual(const("kRimHeightFt"), d.RIM_HEIGHT_FT)
        self.assertEqual(const("kRimRadiusFt"), d.RIM_RADIUS_FT)
        self.assertEqual(const("kThreePtRadiusFt"), d.THREE_PT_R_FT)
        self.assertEqual(const("kCornerThreeXFt"), d.CORNER_THREE_FT)
        self.assertEqual(const("kBaselineZFt"), d.BASELINE_X_FT)
        with open(os.path.join(UE_ROOT, "Source", "CourtLife", "Public", "CLCoreBridge.h")) as f:
            m = re.search(r"CLUnitsPerFoot\s*=\s*([\d.]+)", f.read())
        self.assertEqual(float(m.group(1)), d.UU_PER_FT)

    def test_free_throw_15_from_backboard(self):
        self.assertAlmostEqual(d.FREE_THROW_FROM_BASELINE_FT - d.BACKBOARD_FROM_BASELINE_FT, 15.0)

    def test_corner_meets_arc_inside_half(self):
        meet = math.sqrt(d.THREE_PT_R_FT ** 2 - d.CORNER_THREE_FT ** 2)
        self.assertAlmostEqual(meet, 8.948, places=3)  # ft in front of the rim


class Layout(unittest.TestCase):
    def setUp(self):
        self.p = parts_by_name()

    def test_floor_50_by_47_with_rim_at_origin(self):
        f = self.p["Floor"]
        self.assertEqual(f["mesh"], "Plane")
        self.assertAlmostEqual(extent(f, 0)[0], -5.25)   # baseline
        self.assertAlmostEqual(extent(f, 0)[1], 41.75)   # half-court line
        self.assertAlmostEqual(extent(f, 1)[0], -25.0)
        self.assertAlmostEqual(extent(f, 1)[1], 25.0)
        self.assertEqual(f["location_ft"][2], 0.0)
        self.assertAlmostEqual(f["scale"][0], 47 * 30.48 / 100)
        self.assertAlmostEqual(f["scale"][1], 50 * 30.48 / 100)

    def test_floor_collision_top_is_floor(self):
        self.assertAlmostEqual(extent(self.p["FloorCollision"], 2)[1], 0.0)
        self.assertTrue(self.p["FloorCollision"]["hidden_in_game"])

    def test_backboard(self):
        b = self.p["Backboard"]
        self.assertAlmostEqual(extent(b, 0)[1], -1.25)            # front face 4 ft from baseline
        self.assertAlmostEqual(extent(b, 0)[1] - d.BASELINE_X_FT, 4.0)
        self.assertAlmostEqual(extent(b, 1)[1] - extent(b, 1)[0], 6.0)
        self.assertAlmostEqual(extent(b, 2)[0], 9.5)
        self.assertAlmostEqual(extent(b, 2)[1], 13.0)
        self.assertTrue(b["collision"])

    def test_rim(self):
        rims = [p for n, p in self.p.items() if n.startswith("Rim_") and n != "Rim_Bracket"]
        self.assertEqual(len(rims), d.RIM_SEGMENTS)
        rc = d.rim_tube_center_radius_ft()
        for r in rims:
            x, y, z = r["location_ft"]
            self.assertAlmostEqual(math.hypot(x, y), rc)
            self.assertAlmostEqual(z + d.RIM_TUBE_DIAMETER_FT / 2, 10.0)   # top of rim at 10 ft
            self.assertTrue(r["collision"])
            # Rotated cylinder axis must be tangent to the ring.
            roll, pitch, yaw = r["rotation"]
            self.assertEqual(pitch, 90.0)
            axis = (math.cos(math.radians(yaw)), math.sin(math.radians(yaw)))
            self.assertAlmostEqual(axis[0] * x + axis[1] * y, 0.0, places=9)
        self.assertAlmostEqual(rc - d.RIM_TUBE_DIAMETER_FT / 2, 0.75)       # 9 in inner radius
        total = sum(r["size_ft"][2] for r in rims)
        self.assertGreater(total, 2 * math.pi * rc)                          # ring is closed
        # Rim centre 15 in in front of the backboard face.
        self.assertAlmostEqual(0.0 - extent(self.p["Backboard"], 0)[1], 1.25)

    def test_bracket_spans_backboard_to_rim(self):
        br = self.p["Rim_Bracket"]
        self.assertAlmostEqual(extent(br, 0)[0], d.BACKBOARD_FACE_X_FT)
        self.assertAlmostEqual(extent(br, 0)[1], -d.rim_tube_center_radius_ft() - d.RIM_TUBE_DIAMETER_FT / 2)

    def test_stanchion_out_of_bounds_and_meets_board(self):
        pole, arm = self.p["Stanchion_Pole"], self.p["Stanchion_Arm"]
        self.assertLess(extent(pole, 0)[1], d.BASELINE_X_FT)
        self.assertAlmostEqual(extent(pole, 2)[0], 0.0)
        self.assertAlmostEqual(extent(arm, 0)[0], pole["location_ft"][0])
        self.assertAlmostEqual(extent(arm, 0)[1], extent(self.p["Backboard"], 0)[0])

    def test_names_unique(self):
        names = [p["name"] for p in d.half_court_parts()]
        self.assertEqual(len(names), len(set(names)))


class Transforms(unittest.TestCase):
    def test_local_to_world_identity(self):
        self.assertEqual(d.local_to_world((0, 0, 0), 0, (1, 0, 0)), (30.48, 0.0, 0.0))

    def test_local_to_world_yaw_and_origin(self):
        x, y, z = d.local_to_world((100, 200, 5), 90, (10, 0, 10))
        self.assertAlmostEqual(x, 100.0)
        self.assertAlmostEqual(y, 200 + 304.8)
        self.assertAlmostEqual(z, 5 + 304.8)

    def test_texture_uv_mapping(self):
        u, v = d.court_local_to_tex_uv(0.0, 0.0)           # rim centre
        self.assertAlmostEqual(u * 2048, 1024.0)
        self.assertAlmostEqual(v * 2048, 294.0)
        u, v = d.court_local_to_tex_uv(d.BASELINE_X_FT, 25.0)   # baseline, Unreal right sideline
        self.assertAlmostEqual(u * 2048, 24.0)                  # core x = -25 -> left column
        self.assertAlmostEqual(v * 2048, 84.0)
        u, v = d.court_local_to_tex_uv(d.HALF_COURT_X_FT, -25.0)
        self.assertAlmostEqual(u, d.TEX_UV_OFFSET[0] + d.TEX_UV_SCALE[0])
        self.assertAlmostEqual(v, d.TEX_UV_OFFSET[1] + d.TEX_UV_SCALE[1])


if __name__ == "__main__":
    unittest.main()
