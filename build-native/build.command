#!/bin/bash
# build.command — Compile MediaSupportMac (arm64), auto-discover Swift sources
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="${APP_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
SRC="$SCRIPT_DIR/source/MediaSupportMac"
OUT_DIR="${1:-$SCRIPT_DIR/out}"
source "$SCRIPT_DIR/../scripts/lib/macos_sdk.sh"
SDK="$(msm_macos_sdk)"
MIN_MACOS="15.0"
MODULE_CACHE="$OUT_DIR/.module-cache"

mkdir -p "$OUT_DIR" "$MODULE_CACHE"

SDK_SWIFT_COMPILER=""
SDK_SWIFT_INTERFACE="$(find "$SDK/usr/lib/swift/Swift.swiftmodule" \
    -name '*-apple-macos.swiftinterface' -print -quit 2>/dev/null || true)"
if [[ -n "$SDK_SWIFT_INTERFACE" ]]; then
    SDK_SWIFT_VERSION="$(sed -n 's#^// swift-compiler-version: .*Apple Swift version \([^ ]*\).*#\1#p' \
        "$SDK_SWIFT_INTERFACE" | head -1)"
    HOST_SWIFT_VERSION="$(swiftc --version 2>&1 \
        | sed -n 's#^.*Apple Swift version \([^ ]*\).*#\1#p' | head -1)"
    if [[ -n "$SDK_SWIFT_VERSION" && -n "$HOST_SWIFT_VERSION" \
        && "$SDK_SWIFT_VERSION" != "$HOST_SWIFT_VERSION" ]]; then
        SDK_SWIFT_COMPILER="$(sed -n 's#^// swift-compiler-version: ##p' \
            "$SDK_SWIFT_INTERFACE" | head -1)"
        echo "→ SDK Swift $SDK_SWIFT_VERSION · compiler $HOST_SWIFT_VERSION (compatibility mode)"
    fi
fi

run_swiftc() {
    if [[ -n "$SDK_SWIFT_COMPILER" ]]; then
        swiftc -interface-compiler-version "$SDK_SWIFT_COMPILER" "$@"
    else
        swiftc "$@"
    fi
}

SOURCES=()
while IFS= read -r f; do
    SOURCES+=("$f")
done < <(find "$SRC" -name '*.swift' | sort)

if [[ ${#SOURCES[@]} -eq 0 ]]; then
    echo "✗ Không tìm thấy file .swift trong $SRC"
    exit 1
fi

FRAMEWORKS=(
    AppKit SwiftUI Combine UniformTypeIdentifiers AVKit AVFoundation AVFAudio
    Translation NaturalLanguage CoreText Security FoundationModels IOKit SoundAnalysis Vision
)

echo "→ swiftc arm64 (${#SOURCES[@]} files)"
run_swiftc \
    -O \
    -whole-module-optimization \
    -target "arm64-apple-macos${MIN_MACOS}" \
    -sdk "$SDK" \
    -module-cache-path "$MODULE_CACHE" \
    -parse-as-library \
    "${SOURCES[@]}" \
    $(printf -- "-framework %s " "${FRAMEWORKS[@]}") \
    -o "$OUT_DIR/MediaSupportMac-arm64"

chmod +x "$OUT_DIR/MediaSupportMac-arm64"
cp "$OUT_DIR/MediaSupportMac-arm64" "$OUT_DIR/MediaSupportMac"

echo "✓ $OUT_DIR/MediaSupportMac ($(file -b "$OUT_DIR/MediaSupportMac"))"

for sym in MainWindowController MediaEngineService AVPreviewService AppCoordinator; do
    if grep -aqF "$sym" "$OUT_DIR/MediaSupportMac"; then
        echo "  ✓ $sym"
    else
        echo "  ✗ MISSING $sym"
        exit 1
    fi
done

for bad in NSPopover WKWebView AppModel; do
    if grep -aqF "$bad" "$OUT_DIR/MediaSupportMac" 2>/dev/null; then
        echo "  ✗ BAD SYMBOL $bad"
        exit 1
    fi
done

echo ""
echo "✓ Native build OK"
