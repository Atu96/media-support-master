# Burned-in subtitle OCR

This feature is in the current source/local-build build after 1.0.1. It requires a new build; the published 1.0.1 installer does not contain it.

## User workflow

1. Import a video into the main Timeline workspace. Click **Scan subtitles** beneath the files in the left **Media & subtitles** panel, or the button with the same label and text-viewfinder icon beside **Transcribe** in the middle toolbar. Both open the region-selection sheet for the currently imported video. The toolbar entry remains available when the import panel is hidden. Audio-only files and an active engine job disable OCR; an API key is not required.
2. Move the preview-frame slider to a frame containing subtitles. Drag on the displayed image to select their area; **Bottom area** restores the initial region.
3. Automatic detection focuses on Vietnamese, English, Japanese, Korean and Chinese, using the OCR locales actually supported by the installed OS.
4. **Scan subtitles** runs locally. **Scan more closely** increases sampling from two to four frames per second. **Stop scan** or closing the sheet cancels processing.
5. Complete results become original subtitle cues and a separate working SRT in the existing project store. Use the existing timeline, translation, dubbing and SRT/video export actions.

This extracts text visible in the picture. It does not remove that text from the original video, extract embedded subtitle tracks, transcribe audio, require an API key, or download Whisper/another app-managed model.

## Ownership and execution

After primary OCR, the optional completion offer invites audio transcription to check missing/misread words. Primary transcription does not offer OCR; the **Compare** menu still opens either source manually. Supplementary OCR stages its result for review instead of committing to the transcript. The existing primary OCR action still creates the original transcript. See [comparison and original text priority](subtitle-comparison.md).

| Responsibility | Owner |
|---|---|
| Normalized top-left crop and streaming timing/change accumulator | `Domain/SubtitleTiming/OCRSubtitleAccumulator.swift` |
| Frame extraction, Vision recognition, language detection and cancellation | `Infrastructure/Translation/SubtitleOCRService.swift` |
| Job/snapshot/progress and complete-result commit | `Presentation/Features/Subtitles/Create/SubtitleOCRCreateController.swift` |
| Frame preview, drag selection and scan controls | `SubtitleOCRConfigurationView.swift` |
| Active Timeline entry and sheet presentation | `SubtitleTimelineWorkspace.swift` |
| Legacy create-card entry | `SubtitleDraftMediaCard.swift` |
| Adopting the generated transcript without restoring an older SRT | `SubtitleViewModel+Session.swift` |

Scanning pauses playback in the main preview and uses a utility worker, one frame/recognition request at a time, with a maximum image dimension of 1280 pixels. The crop is applied before OCR. Preferred video transforms are applied in both preview and scan; selection coordinates refer to the displayed image. A digest of normalized RGB pixels avoids repeated recognition when the crop is unchanged; equal-luminance color changes still invalidate it. An autorelease pool releases per-frame objects. Progress is based on actual sampled video time, throttled to percentage changes; 100% is shown after commit.

Vision revision 3 performs automatic script/language selection with the available primary locales; Vietnamese may be returned as `vi-VT`, so that value is obtained at runtime. The final source-language code is derived from recognized text using NaturalLanguage, never from audio. Restricting the candidate locales avoids unnecessary language-correction work. Framework startup costs and supported OCR languages vary by OS.

The accumulator preserves recognized line order, punctuation and Unicode text, normalizes whitespace, groups repeated frames into cues, retains observed blank gaps, and suppresses one-sample text jitter. Unknown/low-confidence recognition does not invent words. Timing is estimated between sampled frames; brief subtitles, fades, low contrast, complex backgrounds, logos inside the selection or ambiguous text can need review. No word timestamps are fabricated and Japanese layout tailoring is unchanged.

Cancellation reaches the worker, frame generator and Vision request. Changing media or editing/switching the active transcript stops a scan. Commit also checks media, cues, variant, SRT URL and pending edit text against its start snapshot. Failed, cancelled or stale scans preserve the active transcript. A successful scan writes the canonical working SRT atomically and uses the existing session/backup path. Automatic reopening only imports a sibling SRT if the working transcript is missing or the sibling is newer; explicit SRT import is unchanged. This prevents an older export from replacing new OCR or manual edits.

## Verification

Core tests cover region clamping/reverse drag, repeated text, multiline preservation, blanks, uncertain frames, jitter, finite/non-overlapping timestamps, SRT round-trip and sibling-file freshness. Native tests create offline synthetic videos for VI/EN/JA/KO/ZH, one/two lines, rotation metadata, both sampling modes, crop exclusion, blank-region failure and cancellation. No API or personal media is used.

The TEST-only `MSM_SUBTITLE_OCR_SMOKE_DIR` hook scans `subtitles.mp4` in a synthetic fixture directory and writes `ocr-result.srt`. Release builds ignore the hook. This checks the packaged processing service, not the visibility of a UI entry. UI review must follow `MainWindowView.moduleContent` into the active Timeline workspace, import video, check both OCR entries, open region selection and repeat with the import panel hidden. Native measurements describe the synthetic scan only, not a guarantee for the full app, long user videos, every font or every supported macOS version. Manual UI dragging, real-video quality and older-OS testing are additional checks.

Local verification on 2026-10-10: 87 core tests, native OCR groups, other native/export groups and 646 localization keys across five locales passed. TEST build 20261010-221609 started and passed the packaged OCR→SRT smoke. The warm four-second English synthetic clip took 0.41 seconds with maximum RSS 74,989,568 bytes; frame extraction was 0.102 seconds and recognition 0.275 seconds. These CLI numbers exclude the UI and do not establish cold-start or long-video performance. The full multi-language synthetic harness also checks rotation, closer sampling and equal-luminance color-digest invalidation. OCR uses macOS-readable media; unsupported video codecs/containers fail without committing a new transcript.

Entry correction on 2026-10-12: the first entry was attached only to the legacy create card, which is not displayed by the current main window. Both entries and the sheet are now wired in the active Timeline workspace. The full offline suite (87 core tests, native groups and 646 keys × five locales), TEST build/startup 20261012-053444 and packaged OCR→SRT smoke passed. Manual region dragging and real-user video testing remain separate checks.
