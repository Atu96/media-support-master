# -*- coding: utf-8 -*-
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from lib.pipeline import refine_blocks  # noqa: E402
from lib.profile import load_profile  # noqa: E402
from lib.srt_io import read_srt  # noqa: E402
from tests.helpers import make_whisper_srt  # noqa: E402


class TestEnglishRefine(unittest.TestCase):
    def test_merge_fragments_into_sentence(self):
        """Whisper fragments should merge into one cue until sentence end."""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "in.srt"
            out = Path(tmp) / "out.srt"
            make_whisper_srt(
                [
                    ("This is the first", 0.0, 1.2),
                    ("part of a sentence", 1.25, 2.4),
                    ("that was split badly.", 2.45, 3.8),
                    ("Next sentence here.", 4.0, 5.5),
                ],
                path,
            )
            blocks = refine_blocks(read_srt(str(path)), "en", load_profile("en_youtube"))
            write_path = out
            from lib.srt_io import write_srt

            write_srt(str(write_path), blocks)
            texts = [b.text.replace("\n", " ") for b in blocks]
            self.assertEqual(len(blocks), 2)
            self.assertIn("sentence that was split badly.", texts[0])
            self.assertEqual("Next sentence here.", texts[1])

    def test_wrap_long_line(self):
        profile = load_profile("en_youtube")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "in.srt"
            long_text = (
                "The quick brown fox jumps over the lazy dog while the sun sets behind the mountains."
            )
            make_whisper_srt([(long_text, 0.0, 4.0)], path)
            blocks = refine_blocks(read_srt(str(path)), "en", profile)
            self.assertEqual(len(blocks), 1)
            self.assertIn("\n", blocks[0].text)
            lines = blocks[0].text.split("\n")
            self.assertEqual(len(lines), 2)
            for line in lines:
                self.assertLessEqual(len(line), profile.max_line_chars + 6)


if __name__ == "__main__":
    unittest.main()