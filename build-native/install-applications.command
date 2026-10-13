#!/bin/bash
# Build, validate and atomically replace the main app. User data stays outside the bundle.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="${APP_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$APP_ROOT/scripts/common.sh"
case "${1:-}" in
    "") "$SCRIPT_DIR/test.command" ;;
    --qa-verified) info "Offline QA already passed for the unchanged runtime source." ;;
    *) fail "Usage: install-applications.command [--qa-verified]" ;;
esac
mkdir -p "$WORK_DIR"
STAGING="$(mktemp -d "$WORK_DIR/main-install.XXXXXX")"
BUILD_ID="$(TZ=Asia/Ho_Chi_Minh date +%Y%m%d-%H%M%S)"
BUILD_NUM="$(TZ=Asia/Ho_Chi_Minh date +%y%m%d%H%M)"
DEST_APP="/Applications/$APP_FOLDER"
TEMP_APP="/Applications/.Media-Support-Master-installing-$BUILD_ID.app"
PREVIOUS_APP="$DIST_DIR/backups/applications/Media Support Master.previous.app"
LEGACY_TEST="$DIST_DIR/test/$TEST_APP_FOLDER"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
REPLACED=0
HAD_PREVIOUS=0
TEMP_CREATED=0
cleanup() {
    rm -rf "$STAGING"
    if [[ "$TEMP_CREATED" == 1 && -e "$TEMP_APP" ]]; then rm -rf "$TEMP_APP"; fi
}
rollback() {
    if [[ "$REPLACED" == 1 ]]; then
        rm -rf "$DEST_APP"
        if [[ "$HAD_PREVIOUS" == 1 ]]; then mv "$PREVIOUS_APP" "$DEST_APP"; fi
    fi
}
trap cleanup EXIT
trap rollback ERR
[[ ! -e "$TEMP_APP" ]] || fail "Installation staging already exists: $TEMP_APP"
MSM_BUNDLE_FFMPEG=0 "$SCRIPT_DIR/assemble-arm.command" "$STAGING" "$APP_FOLDER" release
APP="$STAGING/$APP_FOLDER"
RUNTIME="$APP/Contents/Resources/Runtime"
mkdir -p "$RUNTIME"
while IFS= read -r -d '' relative; do
    case "$relative" in */tests/*|*/run_tests.sh|scripts/lib/macos_sdk.sh|scripts/sign-tools-manifest.swift|scripts/lib/prepare_japanese_helper.py) continue ;; esac
    mkdir -p "$RUNTIME/$(dirname "$relative")"
    cp -p "$APP_ROOT/$relative" "$RUNTIME/$relative"
done < <(git -C "$APP_ROOT" ls-files -z -- scripts engines/SRT_Refine)
cp "$APP_ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :MediaSupportBuildId string $BUILD_ID" "$APP/Contents/Info.plist"
printf '%s\n' "$BUILD_ID" > "$APP/Contents/Resources/MSM_BUILD_ID.txt"
git -C "$APP_ROOT" rev-parse HEAD > "$APP/Contents/Resources/MSM_SOURCE_COMMIT.txt"
git -C "$APP_ROOT" diff HEAD -- Contents build-native/source scripts engines assets | shasum -a 256 | awk '{print $1}' > "$APP/Contents/Resources/MSM_SOURCE_DIFF_SHA256.txt"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
SOURCE_HASH="$(shasum -a 256 "$APP/Contents/MacOS/$BINARY_NAME" | awk '{print $1}')"
# Keep the signed binary hash outside its resource seal (no self-referential stamp).
"$SCRIPT_DIR/run-native-fixtures.command" "$APP"
quit_bundle() {
    local bundle="$1" executable="$1/Contents/MacOS/$BINARY_NAME"
    if pgrep -f -x "$executable" >/dev/null; then
        osascript - "$bundle" <<'OSA'
on run argv
    set appPath to item 1 of argv
    with timeout of 10 seconds
        tell application appPath to quit
    end timeout
end run
OSA
        for _ in {1..40}; do
            if ! pgrep -f -x "$executable" >/dev/null; then return; fi
            sleep 0.25
        done
        fail "App is still running; installation stopped without replacing it."
    fi
}
if [[ -d "$LEGACY_TEST" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LEGACY_TEST/Contents/Info.plist")" == com.gemst.media-support-master ]] || fail "Unexpected TEST bundle identifier."
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :MediaSupportBuildChannel' "$LEGACY_TEST/Contents/Info.plist")" == test ]] || fail "Unexpected TEST bundle channel."
fi
quit_bundle "$DEST_APP"
quit_bundle "$LEGACY_TEST"
[[ ! -e "$TEMP_APP" ]] || fail "Installation staging appeared while building: $TEMP_APP"
TEMP_CREATED=1
ditto "$APP" "$TEMP_APP"
codesign --verify --deep --strict "$TEMP_APP"
[[ "$(shasum -a 256 "$TEMP_APP/Contents/MacOS/$BINARY_NAME" | awk '{print $1}')" == "$SOURCE_HASH" ]] || fail "Staged binary differs from validated build."
if [[ -d "$DEST_APP" ]]; then
    mkdir -p "$(dirname "$PREVIOUS_APP")"
    [[ ! -x "$LSREGISTER" ]] || "$LSREGISTER" -u "$DEST_APP" 2>/dev/null || true
    rm -rf "$PREVIOUS_APP"
    mv "$DEST_APP" "$PREVIOUS_APP"
    HAD_PREVIOUS=1
fi
REPLACED=1
mv "$TEMP_APP" "$DEST_APP"
[[ ! -x "$LSREGISTER" ]] || "$LSREGISTER" -f "$DEST_APP" 2>/dev/null || true
open "$DEST_APP"
STARTED_PID=""
for _ in {1..40}; do
    STARTED_PID="$(pgrep -f -x "$DEST_APP/Contents/MacOS/$BINARY_NAME" | head -1 || true)"
    [[ -n "$STARTED_PID" ]] && break
    sleep 0.25
done
[[ -n "$STARTED_PID" ]] || fail "Main app failed startup; rollback restores the previous app."
# Remove only the validated TEST bundle, after the replacement has passed startup.
if [[ -d "$LEGACY_TEST" ]]; then
    [[ ! -x "$LSREGISTER" ]] || "$LSREGISTER" -u "$LEGACY_TEST" 2>/dev/null || true
    rm -rf "$LEGACY_TEST"
fi
REPLACED=0
ok "Main app: $DEST_APP"
ok "Build: $BUILD_ID | Startup PID: $STARTED_PID"
ok "Signed binary SHA-256: $SOURCE_HASH"
