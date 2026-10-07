#!/usr/bin/env python3
"""Pure regression for the project-owned ASS music subtitle renderer."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


def load_renderer(path: Path):
    spec = importlib.util.spec_from_file_location("msm_music_burn", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    renderer = load_renderer(Path(sys.argv[1]))
    blocks = [(0.0, 2.4, "Một dòng nhạc\nbay thật nhẹ")]
    common = dict(
        font="Avenir Next",
        font_size=54,
        text_color="#FFFFFF",
        box_enabled=False,
        box_color="#000000",
        box_opacity=0.8,
        outline_color="#000000",
        outline_opacity=1,
        outline_width=3,
        shadow_color="#000000",
        shadow_opacity=0.7,
        shadow_blur=2,
        shadow_distance=4,
        shadow_angle=315,
        fade_in_ms=220,
        fade_out_ms=260,
        margin_bottom=52,
        play_res=(1920, 1080),
        effect_intensity=0.72,
        effect_speed=1.1,
        effect_direction="left",
        effect_density=6,
        effect_color="#8FD3FF",
    )

    none = renderer.build_ass(blocks, effect_preset="none", **common)
    assert "\\fad(" not in none

    slide = renderer.build_ass(blocks, effect_preset="softSlide", **common)
    assert "\\move(" in slide and "-" in slide

    pop = renderer.build_ass(blocks, effect_preset="softPop", **common)
    assert "\\fscx" in pop and "\\t(" in pop

    fairy_a = renderer.build_ass(blocks, effect_preset="fairyDust", **common)
    fairy_b = renderer.build_ass(blocks, effect_preset="fairyDust", **common)
    assert fairy_a == fairy_b
    assert fairy_a.count("Dialogue:") == 7
    assert "✦" in fairy_a

    butterfly = renderer.build_ass(blocks, effect_preset="butterfly", **common)
    assert "\\p1" in butterfly
    assert butterfly.count("Dialogue:") == 7

    print("✓ Music subtitle renderer regression OK — deterministic effects and decorations")


if __name__ == "__main__":
    main()
