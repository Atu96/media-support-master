# -*- coding: utf-8 -*-
"""Japanese plugin — MeCab + Kinsoku (chuẩn nhà đài / broadcast)."""

from __future__ import annotations

import os
import re
import subprocess
import unicodedata

from lib.profile import Profile
from plugins.base import RefinePlugin

# Không đứng đầu dòng (禁則処理 — head)
KINSOKU_HEAD_PROHIBITED = {
    # Trợ từ / kết thúc
    "が", "は", "を", "に", "へ", "と", "より", "から", "で", "や", "の", "も", "か",
    "ね", "よ", "な", "ぞ", "さ", "わ", "っけ",
    # Dấu / ngoặc đóng
    "、", "。", "・", "！", "？", "…", "‥", "――", "ー", "～", "〜",
    "」", "』", "）", "］", "】", "〉", "》",
    "％", "%", "℃",
    # Kết thúc phổ biến (không rơi đầu dòng 2)
    "だ", "です", "ます", "でした", "ました", "である", "でした",
    "减", "減",
}

# Không đứng cuối dòng (禁則 — tail)
KINSOKU_TAIL_PROHIBITED = {
    "「", "『", "（", "［", "【", "〈", "《",
}

# Cụm không được xé giữa chừng (mở rộng dần)
ATOMIC_COMPOUNDS = [
    "肉そぼろ",
    "五分の一",
    "あなた自身",
    "ウクライナ",
    "ロシア",
    "クリミア",
    "モスクワ",
    "クレムリン",
    "タンクローリー",
    "S400",
    "S-400",
    "S350",
    "S-350",
]

# Ưu tiên ngắt SAU các dấu này (thắng tỷ lệ 1:2)
WRAP_PUNCT = {"、", "。", "！", "？", "…", "――", "・"}
PARTICLE_SURFACES = {"が", "は", "を", "に", "へ", "と", "で", "も", "や", "から", "より", "の"}

_MECAB_TAGGER = None


def _mecab_dic_dir() -> str:
    env = os.environ.get("MECAB_DICDIR")
    if env and os.path.isdir(env):
        return env
    for candidate in (
        "/opt/homebrew/lib/mecab/dic/unidic",
        "/usr/local/lib/mecab/dic/unidic",
        "/opt/homebrew/lib/mecab/dic/ipadic",
        "/usr/local/lib/mecab/dic/ipadic",
    ):
        if os.path.isdir(candidate):
            return candidate
    for formula, name in (("mecab-unidic", "unidic"), ("mecab-ipadic", "ipadic")):
        try:
            prefix = subprocess.check_output(
                ["brew", "--prefix", formula], text=True, stderr=subprocess.DEVNULL
            ).strip()
            path = f"{prefix}/lib/mecab/dic/{name}"
            if os.path.isdir(path):
                return path
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
    return "/opt/homebrew/lib/mecab/dic/ipadic"


def _get_mecab_tagger():
    global _MECAB_TAGGER
    if _MECAB_TAGGER is None:
        import MeCab

        dic = _mecab_dic_dir()
        _MECAB_TAGGER = MeCab.Tagger(f"-r /dev/null -d {dic}")
    return _MECAB_TAGGER


def tokenize_mecab(text: str) -> list[dict]:
    tagger = _get_mecab_tagger()
    node = tagger.parseToNode(text)
    tokens = []
    while node:
        surf = node.surface
        if surf:
            feat = node.feature.split(",")
            tokens.append(
                {
                    "surface": surf,
                    "pos": feat[0] if feat else "",
                    "pos_detail": feat[1] if len(feat) > 1 else "",
                    "pos_detail2": feat[2] if len(feat) > 2 else "",
                    "conj_form": feat[5] if len(feat) > 5 else "",
                }
            )
        node = node.next
    return tokens


def is_split_safe_boundary(prev_tok: dict | None, next_tok: dict | None) -> bool:
    """Ranh giới an toàn theo Kinsoku + hình thái (broadcast)."""
    if next_tok is None:
        return True
    next_surf = next_tok["surface"]
    prev_surf = prev_tok["surface"] if prev_tok else ""

    if next_surf in KINSOKU_HEAD_PROHIBITED or next_tok["pos"] == "助詞":
        return False
    if prev_surf in KINSOKU_TAIL_PROHIBITED:
        return False
    if next_tok["pos"] in {"助動詞", "接尾"}:
        return False
    # Động từ phụ / biến tố dính
    if next_tok["pos"] == "動詞" and next_surf in {
        "する", "した", "している", "て", "た", "ている", "たい",
        "られる", "られ", "ない", "ず", "せる", "させる",
        "れる", "よう", "う",
    }:
        return False
    if prev_surf in {"て", "で", "に", "を"} and next_tok["pos"] == "動詞":
        return False
    if next_surf in {"った", "ている", "てる", "ちゃう", "じゃう"}:
        return False
    # 「の＋名詞」không cắt giữa
    if prev_surf == "の" and next_tok["pos"] in {"名詞", "代名詞"}:
        return False
    # Động từ 連体形 + danh từ
    if (
        prev_tok
        and prev_tok["pos"] == "動詞"
        and prev_tok.get("conj_form", "") == "連体形"
        and next_tok["pos"] in {"名詞", "代名詞"}
    ):
        return False
    # Số + đơn vị / hậu tố
    if prev_tok and prev_tok["pos"] == "名詞" and prev_tok.get("pos_detail") == "数":
        if next_tok["pos"] in {"名詞", "接尾"} or next_surf in {
            "人", "機", "発", "キロ", "メートル", "％", "%", "年", "月", "日", "時", "分",
        }:
            return False
    return True


def _ideal_split(total_len: int, top_line_ratio: float) -> float:
    """Vị trí tách lý tưởng theo tỷ lệ dòng trên/dưới (panel app)."""
    ratio = top_line_ratio if top_line_ratio and top_line_ratio > 0 else 1.0
    # top:bottom = ratio:1 → top fraction = ratio/(ratio+1)
    return total_len * (ratio / (1.0 + ratio))


def wrap_text_mecab(
    text: str,
    max_chars: int,
    top_line_ratio: float = 1.0,
) -> str:
    """Xuống 2 dòng JP: **dấu câu (、。) thắng tuyệt đối** so với tỷ lệ 1:2.

    - Dưới max_chars: vẫn ngắt sau 、 nếu hai vế ≥ 6 ký tự (broadcast).
    - Trên max: phase punct trước, MeCab sau — không cướp punct vì 1:2.
    """
    text = text.replace("\n", "")
    if not text:
        return text

    total_len = len(text)
    ideal = _ideal_split(total_len, top_line_ratio)
    min_side = 6

    def _punct_char_splits(hard_limit: int) -> list[tuple[float, int]]:
        """Ngắt sau ký tự punct (không cần MeCab) — dùng khi under-max hoặc MeCab fail."""
        pool: list[tuple[float, int]] = []
        for i, ch in enumerate(text):
            if ch not in WRAP_PUNCT:
                continue
            sp = i + 1  # sau dấu
            left_len, right_len = sp, total_len - sp
            if left_len < min_side or right_len < min_side:
                continue
            if left_len > hard_limit or right_len > hard_limit:
                continue
            score = abs(sp - ideal) * 0.12
            if top_line_ratio <= 0.55 and left_len > right_len:
                score += (left_len - right_len) * 0.08  # punct: phạt rất nhẹ
            pool.append((score, sp))
        return pool

    # Under max: ưu tiên punct 2 dòng khi hai vế đủ dài
    if total_len <= max_chars:
        pool = _punct_char_splits(max_chars)
        if pool:
            best = min(pool)[1]
            return text[:best] + "\n" + text[best:]
        return text

    tokens = tokenize_mecab(text)
    if not tokens:
        pool = _punct_char_splits(max_chars + 10)
        if pool:
            best = min(pool)[1]
            return text[:best] + "\n" + text[best:]
        mid = min(max(1, int(ideal)), max_chars)
        return text[:mid] + "\n" + text[mid:]

    tok_starts: list[int] = []
    pos = 0
    for tok in tokens:
        tok_starts.append(pos)
        pos += len(tok["surface"])

    def is_atomic_broken(sp: int) -> bool:
        for compound in ATOMIC_COMPOUNDS:
            cp = text.find(compound)
            while cp != -1:
                if cp < sp < cp + len(compound):
                    return True
                cp = text.find(compound, cp + 1)
        return False

    def is_after_punct(k: int) -> bool:
        return tokens[k - 1]["surface"] in WRAP_PUNCT

    def collect(char_limit: int, punct_only: bool) -> list[tuple[float, int]]:
        pool: list[tuple[float, int]] = []
        for k in range(1, len(tokens)):
            sp = tok_starts[k]
            left_len, right_len = sp, total_len - sp
            if left_len <= 0 or right_len <= 0:
                continue
            if left_len > char_limit or right_len > char_limit:
                continue
            if punct_only and not is_after_punct(k):
                continue
            if not punct_only:
                if not is_split_safe_boundary(tokens[k - 1], tokens[k]):
                    continue
                if is_atomic_broken(sp):
                    continue
            else:
                if is_atomic_broken(sp):
                    continue
                if left_len < min_side or right_len < min_side:
                    continue
            if is_after_punct(k):
                score = abs(sp - ideal) * 0.12
                if top_line_ratio <= 0.55 and left_len > right_len:
                    score += (left_len - right_len) * 0.08
            else:
                score = 1000 + abs(sp - ideal)
                if tokens[k - 1]["surface"] in PARTICLE_SURFACES:
                    score -= 8
                if top_line_ratio <= 0.55 and left_len > right_len:
                    score += (left_len - right_len) * 3.0
            if right_len < 2 or left_len < 2:
                score += 30
            pool.append((score, sp))
        return pool

    best: int | None = None
    # Phase 1: chỉ ngắt sau 、。！？ — nới soft (punct thắng 1:2)
    for soft in (0, 2, 4, 6, 8, 10):
        pool = collect(max_chars + soft, punct_only=True)
        if not pool:
            pool = _punct_char_splits(max_chars + soft)
        if pool:
            best = min(pool)[1]
            break
    # Phase 2: biên MeCab an toàn
    if best is None:
        for soft in (0, 2, 4, 6):
            pool = collect(max_chars + soft, punct_only=False)
            if pool:
                best = min(pool)[1]
                break
    # Phase 3: fallback token gần ideal
    if best is None:
        best = min(int(ideal), max_chars)
        best_dist = abs(best - ideal)
        for k in range(1, len(tokens)):
            sp = tok_starts[k]
            if sp <= 0 or sp >= total_len:
                continue
            if tokens[k]["surface"] in KINSOKU_HEAD_PROHIBITED:
                continue
            if tokens[k]["pos"] == "助詞":
                continue
            if is_atomic_broken(sp):
                continue
            dist = abs(sp - ideal)
            if dist < best_dist:
                best_dist = dist
                best = sp

    return text[:best] + "\n" + text[best:]


class JapaneseMecabPlugin(RefinePlugin):
    lang_codes = ("ja", "jp")

    def is_sentence_end(self, text: str) -> bool:
        stripped = text.rstrip()
        if not stripped:
            return False
        # Hết câu nhà đài: 。！？… và dấu kép đóng sau đó
        return bool(re.search(r"[。！？…][」』）\]]*$", stripped))

    def normalize_cue_text(self, text: str) -> str:
        text = unicodedata.normalize("NFKC", text.replace("\n", ""))
        # JP broadcast: không giữ space Latin thừa giữa kana
        return re.sub(r"\s+", "", text).strip()

    def wrap_lines(self, text: str, profile: Profile) -> str:
        text = self.normalize_cue_text(text)
        if profile.max_block_chars <= profile.max_line_chars:
            return text
        ratio = getattr(profile, "top_line_ratio", 1.0) or 1.0
        try:
            return wrap_text_mecab(text, profile.max_line_chars, top_line_ratio=ratio)
        except Exception:
            if len(text) <= profile.max_line_chars:
                return text
            mid = max(1, int(_ideal_split(len(text), ratio)))
            mid = min(mid, profile.max_line_chars)
            return text[:mid] + "\n" + text[mid:]

    def split_indices(self, text: str, profile: Profile) -> list[int]:
        text = self.normalize_cue_text(text)
        if len(text) <= profile.max_block_chars:
            return []

        tokens: list[dict] = []
        try:
            tokens = tokenize_mecab(text)
        except Exception:
            tokens = []

        if not tokens:
            mid = len(text) // 2
            return [mid] if mid < len(text) else []

        tok_starts: list[int] = []
        pos = 0
        for tok in tokens:
            tok_starts.append(pos)
            pos += len(tok["surface"])

        indices: list[int] = []
        cursor = 0
        while cursor < len(text):
            remaining = len(text) - cursor
            if remaining <= profile.max_block_chars:
                break
            target = cursor + profile.max_block_chars
            best = None
            best_score = 10**9
            for k in range(1, len(tokens)):
                sp = tok_starts[k]
                if sp <= cursor or sp >= len(text):
                    continue
                if sp > target + 6:
                    break
                if not is_split_safe_boundary(tokens[k - 1], tokens[k]):
                    continue
                # Ưu tiên gần target; thưởng ngắt sau 、
                score = abs(sp - target)
                if tokens[k - 1]["surface"] in WRAP_PUNCT:
                    score -= 8
                if score < best_score:
                    best_score = score
                    best = sp
            if best is None or best <= cursor:
                best = min(cursor + profile.max_block_chars, len(text))
            indices.append(best)
            cursor = best
        return indices

    def leading_punct(self) -> set[str]:
        return {"、", "。", "――", "・", "…", ",", ".", "!", "?", "！", "？"}
