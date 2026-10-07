#!/bin/bash
# run_burn_srt_video.sh <video> <srt> [--font ...] [--font-size N] ...
set -euo pipefail

VIDEO="${1:-}"
SRT="${2:-}"
shift 2 || true
EXTRA_ARGS=("$@")

[[ -n "$VIDEO" && -f "$VIDEO" ]] || { echo "❌ Usage: run_burn_srt_video.sh <video> <srt> [style args]"; exit 1; }
[[ -n "$SRT" && -f "$SRT" ]] || { echo "❌ Không tìm thấy SRT: $SRT"; exit 1; }

APP_ROOT="${APP_ROOT:-$HOME/Documents/Media Support App}"
TOOLS_ROOT="${TOOLS_ROOT:-$HOME/Documents/Tools}"
WHISPER_HOME="${WHISPER_HOME:-$TOOLS_ROOT/Whisper_Native}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
MSM_COMMON_SH="$SCRIPT_DIR/common.sh"
# shellcheck source=lib/media_deps.sh
source "$SCRIPT_DIR/lib/media_deps.sh"

cleanup() { msm_cleanup_ffmpeg_shim; }
trap cleanup EXIT INT TERM

msm_setup_ffmpeg || { echo "❌ ffmpeg not found"; exit 1; }

# Renderer canonical nằm cùng dự án để effect model/test không phụ thuộc Tools ngoài app.
# Giữ fallback cũ cho bundle/source chưa đồng bộ trong giai đoạn chuyển tiếp.
BURN_PY="$SCRIPT_DIR/lib/burn_srt_video.py"
[[ -f "$BURN_PY" ]] || BURN_PY="$WHISPER_HOME/burn_srt_video.py"
[[ -f "$BURN_PY" ]] || { echo "❌ Không tìm thấy burn_srt_video.py"; exit 1; }

VENV_PYTHON="$WHISPER_HOME/venv/bin/python"
[[ -x "$VENV_PYTHON" ]] || VENV_PYTHON="$(command -v python3)"

echo "✅ Video: $VIDEO"
echo "✅ SRT: $SRT"
echo "✅ ffmpeg: $(command -v ffmpeg)"

"$VENV_PYTHON" "$BURN_PY" "$VIDEO" "$SRT" "${EXTRA_ARGS[@]}"
