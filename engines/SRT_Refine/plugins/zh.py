# -*- coding: utf-8 -*-
"""Chinese plugin — ngắt theo dấu câu / 禁则 đơn giản (không cần jieba)."""

from __future__ import annotations

import re
import unicodedata

from lib.profile import Profile
from plugins.base import RefinePlugin

# Không đứng đầu dòng (dấu + trợ từ/tiểu từ hay gặp)
_HEAD_PROHIBITED = (
    set("，。！？、；：…—～」』）】》〉%％℃")
    | set(",.!?;:)]}%")
    | set("的了着过吗呢吧啊呀嘛么")
)
# Không đứng cuối dòng
_TAIL_PROHIBITED = set("「『（【《〈") | set("([{")

_SENTENCE_END = re.compile(r"[。！？…][」』）\]]*$")
_BREAK_CHARS = set("，。！？、；：…")


def _norm(text: str) -> str:
    text = unicodedata.normalize("NFKC", text.replace("\n", ""))
    # Giữ space giữa Latin/số nếu có; gộp space thừa
    text = re.sub(r"\s+", " ", text).strip()
    # Bỏ space giữa CJK (Whisper đôi khi chèn)
    text = re.sub(r"(?<=[\u4e00-\u9fff])\s+(?=[\u4e00-\u9fff])", "", text)
    return text


def _ideal(total: int, ratio: float) -> float:
    r = ratio if ratio and ratio > 0 else 1.0
    return total * (r / (1.0 + r))


def _char_width_units(ch: str) -> int:
    """Đếm 'ô' hiển thị: CJK/fullwidth ≈ 1, Latin hẹp cũng 1 (subtitle char count)."""
    return 1


def _len(text: str) -> int:
    return sum(_char_width_units(c) for c in text)


class ChinesePlugin(RefinePlugin):
    lang_codes = ("zh", "yue", "zh_cn", "zh_tw", "zh_hk")

    def supports(self, lang: str) -> bool:
        lang = (lang or "").lower().replace("_", "-").split("-")[0]
        return lang in {"zh", "yue", "cmn"}

    def is_sentence_end(self, text: str) -> bool:
        stripped = text.rstrip()
        return bool(stripped) and bool(_SENTENCE_END.search(stripped))

    def normalize_cue_text(self, text: str) -> str:
        return _norm(text)

    def wrap_lines(self, text: str, profile: Profile) -> str:
        text = self.normalize_cue_text(text)
        if _len(text) <= profile.max_line_chars:
            return text
        if profile.max_block_chars <= profile.max_line_chars:
            return text

        ratio = getattr(profile, "top_line_ratio", 1.0) or 1.0
        ideal = _ideal(len(text), ratio)
        max_c = profile.max_line_chars
        want_shorter_top = ratio <= 0.55
        n = len(text)

        candidates: list[tuple[float, int]] = []
        for i in range(1, n):
            left, right = text[:i], text[i:]
            if not left or not right:
                continue
            if _len(left) > max_c + 2 or _len(right) > max_c + 2:
                continue
            # 禁则
            if right[0] in _HEAD_PROHIBITED:
                continue
            if left[-1] in _TAIL_PROHIBITED:
                continue
            score = abs(i - ideal)
            # Ưu tiên mạnh sau dấu câu
            if left[-1] in "。！？":
                score -= 14
            elif left[-1] in _BREAK_CHARS:
                score -= 8
            if _len(left) < 2 or _len(right) < 2:
                score += 15
            if want_shorter_top and _len(left) > _len(right):
                score += (_len(left) - _len(right)) * 5 + 20
            candidates.append((score, i))

        if not candidates:
            # Nới limit để vẫn tránh 禁则
            for i in range(1, n):
                right_ok = text[i:]
                if not right_ok:
                    continue
                if text[i] in _HEAD_PROHIBITED:
                    continue
                if text[i - 1] in _TAIL_PROHIBITED:
                    continue
                if _len(text[:i]) <= max_c + 4 and _len(right_ok) <= max_c + 4:
                    candidates.append((abs(i - ideal), i))

        if candidates:
            candidates.sort()
            best = candidates[0][1]
            return text[:best] + "\n" + text[best:]

        mid = max(1, min(int(ideal), max_c))
        return text[:mid] + "\n" + text[mid:]

    def split_indices(self, text: str, profile: Profile) -> list[int]:
        text = self.normalize_cue_text(text)
        if _len(text) <= profile.max_block_chars:
            return []

        indices: list[int] = []
        cursor = 0
        n = len(text)
        while cursor < n:
            remaining = n - cursor
            if remaining <= profile.max_block_chars:
                break
            target = cursor + profile.max_block_chars
            best = None
            best_score = 10**9
            lo = cursor + max(2, profile.max_block_chars // 3)
            hi = min(n - 1, target + 4)
            for i in range(lo, hi + 1):
                left_ch = text[i - 1]
                right_ch = text[i] if i < n else ""
                if right_ch in _HEAD_PROHIBITED:
                    continue
                if left_ch in _TAIL_PROHIBITED:
                    continue
                score = abs(i - target)
                if left_ch in _BREAK_CHARS:
                    score -= 10
                if score < best_score:
                    best_score = score
                    best = i
            if best is None or best <= cursor:
                best = min(cursor + profile.max_block_chars, n)
            indices.append(best)
            cursor = best
        return indices

    def leading_punct(self) -> set[str]:
        return {"，", "。", "、", "！", "？", "；", "：", "…", ",", ".", "!", "?"}
