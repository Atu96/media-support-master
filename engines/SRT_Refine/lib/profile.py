# -*- coding: utf-8 -*-
"""Timing / wrap profiles per language or use-case."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


PROFILES_DIR = Path(__file__).resolve().parent / "profiles"


@dataclass(frozen=True)
class Profile:
    max_cps: float = 17.0
    min_duration: float = 0.8
    max_duration: float = 6.5
    # 0 = cue dính liền (liên tục). >0 chỉ khi cần khe cứng giữa cue.
    min_gap: float = 0.0
    end_pad: float = 0.15
    max_line_chars: int = 42
    max_block_chars: int = 84
    merge_gap: float = 0.6
    cps_cluster_multiplier: float = 2.0
    cluster_gap: float = 2.0
    # Gap ≤ này coi là cùng chuỗi nói → dính liền (end = start kế).
    # 1.2s: nuốt nghỉ ngắn Whisper; im lặng thật dài hơn vẫn giữ.
    continuity_gap: float = 1.2
    # top / bottom — 1.0 = 1:1, 2/3 ≈ 0.667, 0.5 = 1:2
    top_line_ratio: float = 1.0


DEFAULT_PROFILES: dict[str, Profile] = {
    "generic": Profile(),
    "en_youtube": Profile(
        max_cps=17.0,
        max_line_chars=42,
        max_block_chars=84,
        merge_gap=0.6,
    ),
    "ja_davinci": Profile(
        max_cps=14.0,
        max_line_chars=18,
        max_block_chars=36,
        merge_gap=0.5,
    ),
    "vi_youtube": Profile(
        max_cps=17.0,
        max_line_chars=42,
        max_block_chars=84,
        merge_gap=0.55,
    ),
    "zh_short": Profile(
        max_cps=15.0,
        max_line_chars=16,
        max_block_chars=32,
        merge_gap=0.5,
    ),
}


def _load_yaml_profile(name: str) -> Profile | None:
    path = PROFILES_DIR / f"{name}.yaml"
    if not path.is_file():
        return None
    try:
        import yaml
    except ImportError:
        return None
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    base = DEFAULT_PROFILES.get(name, DEFAULT_PROFILES["generic"])
    fields = {f.name: data.get(f.name, getattr(base, f.name)) for f in Profile.__dataclass_fields__.values()}
    return Profile(**fields)


def load_profile(name: str) -> Profile:
    yaml_profile = _load_yaml_profile(name)
    if yaml_profile is not None:
        return yaml_profile
    return DEFAULT_PROFILES.get(name, DEFAULT_PROFILES["generic"])


def profile_for_lang(lang: str) -> Profile:
    lang = (lang or "auto").lower().replace("_", "-").split("-")[0]
    if lang in {"ja", "jp"}:
        return load_profile("ja_davinci")
    if lang == "en":
        return load_profile("en_youtube")
    if lang == "vi":
        return load_profile("vi_youtube")
    if lang in {"zh", "yue", "cmn"}:
        return load_profile("zh_short")
    return load_profile("generic")