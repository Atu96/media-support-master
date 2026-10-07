#!/bin/bash
# export-test-app.command — Build app test ARM (luôn binary mới + stamp version)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="${APP_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=../scripts/common.sh
source "$APP_ROOT/scripts/common.sh"

OUT_APP="$DIST_DIR/test/$TEST_APP_FOLDER"
STAGING="$WORK_DIR/test-ui/staging"
BUILD_ID="$(date +%Y%m%d-%H%M%S)"
# CFBundleVersion monotonic (Launch Services / Dock hay bám bản cũ nếu version không đổi)
BUILD_NUM="$(date +%y%m%d%H%M)"

echo ""
echo "=== Export Media Support Master — app test ARM ==="
echo "    build-id: $BUILD_ID  version-build: $BUILD_NUM"
echo ""

# Tắt process cũ — tránh macOS giữ binary mapped
killall MediaSupportMac 2>/dev/null || true
sleep 0.3

mkdir -p "$(dirname "$OUT_APP")" "$WORK_DIR/test-ui"
ASSEMBLED=$("$SCRIPT_DIR/assemble-arm.command" "$STAGING" "$TEST_APP_FOLDER" test | tail -1)

# Xóa app dist cũ hoàn toàn (tránh merge file cũ trong bundle)
rm -rf "$OUT_APP"
cp -R "$ASSEMBLED" "$OUT_APP"

# Luôn ép binary mới nhất từ out/
cp -f "$BUILD_NATIVE/out/$BINARY_NAME" "$OUT_APP/Contents/MacOS/$BINARY_NAME"
chmod +x "$OUT_APP/Contents/MacOS/$BINARY_NAME"

OUT_HASH=$(shasum -a 256 "$BUILD_NATIVE/out/$BINARY_NAME" | awk '{print $1}')
APP_HASH=$(shasum -a 256 "$OUT_APP/Contents/MacOS/$BINARY_NAME" | awk '{print $1}')
if [[ "$OUT_HASH" != "$APP_HASH" ]]; then
    fail "Binary .app lệch out/ — hãy build lại (out=$OUT_HASH app=$APP_HASH)"
fi
ok "Binary synced với out/ ($OUT_HASH)"

# Stamp version — mỗi lần export khác nhau → Dock/Spotlight không “dính” bản cũ
PLIST="$OUT_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUM" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :MediaSupportBuildChannel test" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :MediaSupportBuildId $BUILD_ID" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :MediaSupportBuildId string $BUILD_ID" "$PLIST"
# Ghi stamp vào Resources (user/agent đối chiếu)
echo "$BUILD_ID" > "$OUT_APP/Contents/Resources/MSM_BUILD_ID.txt"
echo "$OUT_HASH" > "$OUT_APP/Contents/Resources/MSM_BINARY_SHA256.txt"

xattr -cr "$OUT_APP" 2>/dev/null || true
codesign --deep --force --sign - "$OUT_APP" 2>/dev/null || true

# Staging cùng bundle id → dễ mở nhầm. Xóa sau khi copy dist.
rm -rf "$STAGING/$TEST_APP_FOLDER"

# Đăng ký đúng path dist với Launch Services
if [[ -x /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister ]]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$OUT_APP" 2>/dev/null || true
fi

echo ""
ok "App test ARM:"
echo "  $OUT_APP"
echo "  build-id: $BUILD_ID"
echo "  sha256:   $OUT_HASH"
echo ""
echo "Mở đúng path (không dùng Spotlight/Dock cũ):"
echo "  open \"$OUT_APP\""
echo ""
echo "Sửa Swift: $BUILD_NATIVE/source/MediaSupportMac/"
echo "Engine:    $TOOLS_ROOT/"
echo ""
