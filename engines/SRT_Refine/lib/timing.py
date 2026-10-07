# -*- coding: utf-8 -*-
"""Language-agnostic timing repair — logic mirrored from Whisper_Native/srt_core.py."""

from __future__ import annotations

from lib.profile import Profile
from lib.srt_io import SRTBlock


def merge_tail_fragments(blocks: list[SRTBlock], profile: Profile) -> list[SRTBlock]:
    """Gộp mảnh rác <= 5 ký tự hoặc <= 0.25s vào cue trước."""
    if not blocks:
        return blocks
    merged = [blocks[0]]
    for block in blocks[1:]:
        prev = merged[-1]
        if block.duration <= 0.25 or len(block.text.strip()) <= 5:
            merged[-1] = SRTBlock(
                text=prev.text + block.text,
                start=prev.start,
                end=block.end,
            )
        else:
            merged.append(block)
    return merged


def _abut_gap() -> float:
    """Khe giữa cue liên tục — 0 = dính liền (start_next == end_prev)."""
    return 0.0


def redistribute_cps_clusters(blocks: list[SRTBlock], profile: Profile) -> list[SRTBlock]:
    """Tái phân bổ timing khi Whisper dồn quá nhiều chữ vào cửa sổ quá ngắn."""
    if not blocks:
        return blocks

    threshold = profile.max_cps * profile.cps_cluster_multiplier
    result = list(blocks)
    abut = _abut_gap()

    def block_cps(block: SRTBlock) -> float:
        if block.duration <= 0:
            return float("inf")
        return block.char_count / block.duration

    impossible = [block_cps(b) > threshold for b in blocks]
    i = 0
    while i < len(blocks):
        if not impossible[i]:
            i += 1
            continue

        j = i
        while (
            j + 1 < len(blocks)
            and impossible[j + 1]
            and blocks[j + 1].start - blocks[j].end <= profile.cluster_gap
        ):
            j += 1

        if j == i:
            block = blocks[i]
            min_needed = max(block.char_count / profile.max_cps, profile.min_duration)
            if block.duration < min_needed:
                result[i] = SRTBlock(block.text, block.start, block.start + min_needed)
            i += 1
            continue

        cluster = blocks[i : j + 1]
        cluster_start = cluster[0].start
        cluster_end = cluster[-1].end
        total_duration = cluster_end - cluster_start
        total_chars = sum(max(1, b.char_count) for b in cluster)

        if total_chars == 0 or total_duration <= 0:
            i = j + 1
            continue

        min_needed_total = total_chars / profile.max_cps
        if total_duration < min_needed_total:
            next_cap = (
                blocks[j + 1].start
                if j + 1 < len(blocks)
                else cluster_start + min_needed_total + 5.0
            )
            # Giữ sát cue kế nếu min_gap=0; không tạo lỗ nhân tạo.
            cluster_end = min(cluster_start + min_needed_total, next_cap - abut)
            total_duration = max(cluster_end - cluster_start, profile.min_duration)

        char_counts = [max(1, b.char_count) for b in cluster]
        ratios = [c / total_chars for c in char_counts]
        durations = [max(r * total_duration, profile.min_duration) for r in ratios]

        total_alloc = sum(durations)
        if total_alloc > total_duration:
            scale = total_duration / total_alloc
            durations = [d * scale for d in durations]

        cur_time = cluster_start
        for k, block in enumerate(cluster):
            new_s = cur_time
            new_e = cur_time + durations[k]
            result[i + k] = SRTBlock(
                block.text,
                new_s,
                max(new_e, new_s + 0.01),
            )
            cur_time = new_e + abut

        i = j + 1

    return result


def chain_continuous_timings(blocks: list[SRTBlock], profile: Profile) -> list[SRTBlock]:
    """Alias → ``force_abut_all_cues`` (khít tuyệt đối)."""
    return force_abut_all_cues(blocks, profile)


def force_abut_all_cues(blocks: list[SRTBlock], profile: Profile | None = None) -> list[SRTBlock]:
    """Khít tuyệt đối: end_i == start_{i+1} theo thứ tự thời gian.

    - Giữ **start** mỗi cue (mốc Whisper / sau refine).
    - End cue i luôn = start cue i+1 → không khe trống giữa hai dòng.
    - Im lặng giữa hai cue → dồn vào **đuôi cue trước** (sub vẫn hiện).
    - Cue cuối: giữ end gốc.
    - Thuận kéo dãn timeline sau này (partition liên tục).
    """
    if len(blocks) < 2:
        return blocks

    ordered = sorted(blocks, key=lambda b: (b.start, b.end))
    result: list[SRTBlock] = []
    for i, cur in enumerate(ordered):
        if i + 1 < len(ordered):
            nxt = ordered[i + 1]
            new_end = nxt.start
            if new_end <= cur.start:
                new_end = cur.start + 0.01
            result.append(SRTBlock(cur.text, cur.start, new_end))
        else:
            end = cur.end if cur.end > cur.start else cur.start + 0.01
            result.append(SRTBlock(cur.text, cur.start, end))

    # Ép lại một lượt: end_i == start_{i+1}
    for i in range(len(result) - 1):
        cur, nxt = result[i], result[i + 1]
        if abs(cur.end - nxt.start) < 1e-9:
            continue
        new_end = nxt.start
        if new_end <= cur.start:
            new_end = cur.start + 0.01
            result[i + 1] = SRTBlock(nxt.text, new_end, max(nxt.end, new_end + 0.01))
        result[i] = SRTBlock(cur.text, cur.start, new_end)

    return result


def finalize_block_timings(blocks: list[SRTBlock], profile: Profile) -> list[SRTBlock]:
    """Sàn duration/CPS trong cửa sổ [start, start_next); luôn chạm start_next nếu có.

    Sau bước này pipeline gọi ``force_abut_all_cues`` để bảo đảm
    end_i == start_{i+1} tuyệt đối (khít cho kéo timeline).
    """
    if not blocks:
        return blocks
    fixed: list[SRTBlock] = []
    n = len(blocks)
    for idx, block in enumerate(blocks):
        start = block.start
        end = block.end
        need = (
            max(block.char_count / profile.max_cps, profile.min_duration)
            if block.char_count
            else profile.min_duration
        )
        if fixed:
            floor = fixed[-1].end + profile.min_gap
            if start < floor:
                start = floor
        desired_end = max(end, start + need)
        next_start = blocks[idx + 1].start if idx + 1 < n else None
        if next_start is not None and next_start > start:
            # Trong chuỗi sub: ưu tiên chạm start kế (khít); không đè quá.
            end = next_start if desired_end >= next_start else next_start
            # desired_end có thể < next_start — vẫn kéo tới next_start (khít).
            end = next_start
        else:
            end = desired_end
        if end <= start:
            end = start + 0.01
        fixed.append(SRTBlock(block.text, start, end))
    return fixed


def attach_leading_punct(blocks: list[SRTBlock], leading_punct: set[str]) -> list[SRTBlock]:
    """Dán dấu câu rớt đầu cue vào cue trước — không kéo dài end_time."""
    cleaned: list[SRTBlock] = []
    for block in blocks:
        stripped = block.text
        while stripped and stripped[0] in leading_punct:
            if cleaned:
                prev = cleaned[-1]
                cleaned[-1] = SRTBlock(prev.text + stripped[0], prev.start, prev.end)
            stripped = stripped[1:].lstrip()
        if stripped:
            cleaned.append(SRTBlock(stripped, block.start, block.end))
    return cleaned