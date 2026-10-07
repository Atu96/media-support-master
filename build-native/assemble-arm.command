#!/bin/bash
# assemble-arm.command — Compile Swift + lắp .app ARM (không nhúng Python)
#
# Usage: assemble-arm.command <staging_parent> [app_folder_name] [build_channel]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="${APP_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=../scripts/common.sh
source "$APP_ROOT/scripts/common.sh"

STAGING_PARENT="${1:-}"
APP_FOLDER_NAME="${2:-$TEST_APP_FOLDER}"
BUILD_CHANNEL="${3:-test}"

case "$BUILD_CHANNEL" in
    release|test) ;;
    *) fail "Build channel không hợp lệ: $BUILD_CHANNEL" ;;
esac

[[ -n "$STAGING_PARENT" ]] || fail "Thiếu staging_parent."

info "[native] Compile Swift (channel=$BUILD_CHANNEL)..."
"$SCRIPT_DIR/build.command" >&2

APP_STAGING="$STAGING_PARENT/$APP_FOLDER_NAME"
rm -rf "$APP_STAGING"
mkdir -p "$APP_STAGING/Contents/MacOS"
mkdir -p "$APP_STAGING/Contents/Resources/ffmpeg"
mkdir -p "$APP_STAGING/Contents/Resources/offline-whisper"

cp "$CONTENTS_REF/Info.plist" "$APP_STAGING/Contents/Info.plist"
cp -p "$BUILD_NATIVE/out/MediaSupportMac" "$APP_STAGING/Contents/MacOS/MediaSupportMac"
chmod +x "$APP_STAGING/Contents/MacOS/MediaSupportMac"
verify_arm_binary "$APP_STAGING/Contents/MacOS/MediaSupportMac" "Bundle binary"

# Native localization resources. Keep the .lproj directories intact so macOS
# can select the preferred language without an app-specific runtime switch.
LOCALIZATION_SRC="$BUILD_NATIVE/source/MediaSupportMac/Resources/Localization"
if [[ -d "$LOCALIZATION_SRC" ]]; then
    while IFS= read -r localization_dir; do
        cp -R "$localization_dir" "$APP_STAGING/Contents/Resources/"
    done < <(find "$LOCALIZATION_SRC" -maxdepth 1 -type d -name '*.lproj' -print | sort)
    ok "Localization resources copied"
fi

# Whisper Offline: chỉ đóng gói engine ARM nhỏ; model 1,62 GB do user tự tải trong Cài đặt.
OFFLINE_WHISPER_SRC="$BUILD_NATIVE/assets/offline-whisper"
if [[ -x "$OFFLINE_WHISPER_SRC/bin/whisper-cli" ]]; then
    cp -R "$OFFLINE_WHISPER_SRC/bin" "$APP_STAGING/Contents/Resources/offline-whisper/"
    cp -R "$OFFLINE_WHISPER_SRC/licenses" "$APP_STAGING/Contents/Resources/offline-whisper/"
    chmod +x "$APP_STAGING/Contents/Resources/offline-whisper/bin/whisper-cli"
    ok "Bundled Whisper Offline engine (model không nằm trong app)"
else
    info "Không có offline-whisper engine asset"
fi

# ffmpeg fallback từ Resources (không tải lại)
FFMPEG_SRC="$RESOURCES/Contents/Resources/PlaywrightBrowsers/ffmpeg-1011/ffmpeg-mac"
if [[ -x "$FFMPEG_SRC" ]]; then
    cp -p "$FFMPEG_SRC" "$APP_STAGING/Contents/Resources/ffmpeg/ffmpeg-mac"
    chmod +x "$APP_STAGING/Contents/Resources/ffmpeg/ffmpeg-mac"
    ln -sf "ffmpeg-mac" "$APP_STAGING/Contents/Resources/ffmpeg/ffmpeg"
    ok "Bundled ffmpeg fallback"
else
    info "Không có ffmpeg trong Resources — dùng brew ffmpeg khi chạy"
fi

# Optional: AppIcon từ Resources nếu có
ICON_SRC="$APP_ROOT/assets/branding/AppIcon.icns"
[[ -f "$ICON_SRC" ]] || ICON_SRC="$RESOURCES/Contents/Resources/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
    cp -p "$ICON_SRC" "$APP_STAGING/Contents/Resources/AppIcon.icns"
    ok "AppIcon copied from Resources"
fi

/usr/libexec/PlistBuddy -c "Set :MediaSupportBuildChannel $BUILD_CHANNEL" "$APP_STAGING/Contents/Info.plist" 2>/dev/null || true

xattr -cr "$APP_STAGING" 2>/dev/null || true
codesign --deep --force --sign - "$APP_STAGING" 2>/dev/null || true

ok "ARM app assembled ($BUILD_CHANNEL): $APP_STAGING"
printf '%s\n' "$APP_STAGING"
