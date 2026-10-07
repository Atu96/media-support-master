#!/usr/bin/env python3
"""Offline regression tests for script_align_multilang.py."""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path


FIXTURE_SRT = """1
00:00:00,000 --> 00:00:03,000
Welcome to the subtitle editor.

2
00:00:03,000 --> 00:00:06,000
It keeps every complete word.
"""


def run_aligner(aligner: Path, lang: str, whisper: str, script: str) -> str:
    with tempfile.TemporaryDirectory(prefix="msm-align-test-") as temp:
        root = Path(temp)
        whisper_path = root / "whisper.srt"
        script_path = root / "script.txt"
        output_path = root / "output.srt"
        whisper_path.write_text(whisper, encoding="utf-8")
        script_path.write_text(script, encoding="utf-8")
        env = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "MSM_MAX_LINE_CHARS": "18",
            "MSM_MAX_BLOCK_CHARS": "36",
            "MSM_MAX_LINES": "2",
        }
        subprocess.run(
            [sys.executable, str(aligner), str(whisper_path), str(script_path), str(output_path), "--lang", lang],
            check=True,
            env=env,
            capture_output=True,
            text=True,
        )
        return output_path.read_text(encoding="utf-8")


def cue_texts(srt: str) -> list[str]:
    result: list[str] = []
    for block in re.split(r"\n\s*\n", srt.strip()):
        lines = block.splitlines()
        result.append(" ".join(lines[2:]))
    return result


def assert_monotonic(srt: str) -> None:
    starts = re.findall(r"(\d\d:\d\d:\d\d,\d{3}) -->", srt)
    assert starts == sorted(starts), f"timecodes are not monotonic: {starts}"


def main() -> None:
    aligner = Path(sys.argv[1])

    english_script = "Welcome to the subtitle editor. It keeps every complete word."
    english = run_aligner(aligner, "en", FIXTURE_SRT, english_script)
    assert "subtitle" in english and "complete" in english
    assert "subti\ntle" not in english and "comp\nlete" not in english
    assert " ".join(cue_texts(english)).replace("\n", " ") == english_script
    assert_monotonic(english)

    russian_script = "Сегодня мы проверяем русские субтитры. Слова нельзя разрывать посередине."
    russian_whisper = FIXTURE_SRT.replace(
        "Welcome to the subtitle editor.", "Сегодня мы проверяем русские субтитры."
    ).replace("It keeps every complete word.", "Слова нельзя разрывать посередине.")
    russian = run_aligner(aligner, "ru", russian_whisper, russian_script)
    assert "русские" in russian and "посередине" in russian
    assert " ".join(cue_texts(russian)).replace("\n", " ") == russian_script
    assert_monotonic(russian)

    chinese_script = "今天我们测试中文字幕。换行不能破坏时间轴！"
    chinese_whisper = FIXTURE_SRT.replace(
        "Welcome to the subtitle editor.", "今天我们测试中文字幕。"
    ).replace("It keeps every complete word.", "换行不能破坏时间轴！")
    chinese = run_aligner(aligner, "zh", chinese_whisper, chinese_script)
    assert "今天我们测试中文字幕。" in chinese.replace("\n", "")
    assert "换行不能破坏时间轴！" in chinese.replace("\n", "")
    assert_monotonic(chinese)

    korean_script = "오늘은 한국어 자막 줄바꿈을 확인합니다. 낱말의 순서와 간격을 그대로 지킵니다."
    korean_whisper = FIXTURE_SRT.replace(
        "Welcome to the subtitle editor.", "오늘은 한국어 자막 줄바꿈을 확인합니다."
    ).replace("It keeps every complete word.", "낱말의 순서와 간격을 그대로 지킵니다.")
    korean = run_aligner(aligner, "ko", korean_whisper, korean_script)
    assert "한국어" in korean and "순서와" in korean
    assert " ".join(cue_texts(korean)).replace("\n", " ") == korean_script
    assert_monotonic(korean)

    print("✓ Multi-language script align tests OK — không dùng API")


if __name__ == "__main__":
    main()
