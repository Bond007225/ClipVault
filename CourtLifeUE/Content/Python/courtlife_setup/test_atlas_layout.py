"""Plain-python unit tests (no Unreal needed).

Run from anywhere:
    python3 CourtLifeUE/Content/Python/courtlife_setup/test_atlas_layout.py
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import atlas_layout as al  # noqa: E402
import textures  # noqa: E402

CLTYPES_H = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "..",
    "Source", "CourtLife", "Public", "CLTypes.h"))


class AtlasLayoutTests(unittest.TestCase):
    def setUp(self):
        self.regions = al.build_layout()

    def test_valid(self):
        self.assertEqual(al.validate(self.regions), [])

    def test_slot_order_matches_cpp_enum(self):
        self.assertEqual(len(self.regions), 9)
        self.assertEqual([r.slot for r in self.regions], list(al.SLOT_ORDER))
        if os.path.exists(CLTYPES_H):
            with open(CLTYPES_H, encoding="utf-8") as f:
                src = f.read()
            start = src.index("enum class ECLTattooSlot")
            body = src[src.index("{", start) + 1:src.index("}", start)]
            enum = [t.strip() for t in body.split(",") if t.strip()]
            self.assertEqual(enum, list(al.SLOT_ORDER))

    def test_uv_in_unit_range_and_ordered(self):
        for r in self.regions:
            (u0, v0), (u1, v1) = r.uv_min, r.uv_max
            self.assertTrue(0 <= u0 < u1 <= 1, r.slot)
            self.assertTrue(0 <= v0 < v1 <= 1, r.slot)

    def test_padding_at_least_16px(self):
        for i, a in enumerate(self.regions):
            for b in self.regions[i + 1:]:
                self.assertGreaterEqual(al._gap(a, b), 16, f"{a.slot}/{b.slot}")
            self.assertGreaterEqual(min(a.x, a.y), 16)
            self.assertLessEqual(a.x + a.w, al.ATLAS_SIZE - 16)
            self.assertLessEqual(a.y + a.h, al.ATLAS_SIZE - 16)

    def test_aspects_realistic(self):
        by = {r.slot: r.aspect for r in self.regions}
        self.assertGreater(by["Neck"], 2.5)               # wide, short band
        for s in ("LeftUpperArm", "LeftForearm", "LeftCalf"):
            self.assertTrue(0.6 < by[s] < 1.1, s)         # limbs ~ as long as around
        self.assertLess(by["LeftCalf"], by["LeftForearm"])
        self.assertLess(by["LeftForearm"], by["LeftUpperArm"])

    def test_uniform_texel_density(self):
        for r in self.regions:
            self.assertAlmostEqual(r.px_per_cm, al.PX_PER_CM, delta=0.1)

    def test_validate_detects_overlap(self):
        bad = list(self.regions)
        r = bad[1]
        bad[2] = al.Region(bad[2].slot, 2, r.x + 10, r.y, r.w, r.h, r.aspect, r.circumference_cm, r.length_cm)
        self.assertTrue(any("overlaps" in e for e in al.validate(bad)))

    def test_validate_detects_tight_padding(self):
        bad = list(self.regions)
        r = bad[1]
        bad[2] = al.Region(bad[2].slot, 2, r.x + r.w + 8, r.y, r.w, r.h, r.aspect, r.circumference_cm, r.length_cm)
        self.assertTrue(any("apart" in e for e in al.validate(bad)))

    def test_validate_detects_out_of_bounds_and_order(self):
        bad = list(self.regions)
        r = bad[0]
        bad[0] = al.Region(r.slot, 0, al.ATLAS_SIZE - 100, r.y, r.w, r.h, r.aspect, r.circumference_cm, r.length_cm)
        self.assertTrue(any("out of bounds" in e for e in al.validate(bad)))
        swapped = [self.regions[1], self.regions[0]] + self.regions[2:]
        self.assertTrue(any("slot order" in e for e in al.validate(swapped)))

    def test_json_roundtrip_matches_layout(self):
        with tempfile.TemporaryDirectory() as d:
            path = al.export_json(os.path.join(d, "layout.json"))
            with open(path) as f:
                data = json.load(f)
        self.assertEqual(data["atlas_size"], 2048)
        self.assertEqual(data["slot_order"], list(al.SLOT_ORDER))
        for r, j in zip(self.regions, data["regions"]):
            self.assertEqual(j["slot"], r.slot)
            self.assertEqual(j["uv_min"], list(r.uv_min))
            self.assertEqual(j["uv_max"], list(r.uv_max))
            self.assertEqual(j["aspect"], r.aspect)

    def test_checked_in_json_is_current(self):
        if not os.path.exists(al.JSON_PATH):
            self.skipTest("json not exported yet")
        with open(al.JSON_PATH) as f:
            on_disk = json.load(f)
        self.assertEqual(on_disk, al.to_json_dict(),
                         "tattoo_atlas_layout.json is stale: run python3 atlas_layout.py")


class TgaTests(unittest.TestCase):
    def test_header_and_size(self):
        data = textures.tga_bytes(2, 2, [(255, 0, 0, 255)] * 4)
        self.assertEqual(len(data), 18 + 16)
        self.assertEqual(data[2], 2)
        self.assertEqual(data[16], 32)
        self.assertEqual(data[18:22], bytes((0, 0, 255, 255)))  # BGRA

    def test_rejects_wrong_count(self):
        with self.assertRaises(ValueError):
            textures.tga_bytes(2, 2, [(0, 0, 0, 0)] * 3)

    def test_pillow_reads_it(self):
        try:
            from PIL import Image
        except ImportError:
            self.skipTest("Pillow not installed")
        with tempfile.TemporaryDirectory() as d:
            p = textures.write_solid_tga(os.path.join(d, "t.tga"), (10, 20, 30, 0))
            with Image.open(p) as img:
                self.assertEqual(img.size, (4, 4))
                self.assertEqual(img.convert("RGBA").getpixel((3, 3)), (10, 20, 30, 0))


if __name__ == "__main__":
    unittest.main(verbosity=2)
