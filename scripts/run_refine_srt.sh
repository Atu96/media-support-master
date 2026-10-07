#!/bin/zsh
# run_refine_srt.sh — App wrapper → engines/SRT_Refine
# Usage: run_refine_srt.sh <in.srt> <lang> <out.srt> [profile] [--max-line-chars N …]
set -euo pipefail

IN_SRT="${1:-}"
LANG="${2:-auto}"
OUT_SRT="${3:-}"
PROFILE="${4:-}"
shift $(( $# >= 4 ? 4 : $# )) || true
EXTRA_ARGS=("$@")

APP_ROOT="${APP_ROOT:-$HOME/Documents/Media Support App}"
SRT_REFINE_HOME="${SRT_REFINE_HOME:-$APP_ROOT/engines/SRT_Refine}"

exec "$SRT_REFINE_HOME/run_refine_srt.sh" "$IN_SRT" "$LANG" "$OUT_SRT" "$PROFILE" "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
