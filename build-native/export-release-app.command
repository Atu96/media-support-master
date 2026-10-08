#!/bin/bash
# Create an Apple silicon DMG from the committed source.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="${APP_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$APP_ROOT/scripts/common.sh"
SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS_REF/Info.plist")"
TAG="${1:-v$SOURCE_VERSION}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-preview\.[0-9]+)?$ ]] || fail "Expected vX.Y.Z or vX.Y.Z-preview.N"
[[ "$TAG" == "v$SOURCE_VERSION" || "$TAG" == "v$SOURCE_VERSION-preview."* ]] || fail "Tag does not match app version $SOURCE_VERSION"
[[ -f "$APP_ROOT/docs/releases/${TAG#v}.md" ]] || fail "Write release notes before packaging."
SOURCE_COMMIT="$(git -C "$APP_ROOT" rev-parse HEAD)"
git -C "$APP_ROOT" diff --quiet HEAD -- Contents build-native/source scripts engines assets \
    || fail "Commit runtime changes before packaging."
RELEASE_DIR="$DIST_DIR/release"
mkdir -p "$RELEASE_DIR" "$WORK_DIR"
DMG="$RELEASE_DIR/Media-Support-Master-${TAG#v}-arm64.dmg"
[[ ! -e "$DMG" ]] || fail "Release artifact already exists: $DMG"
STAGING="$(mktemp -d "$WORK_DIR/release.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

# No unreviewed local FFmpeg binary is redistributed. Native workflows remain
# available; the documented legacy extraction/fallback paths use user tools.
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
cp "$APP_ROOT/README.md" "$STAGING/README.md"
cp "$APP_ROOT/docs/releases/${TAG#v}.md" "$STAGING/Release-Notes.md"
BUILD_ID="$(TZ=Asia/Ho_Chi_Minh date +%Y%m%d-%H%M%S)"
/usr/libexec/PlistBuddy -c "Add :MediaSupportBuildId string $BUILD_ID" "$APP/Contents/Info.plist"
printf '%s\n' "$BUILD_ID" > "$APP/Contents/Resources/MSM_BUILD_ID.txt"
printf '%s\n' "$SOURCE_COMMIT" > "$APP/Contents/Resources/MSM_SOURCE_COMMIT.txt"
printf '%s\n' "$TAG" > "$APP/Contents/Resources/MSM_RELEASE_TAG.txt"
codesign --force --sign - "$APP/Contents/Resources/offline-whisper/bin/whisper-cli"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "Media Support Master" -srcfolder "$STAGING" -format UDZO "$DMG"
hdiutil verify "$DMG"
(cd "$RELEASE_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
ok "Release DMG: $DMG"
ok "Source: $SOURCE_COMMIT | Build: $BUILD_ID | Tag: $TAG"
ok "Signed binary SHA-256: $(shasum -a 256 "$APP/Contents/MacOS/MediaSupportMac" | awk '{print $1}')"
