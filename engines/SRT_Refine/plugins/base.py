# -*- coding: utf-8 -*-
"""Plugin contract — timing merge/split + display wrap per language."""

from __future__ import annotations

from abc import ABC, abstractmethod

from lib.profile import Profile


class RefinePlugin(ABC):
    lang_codes: tuple[str, ...] = ()

    @abstractmethod
    def is_sentence_end(self, text: str) -> bool:
        """True nếu text kết thúc bằng dấu kết câu."""

    @abstractmethod
    def normalize_cue_text(self, text: str) -> str:
        """Chuẩn hóa text một cue trước merge/split."""

    @abstractmethod
    def wrap_lines(self, text: str, profile: Profile) -> str:
        """Xuống dòng trong cue (tối đa 2 dòng)."""

    @abstractmethod
    def split_indices(self, text: str, profile: Profile) -> list[int]:
        """Vị trí cắt ưu tiên (char index) khi cue quá dài."""

    def leading_punct(self) -> set[str]:
        return {",", ".", "!", "?", ";", ":", "、", "。", "――", "・"}

    def supports(self, lang: str) -> bool:
        lang = (lang or "").lower().split("-")[0]
        return lang in self.lang_codes