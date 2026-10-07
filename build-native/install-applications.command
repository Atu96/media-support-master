#!/bin/bash
# install-applications.command — Cài build đã test, chỉ giữ đúng một bản previous để phục hồi.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="${APP_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=../scripts/common.sh
source "$APP_ROOT/scripts/common.sh"

SOURCE_APP="$DIST_DIR/test/$TEST_APP_FOLDER"
DEST_APP="/Applications/$APP_FOLDER"
BACKUP_DIR="$DIST_DIR/backups/applications"
PREVIOUS_APP="$BACKUP_DIR/Media Support Master.previous.app"

"$SCRIPT_DIR/test.command"

[[ -d "$SOURCE_APP" ]] || fail "Chưa có app test để cài: $SOURCE_APP"
BUILD_ID="$(cat "$SOURCE_APP/Contents/Resources/MSM_BUILD_ID.txt" 2>/dev/null || true)"
[[ -n "$BUILD_ID" ]] || fail "App test thiếu build-id."

SOURCE_HASH="$(shasum -a 256 "$SOURCE_APP/Contents/MacOS/$BINARY_NAME" | awk '{print $1}')"
STAMPED_HASH="$(cat "$SOURCE_APP/Contents/Resources/MSM_BINARY_SHA256.txt" 2>/dev/null || true)"
[[ -n "$STAMPED_HASH" ]] || fail "App test thiếu checksum build."
codesign --verify --deep --strict "$SOURCE_APP" 2>/dev/null \
    || fail "Chữ ký app test không hợp lệ."

mkdir -p "$BACKUP_DIR"
TEMP_APP="/Applications/.Media-Support-Master-installing-$BUILD_ID.app"
[[ ! -e "$TEMP_APP" ]] || fail "Còn app cài tạm: $TEMP_APP"

OLD_BACKUP=""
restore_on_error() {
    if [[ ! -d "$DEST_APP" && -n "$OLD_BACKUP" && -d "$OLD_BACKUP" ]]; then
        mv "$OLD_BACKUP" "$DEST_APP"
    fi
}
trap restore_on_error ERR

killall "$BINARY_NAME" 2>/dev/null || true
ditto "$SOURCE_APP" "$TEMP_APP"

if [[ -d "$DEST_APP" ]]; then
    rm -rf "$PREVIOUS_APP"
    OLD_BACKUP="$PREVIOUS_APP"
    mv "$DEST_APP" "$OLD_BACKUP"
fi

mv "$TEMP_APP" "$DEST_APP"
xattr -cr "$DEST_APP" 2>/dev/null || true

INSTALLED_HASH="$(shasum -a 256 "$DEST_APP/Contents/MacOS/$BINARY_NAME" | awk '{print $1}')"
[[ "$INSTALLED_HASH" == "$SOURCE_HASH" ]] || fail "Binary Applications lệch bản đã test."
codesign --verify --deep --strict "$DEST_APP" 2>/dev/null \
    || fail "Chữ ký app Applications không hợp lệ."

if [[ -x /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister ]]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$DEST_APP" 2>/dev/null || true
fi

open "$DEST_APP"
ok "Đã cài và mở: $DEST_APP"
echo "  build-id: $BUILD_ID"
echo "  sha256:   $INSTALLED_HASH"
if [[ -n "$OLD_BACKUP" ]]; then
    echo "  app cũ:   $OLD_BACKUP"
fi
