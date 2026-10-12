# Media Support Master

A native Mac app for creating, editing, translating, and dubbing subtitles from recorded media, on-screen text, or a script.

For **Apple silicon, macOS 15+**. The interface supports English, Vietnamese, Japanese, Korean, and Simplified Chinese. New installations start in English; upgrades preserve a saved language.

## Features

- **Transcription:** Groq Whisper or the downloadable Whisper Turbo Offline model, plus integrated spoken-language detection.
- **Subtitle editing:** import SRT, edit text/timing, move, split or merge cues, and undo changes. Native font measurements and language-aware layout support one/two lines; QC highlights issues and offers explicit repair.
- **Local OCR:** select the burned-in subtitle area in a video. Automatic recognition focuses on Vietnamese, English, Japanese, Korean, and Chinese and produces editable cues. It does not remove text from the picture.
- **Scripts:** paste text or import TXT and align it to speech. Sufficiently matched existing original cues can supply timing without another transcription.
- **Translation and summaries:** Apple local, Groq, or Gemini integrations, subject to device/language/model availability.
- **AI dubbing:** Google Cloud Text-to-Speech, ElevenLabs, Maziao, or Apple speech, with voice selection, duration adjustment, and local cache management. Provider catalogs may include account-accessible custom/cloned voices; this app does not create voice clones.
- **Cross-checking:** compare OCR and audio-derived subtitles and choose results before applying changes.
- **Media preview/export:** video, waveform, subtitle styling/position, and SRT, plain-text TXT, FCPXML, or video with subtitles and dubbed audio.

Maziao's **Connected paragraphs** mode groups nearby cues into editable DUB blocks while keeping SUB cues unchanged. It fits the whole paragraph span; internal speech may not match each subtitle boundary. **Each cue** retains the earlier method. Cloud dubbing includes bounded concurrency, cached speech reuse, and recovery of known Maziao tasks. See [dubbing behavior and limits](docs/development/dubbing.md).

Review recognition, translation, timing, and voices, especially names, unclear recordings, and small/stylized text. Language-aware layout helps unpunctuated text without guaranteeing perfect sentence understanding; Japanese keeps its separate path. Imported SRT has cue times, not word timestamps. Reformatting uses text/gaps; verified word timing is used when supplied by transcription.

## Installation

### Downloads

| Build | Download | Contents |
|---|---|---|
| Current preview | [1.0.1-preview.1, arm64](https://github.com/Atu96/media-support-master/releases/tag/v1.0.1-preview.1) | Current OCR, comparison, QC, script-priority, paragraph-dubbing, and toolbar workflows. |
| Earlier stable | [1.0.1, arm64](https://github.com/Atu96/media-support-master/releases/tag/v1.0.1) | Integrated Japanese tools; predates the newer source/preview features above. |

Release pages provide notes and SHA-256 checksum files. [All releases](https://github.com/Atu96/media-support-master/releases) include older installers; 1.0.0 predates bundled Japanese alignment and retains a legacy Japanese dependency.

1. Download the DMG, open it, and drag the app into **Applications**.
2. Open the app. Builds are **ad-hoc signed, not Developer ID signed or notarized**. If blocked, follow [Apple's safe-opening guidance](https://support.apple.com/en-us/102445) and approve only a source you trust. Do not disable system-wide protections.
3. Configure a provider in **Settings**, or download/import the offline model when needed.

Intel/other operating systems are not supported by these installers. Media must be readable by macOS; extensions do not guarantee codec support. Testing does not cover every supported OS, device, or codec.

### Requirements and permissions

- **Cloud:** your own credentials, internet access, and appropriate provider API/model access. Providers control fees, voices, quotas, and terms.
- **Whisper Offline:** approximately **1.62 GB**, downloaded/imported separately for transcription, spoken-language detection, and fresh script alignment. The executable is bundled; the model is excluded from Git/installers. OCR and matched existing-cue script timing need no Whisper model.
- **Apple local:** this app requires macOS 26+ for Apple translation/summaries and checks availability. Translation needs supported language packs; summaries require available, enabled Apple Intelligence and a supported language.
- **Final Cut Pro exports:** FCPXML targets Final Cut Pro. The bundled **Phu de nen den** Motion title installs when missing and preserves existing/customized templates.
- **Tools:** active subtitle workflows use native/bundled tools, including Japanese MeCab/UniDic, without separate Python/Homebrew/FFmpeg. Optional legacy scripts have separate dependencies; see [integrated tools](docs/development/integrated-tools.md).
- **Permissions:** macOS may request folder and Keychain access. Recorded-file transcription and region OCR do not capture a microphone or record your screen and need neither permission.

Settings offers signed **tool updates** for managed helpers/templates. These do not upgrade the app itself.

## Quick start

1. Import video/audio or SRT.
2. Choose **Extract subtitles from audio**, **Extract video subtitles** (select the OCR area), or **Create subtitles from text**.
3. Review/edit, choose one/two lines, and use QC or optional comparison.
4. Translate, summarize, or dub. **Dub this part** appears with SUB selection; Maziao paragraph mode includes adjacent cues in that paragraph. **Dub all** processes the transcript.
5. Use **Export → SRT / TXT / XML** or title-bar settings for video export. TXT omits timestamps; SRT/FCPXML retain timing.

Guides: [Timeline (Vietnamese)](docs/development/timeline-workflows.md), [OCR](docs/development/subtitle-ocr.md), [comparison/scripts](docs/development/subtitle-comparison.md), and [dubbing](docs/development/dubbing.md).

### Build and test

Install Apple developer command-line tools with a macOS SDK containing `FoundationModels`, plus Python 3 for build/QA scripts. The tested build uses a macOS 26 SDK. From a checkout:

```sh
./build-native/test.command
./build-native/export-test-app.command
open ./dist/test/Media_Support_Master_TEST.app
```

Scripts locate the checkout; `APP_ROOT` can override it. Initial assembly may download and checksum-verify the pinned Japanese helper from GitHub Releases. Artifacts/TEST bundles are Git-ignored; offline QA does not call provider APIs or read their credentials.

With macOS 27 SDK selected, the build prefers an installed macOS 26 SDK for tested SwiftUI behavior. `MSM_MACOS_SDK_PATH` overrides SDK selection; standalone tools lacking the SwiftUI macro plugin are insufficient for a macOS 27 SDK build.

The optional legacy subtitle-refine engine uses its own environment:

```sh
python3 -m venv engines/SRT_Refine/venv
engines/SRT_Refine/venv/bin/python -m pip install -r engines/SRT_Refine/requirements.txt
```

See [build/test notes](docs/development/build-and-test.md), [architecture](docs/development/architecture.md), and [third-party notices](THIRD_PARTY_NOTICES.md).

## Privacy & Data Handling

| Task | Processing / data sent |
|---|---|
| Editing, layout/QC, preview, OCR, video export | Local. OCR reads the selected video region. |
| Whisper Offline, script alignment, spoken-language detection, Apple speech | Local installed model/tools/system voices. |
| Available Apple local translation/summaries | Apple's system translation/on-device model; system resources may need downloading. |
| Groq transcription or cloud audio comparison | Extracted audio chunks go to Groq, not the video picture. Optional semantic refinement also sends word text/timestamps. |
| Groq/Gemini translation or summaries | Subtitle/transcript text and language/task prompts go to the selected provider. |
| Google Cloud/ElevenLabs/Maziao dubbing | Requested text and voice/model/settings go to the provider; paragraph mode includes the full paragraph. Audio downloads into local cache. |

**Keys and local storage.** Keys are saved in **macOS Keychain** and used for provider authentication. Backups can contain text, summaries, filenames, and paths; exports and cached speech are local files. Configure backup location/retention and manage cache in **Settings → Dubbing**. Cloud-synced folders may be synced by your storage service. Local deletion does not delete provider copies/history.

**Other connections.** Credential checks, catalogs, and quotas contact providers; explicit Groq quota refresh uses a minimal text request and can consume quota. Automatic tool checks contact GitHub when due; model downloads contact Hugging Face. Voice-sample/support pages use your browser and those sites' policies. The click-only Ko-fi URL has no user project paths, history, or account data added by the app.

Cloud retention, training, and access depend on provider terms/account settings, not a guarantee from this app. Review policies before sending sensitive content: [Groq](https://console.groq.com/docs/your-data), [Gemini](https://ai.google.dev/gemini-api/terms), [Google Cloud TTS](https://docs.cloud.google.com/text-to-speech/docs/data-logging), [ElevenLabs](https://elevenlabs.io/privacy-policy), [Maziao](https://maziao.com/en/privacy).

## Responsible Media Use

- Use media you own, have permission for, or are otherwise entitled to process; consider video, audio, music, scripts, subtitles, and identifiable people.
- Translation/subtitling/dubbing **does not automatically grant republication rights** to copyrighted content. Processing and distributing an adapted version can require different permissions.
- Do not use AI voices for impersonation, deception, fraud, or exploiting a real person's voice without necessary permission. API-catalog availability does not prove consent or unrestricted publication rights.
- Respect copyright, privacy, provider terms, and publishing-platform rules, including applicable synthetic-media disclosure. See YouTube's [copyright](https://support.google.com/youtube/answer/2797466?hl=en) and [AI-disclosure](https://support.google.com/youtube/answer/14328491?hl=en) guidance.

The app does not verify ownership/consent or certify platform compliance.

## License

No open-source license has been selected for this project's own code. Public GitHub access does not grant unrestricted modification, redistribution, or commercial reuse. Contact the maintainer about reuse/distribution; see [GitHub's no-license explanation](https://choosealicense.com/no-permission/).

Bundled components retain their own licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and bundled notices. These grant neither an app-wide license nor rights to processed media.

## Support and feedback

Use [GitHub Issues](https://github.com/Atu96/media-support-master/issues) with app/build and macOS versions, provider/model, and reproduction steps. Share only permitted samples; remove keys, sensitive transcripts, personal filenames, and private logs. Proposed contributions should describe scoped changes/checks and discuss permissions while the project has no app-wide license.

If the app helps, [support development on Ko-fi](https://ko-fi.com/atu1202). Support is optional, unlocks no features, and does not affect quitting. The link also appears in **Settings → About** and the resource bar.
