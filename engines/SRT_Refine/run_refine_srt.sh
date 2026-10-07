#!/bin/zsh
# run_refine_srt.sh <input.srt> <lang> <output.srt> [profile] [extra refine_srt.py args…]
set -euo pipefail

IN_SRT="${1:-}"
LANG="${2:-auto}"
OUT_SRT="${3:-}"
PROFILE="${4:-}"
shift $(( $# >= 4 ? 4 : $# )) || true
EXTRA_ARGS=("$@")

[[ -n "$IN_SRT" && -f "$IN_SRT" && -n "$OUT_SRT" ]] || {
    echo "❌ Usage: run_refine_srt.sh <input.srt> <lang> <output.srt> [profile] [extra…]"
    exit 1
}

APP_ROOT="${APP_ROOT:-$HOME/Documents/Media Support App}"
TOOLS_ROOT="${TOOLS_ROOT:-$HOME/Documents/Tools}"
SRT_REFINE_HOME="${SRT_REFINE_HOME:-$APP_ROOT/engines/SRT_Refine}"

if [[ ! -d "$SRT_REFINE_HOME" && -d "$TOOLS_ROOT/SRT_Refine" ]]; then
    SRT_REFINE_HOME="$TOOLS_ROOT/SRT_Refine"
fi

PYTHON="${SRT_REFINE_HOME}/venv/bin/python"
[[ -x "$PYTHON" ]] || PYTHON="${WHISPER_HOME:-$TOOLS_ROOT/Whisper_Native}/venv/bin/python"

[[ -x "$PYTHON" ]] || {
    echo "❌ Python venv không tìm thấy (SRT_Refine hoặc Whisper_Native)"
    exit 1
}

ARGS=(--in "$IN_SRT" --out "$OUT_SRT" --lang "$LANG")
[[ -n "$PROFILE" ]] && ARGS+=(--profile "$PROFILE")
ARGS+=("${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")

echo "⏳ SRT refine ($LANG)…"
"$PYTHON" "$SRT_REFINE_HOME/refine_srt.py" "${ARGS[@]}"
