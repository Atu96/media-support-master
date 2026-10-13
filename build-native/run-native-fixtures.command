#!/bin/bash
# Run TEST-only fixtures in a private disposable copy; never install a TEST app.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="${APP_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$APP_ROOT/scripts/common.sh"
SOURCE_APP="${1:-/Applications/$APP_FOLDER}"
[[ -d "$SOURCE_APP" ]] || fail "Missing app: $SOURCE_APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")" == com.gemst.media-support-master ]] || fail "Unexpected app identifier."
codesign --verify --deep --strict "$SOURCE_APP"
mkdir -p "$WORK_DIR"
FIXTURE_ROOT="$(mktemp -d "$WORK_DIR/native-fixtures.XXXXXX")"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT
APP="$FIXTURE_ROOT/Fixture.app"
ditto "$SOURCE_APP" "$APP"
/usr/libexec/PlistBuddy -c 'Set :MediaSupportBuildChannel test' "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$WORK_DIR/qa-latest"
LOG="$WORK_DIR/qa-latest/native-comparison.log"
env -u MSM_ALLOW_PAID_MAZIAO_PROBE MSM_SUBTITLE_COMPARISON_SMOKE_DIR="$FIXTURE_ROOT/comparison" "$APP/Contents/MacOS/$BINARY_NAME" > "$LOG" 2>&1
grep -q '^COMPARISON_SMOKE_OK ' "$LOG" || fail "Comparison fixture did not complete."
grep -q '^SPEECH_LANGUAGE_SMOKE_OK ' "$LOG" || fail "Speech language fixture did not complete."
cat "$LOG"
LOG="$WORK_DIR/qa-latest/native-dubbing.log"
env -u MSM_ALLOW_PAID_MAZIAO_PROBE MSM_DUBBING_OPTIMIZATION_SMOKE_DIR="$FIXTURE_ROOT/dubbing" "$APP/Contents/MacOS/$BINARY_NAME" > "$LOG" 2>&1
grep -q '^DUBBING_SMOKE_OK ' "$LOG" || fail "Dubbing fixture did not complete."
grep -q '^MAZIAO_CONTEXT_SMOKE_OK ' "$LOG" || fail "Maziao context fixture did not complete."
cat "$LOG"
LOG="$WORK_DIR/qa-latest/native-markers.log"
env -u MSM_ALLOW_PAID_MAZIAO_PROBE MSM_TIMELINE_MARKER_SMOKE=1 "$APP/Contents/MacOS/$BINARY_NAME" > "$LOG" 2>&1
grep -q '^TIMELINE_MARKER_SMOKE_OK ' "$LOG" || fail "Marker manifest fixture did not complete."
cat "$LOG"
ok "Native fixtures passed; disposable bundle removed on exit."
