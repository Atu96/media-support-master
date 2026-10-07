#!/usr/bin/env python3
"""SRT → FCPXML template «Phu de nen den» — đồng bộ 100% style từ Media Support App.

App gửi (fcpxmlCLIArgs):
  --fps --width --height
  --font --font-face --font-size --font-color
  --bg-opacity --bg-color --box-width-percent --box-corner-radius
  --fade-in-ms --fade-out-ms --margin-bottom --position-y

Đồng bộ preview 1080p:
  • font / fontFace / fontSize  → text-style (cỡ chữ CHỈ ở đây, không nhân Scale)
  • fontColor                   → text-style
  • bg-opacity / bg-color       → độ trong suốt / màu hộp
  • box width / corner radius  → bề ngang / độ bo nền Motion
  • fade in / fade out         → opacity của toàn title
  • margin-bottom               → Position Y (1 px ≈ 1 Y; neo 48 → -414)
  • Bottom Margin template      → cố định (không đánh Position)
  • Scale X                     → độ rộng nền cố định theo panel app
"""

from __future__ import annotations

import os
import re
from math import gcd
from pathlib import Path

# --- Calibrate template «Phu de nen den» @ 1080p (khớp SubtitleBurnStyle) ---
REF_MARGIN = 48
REF_POS_Y = -414
REF_BOTTOM_MARGIN = -192.356
REF_FONT_SIZE = 54
MARGIN_TO_Y_SCALE = 1.0
FONT_TO_Y_LIFT = 0.45  # pt → nhích Y khi font to (giữ đáy gần lề)


def srt_to_sec(tc: str) -> float:
    h, m, rest = tc.split(":")
    s, ms = rest.replace(",", ".").split(".")
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def snap_to_frame(t: float, fps_num: int, fps_den: int) -> str:
    frames = round(t * fps_den / fps_num)
    num = frames * fps_num
    den = fps_den
    g = gcd(abs(num), den)
    num //= g
    den //= g
    return f"{num}s" if den == 1 else f"{num}/{den}s"


def xml_escape(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def parse_srt(path: str) -> list[tuple[float, float, str]]:
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    blocks: list[tuple[float, float, str]] = []
    for blk in re.split(r"\n\n+", raw.strip()):
        lines = blk.strip().split("\n")
        if len(lines) < 2:
            continue
        try:
            int(lines[0].strip())
        except ValueError:
            continue
        m = re.match(
            r"(\d+:\d+:\d+[,\.]\d+)\s*-->\s*(\d+:\d+:\d+[,\.]\d+)", lines[1]
        )
        if not m:
            continue
        start = srt_to_sec(m.group(1))
        end = srt_to_sec(m.group(2))
        text = "\n".join(lines[2:]) if len(lines) > 2 else ""
        blocks.append((start, end, text))
    return blocks


def frame_dur_str(fps_num: int, fps_den: int) -> str:
    if fps_num == 1:
        return f"100/{fps_den * 100}s"
    return f"{fps_num}/{fps_den}s"


# PostScript / family → (FCP family, default face)
_FONT_FAMILY_MAP = {
    "pingfangsc": "PingFang SC",
    "pingfang sc": "PingFang SC",
    "pingfanghk": "PingFang HK",
    "pingfang hk": "PingFang HK",
    "pingfangtc": "PingFang TC",
    "pingfang tc": "PingFang TC",
    "hiraginosans": "Hiragino Sans",
    "hiragino sans": "Hiragino Sans",
    "hirakakupro": "Hiragino Kaku Gothic Pro",
    "hirakakupron": "Hiragino Kaku Gothic ProN",
    "hiragino kaku gothic pro": "Hiragino Kaku Gothic Pro",
    "hiragino kaku gothic pron": "Hiragino Kaku Gothic ProN",
    "hiraginominchopro": "Hiragino Mincho Pro",
    "hiraginominchopron": "Hiragino Mincho ProN",
    "osaka": "Osaka",
    "arialunicodems": "Arial Unicode MS",
    "arial unicode ms": "Arial Unicode MS",
    "arial": "Arial",
    "helvetica": "Helvetica",
    "helveticaneue": "Helvetica Neue",
    "helvetica neue": "Helvetica Neue",
    "sfpro": "SF Pro",
    "sf pro": "SF Pro",
    "noto sans cjk jp": "Noto Sans CJK JP",
    "notosanscjkjp": "Noto Sans CJK JP",
    "yugothic": "YuGothic",
    "yugothicy": "YuGothic",
    "yu gothic": "Yu Gothic",
}


_WEIGHT_TOKENS = {
    "regular", "book", "roman", "medium", "semibold", "demibold", "bold",
    "heavy", "black", "light", "thin", "ultralight",
    "w0", "w1", "w2", "w3", "w4", "w5", "w6", "w7", "w8", "w9",
}


def _split_ps_name(raw: str) -> tuple[str, str]:
    """'PingFangSC-Semibold' → ('pingfangsc', 'semibold'); 'PingFang SC' → ('pingfang sc', '')."""
    s = (raw or "").strip()
    if not s:
        return "", ""
    # PostScript with hyphen weight: Family-Weight
    if "-" in s:
        base, face = s.rsplit("-", 1)
        if face.lower().replace(" ", "") in _WEIGHT_TOKENS or re.match(r"^w\d$", face.lower()):
            return base.lower().replace(" ", ""), face.lower()
        # hyphen in family name only
        return s.lower().replace(" ", ""), ""
    # Spaced name: only treat last word as face if it's a weight (not SC/HK/MS)
    if " " in s:
        parts = s.rsplit(" ", 1)
        if len(parts) == 2 and parts[1].lower() in _WEIGHT_TOKENS:
            return parts[0].lower(), parts[1].lower()
        return s.lower(), ""
    return s.lower().replace("_", ""), ""


def normalize_font(
    name: str, face_hint: str | None = None
) -> tuple[str, str, str]:
    """→ (family, fontFace, bold '0'|'1') cho text-style FCP."""
    raw = (name or "PingFang SC").strip()
    base_key, face_from_ps = _split_ps_name(raw)
    # Try full key then base
    family = None
    key_full = raw.lower().replace("_", "-")
    key_compact = re.sub(r"[^a-z0-9]+", "", raw.lower())
    # Ưu tiên key dài (Helvetica Neue trước Helvetica)
    for k, v in sorted(_FONT_FAMILY_MAP.items(), key=lambda kv: -len(kv[0])):
        kk = re.sub(r"[^a-z0-9]+", "", k)
        if key_full == k or key_compact == kk or key_compact.startswith(kk):
            family = v
            break
    if family is None:
        # Human-readable family already?
        if re.search(r"[\s]", raw) and "-" not in raw:
            family = raw
        else:
            # CamelCase PostScript → insert spaces before caps when possible
            spaced = re.sub(r"([a-z])([A-Z])", r"\1 \2", raw.split("-")[0])
            family = spaced if spaced else raw

    face_raw = (face_hint or face_from_ps or "Regular").strip()
    face_l = face_raw.lower().replace(" ", "")

    # Map common weight tokens → FCP fontFace
    face_map = {
        "regular": "Regular",
        "book": "Regular",
        "roman": "Regular",
        "medium": "Medium",
        "semibold": "Semibold",
        "demibold": "Semibold",
        "bold": "Bold",
        "heavy": "Heavy",
        "black": "Black",
        "light": "Light",
        "thin": "Thin",
        "ultralight": "Ultralight",
        "w0": "W0",
        "w1": "W1",
        "w2": "W2",
        "w3": "W3",
        "w4": "W4",
        "w5": "W5",
        "w6": "W6",
        "w7": "W7",
        "w8": "W8",
        "w9": "W9",
    }
    face = face_map.get(face_l, face_raw if face_raw else "Regular")
    # Capitalize if still raw token
    if face == face_raw and face_raw and face_raw[0].islower():
        face = face_raw[:1].upper() + face_raw[1:]

    bold = "1" if face_l in {"bold", "semibold", "demibold", "heavy", "black", "w6", "w7", "w8", "w9"} else "0"
    return family, face, bold


def margin_to_position_y(
    margin_bottom: int,
    height: int = 1080,
    font_size: int = REF_FONT_SIZE,
) -> int:
    """Lề đáy preview (px @ height) → Position Y FCP."""
    h = int(height) if height else 1080
    half = h / 2.0
    mb = int(margin_bottom)
    y = REF_POS_Y + (mb - REF_MARGIN) * MARGIN_TO_Y_SCALE
    y += FONT_TO_Y_LIFT * (int(font_size) - REF_FONT_SIZE)
    y_min = -half + 24
    y_max = -80.0
    return int(round(max(y_min, min(y_max, y))))


def subtitle_layout(text: str, box_width_percent: int) -> tuple[float, float, bool]:
    """Scale nền Motion theo đúng % chiều ngang ở panel app."""
    lines = [ln.strip() for ln in text.split("\n") if ln.strip()]
    width = max(40, min(100, int(box_width_percent)))
    # Template gốc có scale X 1.0301 ở mặc định 92%.
    sx = 1.0301 * width / 92.0
    sy = 0.95
    return sx, sy, len(lines) >= 2


def seconds_fraction(seconds: float) -> str:
    millis = max(0, int(round(seconds * 1000)))
    if millis == 0:
        return "0s"
    g = gcd(millis, 1000)
    num, den = millis // g, 1000 // g
    return f"{num}s" if den == 1 else f"{num}/{den}s"


def fade_param(duration: float, fade_in_ms: int, fade_out_ms: int) -> str:
    """Fade cả chữ và nền; mỗi phía không vượt quá nửa cue."""
    half_ms = max(0, int(duration * 1000 / 2))
    fade_in = min(max(0, int(fade_in_ms)), half_ms)
    fade_out = min(max(0, int(fade_out_ms)), half_ms)
    if fade_in == 0 and fade_out == 0:
        return ""
    children: list[str] = []
    if fade_in:
        children.append(
            f'                  <fadeIn type="easeInOut" duration="{seconds_fraction(fade_in / 1000)}"/>'
        )
    if fade_out:
        children.append(
            f'                  <fadeOut type="easeInOut" duration="{seconds_fraction(fade_out / 1000)}"/>'
        )
    inside = "\n".join(children)
    return (
        '                <param name="Opacity" key="9999/10003/1/200/202" value="1">\n'
        f"{inside}\n"
        "                </param>\n"
    )


EFFECT_NAME = "Phu de nen den"
EFFECT_UID = "~/Titles.localized/Phu de nen den/Phu de nen den.moti"
EFFECT_SRC = (Path.home() / "Library/Containers/com.apple.FinalCut/Data/Movies"
    / "Motion Templates.localized/Titles.localized/Phu de nen den/Phu de nen den.moti").as_uri()

PARAMS_1LINE = """\
                <param name="Hiệu ứng vào" key="9999/10000/2/101" value="0"/>
                <param name="Hiệu ứng ra" key="9999/10000/2/102" value="0"/>
                <param name="Fade In Time" key="9999/10003/12450/200" value="0"/>
                <param name="Fade Out Time" key="9999/10003/12450/201" value="0"/>
                <param name="Rộng nền" key="9999/10003/10043/1/100/105/1" value="{scale_x}"/>
                <param name="Cao nền" key="9999/10003/10043/1/100/105/2" value="{scale_y}"/>
                <param name="Độ trong suốt" key="9999/10003/10043/2/353/113/141" value="{opacity}"/>
                <param name="Màu nền" key="9999/10003/10043/2/353/113/111" value="{bg_color}"/>
                <param name="Độ nhọn viền" key="9999/10003/10043/2/353/144" value="{corner_radius}"/>
                <param name="Position" key="9999/10003/10065/1/100/101" value="0 {pos_y}"/>
                <param name="Anchor Point" key="9999/10003/10065/1/100/107" value="862.491 -96.1779"/>
                <param name="Layout Method" key="9999/10003/10065/2/314" value="1 (Paragraph)"/>
                <param name="Right Margin" key="9999/10003/10065/2/324" value="1724.98"/>
                <param name="Bottom Margin" key="9999/10003/10065/2/326" value="{bottom_margin}"/>
                <param name="Alignment" key="9999/10003/10065/2/354/10038/401" value="1 (Center)"/>
                <param name="Alignment" key="9999/10003/10065/2/373" value="0 (Left) 1 (Middle)"/>"""

PARAMS_2LINE = """\
                <param name="Hiệu ứng vào" key="9999/10000/2/101" value="0"/>
                <param name="Hiệu ứng ra" key="9999/10000/2/102" value="0"/>
                <param name="Fade In Time" key="9999/10003/12450/200" value="0"/>
                <param name="Fade Out Time" key="9999/10003/12450/201" value="0"/>
                <param name="Rộng nền" key="9999/10003/10043/1/100/105/1" value="{scale_x}"/>
                <param name="Cao nền" key="9999/10003/10043/1/100/105/2" value="{scale_y}"/>
                <param name="Độ trong suốt" key="9999/10003/10043/2/353/113/141" value="{opacity}"/>
                <param name="Màu nền" key="9999/10003/10043/2/353/113/111" value="{bg_color}"/>
                <param name="Độ nhọn viền" key="9999/10003/10043/2/353/144" value="{corner_radius}"/>
                <param name="Position" key="9999/10003/10065/1/100/101" value="0 {pos_y}"/>
                <param name="Anchor Point" key="9999/10003/10065/1/100/107" value="862.491 -96.1779"/>
                <param name="Layout Method" key="9999/10003/10065/2/314" value="1 (Paragraph)"/>
                <param name="Right Margin" key="9999/10003/10065/2/324" value="1724.98"/>
                <param name="Bottom Margin" key="9999/10003/10065/2/326" value="{bottom_margin}"/>
                <param name="Alignment" key="9999/10003/10065/2/354/10038/401" value="1 (Center)"/>
                <param name="Alignment" key="9999/10003/10065/2/354/3001947110/401" value="1 (Center)"/>
                <param name="Alignment" key="9999/10003/10065/2/373" value="0 (Left) 1 (Middle)"/>"""


def convert(
    srt_path: str,
    out_path: str | None = None,
    fps_num: int = 1,
    fps_den: int = 24,
    width: int = 1920,
    height: int = 1080,
    font: str = "PingFang SC",
    font_face: str | None = None,
    font_size: int = REF_FONT_SIZE,
    font_color: str = "1 1 1 1",
    outline_color: str = "0 0 0 0",
    outline_width: int = 0,
    shadow_color: str = "0 0 0 0",
    shadow_distance: int = 0,
    shadow_angle: int = 315,
    bg_opacity: float = 0.9,
    bg_color: str = "0 0 0 1",
    box_width_percent: int = 92,
    box_corner_radius: int = 6,
    fade_in_ms: int = 0,
    fade_out_ms: int = 0,
    position_y: int | None = None,
    margin_bottom: int | None = None,
) -> str | None:
    blocks = parse_srt(srt_path)
    if not blocks:
        print("❌ Không parse được SRT.")
        return None

    family, face, bold_attr = normalize_font(font, face_hint=font_face)
    font_size = max(18, min(200, int(font_size)))
    bg_opacity = max(0.0, min(1.0, float(bg_opacity)))
    box_width_percent = max(40, min(100, int(box_width_percent)))
    box_corner_radius = max(0, min(100, int(box_corner_radius)))
    fade_in_ms = max(0, int(fade_in_ms))
    fade_out_ms = max(0, int(fade_out_ms))
    height = int(height) if height else 1080
    width = int(width) if width else 1920

    # Lề đáy → Position Y. Ưu tiên --position-y từ app nếu khớp công thức (1 nguồn).
    if margin_bottom is not None:
        mb = max(0, min(200, int(margin_bottom)))
        computed = margin_to_position_y(mb, height=height, font_size=font_size)
        # App gửi position-y cùng công thức — tin computed (tránh lệch version cũ)
        pos_y = computed
        if position_y is not None and abs(int(position_y) - computed) > 2:
            print(
                f"   ⚠️ position-y app={position_y} ≠ computed={computed} "
                f"(dùng computed; cập nhật app nếu lệch)"
            )
    elif position_y is not None:
        mb = REF_MARGIN
        pos_y = int(position_y)
    else:
        mb = REF_MARGIN
        pos_y = margin_to_position_y(mb, height=height, font_size=font_size)

    bottom_m = REF_BOTTOM_MARGIN
    tc = lambda t: snap_to_frame(t, fps_num, fps_den)

    total = max(e for _, e, _ in blocks)
    gap_dur = tc(total)
    fd = frame_dur_str(fps_num, fps_den)
    fmt_name = f"FFVideoFormat{height}p{fps_den}"
    proj_name = xml_escape(os.path.splitext(os.path.basename(srt_path))[0])

    titles: list[str] = []
    for i, (s, e, text) in enumerate(blocks, 1):
        if e <= s:
            continue
        title_label = xml_escape(text.split("\n")[0][:40])
        ts_id = f"ts{i}"
        xml_text = xml_escape(text)
        scale_x, scale_y, is2 = subtitle_layout(text, box_width_percent)
        tmpl = PARAMS_2LINE if is2 else PARAMS_1LINE
        params = tmpl.format(
            scale_x=f"{scale_x:.4f}",
            scale_y=f"{scale_y:.4f}",
            opacity=f"{bg_opacity:.4f}",
            bg_color=bg_color,
            corner_radius=box_corner_radius,
            pos_y=pos_y,
            bottom_margin=f"{bottom_m:.4f}",
        )
        fade = fade_param(e - s, fade_in_ms, fade_out_ms)

        titles.append(
            f'              <title ref="r2" lane="1" offset="{tc(s)}" name="{title_label} - {EFFECT_NAME}" duration="{tc(e - s)}">\n'
            f"{fade}"
            f"{params}\n"
            f"                <text>\n"
            f'                  <text-style ref="{ts_id}">{xml_text}</text-style>\n'
            f"                </text>\n"
            f'                <text-style-def id="{ts_id}">\n'
            f'                  <text-style font="{xml_escape(family)}" fontSize="{font_size}" '
            f'fontFace="{xml_escape(face)}"\n'
            f'                            fontColor="{font_color}" strokeColor="{outline_color}" '
            f'strokeWidth="{-abs(outline_width)}" shadowColor="{shadow_color}" '
            f'shadowOffset="{shadow_distance} {shadow_angle}" bold="{bold_attr}" '
            f'alignment="center"/>\n'
            f"                </text-style-def>\n"
            f"              </title>"
        )

    body = "\n".join(titles)

    fcpxml = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE fcpxml>

<fcpxml version="1.11">
  <resources>
    <format id="r1" name="{fmt_name}"
            frameDuration="{fd}"
            width="{width}"
            height="{height}"
            colorSpace="1-1-1 (Rec. 709)"/>
    <effect id="r2" name="{EFFECT_NAME}"
            uid="{EFFECT_UID}"
            src="{EFFECT_SRC}"/>
  </resources>
  <library>
    <event name="Subtitles">
      <project name="{proj_name}">
        <sequence format="r1" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k">
          <spine>
            <gap name="Gap" offset="0s" duration="{gap_dur}">
{body}
            </gap>
          </spine>
        </sequence>
      </project>
    </event>
  </library>
</fcpxml>
"""

    if out_path is None:
        out_path = os.path.splitext(srt_path)[0] + ".fcpxml"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(fcpxml)

    print(f"✅ {len(blocks)} subtitles → {out_path}")
    print(
        f"   style font={family!r} face={face!r} size={font_size} bold={bold_attr} "
        f"color={font_color} bg={bg_opacity} marginBottom={mb} posY={pos_y} "
        f"bgColor={bg_color} width={box_width_percent}% corner={box_corner_radius} "
        f"fade={fade_in_ms}/{fade_out_ms}ms bottomM={bottom_m:.2f} fps={fps_den} {width}x{height}"
    )
    return out_path


if __name__ == "__main__":
    import argparse

    p = argparse.ArgumentParser(
        description='SRT → FCPXML «Phu de nen den» — đồng bộ style app 100%'
    )
    p.add_argument("input", help="input .srt")
    p.add_argument("output", nargs="?", help="output .fcpxml")
    p.add_argument("--fps", default="24")
    p.add_argument("--width", type=int, default=1920)
    p.add_argument("--height", type=int, default=1080)
    p.add_argument("--font", default="PingFang SC")
    p.add_argument("--font-face", default=None, help="Regular / Semibold / W3…")
    p.add_argument("--font-size", type=int, default=REF_FONT_SIZE)
    p.add_argument("--font-color", default="1 1 1 1")
    p.add_argument("--outline-color", default="0 0 0 0")
    p.add_argument("--outline-width", type=int, default=0)
    p.add_argument("--shadow-color", default="0 0 0 0")
    p.add_argument("--shadow-distance", type=int, default=0)
    p.add_argument("--shadow-angle", type=int, default=315)
    p.add_argument("--bg-opacity", type=float, default=0.9)
    p.add_argument("--bg-color", default="0 0 0 1")
    p.add_argument("--box-width-percent", type=int, default=92)
    p.add_argument("--box-corner-radius", type=int, default=6)
    p.add_argument("--fade-in-ms", type=int, default=0)
    p.add_argument("--fade-out-ms", type=int, default=0)
    p.add_argument(
        "--margin-bottom",
        type=int,
        default=None,
        help="Lề đáy px (preview @1080) → Position Y",
    )
    p.add_argument(
        "--position-y",
        type=int,
        default=None,
        help="Position Y (app computed; fallback nếu không có margin)",
    )
    args = p.parse_args()

    fps_map = {
        "24": (1, 24),
        "25": (1, 25),
        "30": (1, 30),
        "48": (1, 48),
        "60": (1, 60),
        "2997": (1001, 30000),
        "2398": (1001, 24000),
    }
    fn, fd = fps_map.get(args.fps, (1, 24))

    convert(
        args.input,
        args.output,
        fps_num=fn,
        fps_den=fd,
        width=args.width,
        height=args.height,
        font=args.font,
        font_face=args.font_face,
        font_size=args.font_size,
        font_color=args.font_color,
        outline_color=args.outline_color,
        outline_width=args.outline_width,
        shadow_color=args.shadow_color,
        shadow_distance=args.shadow_distance,
        shadow_angle=args.shadow_angle,
        bg_opacity=args.bg_opacity,
        bg_color=args.bg_color,
        box_width_percent=args.box_width_percent,
        box_corner_radius=args.box_corner_radius,
        fade_in_ms=args.fade_in_ms,
        fade_out_ms=args.fade_out_ms,
        position_y=args.position_y,
        margin_bottom=args.margin_bottom,
    )
