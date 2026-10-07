# -*- coding: utf-8 -*-
"""Parse / render SRT — shared I/O for whisper-only refine pipeline."""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class SRTBlock:
    text: str
    start: float
    end: float

    @property
    def duration(self) -> float:
        return self.end - self.start

    @property
    def char_count(self) -> int:
        return len(self.text.replace("\n", ""))


def parse_srt_time(time_str: str) -> float:
    parts = re.split(r"[:,.]", time_str.strip())
    h, m, s, ms = map(int, parts)
    return h * 3600 + m * 60 + s + ms / 1000.0


def format_srt_time(seconds: float) -> str:
    total_s = int(seconds)
    ms = int(round((seconds - total_s) * 1000))
    if ms >= 1000:
        total_s += 1
        ms -= 1000
    h = total_s // 3600
    m = (total_s % 3600) // 60
    s = total_s % 60
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def read_srt(path: str) -> list[SRTBlock]:
    with open(path, encoding="utf-8", errors="replace") as f:
        content = f.read()
    return parse_srt_content(content)


def parse_srt_content(content: str) -> list[SRTBlock]:
    blocks: list[SRTBlock] = []
    for block in re.split(r"\n\s*\n", content.strip()):
        lines = [line.strip() for line in block.split("\n") if line.strip()]
        if len(lines) < 3:
            continue
        timing_parts = lines[1].split("-->")
        if len(timing_parts) != 2:
            continue
        text = "\n".join(lines[2:])
        blocks.append(
            SRTBlock(
                text=text,
                start=parse_srt_time(timing_parts[0]),
                end=parse_srt_time(timing_parts[1]),
            )
        )
    return blocks


def write_srt(path: str, blocks: list[SRTBlock]) -> None:
    with open(path, "w", encoding="utf-8") as out:
        for idx, block in enumerate(blocks, 1):
            out.write(
                f"{idx}\n"
                f"{format_srt_time(block.start)} --> {format_srt_time(block.end)}\n"
                f"{block.text}\n\n"
            )