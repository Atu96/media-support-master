#!/bin/bash
# run_detect_media_lang.sh <media_file>
# Nhận diện ngôn ngữ nói từ audio/video qua Whisper (Metal) — ghi sidecar .msm-lang.json
set -euo pipefail

MEDIA_FILE="${1:-}"
[[ -n "$MEDIA_FILE" && -f "$MEDIA_FILE" ]] || {
    echo "❌ Usage: run_detect_media_lang.sh <media_file>"
    exit 1
}

APP_ROOT="${APP_ROOT:-$HOME/Documents/Media Support App}"
TOOLS_ROOT="${TOOLS_ROOT:-$HOME/Documents/Tools}"
WHISPER_HOME="${WHISPER_HOME:-$TOOLS_ROOT/Whisper_Native}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
MSM_COMMON_SH="$SCRIPT_DIR/common.sh"
# shellcheck source=lib/media_deps.sh
source "$SCRIPT_DIR/lib/media_deps.sh"

cleanup() { msm_cleanup_ffmpeg_shim; [[ -d "${OUT_DIR:-}" ]] && rm -rf "$OUT_DIR"; }
trap cleanup EXIT INT TERM

msm_setup_ffmpeg || { echo "❌ ffmpeg not found"; exit 1; }

source "$WHISPER_HOME/lib/paths.sh"
whisper_load_paths "$WHISPER_HOME/lib/paths.sh"
whisper_check_deps 0 0 || exit 1

BASENAME="$(basename "$MEDIA_FILE" | sed 's/\.[^.]*$//')"
MEDIA_DIR="$(dirname "$MEDIA_FILE")"
OUT_DIR="$(mktemp -d /tmp/msm_detect_XXXXXX)"

WAV_FILE="$OUT_DIR/audio.wav"
echo "✅ ffmpeg: $(command -v ffmpeg)"
echo "⏳ Trích xuất âm thanh..."
msm_ffmpeg_extract_audio "$MEDIA_FILE" "$WAV_FILE" || exit 1

echo "⏳ Whisper detect language..."
DETECT_LOG="$("$WHISPER_CLI" -m "$WHISPER_MODEL" -f "$WAV_FILE" --detect-language --language auto 2>&1 || true)"
DETECTED="$(echo "$DETECT_LOG" | sed -n 's/.*auto-detected language: \([a-zA-Z-]*\).*/\1/p' | head -1 | tr '[:upper:]' '[:lower:]')"
CONF="$(echo "$DETECT_LOG" | sed -n 's/.*(p = \([0-9.]*\)).*/\1/p' | head -1)"

[[ -n "$DETECTED" ]] || {
    echo "❌ Không detect được ngôn ngữ từ audio."
    exit 1
}

LANG_FILE="$MEDIA_DIR/${BASENAME}.msm-lang.json"
CONF_JSON="${CONF:-0}"
cat > "$LANG_FILE" <<JSON
{"language":"$DETECTED","confidence":$CONF_JSON,"detector":"whisper","media":"$MEDIA_FILE","detectedAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON

echo "✅ Detect: $DETECTED (confidence $CONF_JSON)"
echo "✅ Sidecar: $LANG_FILE"