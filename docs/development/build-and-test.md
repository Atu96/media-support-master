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

Building the app does not install all legacy workflows. Existing wrappers can still need external Whisper/FFmpeg/media tools. Diagnostics currently check that legacy environment, so a new checkout can build while reporting missing runtime tools. Offline native transcription uses the included small Whisper engine and a separately downloaded model.

The TEST bundle finds scripts relative to its checkout. Release bundles prefer their own `Contents/Resources/Runtime` scripts; `APP_ROOT` can explicitly override this. Legacy external tools remain separate dependencies.

## Preview DMG

Commit runtime changes, run the offline QA gate above, write the matching `docs/releases/X.Y.Z-preview.N.md`, then use `./build-native/export-release-app.command vX.Y.Z-preview.N` with the actual app version. It compiles the release app, bundles tracked runtime scripts/refine source and the Motion title (no environments or tests), signs locally, creates and verifies a DMG under `dist/release`, and writes a relative-filename SHA-256 file. It deliberately excludes local FFmpeg binaries and models. Verify a read-only mount and startup before publishing; never reuse a published tag or overwrite its assets. The preview is ad-hoc signed, not notarized. See [integrated tools](integrated-tools.md) for the current native paths and tool-feed maintenance.

## Reporting checks

Passing source/fixture tests is not the same as testing real media, a paid provider, UI interaction, or installer notarization. Describe the exact tests, tool versions, media and provider scope. Do not put personal logs, keys, project paths or media into the repository.

Local agent/checkpoint/archive notes remain outside Git. A fresh clone uses these developer notes and the actual code/tests as its guide.
