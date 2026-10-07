#!/usr/bin/env python3
"""SRT → ASS → ffmpeg burn, including deterministic app-only music effects."""

from __future__ import annotations

import argparse
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path


MUSIC_PRESETS = {
    "gentleFloat",
    "softSlide",
    "softPop",
    "lightSweep",
    "fairyDust",
    "butterfly",
}


def srt_to_sec(tc: str) -> float:
    h, m, rest = tc.split(":")
    s, ms = rest.replace(",", ".").split(".")
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def sec_to_ass(sec: float) -> str:
    sec = max(0, sec)
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = sec % 60
    return f"{h}:{m:02d}:{s:05.2f}"


def hex_to_ass(hex_str: str, opacity: float = 1.0) -> str:
    cleaned = re.sub(r"[^0-9a-fA-F]", "", hex_str)
    if len(cleaned) != 6:
        cleaned = "ffffff"
    r = int(cleaned[0:2], 16)
    g = int(cleaned[2:4], 16)
    b = int(cleaned[4:6], 16)
    alpha = max(0, min(255, round((1.0 - opacity) * 255)))
    return f"&H{alpha:02X}{b:02X}{g:02X}{r:02X}"


def parse_srt(path: Path):
    raw = path.read_text(encoding="utf-8")
    blocks = []
    for block in re.split(r"\n\s*\n", raw.strip()):
        lines = block.strip().splitlines()
        if len(lines) < 2:
            continue
        timing_index = 1 if lines[0].strip().isdigit() else 0
        if timing_index >= len(lines):
            continue
        match = re.match(
            r"(\d+:\d+:\d+[,\.]\d+)\s*-->\s*(\d+:\d+:\d+[,\.]\d+)",
            lines[timing_index],
        )
        if not match:
            continue
        start = srt_to_sec(match.group(1))
        end = srt_to_sec(match.group(2))
        text = "\n".join(lines[timing_index + 1 :])
        blocks.append((start, end, text))
    return blocks


def ass_dialogue(layer: int, start: float, end: float, override: str, text: str) -> str:
    return (
        f"Dialogue: {layer},{sec_to_ass(start)},{sec_to_ass(end)},Default,,0,0,0,,"
        f"{override}{text}"
    )


def deterministic_unit(seed: int) -> float:
    value = (seed * 1_103_515_245 + 12_345) & 0x7FFFFFFF
    return value / 0x7FFFFFFF


def text_effect_tags(
    preset: str,
    *,
    width: int,
    height: int,
    margin_bottom: int,
    fade_in_ms: int,
    fade_out_ms: int,
    intensity: float,
    speed: float,
    direction: str,
    duration_ms: int,
) -> list[str]:
    tags: list[str] = []
    if preset != "none" and (fade_in_ms > 0 or fade_out_ms > 0):
        tags.append(f"\\fad({fade_in_ms},{fade_out_ms})")

    enter_ms = max(90, min(duration_ms // 2, round(260 / max(speed, 0.5))))
    center_x = width / 2
    baseline_y = height - margin_bottom
    amount = max(12, round(54 * intensity))

    if preset in {"gentleFloat", "fairyDust", "butterfly"}:
        tags.append(
            f"\\an2\\move({center_x:.1f},{baseline_y + amount:.1f},"
            f"{center_x:.1f},{baseline_y:.1f},0,{enter_ms})"
        )
    elif preset == "softSlide":
        if direction == "left":
            start_x, start_y = -max(120, width * 0.12), baseline_y
        elif direction == "right":
            start_x, start_y = width + max(120, width * 0.12), baseline_y
        else:
            start_x, start_y = center_x, baseline_y + amount
        tags.append(
            f"\\an2\\move({start_x:.1f},{start_y:.1f},"
            f"{center_x:.1f},{baseline_y:.1f},0,{enter_ms})"
        )
    elif preset == "softPop":
        start_scale = max(60, round(82 - 18 * intensity))
        tags.extend(
            [
                f"\\fscx{start_scale}\\fscy{start_scale}",
                f"\\t(0,{enter_ms},\\fscx104\\fscy104)",
                f"\\t({enter_ms},{enter_ms + 100},\\fscx100\\fscy100)",
            ]
        )
    elif preset == "lightSweep":
        bright = max(120, min(duration_ms - 100, round(duration_ms * 0.48)))
        effect_color = "&H00FFFFFF"
        tags.extend(
            [
                f"\\t({bright},{bright + 120},\\1c{effect_color}\\blur1.4)",
                f"\\t({bright + 120},{bright + 310},\\blur0)",
            ]
        )
    return tags


def decoration_events(
    preset: str,
    *,
    cue_index: int,
    start: float,
    end: float,
    width: int,
    height: int,
    margin_bottom: int,
    density: int,
    intensity: float,
    speed: float,
    color: str,
) -> list[str]:
    if preset not in {"fairyDust", "butterfly"}:
        return []

    result: list[str] = []
    duration = max(0.15, end - start)
    count = max(2, min(18, density))
    ass_color = hex_to_ass(color, max(0.2, min(1, intensity)))
    safe_bottom = height - margin_bottom - 20

    for index in range(count):
        x_unit = deterministic_unit(cue_index * 2_003 + index * 37 + 11)
        y_unit = deterministic_unit(cue_index * 4_001 + index * 53 + 29)
        phase = deterministic_unit(cue_index * 7_001 + index * 71 + 47)
        event_start = start + min(duration * 0.55, phase * duration * 0.45)
        event_duration = min(duration - (event_start - start), (0.65 + y_unit * 0.8) / max(speed, 0.5))
        event_end = max(event_start + 0.18, min(end, event_start + event_duration))
        x0 = width * (0.12 + x_unit * 0.76)
        y0 = safe_bottom - (18 + y_unit * 92)
        x1 = x0 + (x_unit - 0.5) * 70 * intensity
        y1 = y0 - (28 + 45 * intensity)

        if preset == "fairyDust":
            size = round(13 + y_unit * 12)
            tags = (
                "{" + f"\\an5\\fnArial\\fs{size}\\bord0\\shad0\\c{ass_color}"
                f"\\move({x0:.1f},{y0:.1f},{x1:.1f},{y1:.1f})\\fad(100,180)\\blur0.6" + "}"
            )
            result.append(ass_dialogue(2, event_start, event_end, tags, "✦"))
        else:
            scale = 0.7 + y_unit * 0.55
            drawing = (
                "m 24 12 b 4 -4 0 14 18 24 "
                "b 2 34 12 48 24 29 "
                "b 36 48 46 34 30 24 "
                "b 48 14 44 -4 24 12 "
                "m 22 10 l 26 10 l 26 36 l 22 36"
            )
            tags = (
                "{" + f"\\an5\\p1\\bord0\\shad0\\c{ass_color}\\fscx{scale * 100:.0f}\\fscy{scale * 100:.0f}"
                f"\\move({x0:.1f},{y0:.1f},{x1:.1f},{y1:.1f})\\fad(130,220)" + "}"
            )
            result.append(ass_dialogue(2, event_start, event_end, tags, drawing))
    return result


def build_ass(
    blocks,
    *,
    font,
    font_size,
    text_color,
    box_enabled,
    box_color,
    box_opacity,
    outline_color,
    outline_opacity,
    outline_width,
    shadow_color,
    shadow_opacity,
    shadow_blur,
    shadow_distance,
    shadow_angle,
    fade_in_ms,
    fade_out_ms,
    margin_bottom,
    play_res,
    effect_preset="softFade",
    effect_intensity=0.68,
    effect_speed=1.0,
    effect_direction="up",
    effect_density=8,
    effect_color="#8FD3FF",
):
    width, height = play_res
    primary = hex_to_ass(text_color)
    back = hex_to_ass(box_color, box_opacity) if box_enabled else "&H00000000"
    border_style = 3 if box_enabled else 1
    outline_colour = hex_to_ass(outline_color, outline_opacity)
    shadow_colour = hex_to_ass(shadow_color, shadow_opacity)

    header = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {width}
PlayResY: {height}
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,{font},{font_size},{primary},&H000000FF,{outline_colour},{back},-1,0,0,0,100,100,0,0,{border_style},{outline_width},{shadow_distance},2,20,20,{margin_bottom},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""

    lines = [header]
    for cue_index, (start, end, text) in enumerate(blocks):
        if end <= start or not text.strip():
            continue
        safe = text.replace("{", "（").replace("}", "）").replace("\n", "\\N")
        duration_ms = max(1, round((end - start) * 1000))
        tags = text_effect_tags(
            effect_preset,
            width=width,
            height=height,
            margin_bottom=margin_bottom,
            fade_in_ms=fade_in_ms,
            fade_out_ms=fade_out_ms,
            intensity=max(0.1, min(1, effect_intensity)),
            speed=max(0.5, min(2, effect_speed)),
            direction=effect_direction,
            duration_ms=duration_ms,
        )
        if shadow_distance > 0:
            radians = math.radians(shadow_angle)
            tags.extend(
                [
                    f"\\xshad{math.cos(radians) * shadow_distance:.2f}",
                    f"\\yshad{-math.sin(radians) * shadow_distance:.2f}",
                ]
            )
        if shadow_blur > 0:
            tags.append(f"\\blur{shadow_blur}")
        override = "{" + "".join(tags) + "}" if tags else ""
        lines.append(ass_dialogue(1, start, end, override, safe))
        lines.extend(
            decoration_events(
                effect_preset,
                cue_index=cue_index,
                start=start,
                end=end,
                width=width,
                height=height,
                margin_bottom=margin_bottom,
                density=effect_density,
                intensity=effect_intensity,
                speed=effect_speed,
                color=effect_color,
            )
        )
    return "\n".join(lines)


def probe_resolution(video: Path):
    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=width,height",
        "-of",
        "csv=p=0:s=x",
        str(video),
    ]
    try:
        output = subprocess.check_output(cmd, text=True).strip()
        width, height = output.split("x")
        return int(width), int(height)
    except Exception:
        return 1920, 1080


def burn(video: Path, output: Path, ass_text: str):
    with tempfile.TemporaryDirectory(prefix="msm_burn_") as temp:
        ass_path = Path(temp) / "subtitle-effects.ass"
        ass_path.write_text(ass_text, encoding="utf-8")
        cmd = [
            "ffmpeg",
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "warning",
            "-y",
            "-i",
            str(video),
            "-vf",
            f"ass={ass_path}",
            "-c:a",
            "copy",
            str(output),
        ]
        print(f"⏳ ffmpeg burn sub → {output.name}")
        process = subprocess.run(cmd, capture_output=True, text=True)
        if process.returncode != 0:
            error = (process.stderr or process.stdout or "").strip()
            print(f"❌ ffmpeg thoát mã {process.returncode}")
            if error:
                print(error[-2400:])
            raise SystemExit(process.returncode)
    print(f"✅ Video có sub: {output}")


def main():
    parser = argparse.ArgumentParser(description="Burn SRT với style và hiệu ứng nhạc")
    parser.add_argument("video")
    parser.add_argument("srt")
    parser.add_argument("-o", "--output")
    parser.add_argument("--font", default="Hiragino Sans")
    parser.add_argument("--font-size", type=int, default=48)
    parser.add_argument("--text-color", default="#FFFFFF")
    parser.add_argument("--box", dest="box", action="store_true", default=True)
    parser.add_argument("--no-box", dest="box", action="store_false")
    parser.add_argument("--box-color", default="#000000")
    parser.add_argument("--box-opacity", type=float, default=0.75)
    parser.add_argument("--outline-color", default="#000000")
    parser.add_argument("--outline-opacity", type=float, default=1)
    parser.add_argument("--outline-width", type=int, default=0)
    parser.add_argument("--shadow-color", default="#000000")
    parser.add_argument("--shadow-opacity", type=float, default=0.75)
    parser.add_argument("--shadow-blur", type=int, default=0)
    parser.add_argument("--shadow-distance", type=int, default=0)
    parser.add_argument("--shadow-angle", type=int, default=315)
    parser.add_argument("--fade-in", type=int, default=200)
    parser.add_argument("--fade-out", type=int, default=200)
    parser.add_argument("--effect-preset", choices=["none", "softFade", *sorted(MUSIC_PRESETS)], default="softFade")
    # Fallback compatibility for the native model that separates transition
    # from decoration. ASS cannot compose every native layer, but it must accept
    # the canonical arguments and preserve the closest visual meaning.
    parser.add_argument(
        "--text-transition",
        choices=["none", "leftToRight", "rightToLeft", "bottomUp", "softPop", "wordByWord"],
    )
    parser.add_argument(
        "--visual-effect",
        choices=["none", "goldenSweep", "neonAura", "starlight", "butterflyTrail"],
    )
    parser.add_argument("--effect-intensity", type=float, default=0.68)
    parser.add_argument("--effect-speed", type=float, default=1)
    parser.add_argument("--effect-direction", choices=["up", "left", "right"], default="up")
    parser.add_argument("--effect-density", type=int, default=8)
    parser.add_argument("--effect-color", default="#8FD3FF")
    parser.add_argument("--margin-bottom", type=int, default=48)
    parser.add_argument("--width", type=int, default=0)
    parser.add_argument("--height", type=int, default=0)
    args = parser.parse_args()

    video = Path(args.video).expanduser()
    srt = Path(args.srt).expanduser()
    if not video.is_file() or not srt.is_file():
        print("❌ Thiếu video hoặc SRT đầu vào")
        raise SystemExit(1)
    blocks = parse_srt(srt)
    if not blocks:
        print("❌ SRT trống hoặc không parse được")
        raise SystemExit(1)

    play_res = (args.width, args.height) if args.width > 0 and args.height > 0 else probe_resolution(video)
    visual_map = {
        "goldenSweep": "lightSweep",
        "neonAura": "gentleFloat",
        "starlight": "fairyDust",
        "butterflyTrail": "butterfly",
    }
    transition_map = {
        "none": "none",
        "leftToRight": "softFade",
        "rightToLeft": "softSlide",
        "bottomUp": "softSlide",
        "softPop": "softPop",
        "wordByWord": "softFade",
    }
    effective_preset = visual_map.get(args.visual_effect or "")
    if effective_preset is None and args.text_transition is not None:
        effective_preset = transition_map[args.text_transition]
    if effective_preset is None:
        effective_preset = args.effect_preset
    effective_direction = args.effect_direction
    if args.text_transition == "rightToLeft":
        effective_direction = "right"
    elif args.text_transition == "leftToRight":
        effective_direction = "left"
    elif args.text_transition == "bottomUp":
        effective_direction = "up"

    ass_text = build_ass(
        blocks,
        font=args.font,
        font_size=args.font_size,
        text_color=args.text_color,
        box_enabled=args.box,
        box_color=args.box_color,
        box_opacity=args.box_opacity,
        outline_color=args.outline_color,
        outline_opacity=args.outline_opacity,
        outline_width=args.outline_width,
        shadow_color=args.shadow_color,
        shadow_opacity=args.shadow_opacity,
        shadow_blur=args.shadow_blur,
        shadow_distance=args.shadow_distance,
        shadow_angle=args.shadow_angle,
        fade_in_ms=args.fade_in,
        fade_out_ms=args.fade_out,
        margin_bottom=args.margin_bottom,
        play_res=play_res,
        effect_preset=effective_preset,
        effect_intensity=args.effect_intensity,
        effect_speed=args.effect_speed,
        effect_direction=effective_direction,
        effect_density=args.effect_density,
        effect_color=args.effect_color,
    )
    output = Path(args.output).expanduser() if args.output else video.with_name(f"{video.stem}_subbed{video.suffix}")
    burn(video, output, ass_text)


if __name__ == "__main__":
    main()
