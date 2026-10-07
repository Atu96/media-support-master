#!/bin/zsh
# run_whisper_srt.sh <media_file>
# Wrapper — gọi whisper-cli từ Tools/Whisper_Native (không cần Finder)
set -euo pipefail

MEDIA_FILE="${1:-}"
[[ -n "$MEDIA_FILE" && -f "$MEDIA_FILE" ]] || {
    echo "❌ Usage: run_whisper_srt.sh <media_file>" >&2
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

# % ra stderr — macOS unbuffered khi pipe vào app (stdout hay dồn buffer).
msm_progress() {
    print -u2 -r -- "MSM_PROGRESS:$1"
}

cleanup() { msm_cleanup_ffmpeg_shim; [[ -d "${OUT_DIR:-}" ]] && rm -rf "$OUT_DIR"; }
trap cleanup EXIT INT TERM

msm_setup_ffmpeg || { echo "❌ ffmpeg not found" >&2; exit 1; }

source "$WHISPER_HOME/lib/paths.sh"
whisper_load_paths "$WHISPER_HOME/lib/paths.sh"
whisper_check_deps 0 0 || exit 1

BASENAME="$(basename "$MEDIA_FILE" | sed 's/\.[^.]*$//')"
MEDIA_DIR="$(dirname "$MEDIA_FILE")"
OUT_DIR="$(mktemp -d /tmp/msm_whisper_XXXXXX)"
PARTIAL_SRT="$OUT_DIR/whisper.srt"

WAV_FILE="$OUT_DIR/audio.wav"
echo "✅ File: $MEDIA_FILE"
echo "✅ ffmpeg: $(command -v ffmpeg)"
msm_progress 0
echo "⏳ [1/3] Trích xuất âm thanh PCM..."
msm_ffmpeg_extract_audio "$MEDIA_FILE" "$WAV_FILE" || exit 1
msm_progress 8

echo "⏳ [2/3] Whisper detect language..."
DETECT_LOG="$("$WHISPER_CLI" -m "$WHISPER_MODEL" -f "$WAV_FILE" --detect-language --language auto 2>&1 || true)"
DETECTED="$(echo "$DETECT_LOG" | sed -n 's/.*auto-detected language: \([a-zA-Z-]*\).*/\1/p' | head -1 | tr '[:upper:]' '[:lower:]')"
DETECT_CONF="$(echo "$DETECT_LOG" | sed -n 's/.*(p = \([0-9.]*\)).*/\1/p' | head -1)"
[[ -n "$DETECTED" ]] && echo "✅ Ngôn ngữ audio: $DETECTED"
msm_progress 14

echo "⏳ [3/3] Whisper Metal GPU (SRT) — có thể vài phút..."
WHISPER_LANG="${DETECTED:-auto}"
echo "MSM_PARTIAL_SRT:$PARTIAL_SRT"
touch "$PARTIAL_SRT"

# Prompt gợi dấu câu — large-v3-turbo hay bỏ 。、.! nếu không có.
case "${WHISPER_LANG}" in
    ja|jp)
        WHISPER_PROMPT="以下は正しい句読点（、。！？）付きの日本語字幕です。"
        ;;
    zh|zh-cn|zh-tw|yue)
        WHISPER_PROMPT="以下是带正确标点符号的字幕。"
        ;;
    vi)
        WHISPER_PROMPT="Đây là phụ đề tiếng Việt có đầy đủ dấu câu và dấu thanh."
        ;;
    en)
        WHISPER_PROMPT="These are English subtitles with proper punctuation."
        ;;
    *)
        WHISPER_PROMPT="Subtitles with proper punctuation marks."
        ;;
esac
echo "ℹ️ Whisper prompt (dấu câu): $WHISPER_LANG"

# Relay: \\r progress → MSM_PROGRESS trên stderr (tới app ngay).
RELAY_PY="$SCRIPT_DIR/lib/whisper_progress_relay.py"
msm_progress 15
export PYTHONUNBUFFERED=1
"$WHISPER_CLI" \
    -m "$WHISPER_MODEL" \
    -f "$WAV_FILE" \
    --language "$WHISPER_LANG" \
    --prompt "$WHISPER_PROMPT" \
    --output-srt \
    --output-file "$OUT_DIR/whisper" \
    --print-progress \
    --split-on-word \
    --threads 4 2>&1 | python3 -u "$RELAY_PY"

[[ -f "$PARTIAL_SRT" && -s "$PARTIAL_SRT" ]] || {
    sleep 0.2
}
[[ -f "$PARTIAL_SRT" ]] || {
    echo "❌ whisper-cli không xuất được SRT." >&2
    exit 1
}

msm_progress 86
echo "✅ Whisper xong — đang chuẩn bị SRT…"

FINAL_SRT="$MEDIA_DIR/${BASENAME}.srt"
REFINE="${MSM_REFINE:-1}"
msm_progress 88

if [[ "$REFINE" == "1" ]]; then
    echo "⏳ [4/4] Tinh chỉnh timing & xuống dòng (SRT_Refine)…"
    msm_progress 90
    REFINE_CMD=(bash "$SCRIPT_DIR/run_refine_srt.sh" "$PARTIAL_SRT" "${DETECTED:-auto}" "$FINAL_SRT" "")
    [[ -n "${MSM_MAX_LINE_CHARS:-}" ]] && REFINE_CMD+=(--max-line-chars "$MSM_MAX_LINE_CHARS")
    [[ -n "${MSM_MAX_BLOCK_CHARS:-}" ]] && REFINE_CMD+=(--max-block-chars "$MSM_MAX_BLOCK_CHARS")
    [[ -n "${MSM_TOP_LINE_RATIO:-}" ]] && REFINE_CMD+=(--top-line-ratio "$MSM_TOP_LINE_RATIO")
    if "${REFINE_CMD[@]}"; then
        msm_progress 94
        echo "✅ SRT (refined): $FINAL_SRT"
    else
        echo "⚠️ SRT_Refine thất bại — dùng raw whisper.srt"
        cp "$PARTIAL_SRT" "$FINAL_SRT"
        msm_progress 94
        echo "✅ SRT (raw): $FINAL_SRT"
    fi
else
    cp "$PARTIAL_SRT" "$FINAL_SRT"
    msm_progress 94
    echo "✅ SRT (raw, MSM_REFINE=0): $FINAL_SRT"
fi

# 95 — script xong. App nạp SRT rồi mới 100% (không ramp giả 96→99).
msm_progress 95

if [[ -n "${DETECTED:-}" ]]; then
    LANG_FILE="$MEDIA_DIR/${BASENAME}.msm-lang.json"
    CONF_JSON="${DETECT_CONF:-0}"
    cat > "$LANG_FILE" <<JSON
{"language":"$DETECTED","confidence":$CONF_JSON,"detector":"whisper","media":"$MEDIA_FILE","detectedAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON
    echo "✅ Lang sidecar: $LANG_FILE"
fi
