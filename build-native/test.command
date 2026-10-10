#!/bin/bash
# test.command — Test core Swift độc lập, không đọc Keychain và không gọi API.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/source/MediaSupportMac"
TEST_SRC="$SCRIPT_DIR/tests/MediaSupportCoreTests.swift"
OUT_DIR="$SCRIPT_DIR/.test-out"
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
    fi
fi

run_swiftc() {
    if [[ -n "$SDK_SWIFT_COMPILER" ]]; then
        swiftc -interface-compiler-version "$SDK_SWIFT_COMPILER" "$@"
    else
        swiftc "$@"
    fi
}

SOURCES=(
    "$SRC/Infrastructure/Paths/AppRuntimeRootResolver.swift"
    "$SRC/Domain/Models/AppLanguageSelectionPolicy.swift"
    "$SRC/Domain/Models/SRTSegment.swift"
    "$SRC/Infrastructure/Translation/SRTTimecode.swift"
    "$SRC/Infrastructure/Translation/SRTDocument.swift"
    "$SRC/Infrastructure/Translation/SRTEnglishSentenceSplitter.swift"
    "$SRC/Infrastructure/Translation/SRTSegmentEditor.swift"
    "$SRC/Domain/Models/TimelineCueSelection.swift"
    "$SRC/Domain/Models/GroqConnectionResponseDecoder.swift"
    "$SRC/Domain/Models/GroqRateLimitHeaderDecoder.swift"
    "$SRC/Infrastructure/Translation/SubtitleEditHistory.swift"
    "$SRC/Domain/Models/SubtitleWrapStyle.swift"
    "$SRC/Domain/SubtitleLayout/SubtitleLayoutEngine.swift"
    "$SRC/Domain/SubtitleLayout/SubtitleLinguisticBoundaryContext.swift"
    "$SRC/Domain/SubtitleLayout/SubtitleQualityAnalyzer.swift"
    "$SRC/Domain/SubtitleTiming/SpeechTimingRefiner.swift"
    "$SRC/Domain/SubtitleTiming/SpeechWordTimestamp.swift"
    "$SRC/Domain/SubtitleTiming/SpeechWordTimingProcessor.swift"
    "$SRC/Domain/SubtitleTiming/SemanticCuePlanner.swift"
    "$SRC/Infrastructure/Translation/SubtitleTranscriptPostProcessor.swift"
    "$SRC/Infrastructure/Translation/SubtitleLayoutReflowController.swift"
    "$SRC/Infrastructure/Preview/WaveformPeakService.swift"
    "$SRC/Infrastructure/AI/CloudAIClient.swift"
    "$SRC/Infrastructure/AI/Providers/GroqResponsePolicy.swift"
    "$SRC/Infrastructure/AI/Providers/GroqRateLimitRetryPolicy.swift"
    "$SRC/Infrastructure/AI/CloudAIWorkflow.swift"
    "$SRC/Infrastructure/AI/SemanticCueWorkflow.swift"
    "$SRC/Infrastructure/Preferences/ProjectBackupPathPolicy.swift"
    "$SRC/Domain/Dubbing/DubbingModels.swift"
    "$SRC/Domain/Dubbing/ElevenLabsRequestEncoder.swift"
    "$SRC/Infrastructure/Dubbing/DubbingCacheStore.swift"
    "$SRC/Infrastructure/Dubbing/DubbingAudioDurationCache.swift"
    "$SRC/Infrastructure/Dubbing/MaziaoTaskJournal.swift"
    "$SRC/Infrastructure/Dubbing/DubbingRenderQueue.swift"
    "$SRC/Infrastructure/Dubbing/DubbingAudioTranscoder.swift"
    "$SRC/Infrastructure/Dubbing/DubbingAudioMergeService.swift"
    "$SRC/Domain/Dubbing/MaziaoResponseDecoder.swift"
    "$SRC/App/Localization/L10n.swift"
    "$TEST_SRC"
)

echo "→ Kiểm tra core (${#SOURCES[@]} file, không API)"
run_swiftc \
    -Onone \
    -target "arm64-apple-macos${MIN_MACOS}" \
    -sdk "$SDK" \
    -module-cache-path "$MODULE_CACHE" \
    -parse-as-library \
    -framework AVFoundation \
    -framework CoreText \
    "${SOURCES[@]}" \
    -o "$OUT_DIR/MediaSupportCoreTests"

"$OUT_DIR/MediaSupportCoreTests"
echo "✓ Core tests OK — không dùng API quota"

run_swiftc \
    -Onone \
    -target "arm64-apple-macos${MIN_MACOS}" \
    -sdk "$SDK" \
    -module-cache-path "$MODULE_CACHE" \
    -parse-as-library \
    "$SRC/Domain/Models/SubtitleBurnStyle.swift" \
    "$SCRIPT_DIR/tests/SubtitleBurnStyleTests.swift" \
    -o "$OUT_DIR/SubtitleBurnStyleTests"

"$OUT_DIR/SubtitleBurnStyleTests"

run_swiftc -Onone -target "arm64-apple-macos${MIN_MACOS}" -sdk "$SDK" \
    -module-cache-path "$MODULE_CACHE" -parse-as-library \
    "$SRC/Domain/Models/SRTSegment.swift" \
    "$SRC/Domain/Models/SubtitleBurnStyle.swift" \
    "$SRC/Domain/SubtitleTiming/SpeechWordTimestamp.swift" \
    "$SRC/Domain/SubtitleTiming/NativeScriptAligner.swift" \
    "$SRC/Infrastructure/Translation/SRTDocument.swift" \
    "$SRC/Infrastructure/Translation/SRTTimecode.swift" \
    "$SRC/Infrastructure/Translation/WhisperTimestampDecoder.swift" \
    "$SRC/Infrastructure/Translation/NativeFCPXMLExporter.swift" \
    "$SRC/Infrastructure/Translation/MotionTemplateInstaller.swift" \
    "$SRC/Infrastructure/Translation/NativeAudioPreparation.swift" \
    "$SRC/Infrastructure/Translation/NativeWhisperProcess.swift" \
    "$SRC/Infrastructure/Tools/VerifiedToolManifest.swift" \
    "$SRC/Infrastructure/Tools/VerifiedToolStore.swift" \
    "$SCRIPT_DIR/tests/NativeIntegratedToolsTests.swift" \
    -o "$OUT_DIR/NativeIntegratedToolsTests"
NATIVE_XML_FIXTURES="$(mktemp -d /private/tmp/msm-native-xml.XXXXXX)"
"$OUT_DIR/NativeIntegratedToolsTests" "$NATIVE_XML_FIXTURES"
python3 "$SCRIPT_DIR/tests/test_native_fcpxml.py" "$NATIVE_XML_FIXTURES" "$SCRIPT_DIR/../scripts/lib/convert_srt_fcpxml.py"
rm -rf "$NATIVE_XML_FIXTURES"
if [[ -n "${MSM_JAPANESE_LEGACY_PYTHON:-}" && -n "${MSM_JAPANESE_LEGACY_DICTIONARY:-}" ]]; then
    python3 "$SCRIPT_DIR/tests/test_japanese_helper.py" \
        "$SCRIPT_DIR/../_work/japanese-tools/JapaneseTools/japanese-helper" \
        "$SCRIPT_DIR/../engines/JapaneseAlignment/legacy_core.py" \
        "$MSM_JAPANESE_LEGACY_PYTHON" "$MSM_JAPANESE_LEGACY_DICTIONARY"
fi

# Actual shared native renderer, not the Python fallback. No key/network needed.
run_swiftc -Onone -target "arm64-apple-macos${MIN_MACOS}" -sdk "$SDK" \
    -module-cache-path "$MODULE_CACHE" -parse-as-library \
    "$SRC/Domain/Models/SRTSegment.swift" \
    "$SRC/Infrastructure/Translation/SRTTimecode.swift" \
    "$SRC/Domain/Models/SubtitleBurnStyle.swift" \
    "$SRC/Domain/SubtitleLayout/SubtitleTextLayout.swift" \
    "$SRC/Infrastructure/Preview/SubtitleCueLayerRenderer.swift" \
    "$SRC/Infrastructure/Preview/MusicSubtitleVideoExporter.swift" \
    "$SCRIPT_DIR/tests/SubtitleRendererTests.swift" \
    -o "$OUT_DIR/SubtitleRendererTests"
if [[ -n "${MSM_NATIVE_RENDER_QA_DIR:-}" ]]; then
    "$OUT_DIR/SubtitleRendererTests" "$MSM_NATIVE_RENDER_QA_DIR"
else
    "$OUT_DIR/SubtitleRendererTests"
fi

LOCALIZATION_ROOT="$SRC/Resources/Localization"
LOCALIZATION_LOCALES=(vi en ja ko zh-Hans)
LOCALIZATION_REFERENCE="$LOCALIZATION_ROOT/vi.lproj/Localizable.strings"
[[ -f "$LOCALIZATION_REFERENCE" ]] || {
    echo "✗ Thiếu localization tiếng Việt" >&2
    exit 1
}
for locale in "${LOCALIZATION_LOCALES[@]}"; do
    strings_file="$LOCALIZATION_ROOT/$locale.lproj/Localizable.strings"
    [[ -f "$strings_file" ]] || {
        echo "✗ Thiếu localization: $locale" >&2
        exit 1
    }
    plutil -lint "$strings_file" >/dev/null
done
python3 "$SCRIPT_DIR/tests/test_localization_keys.py" "$LOCALIZATION_ROOT" "${LOCALIZATION_LOCALES[@]}"
echo "✓ Localization OK — đủ khóa vi/en/ja/ko/zh-Hans"

OFFLINE_ASSET="$SCRIPT_DIR/assets/offline-whisper"
OFFLINE_ENGINE="$OFFLINE_ASSET/bin/whisper-cli"
OFFLINE_MANAGER="$SRC/Infrastructure/Translation/OfflineWhisperModelManager.swift"

[[ -x "$OFFLINE_ENGINE" ]] || {
    echo "✗ Thiếu engine Whisper Offline" >&2
    exit 1
}
file "$OFFLINE_ENGINE" | grep -q 'arm64' || {
    echo "✗ Engine Whisper Offline không phải ARM64" >&2
    exit 1
}
if otool -L "$OFFLINE_ENGINE" | tail -n +2 | grep -Eq '(@rpath|/opt/homebrew|/usr/local)'; then
    echo "✗ Engine Whisper Offline còn phụ thuộc thư viện ngoài app" >&2
    exit 1
fi
if find "$OFFLINE_ASSET" -type f -name '*.bin' -print -quit | grep -q .; then
    echo "✗ Model Whisper không được phép đóng gói trong app" >&2
    exit 1
fi
grep -Fq 'expectedBytes: Int64 = 1_624_555_275' "$OFFLINE_MANAGER"
grep -Fq '1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69' "$OFFLINE_MANAGER"
grep -Fq '5359861c739e955e79d9a303bcbc70fb988958b1' "$OFFLINE_MANAGER"
echo "✓ Whisper Offline packaging OK — engine độc lập, model không nằm trong app"

FCPXML_CONVERTER="${MSM_FCPXML_CONVERTER:-$SCRIPT_DIR/../scripts/lib/convert_srt_fcpxml.py}"
python3 "$SCRIPT_DIR/tests/test_fcpxml_style.py" "$FCPXML_CONVERTER"

python3 \
    "$SCRIPT_DIR/tests/test_music_subtitle_effects.py" \
    "$SCRIPT_DIR/../scripts/lib/burn_srt_video.py"

python3 \
    "$SCRIPT_DIR/tests/test_script_align_multilang.py" \
    "$SCRIPT_DIR/../scripts/lib/script_align_multilang.py"
