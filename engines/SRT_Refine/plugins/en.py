# -*- coding: utf-8 -*-
"""English plugin — sentence merge + word wrap (broadcast / YouTube)."""

from __future__ import annotations

import re

from lib.profile import Profile
from plugins.generic import GenericPlugin

_ABBREV_TAIL = re.compile(
    r"\b(Mr|Mrs|Ms|Dr|Prof|Sr|Jr|vs|etc|i\.e|e\.g|U\.S|U\.K|No|St|Gen|Col|Sgt|Lt|Capt|Rev)\.$",
    re.IGNORECASE,
)
_SENTENCE_END = re.compile(r'[.!?]["\')\]]*$')
_STRONG_SPLIT = re.compile(r"[.!?;]")
_SOFT_SPLIT = re.compile(r"[,:—–]")

# Không đứng đầu dòng 2
_HEAD_ORPHAN = {
    "a", "an", "the", "to", "of", "in", "on", "at", "for", "and", "or", "but",
    "is", "are", "was", "were", "be", "been", "being",
    "as", "by", "with", "from", "into", "onto", "upon", "about", "over", "under",
    "that", "this", "these", "those", "which", "who", "whom", "whose",
    "if", "when", "while", "where", "than", "then", "so", "because",
    "not", "no", "nor", "yet",
    "i", "we", "you", "he", "she", "it", "they",
    "my", "our", "your", "his", "her", "its", "their",
}

# Không đứng cuối dòng 1
_TAIL_ORPHAN = {
    "a", "an", "the", "to", "of", "in", "on", "at", "for", "and", "or", "but",
    "as", "by", "with", "from", "into", "that", "this", "if", "when",
}


def _ideal(total: int, ratio: float) -> int:
    r = ratio if ratio and ratio > 0 else 1.0
    return max(1, int(total * (r / (1.0 + r))))


class EnglishPlugin(GenericPlugin):
    lang_codes = ("en",)

    def is_sentence_end(self, text: str) -> bool:
        stripped = text.rstrip()
        if not stripped:
            return False
        if _ABBREV_TAIL.search(stripped):
            return False
        return bool(_SENTENCE_END.search(stripped))

    def wrap_lines(self, text: str, profile: Profile) -> str:
        text = self.normalize_cue_text(text)
        if len(text) <= profile.max_line_chars:
            return text
        if profile.max_block_chars <= profile.max_line_chars:
            return text

        ratio = getattr(profile, "top_line_ratio", 1.0) or 1.0
        # half (0.5) → 1:2; equal (1.0) → 1:1
        mid = _ideal(len(text), ratio)
        max_c = profile.max_line_chars
        want_shorter_top = ratio <= 0.55
        candidates: list[tuple[float, int]] = []

        def consider(idx: int, base_bonus: float = 0.0) -> None:
            left, right = text[:idx].strip(), text[idx:].strip()
            if not left or not right:
                return
            if len(left) > max_c + 2 or len(right) > max_c + 2:
                return
            score = abs(idx - mid) + base_bonus
            left_last = left.split()[-1].lower().strip(".,;:!?\"'")
            right_first = right.split()[0].lower().strip(".,;:!?\"'")
            if left_last in _TAIL_ORPHAN:
                score += 14
            if right_first in _HEAD_ORPHAN:
                score += 14
            if len(right.split()) == 1 and len(right) <= 4:
                score += 10
            # 1:2 — phạt nặng nếu dòng trên dài hơn dòng dưới
            if want_shorter_top and len(left) > len(right):
                score += (len(left) - len(right)) * 4 + 18
            elif not want_shorter_top:
                score += abs(len(left) - len(right)) * 0.2
            candidates.append((score, idx))

        # Ưu tiên dấu câu mạnh → mềm → space
        for match in _STRONG_SPLIT.finditer(text):
            consider(match.end(), base_bonus=-12)
        for match in _SOFT_SPLIT.finditer(text):
            consider(match.end(), base_bonus=-6)
        for m in re.finditer(r" ", text):
            consider(m.start(), base_bonus=2)

        candidates.sort()
        for _, idx in candidates:
            left, right = text[:idx].strip(), text[idx:].strip()
            if not left or not right:
                continue
            if len(left) > max_c + 2 or len(right) > max_c + 2:
                continue
            if want_shorter_top and len(left) > len(right):
                continue  # đã sort; bỏ qua nếu còn sót
            return left + "\n" + right

        # Fallback 1:2: chấp nhận space gần ideal, ép top ≤ bottom
        if want_shorter_top:
            for _, idx in candidates:
                left, right = text[:idx].strip(), text[idx:].strip()
                if left and right and len(left) <= len(right) and len(left) <= max_c + 2 and len(right) <= max_c + 2:
                    return left + "\n" + right

        space = text.rfind(" ", 0, max_c)
        if space > 0:
            return text[:space].strip() + "\n" + text[space:].strip()
        cut = min(max_c, mid)
        return text[:cut] + "\n" + text[cut:].strip()

    def split_indices(self, text: str, profile: Profile) -> list[int]:
        text = self.normalize_cue_text(text)
        if len(text) <= profile.max_block_chars:
            return []

        indices: list[int] = []
        cursor = 0
        while cursor < len(text):
            remaining = text[cursor:]
            if len(remaining) <= profile.max_block_chars:
                break

            window = remaining[: profile.max_block_chars]
            split_at = None

            for match in _STRONG_SPLIT.finditer(window):
                split_at = cursor + match.end()
            if split_at is None:
                for match in _SOFT_SPLIT.finditer(window):
                    split_at = cursor + match.end()
            if split_at is None:
                space = window.rfind(" ")
                split_at = cursor + (space if space > 0 else profile.max_block_chars)

            if split_at <= cursor:
                split_at = cursor + profile.max_block_chars
            indices.append(split_at)
            cursor = split_at

        return indices
