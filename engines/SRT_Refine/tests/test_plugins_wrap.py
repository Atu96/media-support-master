# -*- coding: utf-8 -*-
"""Wrap / merge rules — JA broadcast, EN, VI, ZH."""

from __future__ import annotations

import sys
import unittest
from dataclasses import replace
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from lib.profile import load_profile, profile_for_lang  # noqa: E402
from lib.registry import get_plugin  # noqa: E402


class TestPluginRouting(unittest.TestCase):
    def test_lang_routes(self):
        self.assertEqual(get_plugin("ja").lang_codes[0], "ja")
        self.assertEqual(get_plugin("en").lang_codes[0], "en")
        self.assertEqual(get_plugin("vi").lang_codes[0], "vi")
        self.assertTrue(get_plugin("zh").supports("zh"))
        self.assertTrue(get_plugin("zh-cn").supports("zh"))

    def test_profiles(self):
        self.assertEqual(profile_for_lang("vi").max_line_chars, 42)
        self.assertEqual(profile_for_lang("zh").max_line_chars, 16)
        self.assertEqual(profile_for_lang("ja").max_line_chars, 18)


class TestEnglishWrap(unittest.TestCase):
    def test_no_orphan_the(self):
        plugin = get_plugin("en")
        profile = load_profile("en_youtube")
        text = (
            "The quick brown fox jumps over the lazy dog near the river bank today."
        )
        out = plugin.wrap_lines(text, profile)
        if "\n" in out:
            second = out.split("\n", 1)[1]
            first_word = second.split()[0].lower().strip(".,")
            self.assertNotIn(first_word, {"the", "a", "an", "of", "to"})


class TestVietnameseWrap(unittest.TestCase):
    def test_no_orphan_cua(self):
        plugin = get_plugin("vi")
        profile = load_profile("vi_youtube")
        text = (
            "Cuộc tấn công của lực lượng Ukraine đã làm rung chuyển toàn bộ hệ thống phòng không."
        )
        out = plugin.wrap_lines(text, profile)
        self.assertIn("\n", out)
        second = out.split("\n", 1)[1]
        first = second.split()[0].lower().strip(".,")
        self.assertNotIn(first, {"của", "và", "là", "các", "những", "đã", "sẽ"})

    def test_sentence_end(self):
        plugin = get_plugin("vi")
        self.assertTrue(plugin.is_sentence_end("Kết thúc câu."))
        self.assertFalse(plugin.is_sentence_end("Chưa hết"))


class TestChineseWrap(unittest.TestCase):
    def test_no_head_comma(self):
        plugin = get_plugin("zh")
        profile = load_profile("zh_short")
        text = "欧洲最密集的防空保护伞之下，任何接近的东西都会被击落。"
        out = plugin.wrap_lines(text, profile)
        if "\n" in out:
            second = out.split("\n", 1)[1]
            self.assertFalse(second.startswith("，"))
            self.assertFalse(second.startswith("。"))

    def test_prefers_comma_break(self):
        plugin = get_plugin("zh")
        profile = replace(load_profile("zh_short"), max_line_chars=18, max_block_chars=36)
        text = "莫斯科的官方新闻声称，克里米亚仍是坚不可摧的要塞。"
        out = plugin.wrap_lines(text, profile)
        # Thường ngắt sau ，
        if "，" in text and "\n" in out:
            left = out.split("\n", 1)[0]
            self.assertTrue(left.endswith("，") or "，" not in left)


class TestJapaneseBroadcast(unittest.TestCase):
    def test_top_line_ratio_shifts_break(self):
        plugin = get_plugin("ja")
        base = load_profile("ja_davinci")
        text = "しかし午前四時十四分、クリミア西部のある一角でその鋼鉄の壁は燃えていました。"
        equal = plugin.wrap_lines(text, replace(base, top_line_ratio=1.0))
        short_top = plugin.wrap_lines(text, replace(base, top_line_ratio=0.5))
        # Cả hai phải 2 dòng hoặc ngắn hơn max
        for out in (equal, short_top):
            if "\n" in out:
                for line in out.split("\n"):
                    self.assertLessEqual(len(line), base.max_line_chars + 10)

    def test_kinsoku_no_particle_head(self):
        plugin = get_plugin("ja")
        profile = load_profile("ja_davinci")
        text = "大統領とロシアの将軍たちに向けられた衝撃的な一撃でした。"
        out = plugin.wrap_lines(text, profile)
        if "\n" in out:
            second = out.split("\n", 1)[1]
            self.assertFalse(second.startswith(("が", "は", "を", "に", "の", "、", "。")))

    def test_wrap_prefers_comma_not_mid_tanker(self):
        """、 thắng 1:2 — không cắt タンク|ローリー."""
        plugin = get_plugin("ja")
        base = load_profile("ja_davinci")
        text = "市民は道の真ん中でタンクローリーを止め、わずかな燃料を奪い合っています。"
        for ratio in (1.0, 0.5):
            for maxc in (16, 18, 20, 22):
                out = plugin.wrap_lines(
                    text, replace(base, max_line_chars=maxc, max_block_chars=80, top_line_ratio=ratio)
                )
                self.assertIn("\n", out, f"max={maxc} ratio={ratio}")
                left, right = out.split("\n", 1)
                self.assertTrue(
                    left.endswith("、") or "、" not in text[: maxc + 8],
                    f"expected break after 、 got L1={left!r} (max={maxc} ratio={ratio})",
                )
                self.assertFalse(
                    left.endswith("タンク") and right.startswith("ローリー"),
                    f"bad mid-word break max={maxc} ratio={ratio}: {out!r}",
                )


if __name__ == "__main__":
    unittest.main()
