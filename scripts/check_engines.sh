#!/bin/bash
# check_engines.sh — Kiểm tra engine Tools + deps
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

echo "=== Media Support Master — Engine Check ==="
echo "TOOLS_ROOT=$TOOLS_ROOT"
echo ""

ok_count=0
fail_count=0

check() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "✓ $label"
        ok_count=$((ok_count + 1))
    else
        echo "✗ $label"
        fail_count=$((fail_count + 1))
    fi
}

[[ -d "$TOOLS_ROOT" ]] && echo "✓ Tools folder" || { echo "✗ Tools folder"; fail_count=$((fail_count + 1)); }
[[ -d "$WHISPER_HOME" ]] && echo "✓ Whisper_Native" || { echo "✗ Whisper_Native"; fail_count=$((fail_count + 1)); }
[[ -d "$VIDEO_SCRIPTS" ]] && echo "✓ VideoSegmentCutter scripts" || { echo "✗ VideoSegmentCutter scripts"; fail_count=$((fail_count + 1)); }

if ffmpeg_path="$(resolve_ffmpeg)"; then
    echo "✓ ffmpeg: $ffmpeg_path"
    ok_count=$((ok_count + 1))
else
    echo "✗ ffmpeg not found (brew or Resources bundle)"
    fail_count=$((fail_count + 1))
fi

check "whisper-cli" command -v whisper-cli
check "whisper model" test -f "$WHISPER_HOME/ggml-large-v3-turbo.bin"
check "venv python" test -x "$WHISPER_HOME/venv/bin/python"
check "mecab" command -v mecab
if [[ -d "/opt/homebrew/lib/mecab/dic/unidic" || -d "/usr/local/lib/mecab/dic/unidic" ]]; then
    echo "✓ MeCab UniDic (tiếng Nhật)"
    ok_count=$((ok_count + 1))
else
    echo "⚠ MeCab UniDic chưa có — tiếng Nhật dùng IPADIC dự phòng"
fi
check "cut_batch_interleave.sh" test -x "$VIDEO_SCRIPTS/cut_batch_interleave.sh"

if [[ -d "$SRT_REFINE_HOME" ]]; then
    echo "✓ SRT_Refine: $SRT_REFINE_HOME"
    ok_count=$((ok_count + 1))
    if [[ -x "$SRT_REFINE_HOME/venv/bin/python" ]]; then
        echo "✓ SRT_Refine venv"
        ok_count=$((ok_count + 1))
    else
        echo "✗ SRT_Refine venv (pip install -r requirements.txt)"
        fail_count=$((fail_count + 1))
    fi
else
    echo "✗ SRT_Refine: $SRT_REFINE_HOME"
    fail_count=$((fail_count + 1))
fi

echo ""
echo "Kết quả: $ok_count OK, $fail_count thiếu"
[[ "$fail_count" -eq 0 ]]
