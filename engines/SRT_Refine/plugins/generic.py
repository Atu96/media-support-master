# -*- coding: utf-8 -*-
"""Fallback plugin — punctuation + space wrap."""

from __future__ import annotations

import re

from lib.profile import Profile
from plugins.base import RefinePlugin

_SENTENCE_END = re.compile(r"[.!?。！？…][\"')\]]*$")
_SPLIT_PUNCT = re.compile(r"[,;:.!?、。！？]")


class GenericPlugin(RefinePlugin):
    lang_codes = ("auto",)

    def is_sentence_end(self, text: str) -> bool:
        stripped = text.rstrip()
        return bool(stripped) and bool(_SENTENCE_END.search(stripped))

    def normalize_cue_text(self, text: str) -> str:
        return re.sub(r"\s+", " ", text.replace("\n", " ")).strip()

    def wrap_lines(self, text: str, profile: Profile) -> str:
        text = self.normalize_cue_text(text)
        if len(text) <= profile.max_line_chars:
            return text
        if profile.max_block_chars <= profile.max_line_chars:
            return text

        ratio = getattr(profile, "top_line_ratio", 1.0) or 1.0
        mid = max(1, int(len(text) * (ratio / (1.0 + ratio))))
        best = None
        best_dist = 10**9
        for match in _SPLIT_PUNCT.finditer(text):
            idx = match.end()
            if idx <= 0 or idx >= len(text):
                continue
            left, right = text[:idx].strip(), text[idx:].strip()
            if not left or not right:
                continue
            if len(left) > profile.max_line_chars or len(right) > profile.max_line_chars:
                continue
            dist = abs(idx - mid)
            if dist < best_dist:
                best_dist = dist
                best = idx

        if best is None:
            space = text.rfind(" ", 0, profile.max_line_chars)
            if space > 0:
                return text[:space].strip() + "\n" + text[space:].strip()
            return text[: profile.max_line_chars] + "\n" + text[profile.max_line_chars :].strip()

        return text[:best].strip() + "\n" + text[best:].strip()

    def split_indices(self, text: str, profile: Profile) -> list[int]:
        text = self.normalize_cue_text(text)
        if len(text) <= profile.max_block_chars:
            return []

        indices: list[int] = []
        cursor = 0
        while cursor < len(text):
            chunk = text[cursor : cursor + profile.max_block_chars]
            if len(chunk) < profile.max_block_chars:
                break
            split_at = None
            for match in _SPLIT_PUNCT.finditer(chunk):
                split_at = cursor + match.end()
            if split_at is None:
                space = chunk.rfind(" ")
                split_at = cursor + (space if space > 0 else profile.max_block_chars)
            if split_at <= cursor:
                split_at = cursor + profile.max_block_chars
            indices.append(split_at)
            cursor = split_at
        return indices