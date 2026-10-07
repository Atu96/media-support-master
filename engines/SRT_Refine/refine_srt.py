#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
refine_srt.py — Post-process Whisper SRT (no script).

Usage:
  refine_srt.py --in whisper.srt --out refined.srt --lang en [--profile en_youtube]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

from dataclasses import replace  # noqa: E402

from lib.pipeline import refine_blocks  # noqa: E402
from lib.profile import load_profile, profile_for_lang  # noqa: E402
from lib.srt_io import read_srt, write_srt  # noqa: E402


def _apply_wrap_overrides(profile, args):
    """Áp max line/block + top ratio từ app (panel Kiểu sub)."""
    updates = {}
    if args.max_line_chars and args.max_line_chars > 0:
        updates["max_line_chars"] = int(args.max_line_chars)
    if args.max_block_chars and args.max_block_chars > 0:
        updates["max_block_chars"] = int(args.max_block_chars)
    elif "max_line_chars" in updates:
        # 2 dòng mặc định nếu app không gửi block
        updates["max_block_chars"] = updates["max_line_chars"] * 2

    # twoThirds legacy → equal (1:1). half = 1:2.
    ratio_map = {
        "equal": 1.0,
        "twoThirds": 1.0,
        "half": 0.5,
    }
    if args.top_line_ratio:
        updates["top_line_ratio"] = ratio_map.get(args.top_line_ratio, 1.0)

    if not updates:
        return profile
    return replace(profile, **updates)


def main() -> int:
    parser = argparse.ArgumentParser(description="Refine Whisper SRT (timing + line wrap)")
    parser.add_argument("--in", dest="input_path", required=True, help="Input SRT path")
    parser.add_argument("--out", dest="output_path", required=True, help="Output SRT path")
    parser.add_argument("--lang", default="auto", help="Language code (en, ja, auto, …)")
    parser.add_argument("--profile", default="", help="Profile name override (en_youtube, ja_davinci, …)")
    parser.add_argument("--max-line-chars", type=int, default=0, help="Override max chars per line")
    parser.add_argument("--max-block-chars", type=int, default=0, help="Override max chars per cue")
    parser.add_argument(
        "--top-line-ratio",
        default="",
        help="equal (1:1) | half (1:2) — top vs bottom; twoThirds legacy → equal",
    )
    args = parser.parse_args()

    profile = load_profile(args.profile) if args.profile else profile_for_lang(args.lang)
    profile = _apply_wrap_overrides(profile, args)
    blocks = read_srt(args.input_path)
    refined = refine_blocks(blocks, args.lang, profile)
    write_srt(args.output_path, refined)

    print(f"✅ Refined: {len(blocks)} → {len(refined)} cues")
    print(f"   lang={args.lang} profile={args.profile or 'auto'}")
    print(
        f"   wrap line={profile.max_line_chars} block={profile.max_block_chars} "
        f"top_ratio={getattr(profile, 'top_line_ratio', 1.0)}"
    )
    print(f"   out={args.output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())