# -*- coding: utf-8 -*-
"""Vietnamese plugin — word wrap, tránh từ mồ côi đầu/cuối dòng."""

from __future__ import annotations

import re
import unicodedata

from lib.profile import Profile
from plugins.generic import GenericPlugin

_SENTENCE_END = re.compile(r'[.!?…:"»”\']*$')
_STRONG = re.compile(r"[.!?…]")
_SOFT = re.compile(r"[,;:–—]")

# Không để đứng đầu dòng 2 (orphan đầu)
_HEAD_ORPHAN = {
    "và", "hoặc", "hay", "nhưng", "mà", "nên", "vì", "do", "bởi", "nếu", "thì",
    "của", "cho", "với", "về", "trong", "ngoài", "trên", "dưới", "giữa",
    "từ", "đến", "tới", "theo", "như", "bằng", "cùng",
    "là", "bị", "được", "đã", "sẽ", "đang", "vẫn", "cứ", "hãy", "đừng",
    "các", "những", "mọi", "mỗi", "một", "nhiều", "ít",
    "rất", "quá", "hơi", "khá", "cực", "thật",
    "này", "kia", "đó", "ấy", "nọ",
    "không", "chưa", "chẳng", "chả",
    "tôi", "bạn", "anh", "chị", "em", "họ", "chúng", "ta", "mình",
    "a", "an", "the", "to", "of", "in", "on", "at", "for", "and", "or", "but",
}

# Không để đứng cuối dòng 1 (dangling)
_TAIL_ORPHAN = {
    "và", "hoặc", "hay", "nhưng", "mà", "nên", "vì", "do", "bởi",
    "của", "cho", "với", "về", "trong", "từ", "đến", "theo", "như", "bằng",
    "là", "bị", "được", "đã", "sẽ", "đang",
    "các", "những", "một",
    "không", "chưa",
    "the", "a", "an", "to", "of", "in", "on", "at", "for", "and", "or",
}


def _norm(text: str) -> str:
    text = unicodedata.normalize("NFC", text.replace("\n", " "))
    return re.sub(r"\s+", " ", text).strip()


def _ideal(total: int, ratio: float) -> int:
    r = ratio if ratio and ratio > 0 else 1.0
    return max(1, int(total * (r / (1.0 + r))))


def _word_spans(text: str) -> list[tuple[int, int, str]]:
    """(start, end, word) inclusive end-exclusive."""
    return [(m.start(), m.end(), m.group(0)) for m in re.finditer(r"\S+", text)]


class VietnamesePlugin(GenericPlugin):
    lang_codes = ("vi",)

    def is_sentence_end(self, text: str) -> bool:
        stripped = text.rstrip()
        if not stripped:
            return False
        # Kết thúc bằng . ! ? … (có thể kèm ngoặc/dấu kép)
        return bool(re.search(r'[.!?…]["\'»”)\]]*$', stripped))

    def normalize_cue_text(self, text: str) -> str:
        return _norm(text)

    def wrap_lines(self, text: str, profile: Profile) -> str:
        text = self.normalize_cue_text(text)
        if len(text) <= profile.max_line_chars:
            return text
        if profile.max_block_chars <= profile.max_line_chars:
            return text

        ratio = getattr(profile, "top_line_ratio", 1.0) or 1.0
        ideal = _ideal(len(text), ratio)
        max_c = profile.max_line_chars
        want_shorter_top = ratio <= 0.55
        words = _word_spans(text)
        if len(words) < 2:
            mid = min(max_c, max(1, ideal))
            return text[:mid].strip() + "\n" + text[mid:].strip()

        candidates: list[tuple[float, int]] = []

        def consider(idx: int, bonus: float = 0.0) -> None:
            left, right = text[:idx].strip(), text[idx:].strip()
            if not left or not right:
                return
            if len(left) > max_c + 2 or len(right) > max_c + 2:
                return
            left_last = left.split()[-1].lower().strip(".,;:!?…\"'")
            right_first = right.split()[0].lower().strip(".,;:!?…\"'")
            score = abs(idx - ideal) + bonus
            if left_last in _TAIL_ORPHAN:
                score += 12
            if right_first in _HEAD_ORPHAN:
                score += 12
            if len(right.split()) == 1 and len(right) < 6:
                score += 8
            if want_shorter_top and len(left) > len(right):
                score += (len(left) - len(right)) * 4 + 18
            candidates.append((score, idx))

        for match in _STRONG.finditer(text):
            if 0 < match.end() < len(text):
                consider(match.end(), bonus=-12)
        for match in _SOFT.finditer(text):
            if 0 < match.end() < len(text):
                consider(match.end(), bonus=-6)

        for i in range(len(words) - 1):
            idx = words[i][1]
            while idx < len(text) and text[idx] == " ":
                idx += 1
            if 0 < idx < len(text):
                consider(idx, bonus=2)

        candidates.sort()
        for _, idx in candidates:
            left, right = text[:idx].strip(), text[idx:].strip()
            if not left or not right:
                continue
            if len(left) > max_c + 2 or len(right) > max_c + 2:
                continue
            if want_shorter_top and len(left) > len(right):
                continue
            return left + "\n" + right

        if want_shorter_top:
            for _, idx in candidates:
                left, right = text[:idx].strip(), text[idx:].strip()
                if left and right and len(left) <= len(right):
                    if len(left) <= max_c + 2 and len(right) <= max_c + 2:
                        return left + "\n" + right

        # Fallback: cắt tại space gần max
        space = text.rfind(" ", 0, max_c)
        if space > 0:
            return text[:space].strip() + "\n" + text[space:].strip()
        mid = min(max_c, max(1, ideal))
        return text[:mid] + "\n" + text[mid:].strip()

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
            for match in _STRONG.finditer(window):
                split_at = cursor + match.end()
            if split_at is None:
                for match in _SOFT.finditer(window):
                    split_at = cursor + match.end()
            if split_at is None:
                space = window.rfind(" ")
                split_at = cursor + (space if space > 0 else profile.max_block_chars)
            if split_at <= cursor:
                split_at = cursor + profile.max_block_chars
            indices.append(split_at)
            cursor = split_at
        return indices

    def leading_punct(self) -> set[str]:
        return {",", ".", "!", "?", ";", ":", "…", "—", "–"}
