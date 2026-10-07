# -*- coding: utf-8 -*-
"""Whisper-only SRT refine pipeline — merge, split, timing, wrap."""

from __future__ import annotations

from lib.profile import Profile
from lib.registry import get_plugin
from lib.srt_io import SRTBlock
from lib.timing import (
    attach_leading_punct,
    chain_continuous_timings,
    finalize_block_timings,
    force_abut_all_cues,
    merge_tail_fragments,
    redistribute_cps_clusters,
)
from plugins.base import RefinePlugin


def _normalize_blocks(blocks: list[SRTBlock], plugin: RefinePlugin) -> list[SRTBlock]:
    return [
        SRTBlock(plugin.normalize_cue_text(b.text), b.start, b.end)
        for b in blocks
        if plugin.normalize_cue_text(b.text)
    ]


def _needs_split(block: SRTBlock, profile: Profile) -> bool:
    if block.duration > profile.max_duration:
        return True
    if block.char_count > profile.max_block_chars:
        return True
    if block.duration > 0 and block.char_count / block.duration > profile.max_cps * profile.cps_cluster_multiplier:
        return True
    return False


def merge_consecutive_blocks(
    blocks: list[SRTBlock],
    plugin: RefinePlugin,
    profile: Profile,
) -> list[SRTBlock]:
    if not blocks:
        return blocks

    merged: list[SRTBlock] = []
    current = blocks[0]

    for nxt in blocks[1:]:
        gap = nxt.start - current.end
        combined = f"{current.text} {nxt.text}".strip()
        combined_chars = len(combined.replace("\n", ""))
        combined_dur = nxt.end - current.start

        should_merge = (
            gap <= profile.merge_gap
            and not plugin.is_sentence_end(current.text)
            and combined_chars <= profile.max_block_chars
            and combined_dur <= profile.max_duration * 1.25
        )

        if should_merge:
            current = SRTBlock(combined, current.start, nxt.end)
        else:
            merged.append(current)
            current = nxt

    merged.append(current)
    return merged


def split_block_at(
    block: SRTBlock,
    split_idx: int,
    profile: Profile,
) -> list[SRTBlock]:
    text = block.text.replace("\n", " ")
    left = text[:split_idx].strip()
    right = text[split_idx:].strip()
    if not left or not right:
        return [block]

    # Chia tỷ lệ theo ký tự trong span gốc — mid dính liền (không đục min_gap).
    total = max(block.duration, 0.01)
    ratio = len(left) / max(len(text), 1)
    mid = block.start + total * ratio
    # Giữ mid trong (start, end); không ép min_duration hai phía nếu span hẹp.
    eps = 0.01
    mid = max(mid, block.start + eps)
    mid = min(mid, block.end - eps)
    if mid <= block.start or mid >= block.end:
        return [block]

    return [
        SRTBlock(left, block.start, mid),
        SRTBlock(right, mid, block.end),
    ]


def split_oversized_blocks(
    blocks: list[SRTBlock],
    plugin: RefinePlugin,
    profile: Profile,
) -> list[SRTBlock]:
    result: list[SRTBlock] = []
    for block in blocks:
        pending = [block]
        while pending:
            current = pending.pop(0)
            if not _needs_split(current, profile):
                result.append(current)
                continue

            text = current.text.replace("\n", " ")
            indices = [i for i in plugin.split_indices(text, profile) if 0 < i < len(text)]
            if not indices:
                mid = max(1, len(text) // 2)
                indices = [mid]

            parts = split_block_at(current, indices[0], profile)
            for part in reversed(parts):
                pending.insert(0, part)

    return result


def refine_blocks(
    blocks: list[SRTBlock],
    lang: str,
    profile: Profile | None = None,
) -> list[SRTBlock]:
    plugin = get_plugin(lang)
    prof = profile or __import__("lib.profile", fromlist=["profile_for_lang"]).profile_for_lang(lang)

    blocks = _normalize_blocks(blocks, plugin)
    if not blocks:
        return []

    blocks = merge_consecutive_blocks(blocks, plugin, prof)
    blocks = split_oversized_blocks(blocks, plugin, prof)
    blocks = merge_tail_fragments(blocks, prof)

    blocks = [
        SRTBlock(b.text, b.start, max(b.end, b.start + 0.01))
        for b in blocks
    ]
    blocks = attach_leading_punct(blocks, plugin.leading_punct())
    blocks = redistribute_cps_clusters(blocks, prof)
    blocks = chain_continuous_timings(blocks, prof)
    blocks = finalize_block_timings(blocks, prof)
    blocks = [
        SRTBlock(plugin.wrap_lines(b.text, prof), b.start, b.end)
        for b in blocks
    ]
    blocks = finalize_block_timings(blocks, prof)
    # Bước CUỐI bắt buộc: end_i == start_{i+1} (khít tuyệt đối, dễ kéo dãn sau).
    blocks = force_abut_all_cues(blocks, prof)

    return blocks