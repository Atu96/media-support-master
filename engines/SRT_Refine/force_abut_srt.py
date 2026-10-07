#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Chỉ khép timing: end_i = start_{i+1}. Không đổi chữ / wrap.

Dùng sau align kịch bản (srt_core) để khớp sub tự động (force_abut).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# lib/ cùng package
sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib.srt_io import read_srt, write_srt  # noqa: E402
from lib.timing import force_abut_all_cues  # noqa: E402


def main() -> int:
    p = argparse.ArgumentParser(description="Force-abut SRT timings (no text change)")
    p.add_argument("--in", dest="inp", required=True)
    p.add_argument("--out", dest="out", required=True)
    args = p.parse_args()

    blocks = read_srt(args.inp)
    if not blocks:
        print(f"❌ Không parse được SRT: {args.inp}", file=sys.stderr)
        return 1

    abutted = force_abut_all_cues(blocks, profile=None)
    write_srt(args.out, abutted)
    print(f"✅ force_abut: {len(abutted)} cue → {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
