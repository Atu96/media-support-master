#!/bin/bash
# run_translate_srt.sh <input.srt> <output.srt> <target_lang> [source_lang]
set -euo pipefail

INPUT="${1:-}"
OUTPUT="${2:-}"
TARGET="${3:-}"
SOURCE="${4:-auto}"

[[ -n "$INPUT" && -f "$INPUT" && -n "$OUTPUT" && -n "$TARGET" ]] || {
    echo "❌ Usage: run_translate_srt.sh <input.srt> <output.srt> <target_lang> [source_lang]"
    exit 1
}

TOOLS_ROOT="${TOOLS_ROOT:-$HOME/Documents/Tools}"
WHISPER_HOME="${WHISPER_HOME:-$TOOLS_ROOT/Whisper_Native}"
PYTHON="$WHISPER_HOME/venv/bin/python"
TRANSLATE_PY="$WHISPER_HOME/translate_srt.py"

[[ -x "$PYTHON" ]] || { echo "❌ venv python: $PYTHON"; exit 1; }
[[ -f "$TRANSLATE_PY" ]] || { echo "❌ translate_srt.py not found"; exit 1; }

echo "⏳ Dịch SRT → $TARGET (source: $SOURCE)..."
"$PYTHON" "$TRANSLATE_PY" "$INPUT" "$OUTPUT" "$TARGET" "$SOURCE"
echo "✅ Output: $OUTPUT"