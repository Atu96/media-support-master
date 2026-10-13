# Build and test

## Subtitle comparison and original text priority

The packaged comparison fixture also reproduces a Chinese OCR/restored subtitle context with a fake English speech result. It checks the primary controller sends `auto` to its engine spy and updates the completed transcript's language to English. Expected additional marker: `SPEECH_LANGUAGE_SMOKE_OK`. Backup and one-shot offline preferences are process-local overrides; fixtures use only temporary files and no provider credentials/API.

The paragraph DUB smoke also reports `latestTiming=kept`: editing SUB timing while generation is in progress must use the latest timeline projection at completion. Inspect the focused hook's markers together with the full offline gate; it does not certify every UI click.

The no-key `MSM_DUBBING_OPTIMIZATION_SMOKE_DIR` hook also expects `MAZIAO_CONTEXT_SMOKE_OK`: selected SUB cue expands to its full paragraph, SUB is unchanged, provider model IDs remain unmodified, cache/rates survive renumbering, deletion stays silent across renumbering and cancellation drains. Core fixtures cover context budgets/Unicode/gaps/QC rejection/cache scope. For a separate user-authorized paid contrast test, both `MSM_ALLOW_PAID_MAZIAO_PROBE=1` and `MSM_MAZIAO_CONTEXT_PROBE_DIR=<fresh temp directory>` are required; it uses at most500 fixed sample characters total, the configured Maziao voice/model and two tasks (one paragraph/four short parts). Samples are exported at1× for listening and file validation is not a quality judgment. It requires readable Keychain credentials; failure before credential load sends no TTS request. Do not enable this paid hook during build/offline QA.

Core fixtures cover explicit time-group choices, missing/one-to-many cues, invalid times, stable IDs and conservative existing-cue script mapping across five languages. For the packaged no-key fake-session check, run `./build-native/run-native-fixtures.command` against the installed main app. Expected marker: `COMPARISON_SMOKE_OK` with private staging, explicit choice, Undo, cancellation/stale preservation, OCR-only audio offers, stale-offer clearing after transcription, suppression/manual access and script text/timing preservation. Release ignores this hook. It does not initialize the app UI, touch personal projects, read Keychain or call cloud services. The native OCR and API service contracts have their separate gates; UI clicks and real-media accuracy require focused review. See [workflow](subtitle-comparison.md).

## Requirements

- Apple silicon Mac; deployment target macOS 15 or later.
- Swift/Apple command-line tools and a macOS SDK with the frameworks imported by the app, including FoundationModels.
- Python 3 for fixture checks. No online provider credentials are needed for offline QA.

## Commands

From the checkout root:

```sh
./build-native/install-applications.command
# Optional standalone checks:
./build-native/test.command
./build-native/run-native-fixtures.command
```

`test.command` covers pure Swift models, subtitle layout/timing, provider fixtures, local audio operations, native shaping, localization, packaging, FCPXML, and script alignment. It compiles temporary outputs under `build-native/.test-out`.

`install-applications.command` is the normal development workflow: offline QA → release-channel build with embedded Runtime/tools/notices → disposable native fixtures → staged signature/hash validation → graceful shutdown → atomic replacement and startup at **/Applications/Media Support Master.app**. It keeps one previous main bundle for rollback and removes the known legacy `dist/test` bundle only after successful startup. Credentials, models, preferences and projects are not reset. `--qa-verified` is for an operator who has just passed offline QA on unchanged runtime source.

`export-test-app.command` and `relaunch-test-app.command` are compatibility aliases to the main installer. They no longer create or install a persistent TEST app. `run-native-fixtures.command` creates a temporary test-channel copy without launching/registering it as a user app, runs the no-key comparison/speech-language fixture, and deletes the copy on exit; its log is `_work/qa-latest/native-comparison.log`. Installed main apps ignore TEST-only environment hooks. Other low-level hooks documented below require a disposable development fixture bundle, never the installed app.

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

## Global subtitle position

Open **Subtitle style** in the right inspector. The **Subtitle position** control appears above both Design and Effects: drag right/up to raise every subtitle, left/down to lower them, or use reset to restore the original 48-pixel offset. The value is a percentage of the 1080 reference canvas; near the top, the text box stays in frame even for large fonts or multiple lines. This changes style only and is saved with the existing project settings.

The offline suite covers persisted position/default compatibility, finite/bounded input, native layer placement for one/two/three lines in landscape/portrait/4K and 24 native/Python FCPXML differential fixtures. To test actual local video output after the suite compiles the harness, use a new temporary directory:

```sh
./build-native/.test-out/SubtitleRendererTests /private/tmp/msm-position-export-new --position
```

It renders bottom/top variants with a large font and one/two-line cues, compares movement and retained text pixels, and writes PNG frames. No credentials/network/user media are used. UI drag behavior and real-video quality remain separate checks.

## QC repair and export toolbar

In the active Timeline, **Extract subtitles from audio** transcribes speech from video/audio; **Extract video subtitles** performs local OCR; **Create Subtitles from a Script** opens the existing script composer and aligns the supplied text with speech while retaining its content. **Export** opens SRT/TXT/XML choices using the existing exporters. Video export remains in titlebar settings. See the [current workflow guide](timeline-workflows.md) for the Vietnamese UI names and usage.

QC checks the selected line limit: a two-line cue is invalid when one line is selected. Open a QC cue submenu to show it, repair its layout or edit it manually. The top repair action processes all cues exceeding the line limit. Repair runs locally on the existing cancellable reflow worker and creates one Undo step. It changes only selected cue text/layout, retains original spans and maps stable planning IDs to canonical SRT numbering. Cache hard links and manual-rate aliases keep unchanged speech/spans available after reopening, including composite audio; original cache keys remain for Undo. A long cue can be split with estimated timing within its original span; affected dubbing can need regeneration. Review remaining QC issues rather than assuming every warning can be fixed automatically.

Offline regressions cover one/two-line detection, VI/EN/KO/ZH/JA targeted repair, glyph width/line limits, text/span/planning-ID preservation, SRT round-trip and Undo/Redo. An opaque local cache fixture checks composite hard-link preservation, manual rate aliases, canonical SRT reopening and deletion tombstones; it does not decode or benchmark speech. Existing reflow lifecycle regressions guard worker cancellation and stale requests. Automatic QC remains read-only; empty text/ambiguous overlaps are not filled or trimmed automatically. UI menu clicks and real-provider rendering remain separate checks.

## Dubbing session smoke

After building a TEST bundle, run the following with a new temporary directory:

```sh
mkdir -p /private/tmp/msm-dubbing-smoke
MSM_DUBBING_OPTIMIZATION_SMOKE_DIR=/private/tmp/msm-dubbing-smoke \
  ./dist/test/Media_Support_Master_TEST.app/Contents/MacOS/MediaSupportMac
```

This TEST-only path exits after exercising the actual `DubbingSessionModel` with a fake speech provider and isolated preferences/cache. It checks two-worker generation, identical-text deduplication (including after explicit deletion), ID/line-break reuse, and cancelling immediately before a new render. It reads no provider credentials and makes no network requests. Release bundles ignore this environment variable. The synthetic MP3 fixture used by core QA is checked in; no local encoder is required to run it.

The same smoke now checks Maziao-style batch concurrency through a fake batch provider, automatic SUB-duration fit, manual rates/natural1×/restore-fit, and an actual local mix export. Tone markers at the ends of long/short inputs remain audible after2×/0.5× mapping; audio beyond the source duration is rejected. Fake sessions disable provider usage refresh as well as credential reads.

An optional TEST-only **paid** probe requires both `MSM_ALLOW_PAID_MAZIAO_PROBE=1` and `MSM_MAZIAO_PIPELINE_PROBE_DIR=<temporary directory>`. It reads the configured Maziao voice/model/key and submits exactly four fixed English samples totaling628 characters in two multiParts batches. It never sends personal subtitle/video content. Do not enable it in automated/offline QA; it consumes provider credits and is only for an explicitly authorized live check. On2026-10-12 the probe returned four valid CAF files, peakremote-waiting2,36.91s total. This is not a serial comparison or long-video performance guarantee. See [dubbing details](dubbing.md).
