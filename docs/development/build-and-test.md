# Build and test

## Requirements

- Apple silicon Mac; deployment target macOS 15 or later.
- Swift/Apple command-line tools and a macOS SDK with the frameworks imported by the app, including FoundationModels.
- Python 3 for fixture checks. No online provider credentials are needed for offline QA.

## Commands

From the checkout root:

```sh
./build-native/test.command
./build-native/build.command
./build-native/export-test-app.command
```

`test.command` covers pure Swift models, subtitle layout/timing, provider fixtures, local audio operations, native shaping, localization, packaging, FCPXML, and script alignment. It compiles temporary outputs under `build-native/.test-out`.

`export-test-app.command` builds and stamps a TEST app under `dist/test`. `relaunch-test-app.command` additionally stops existing MediaSupportMac processes and opens that exact bundle; use it when intentionally replacing a running TEST instance. It preserves preferences by default.

The build root is derived from the checkout, with an optional `APP_ROOT` override. AppIcon and the FCPXML converter are repository-owned inputs. FCPXML style tests can override the converter via `MSM_FCPXML_CONVERTER`.

`scripts/lib/macos_sdk.sh` selects an installed macOS 26 SDK when the active SDK is 27, without changing `xcode-select`. This retains the app's existing SwiftUI property-wrapper behavior on standalone tools missing `SwiftUIMacros`. Use `MSM_MACOS_SDK_PATH` for an explicit SDK. A full macOS 27 SDK build needs the matching macro-capable tools; no SDK files or app state properties are rewritten.

## Runtime dependencies

Active subtitle workflows use the integrated native tools, including the packaged Japanese helper from 1.0.1. Native diagnostics report those tools. Offline transcription and script alignment use the included Whisper engine and a separately selected/downloaded model. Retained legacy wrappers can still need external tools when invoked directly; see [integrated tools](integrated-tools.md).

The TEST bundle finds retained scripts relative to its checkout. Release bundles prefer their own `Contents/Resources/Runtime` scripts; `APP_ROOT` can explicitly override this.

## Release DMG

Commit runtime changes, run the offline QA gate above, write the matching `docs/releases/X.Y.Z.md`, then use `./build-native/export-release-app.command vX.Y.Z` with the actual app version. Preview tags use `vX.Y.Z-preview.N` and matching notes. It compiles the release app, bundles tracked runtime scripts/refine source and the Motion title (no environments, tests or maintainer signing helper), signs locally, creates and verifies a DMG under `dist/release`, and writes a relative-filename SHA-256 file. It deliberately excludes local FFmpeg binaries and models. Verify a read-only mount and startup before publishing; never reuse a published tag or overwrite its assets. Signing is ad-hoc, not notarized. See [integrated tools](integrated-tools.md) for the current native paths and tool-feed maintenance.

## Reporting checks

Passing source/fixture tests is not the same as testing real media, a paid provider, UI interaction, or installer notarization. Describe the exact tests, tool versions, media and provider scope. Do not put personal logs, keys, project paths or media into the repository.

Local agent/checkpoint/archive notes remain outside Git. A fresh clone uses these developer notes and the actual code/tests as its guide.

## Subtitle OCR smoke

The OCR hook is documented under [subtitle OCR](subtitle-ocr.md). `test.command` also compiles/runs native `SubtitleOCRTests` with Vision and synthetic H.264 video. To retain fixtures, run `./build-native/.test-out/SubtitleOCRTests /private/tmp/msm-ocr-fixtures-new` with a new directory, then run the TEST binary with `MSM_SUBTITLE_OCR_SMOKE_DIR=/private/tmp/msm-ocr-fixtures-new`. This exercises the packaged OCR→SRT path without Keychain or network. The native test covers auto VI/EN/JA/KO/ZH, crop, rotation, one/two lines, closer sampling and cancellation.

## Dubbing session smoke

After building a TEST bundle, run the following with a new temporary directory:

```sh
mkdir -p /private/tmp/msm-dubbing-smoke
MSM_DUBBING_OPTIMIZATION_SMOKE_DIR=/private/tmp/msm-dubbing-smoke \
  ./dist/test/Media_Support_Master_TEST.app/Contents/MacOS/MediaSupportMac
```

This TEST-only path exits after exercising the actual `DubbingSessionModel` with a fake speech provider and isolated preferences/cache. It checks two-worker generation, identical-text deduplication (including after explicit deletion), ID/line-break reuse, and cancelling immediately before a new render. It reads no provider credentials and makes no network requests. Release bundles ignore this environment variable. The synthetic MP3 fixture used by core QA is checked in; no local encoder is required to run it.
