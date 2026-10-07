#!/bin/bash
# relaunch-test-app.command — Kill + (optional) clear cache + export + open ĐÚNG dist/test
# Dùng sau mỗi lần sửa Swift khi nghi “dính cache / app cũ”.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="${APP_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=../scripts/common.sh
source "$APP_ROOT/scripts/common.sh"

OUT_APP="$DIST_DIR/test/$TEST_APP_FOLDER"
BUNDLE_ID="com.gemst.media-support-master"
CLEAR_CACHE="${1:-}"  # truyền --clear-cache để xóa prefs/cache app (không xóa vault)

echo ""
echo "=== Relaunch test app (anti-stale) ==="
echo ""

# 1) Tắt mọi process binary
killall MediaSupportMac 2>/dev/null || true
sleep 0.4

# 2) Cache / saved state (tuỳ chọn) — KHÔNG xóa vault Movies
if [[ "$CLEAR_CACHE" == "--clear-cache" ]]; then
    info "Xóa cache + saved state + prefs msm.* (giữ vault)…"
    rm -rf "$HOME/Library/Caches/$BUNDLE_ID" 2>/dev/null || true
    rm -rf "$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState" 2>/dev/null || true
    # Prefs layout/style — chỉ khi user muốn “sạch UI”
    defaults delete "$BUNDLE_ID" 2>/dev/null || true
    ok "Cache/prefs cleared"
else
    info "Giữ prefs (thêm --clear-cache nếu muốn reset UI prefs)"
fi

# 3) Build + stamp + đăng ký path dist
"$SCRIPT_DIR/export-test-app.command"

# 4) Mở đúng absolute path (không open -a theo tên)
if [[ ! -d "$OUT_APP" ]]; then
    fail "Không có app: $OUT_APP"
fi
BUILD_ID=$(cat "$OUT_APP/Contents/Resources/MSM_BUILD_ID.txt" 2>/dev/null || echo "?")
echo ""
ok "Opening: $OUT_APP"
echo "    build-id: $BUILD_ID"
open "$OUT_APP"

# Startup smoke: build/relaunch chỉ được coi là đạt khi đúng binary dist/test
# thực sự sống sau khi Launch Services mở app.
BINARY_PATH="$OUT_APP/Contents/MacOS/$BINARY_NAME"
STARTED_PID=""
for _ in {1..30}; do
    STARTED_PID="$(pgrep -f -x "$BINARY_PATH" | head -1 || true)"
    [[ -n "$STARTED_PID" ]] && break
    sleep 0.1
done
[[ -n "$STARTED_PID" ]] || fail "App TEST không sống sau khi mở: $BINARY_PATH"
ok "Startup smoke OK — pid $STARTED_PID · đúng dist/test"
echo ""
