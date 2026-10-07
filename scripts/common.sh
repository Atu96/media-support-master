#!/bin/bash
# common.sh — Paths cho Media Support Master
set -euo pipefail

MSM_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
APP_ROOT="${APP_ROOT:-$(cd "$MSM_COMMON_DIR/.." && pwd)}"
RESOURCES="${RESOURCES:-$HOME/Documents/Resources}"
TOOLS_ROOT="${TOOLS_ROOT:-$HOME/Documents/Tools}"
WHISPER_HOME="${WHISPER_HOME:-$TOOLS_ROOT/Whisper_Native}"
SRT_REFINE_HOME="${SRT_REFINE_HOME:-$APP_ROOT/engines/SRT_Refine}"
VIDEO_SCRIPTS="${VIDEO_SCRIPTS:-$TOOLS_ROOT/VideoSegmentCutter/scripts}"
BUILD_NATIVE="$APP_ROOT/build-native"
CONTENTS_REF="$APP_ROOT/Contents"
DIST_DIR="$APP_ROOT/dist"
WORK_DIR="$APP_ROOT/_work"
BINARY_NAME="MediaSupportMac"
APP_FOLDER="Media Support Master.app"
TEST_APP_FOLDER="Media_Support_Master_TEST.app"

info() { echo "→ $*" >&2; }
ok() { echo "✓ $*" >&2; }
fail() { echo "✗ $*" >&2; exit 1; }

verify_arm_binary() {
    local bin="$1"
    local label="${2:-binary}"
    [[ -x "$bin" ]] || fail "$label không tồn tại: $bin"
    file -b "$bin" | grep -q arm64 || fail "$label không phải arm64: $bin"
    grep -aqF "MainWindowController" "$bin" || fail "$label thiếu MainWindowController"
    ok "$label OK ($(file -b "$bin"))"
}

resolve_ffmpeg() {
    if [[ -n "${FFMPEG:-}" && -x "$FFMPEG" ]]; then
        echo "$FFMPEG"
        return 0
    fi
    local candidate
    for candidate in \
        "$(command -v ffmpeg 2>/dev/null || true)" \
        "/opt/homebrew/bin/ffmpeg" \
        "/usr/local/bin/ffmpeg" \
        "${MSM_APP_RESOURCES:-}/ffmpeg/ffmpeg" \
        "${MSM_APP_RESOURCES:-}/ffmpeg/ffmpeg-mac" \
        "$CONTENTS_REF/Resources/ffmpeg/ffmpeg" \
        "$CONTENTS_REF/Resources/ffmpeg/ffmpeg-mac" \
        "$RESOURCES/Contents/Resources/PlaywrightBrowsers/ffmpeg-1011/ffmpeg-mac"
    do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        echo "$candidate"
        return 0
    done
    return 1
}