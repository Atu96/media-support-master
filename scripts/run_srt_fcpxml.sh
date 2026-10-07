#!/bin/bash
# run_srt_fcpxml.sh <srt> [output.fcpxml] [--fps 24] [--font ...] ...
set -euo pipefail

SRT="${1:-}"
OUT="${2:-}"
if [[ -n "${2:-}" ]]; then
    shift 2
else
    shift 1
fi
EXTRA_ARGS=("$@")

[[ -n "$SRT" && -f "$SRT" ]] || { echo "❌ Usage: run_srt_fcpxml.sh <srt> [output.fcpxml] [style args]"; exit 1; }
[[ -n "$OUT" ]] || OUT="${SRT%.srt}.fcpxml"

TOOLS_ROOT="${TOOLS_ROOT:-$HOME/Documents/Tools}"
WHISPER_HOME="${WHISPER_HOME:-$TOOLS_ROOT/Whisper_Native}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

CONVERT_PY="${MSM_FCPXML_CONVERTER:-$SCRIPT_DIR/lib/convert_srt_fcpxml.py}"
[[ -f "$CONVERT_PY" ]] || { echo "❌ Không tìm thấy convert_srt_fcpxml.py"; exit 1; }

VENV_PYTHON="$WHISPER_HOME/venv/bin/python"
[[ -x "$VENV_PYTHON" ]] || VENV_PYTHON="$(command -v python3)"

echo "✅ SRT: $SRT"
"$VENV_PYTHON" "$CONVERT_PY" "$SRT" "$OUT" "${EXTRA_ARGS[@]}"
echo "🎬 FCPXML: $OUT"