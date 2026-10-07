#!/bin/zsh
# run_tao_srt_kichban.sh <media_file> <script_text_file> [language_code]
# Whisper timing + align theo hệ chữ — progress MSM_PROGRESS (stderr) liên tục, không treo %.
set -euo pipefail

MEDIA_FILE="${1:-}"
SCRIPT_FILE="${2:-}"
LANG_CODE="$(printf '%s' "${3:-ja}" | tr '[:upper:]' '[:lower:]')"
[[ -n "$MEDIA_FILE" && -f "$MEDIA_FILE" ]] || {
    echo "❌ Usage: run_tao_srt_kichban.sh <media_file> <script_text_file> [ja|zh|ko|ru|en|vi|fr|es|pt|de|it]"
    exit 1
}
[[ -n "$SCRIPT_FILE" && -f "$SCRIPT_FILE" ]] || {
    echo "❌ Không tìm thấy file kịch bản: $SCRIPT_FILE"
    exit 1
}
case "$LANG_CODE" in
    ja|zh|ko|ru|en|vi|fr|es|pt|de|it) ;;
    *) echo "❌ Ngôn ngữ kịch bản chưa hỗ trợ: $LANG_CODE"; exit 1 ;;
esac

APP_ROOT="${APP_ROOT:-$HOME/Documents/Media Support App}"
TOOLS_ROOT="${TOOLS_ROOT:-$HOME/Documents/Tools}"
WHISPER_HOME="${WHISPER_HOME:-$TOOLS_ROOT/Whisper_Native}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=lib/media_deps.sh
source "$SCRIPT_DIR/lib/media_deps.sh"

cleanup() { msm_cleanup_ffmpeg_shim; [[ -d "${OUT_DIR:-}" ]] && rm -rf "$OUT_DIR"; }
trap cleanup EXIT INT TERM

msm_setup_ffmpeg || { echo "❌ ffmpeg not found"; exit 1; }

source "$WHISPER_HOME/lib/paths.sh"
whisper_load_paths "$WHISPER_HOME/lib/paths.sh"
whisper_check_deps 0 0 || exit 1
[[ -f "$CORE_PY" ]] || { echo "❌ Không tìm thấy srt_core.py"; exit 1; }

BASENAME="$(basename "$MEDIA_FILE" | sed 's/\.[^.]*$//')"
MEDIA_DIR="$(dirname "$MEDIA_FILE")"
OUT_DIR="$(mktemp -d /tmp/msm_script_align_XXXXXX)"

# Progress → stderr (EngineRunner đọc pipe ngay)
msm_progress() {
    print -u2 -r -- "MSM_PROGRESS:$1"
}

WAV_FILE="$OUT_DIR/audio.wav"
echo "✅ File: $MEDIA_FILE"
echo "✅ Kịch bản: $SCRIPT_FILE"
echo "✅ Ngôn ngữ: $LANG_CODE"
msm_progress 5
echo "⏳ [1/3] Trích xuất PCM WAV 16kHz mono..."
msm_ffmpeg_extract_audio "$MEDIA_FILE" "$WAV_FILE" || exit 1
msm_progress 12

WHISPER_SRT="$OUT_DIR/whisper.srt"
echo "⏳ [2/4] Whisper Metal ($LANG_CODE) — progress liên tục…"
# Map Whisper 0–100 → 15–72 (chừa 73–95 align, 96–100 app nạp)
export MSM_PROG_LOW=15
export MSM_PROG_HIGH=72
export PYTHONUNBUFFERED=1
RELAY_PY="$SCRIPT_DIR/lib/whisper_progress_relay.py"
"$WHISPER_CLI" \
    -m "$WHISPER_MODEL" \
    -f "$WAV_FILE" \
    --language "$LANG_CODE" \
    --max-len 1 \
    --output-srt \
    --output-file "$OUT_DIR/whisper" \
    --print-progress \
    --threads 4 \
    2>&1 | python3 -u "$RELAY_PY"

[[ -f "$WHISPER_SRT" ]] || {
    # một số build ghi whisper.srt khác path
    if [[ -f "$OUT_DIR/whisper.srt" ]]; then
        WHISPER_SRT="$OUT_DIR/whisper.srt"
    else
        echo "❌ whisper-cli không xuất được SRT."
        exit 1
    fi
}
msm_progress 75

msm_progress 80
ALIGNED_SRT="$OUT_DIR/aligned.srt"
FINAL_SRT="${MSM_SCRIPT_OUTPUT:-$MEDIA_DIR/${BASENAME}.srt}"
if [[ "$LANG_CODE" == "ja" ]]; then
    echo "⏳ [3/4] NLP align tiếng Nhật (MeCab + Kinsoku + CPS)…"
    UNIDIC_DIR=""
    for candidate in \
        "/opt/homebrew/lib/mecab/dic/unidic" \
        "/usr/local/lib/mecab/dic/unidic"; do
        if [[ -d "$candidate" ]]; then
            UNIDIC_DIR="$candidate"
            break
        fi
    done
    if [[ -n "$UNIDIC_DIR" ]]; then
        export MECAB_DICDIR="$UNIDIC_DIR"
        echo "✓ MeCab dictionary: UniDic"
    else
        echo "⚠️ Chưa có UniDic — dùng IPADIC dự phòng"
    fi
    "$VENV_PYTHON" "$CORE_PY" "$WHISPER_SRT" "$SCRIPT_FILE" "$ALIGNED_SRT"
else
    echo "⏳ [3/4] Align kịch bản $LANG_CODE theo từ/câu…"
    ALIGN_PY="$SCRIPT_DIR/lib/script_align_multilang.py"
    [[ -f "$ALIGN_PY" ]] || { echo "❌ Thiếu script_align_multilang.py"; exit 1; }
    "$VENV_PYTHON" "$ALIGN_PY" \
        "$WHISPER_SRT" "$SCRIPT_FILE" "$ALIGNED_SRT" --lang "$LANG_CODE"
fi
[[ -f "$ALIGNED_SRT" && -s "$ALIGNED_SRT" ]] || {
    echo "❌ Align kịch bản không ra SRT."
    exit 1
}
msm_progress 88

# [4/4] Khép timing giống sub tự động: end_i = start_{i+1} (giữ chữ kịch bản)
echo "⏳ [4/4] Khép timecode liền mạch (force_abut)…"
SRT_REFINE_HOME="${SRT_REFINE_HOME:-$APP_ROOT/engines/SRT_Refine}"
ABUT_PY="$SRT_REFINE_HOME/force_abut_srt.py"
REFINE_PY="${SRT_REFINE_HOME}/venv/bin/python"
[[ -x "$REFINE_PY" ]] || REFINE_PY="$VENV_PYTHON"
if [[ -f "$ABUT_PY" ]]; then
    if "$REFINE_PY" "$ABUT_PY" --in "$ALIGNED_SRT" --out "$FINAL_SRT"; then
        echo "✅ SRT (align + khít timing): $FINAL_SRT"
    else
        echo "⚠️ force_abut lỗi — giữ bản align (có gap)"
        cp "$ALIGNED_SRT" "$FINAL_SRT"
    fi
else
    echo "⚠️ Không có force_abut_srt.py — copy align thô"
    cp "$ALIGNED_SRT" "$FINAL_SRT"
fi
msm_progress 95

LANG_FILE="$MEDIA_DIR/${BASENAME}.msm-lang.json"
cat > "$LANG_FILE" <<JSON
{"language":"$LANG_CODE","confidence":1,"detector":"script","media":"$MEDIA_FILE","detectedAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON
echo "✅ Lang sidecar: $LANG_FILE"
# 95 — app nạp list sub rồi 100%
