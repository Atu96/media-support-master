# Integrated tools

0.2.2 Preview 1 uses native FCPXML export, a bundled Motion template, native audio extraction, bundled Whisper language detection and native script alignment. The retained 0.2.1 installer predates these changes.

## Runtime

- XML exports the same Motion parameter contract as the established Python converter. Rational time representations can differ while their values remain equal. FPS/style/Unicode fixtures compare the resulting XML trees. Existing Motion templates, including user edits, are preserved; a missing template is installed from the app. Native video and dubbing code are unchanged.
- Audio is streamed through AVAssetReader to 16 kHz mono PCM; no FFmpeg/Python is required for the native paths. Files must be readable by macOS. Unsupported codecs remain an explicit error rather than a silent conversion.
- Short audio uses CPU; recordings of at least 30 seconds use the engine's Metal path unless CPU-only is selected in Settings → Integrated tools. Helpers exit after each job to release model memory. Cancellation reaches audio extraction, alignment and the helper process.
- Vietnamese/English/Korean/Chinese script alignment matches the original text to verified Whisper token spans with a memory-bounded alignment window. Small ASR substitutions may use neighboring token spans. Poor matches are rejected, not filled with evenly distributed times. Japanese script alignment retains the existing MeCab workflow and its legacy dependencies; Japanese subtitle layout is unchanged.
- Script output stays temporary until the same project/transcript snapshot can accept a successful result. Failure/cancellation/stale results do not replace the current transcript. Speech-to-text accuracy and alignment accuracy still need real-media review.
- An existing exact legacy model can be imported after SHA-256 validation, using a hard-link when possible. Model modification time invalidates the cached verification; download is still a separate user choice. The model is not duplicated in the installer.

## Tool updates

The app checks a small signed feed at most once per day when idle, or on a manual request. `updates/tools.json` contains base64 payload/signature fields. Ed25519 verifies its exact payload against the public key in Info.plist. Its payload pins architecture, minimum app version and each allowed file's URL, byte size and SHA-256. Tool assets belong to this repository's GitHub Releases; models are excluded.

Downloads stage in Application Support/Media Support Master/Tools. File integrity, ARM executable header, helper startup and template XML are checked before activation. Busy tasks defer activation; failures keep the current/bundled tools. The previous signed version is retained for rollback; older managed versions are pruned. Templates already installed in the user's Motion folder are preserved, so updates cannot overwrite customized templates.

Maintainers sign a JSON payload with `swift scripts/sign-tools-manifest.swift payload.json updates/tools.json`. The helper stores the private key only in login Keychain under service `com.gemst.media-support-master.tool-updates.signing`. Its printed public key must match Info.plist. Back up that signing key securely before replacing the development Mac; Git does not back up Keychain. Do not blindly follow upstream latest binaries: run the app's compatibility/quality gates before publishing a new signed feed.

Tool updates do not update the app itself. App distribution remains a separate signed/notarized release or future Homebrew/Sparkle workflow.

## Validation

`test.command` includes core/Japanese layout regressions, native script fixtures in five languages, a long script with an ASR substitution, mismatch rejection, token JSON/language parsing, signed manifests, damaged assets, rollback, template preservation, native stereo-to-mono extraction, helper cancellation and 21 native/legacy XML comparisons. It does not call providers or access Keychain.

Optional `MSM_NATIVE_TRANSCRIPT_FIXTURES` points to locally generated synthetic Whisper JSON/TXT fixtures named vi/ko/zh. The TEST app also has an explicit `MSM_INTEGRATED_TOOLS_SMOKE_DIR` diagnostic: a directory containing synthetic `speech.wav` and `script.txt` runs native alignment/detection/XML, without loading the UI or calling online providers. The diagnostic is disabled for release-channel apps.
