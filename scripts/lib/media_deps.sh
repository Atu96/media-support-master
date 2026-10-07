#!/bin/bash
# media_deps.sh — ffmpeg shim + extract audio (GUI app safe)
set -euo pipefail

_msm_ffmpeg_shim_dir=""

msm_cleanup_ffmpeg_shim() {
    [[ -n "$_msm_ffmpeg_shim_dir" && -d "$_msm_ffmpeg_shim_dir" ]] && rm -rf "$_msm_ffmpeg_shim_dir"
    _msm_ffmpeg_shim_dir=""
}

msm_setup_ffmpeg() {
    local candidate=""

    for candidate in \
        "/opt/homebrew/bin/ffmpeg" \
        "/usr/local/bin/ffmpeg" \
        "$(command -v ffmpeg 2>/dev/null || true)" \
        "${FFMPEG:-}" \
        "${MSM_APP_RESOURCES:-}/ffmpeg/ffmpeg" \
        "${MSM_APP_RESOURCES:-}/ffmpeg/ffmpeg-mac"
    do
        [[ -n "$candidate" && -x "$candidate" ]] && break
        candidate=""
    done

    if [[ -z "$candidate" && -n "${MSM_COMMON_SH:-}" && -f "$MSM_COMMON_SH" ]]; then
        # shellcheck disable=SC1090
        source "$MSM_COMMON_SH"
        candidate="$(resolve_ffmpeg 2>/dev/null || true)"
    fi

    [[ -n "$candidate" && -x "$candidate" ]] || return 1

    export FFMPEG="$candidate"
    local dir
    dir="$(dirname "$candidate")"
    export PATH="$dir:${PATH:-}"

    if [[ "$(basename "$candidate")" != "ffmpeg" ]]; then
        _msm_ffmpeg_shim_dir="$(mktemp -d /tmp/msm_ffmpeg_XXXXXX)"
        ln -sf "$candidate" "$_msm_ffmpeg_shim_dir/ffmpeg"
        export PATH="$_msm_ffmpeg_shim_dir:${PATH:-}"
    fi

    command -v ffmpeg >/dev/null 2>&1
}

# Trích PCM 16kHz — -nostdin tránh treo khi chạy từ app GUI
msm_ffmpeg_extract_audio() {
    local input="$1"
    local output="$2"

    [[ -f "$input" ]] || { echo "❌ Không tìm thấy file: $input"; return 1; }

    if [[ "$input" == /Volumes/* ]]; then
        echo "ℹ️  Đọc từ ổ ngoài — có thể chậm với file dài"
    fi

    local size_mb
    size_mb="$(du -m "$input" 2>/dev/null | awk '{print $1}')"
    [[ -n "$size_mb" ]] && echo "ℹ️  Kích thước ~${size_mb} MB"

    echo "⏳ ffmpeg đang trích xuất audio..."

    local heartbeat_pid=""
    (
        while true; do
            sleep 20
            echo "… vẫn đang trích xuất audio ($(date +%H:%M:%S))"
        done
    ) &
    heartbeat_pid=$!

    local rc=0
    ffmpeg -nostdin -hide_banner -loglevel warning -y \
        -i "$input" \
        -vn -sn -dn \
        -ar 16000 -ac 1 -c:a pcm_s16le \
        "$output" 2>&1 || rc=$?

    kill "$heartbeat_pid" 2>/dev/null || true
    wait "$heartbeat_pid" 2>/dev/null || true

    if [[ "$rc" -ne 0 ]]; then
        echo "❌ ffmpeg thoát mã $rc"
        return "$rc"
    fi

    if [[ ! -s "$output" ]]; then
        echo "❌ ffmpeg không tạo được WAV"
        return 1
    fi

    echo "✅ Audio PCM: $(du -h "$output" 2>/dev/null | awk '{print $1}')"
    return 0
}