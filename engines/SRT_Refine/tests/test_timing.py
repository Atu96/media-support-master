# -*- coding: utf-8 -*-
from __future__ import annotations

import sys
import unittest
from dataclasses import replace
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from lib.profile import load_profile  # noqa: E402
from lib.srt_io import SRTBlock  # noqa: E402
from lib.timing import (  # noqa: E402
    chain_continuous_timings,
    finalize_block_timings,
    force_abut_all_cues,
    merge_tail_fragments,
)


class TestTiming(unittest.TestCase):
    def test_merge_tail_fragments(self):
        profile = load_profile("generic")
        blocks = [
            SRTBlock("Hello world", 0.0, 2.0),
            SRTBlock("!", 2.05, 2.1),
        ]
        merged = merge_tail_fragments(blocks, profile)
        self.assertEqual(len(merged), 1)
        self.assertEqual("Hello world!", merged[0].text)

    def test_finalize_allows_abut_when_min_gap_zero(self):
        profile = replace(load_profile("generic"), min_gap=0.0)
        blocks = [
            SRTBlock("A" * 20, 0.0, 1.0),
            SRTBlock("B" * 20, 1.0, 2.0),
        ]
        fixed = finalize_block_timings(blocks, profile)
        self.assertAlmostEqual(fixed[1].start, fixed[0].end, places=3)

    def test_finalize_respects_min_gap_when_set(self):
        profile = replace(load_profile("generic"), min_gap=0.05)
        blocks = [
            SRTBlock("A", 0.0, 1.0),
            SRTBlock("B", 1.02, 2.0),
        ]
        fixed = finalize_block_timings(blocks, profile)
        self.assertGreaterEqual(fixed[1].start, fixed[0].end + profile.min_gap - 1e-9)

    def test_force_abut_all_keeps_starts_fills_any_gap(self):
        profile = replace(load_profile("generic"), min_gap=0.0)
        # Mọi gap đều lấp: end_i == start_{i+1}
        blocks = [
            SRTBlock("あ" * 10, 0.0, 4.5),
            SRTBlock("い" * 10, 5.0, 10.0),
            SRTBlock("う" * 10, 12.0, 14.0),  # gap 2s cũng lấp
        ]
        out = force_abut_all_cues(blocks, profile)
        self.assertEqual(len(out), 3)
        self.assertAlmostEqual(out[0].start, 0.0, places=3)
        self.assertAlmostEqual(out[0].end, out[1].start, places=3)
        self.assertAlmostEqual(out[1].end, out[2].start, places=3)
        self.assertAlmostEqual(out[1].start, 5.0, places=3)
        self.assertAlmostEqual(out[2].start, 12.0, places=3)
        self.assertAlmostEqual(out[2].end, 14.0, places=3)

    def test_chain_alias_force_abut(self):
        profile = replace(load_profile("generic"), min_gap=0.0)
        blocks = [
            SRTBlock("A" * 10, 0.0, 2.0),
            SRTBlock("B" * 10, 4.0, 6.0),
        ]
        out = chain_continuous_timings(blocks, profile)
        self.assertAlmostEqual(out[0].end, 4.0, places=3)
        self.assertAlmostEqual(out[1].start, 4.0, places=3)

    def test_chain_fixes_overlap(self):
        profile = replace(load_profile("generic"), continuity_gap=0.85)
        blocks = [
            SRTBlock("A" * 10, 0.0, 2.5),
            SRTBlock("B" * 10, 2.0, 4.0),
        ]
        out = chain_continuous_timings(blocks, profile)
        self.assertAlmostEqual(out[0].end, 2.0, places=3)
        self.assertAlmostEqual(out[1].start, 2.0, places=3)


if __name__ == "__main__":
    unittest.main()