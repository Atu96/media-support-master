#!/usr/bin/env python3
"""Align a supplied script to Whisper SRT timings for Chinese and spaced languages.

Japanese intentionally stays in the mature MeCab/Kinsoku pipeline. This module
handles Chinese as character-based text and Russian/Latin languages as word-based
text, preserving word boundaries when wrapping subtitles.
"""

from __future__ import annotations

import argparse
import os
import re
import unicodedata
from dataclasses import dataclass
from difflib import SequenceMatcher
from pathlib import Path


TIME_RE = re.compile(
    r"(?P<h>\d{1,2}):(?P<m>\d{2}):(?P<s>\d{2})[,.](?P<ms>\d{3})"
)
SENTENCE_END_RE = re.compile(r"(?<=[.!?])\s+")
SPACED_LANGUAGES = {"ko", "ru", "en", "vi", "fr", "es", "pt", "de", "it"}


@dataclass
class WhisperCue:
    start: float
    end: float
    text: str


@dataclass
class ScriptPiece:
    text: str
    normalized: str
    start_index: int
    end_index: int


def parse_time(value: str) -> float:
    match = TIME_RE.fullmatch(value.strip())
    if not match:
        raise ValueError(f"Timecode không hợp lệ: {value}")
    return (
        int(match["h"]) * 3600
        + int(match["m"]) * 60
        + int(match["s"])
        + int(match["ms"]) / 1000
    )


def format_time(value: float) -> str:
    millis = max(0, int(round(value * 1000)))
    hours, millis = divmod(millis, 3_600_000)
    minutes, millis = divmod(millis, 60_000)
    seconds, millis = divmod(millis, 1_000)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{millis:03d}"


def parse_srt(path: Path) -> list[WhisperCue]:
    raw = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    cues: list[WhisperCue] = []
    for block in re.split(r"\n\s*\n", raw.strip()):
        lines = [line.strip() for line in block.splitlines() if line.strip()]
        time_index = next((i for i, line in enumerate(lines) if "-->" in line), None)
        if time_index is None:
            continue
        start_text, end_text = [part.strip() for part in lines[time_index].split("-->", 1)]
        text = " ".join(lines[time_index + 1 :]).strip()
        if text:
            cues.append(WhisperCue(parse_time(start_text), parse_time(end_text), text))
    return cues


def normalize_for_match(text: str) -> str:
    normalized = unicodedata.normalize("NFKC", text).casefold()
    return "".join(ch for ch in normalized if ch.isalnum())


def clean_script(text: str, lang: str) -> str:
    text = unicodedata.normalize("NFC", text).replace("\r\n", "\n").replace("\r", "\n")
    if lang in SPACED_LANGUAGES:
        return re.sub(r"\s+", " ", text).strip()
    return re.sub(r"[ \t]+", "", text).strip()


def split_sentences(text: str, lang: str) -> list[str]:
    if not text:
        return []
    if lang == "zh":
        pieces = re.findall(r"[^。！？!?\n]+[。！？!?]?", text)
    else:
        pieces = SENTENCE_END_RE.split(text)
    return [piece.strip() for piece in pieces if piece.strip()]


def chunk_spaced(sentence: str, limit: int) -> list[str]:
    words = sentence.split()
    if not words:
        return []
    chunks: list[str] = []
    current: list[str] = []
    current_len = 0
    for word in words:
        addition = len(word) + (1 if current else 0)
        if current and current_len + addition > limit:
            chunks.append(" ".join(current))
            current = [word]
            current_len = len(word)
        else:
            current.append(word)
            current_len += addition
    if current:
        chunks.append(" ".join(current))
    return chunks


def chunk_cjk(sentence: str, limit: int) -> list[str]:
    if len(sentence) <= limit:
        return [sentence]
    chunks: list[str] = []
    remaining = sentence
    preferred = "，、；：,;:"
    while len(remaining) > limit:
        window = remaining[: limit + 1]
        cut = max((window.rfind(mark) + 1 for mark in preferred), default=0)
        if cut < max(4, limit // 2):
            cut = limit
        chunks.append(remaining[:cut])
        remaining = remaining[cut:]
    if remaining:
        chunks.append(remaining)
    return chunks


def build_pieces(script: str, lang: str, limit: int) -> list[ScriptPiece]:
    texts: list[str] = []
    for sentence in split_sentences(script, lang):
        if lang == "zh":
            texts.extend(chunk_cjk(sentence, limit))
        else:
            texts.extend(chunk_spaced(sentence, limit))

    pieces: list[ScriptPiece] = []
    cursor = 0
    for text in texts:
        normalized = normalize_for_match(text)
        if not normalized:
            continue
        pieces.append(ScriptPiece(text, normalized, cursor, cursor + len(normalized)))
        cursor += len(normalized)
    return pieces


def whisper_char_timing(cues: list[WhisperCue]) -> tuple[str, list[tuple[float, float]]]:
    chars: list[str] = []
    timings: list[tuple[float, float]] = []
    for cue in cues:
        normalized = normalize_for_match(cue.text)
        if not normalized:
            continue
        duration = max(0.05, cue.end - cue.start)
        step = duration / len(normalized)
        for index, char in enumerate(normalized):
            chars.append(char)
            timings.append((cue.start + index * step, cue.start + (index + 1) * step))
    return "".join(chars), timings


def aligned_piece_times(
    pieces: list[ScriptPiece], whisper_text: str, whisper_times: list[tuple[float, float]]
) -> tuple[list[tuple[float, float]], float]:
    script_text = "".join(piece.normalized for piece in pieces)
    matcher = SequenceMatcher(None, script_text, whisper_text, autojunk=False)
    script_to_whisper: dict[int, int] = {}
    matched = 0
    for block in matcher.get_matching_blocks():
        for offset in range(block.size):
            script_to_whisper[block.a + offset] = block.b + offset
            matched += 1

    media_start = whisper_times[0][0]
    media_end = whisper_times[-1][1]
    media_duration = max(0.8, media_end - media_start)
    script_length = max(1, len(script_text))
    raw: list[tuple[float, float]] = []
    for piece in pieces:
        matched_indexes = [
            script_to_whisper[index]
            for index in range(piece.start_index, piece.end_index)
            if index in script_to_whisper
        ]
        if matched_indexes:
            start = whisper_times[min(matched_indexes)][0]
            end = whisper_times[max(matched_indexes)][1]
        else:
            start = media_start + media_duration * piece.start_index / script_length
            end = media_start + media_duration * piece.end_index / script_length
        raw.append((start, end))

    result: list[tuple[float, float]] = []
    previous_end = media_start
    for index, (start, end) in enumerate(raw):
        start = max(previous_end, start)
        if index + 1 < len(raw):
            next_start = max(start + 0.35, raw[index + 1][0])
            end = min(max(end, start + 0.8), next_start)
        else:
            end = min(media_end, max(end, start + 0.8))
        if end <= start:
            end = start + 0.35
        result.append((start, end))
        previous_end = end
    ratio = matched / max(1, len(script_text))
    return result, ratio


def wrap_spaced(text: str, max_chars: int, max_lines: int) -> str:
    words = text.split()
    if len(text) <= max_chars or len(words) < 2 or max_lines <= 1:
        return text
    lines: list[str] = []
    current: list[str] = []
    current_len = 0
    for word in words:
        addition = len(word) + (1 if current else 0)
        if current and current_len + addition > max_chars and len(lines) < max_lines - 1:
            lines.append(" ".join(current))
            current = [word]
            current_len = len(word)
        else:
            current.append(word)
            current_len += addition
    if current:
        lines.append(" ".join(current))
    return "\n".join(lines)


def wrap_cjk(text: str, max_chars: int, max_lines: int) -> str:
    if len(text) <= max_chars or max_lines <= 1:
        return text
    lines = chunk_cjk(text, max_chars)
    if len(lines) <= max_lines:
        return "\n".join(lines)
    return "\n".join(lines[: max_lines - 1] + ["".join(lines[max_lines - 1 :])])


def write_srt(
    output: Path,
    pieces: list[ScriptPiece],
    times: list[tuple[float, float]],
    lang: str,
    max_line: int,
    max_lines: int,
) -> None:
    blocks: list[str] = []
    for index, (piece, (start, end)) in enumerate(zip(pieces, times), 1):
        text = (
            wrap_cjk(piece.text, max_line, max_lines)
            if lang == "zh"
            else wrap_spaced(piece.text, max_line, max_lines)
        )
        blocks.append(
            f"{index}\n{format_time(start)} --> {format_time(end)}\n{text}"
        )
    output.write_text("\n\n".join(blocks) + "\n", encoding="utf-8")


def positive_env(name: str, default: int) -> int:
    try:
        return max(1, int(os.environ.get(name, str(default))))
    except ValueError:
        return default


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("whisper_srt", type=Path)
    parser.add_argument("script_file", type=Path)
    parser.add_argument("output_srt", type=Path)
    parser.add_argument("--lang", required=True, choices=["zh", *sorted(SPACED_LANGUAGES)])
    args = parser.parse_args()

    max_line = positive_env("MSM_MAX_LINE_CHARS", 33)
    max_lines = min(3, positive_env("MSM_MAX_LINES", 2))
    max_block = max(max_line, positive_env("MSM_MAX_BLOCK_CHARS", max_line * max_lines))

    cues = parse_srt(args.whisper_srt)
    script = clean_script(args.script_file.read_text(encoding="utf-8-sig"), args.lang)
    if not cues:
        raise SystemExit("❌ Whisper SRT không có cue để canh timing")
    if not script:
        raise SystemExit("❌ Kịch bản trống")

    pieces = build_pieces(script, args.lang, max_block)
    whisper_text, whisper_times = whisper_char_timing(cues)
    if not pieces or not whisper_text:
        raise SystemExit("❌ Không có nội dung hợp lệ để align")

    times, ratio = aligned_piece_times(pieces, whisper_text, whisper_times)
    write_srt(args.output_srt, pieces, times, args.lang, max_line, max_lines)
    print(f"MSM_ALIGN_MATCH:{ratio * 100:.1f}")
    if ratio < 0.35:
        print("⚠️ Độ khớp audio/kịch bản thấp — nên kiểm tra lại ngôn ngữ đã chọn")
    print(f"✅ Align {args.lang}: {len(pieces)} cue")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
