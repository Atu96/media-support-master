# -*- coding: utf-8 -*-
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from lib.srt_io import SRTBlock, format_srt_time, write_srt  # noqa: E402


def make_whisper_srt(blocks: list[tuple[str, float, float]], path: Path) -> None:
    srt_blocks = [SRTBlock(text=t, start=s, end=e) for t, s, e in blocks]
    write_srt(str(path), srt_blocks)