# Media Support Master

A Mac app for transcribing media, editing subtitles, translating text, and dubbing audio in one timeline.

## What it does

- Transcribe with Groq Whisper or the downloadable Whisper Turbo Offline model.
- Import SRT, edit text and timing, split or merge cues, and undo edits.
- Arrange one- or two-line subtitles with native font measurements and language-aware boundaries, including transcripts without punctuation.
- Translate and summarize through the available Apple, Groq, or Gemini integrations.
- Dub with Google, ElevenLabs, Maziao, or Apple speech; manage voice selection and the local audio cache.
- Export SRT, plain text, FCPXML, or video with subtitles and dubbing.

## Availability

This public repository contains development source for Apple silicon Macs. The app targets macOS 15 or later. Download the first preview from [GitHub Releases](https://github.com/Atu96/media-support-master/releases/tag/v0.2.1-preview.1); see its notes for setup and known limits. Intel is not supported by that installer.

The preview installer and local TEST bundles use ad-hoc signing; they are not Developer ID signed or notarized. A source build is not a certification that every provider, language, or media file has been tested live.

## Quick start

1. Download the arm64 DMG, open it, and drag the app into Applications; or build the TEST app using the instructions below. macOS may require first-launch approval in Privacy & Security because the preview is not notarized.
2. Import a video/audio file or an existing SRT. Configure a provider key or download the offline model in Settings if you want to transcribe.
3. Transcribe, review the cues, and choose a one- or two-line layout. Layout runs in the background.
4. Edit, translate, or dub the cues you need.
5. Use **Export SRT / TXT / XML**, or the title-bar export settings for video output.

A new installation starts in English. Upgrades preserve a valid saved language, including System mode. The interface also includes Vietnamese, Japanese, Korean, and Simplified Chinese.

## Limits and dependencies

**Current source after 0.2.1 Preview 1:** XML, spoken-language detection and Vietnamese/English/Korean/Chinese script alignment now use integrated native tools. A Motion template is included, and signed tool updates are available in Settings. Japanese script alignment keeps its existing workflow. The downloadable 0.2.1 preview predates this migration; see [integrated tool notes](docs/development/integrated-tools.md).

- Online providers require your own credentials and may charge for usage. Voice/model availability and quotas belong to the provider.
- The offline model is downloaded separately (about 1.62 GB); it is not stored in Git or bundled with the app. The small ARM Whisper executable and its notices are included.
- The release bundles its runtime scripts. Existing legacy workflows still use external tools under `~/Documents/Tools`, including `Whisper_Native`. FFmpeg is required for some extraction/fallback operations and is not bundled with this preview. Missing tools are reported by diagnostics; the installer does not install or rebuild them.
- FCPXML refers to the custom Motion title **Phu de nen den**, which is not packaged in this repository. A matching title installation is needed for that appearance in Final Cut Pro. The converter and its style regression are included.
- Subtitle boundaries use local token/phrase rules and available macOS language analysis. They can improve unpunctuated text, but do not guarantee perfect sentence understanding. Japanese retains its separate existing layout path.
- SRT imports do not contain per-word audio timestamps. Reformatting an existing project uses its text and cue gaps; verified word timestamps are used when supplied during transcription.
- Native preview/export and fixture tests are covered by automated QA. Real media and paid-provider testing remain separate checks.

## Privacy

API credentials are stored in macOS Keychain. Projects, exports, and dubbing cache are kept on your Mac. A selected online service receives the audio or text required for its task; offline processing has different requirements. Do not include private media, provider keys, or logs containing personal information in issue reports.

Support links open only when clicked. The app sends no file paths, usage history, or account information in the Ko-fi URL, and never treats opening the page as a payment.

## Support

If this app saves you time, you can [support its development on Ko-fi](https://ko-fi.com/atu1202). No pressure — thanks for using it! ❤️

Support is optional and does not unlock features or affect quitting the app. The same link is available in **Settings → About** and the resource bar.

## Build and test

Install Apple developer command-line tools with a macOS SDK that includes `FoundationModels` (the current build uses a macOS 26 SDK), plus Python 3. Run from a checkout:

```sh
./build-native/test.command
./build-native/export-test-app.command
open ./dist/test/Media_Support_Master_TEST.app
```

These commands locate the checkout automatically. `APP_ROOT` can override the root. Build artifacts and TEST bundles are ignored by Git. The offline QA command does not call APIs or read provider credentials.

When the active SDK is macOS 27, the build prefers an installed macOS 26 SDK to retain this app's tested SwiftUI state behavior. `MSM_MACOS_SDK_PATH` can select a specific SDK. Standalone command-line tools that lack the SwiftUI macro plugin are not sufficient for a macOS 27 SDK build.

For the optional legacy subtitle-refine engine:

```sh
python3 -m venv engines/SRT_Refine/venv
engines/SRT_Refine/venv/bin/python -m pip install -r engines/SRT_Refine/requirements.txt
```

See [build and test notes](docs/development/build-and-test.md) and [architecture](docs/development/architecture.md). Please keep changes scoped and describe the behavior and checks in contributions.

## License

An open-source license has not been selected for this project's own code. Public access to the repository does not grant a new open-source license. Third-party components retain their own licenses; see [notices](THIRD_PARTY_NOTICES.md).
