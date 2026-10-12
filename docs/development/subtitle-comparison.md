# Subtitle comparison and original text priority

Available in the current source/TEST build. The published 1.0.1 installer predates this workflow.

## Optional second source

After a successful audio transcription of a video, the app offers OCR if the picture contains subtitles. After a successful OCR scan, it offers speech recognition. The OCR offer appears after closing its scan sheet. **Later** dismisses the offer; **Do not remind me again** persists across launches. No offer follows the supplementary scan or application, and audio-only files do not offer OCR. The toolbar **Compare** menu remains available even with reminders disabled.

OCR uses the existing local region-selection/scan workflow and its 2/4 fps, single-worker budget. Audio comparison explicitly offers Groq cloud (uses API quota after **Get additional version**) or the already installed Whisper Offline model. No recognition starts from an offer alone and there is no automatic paid fallback.

The supplementary output stays separate from the current SRT, project backup and timeline. After scanning, the review groups overlapping time intervals so one audio cue can be compared with several OCR cues. **Show differences only** can be disabled to see every group. The current version is selected by default, including missing intervals; choose **OCR version** or **Audio version** individually. An empty side means no cues for that time group. Selecting the empty side explicitly removes that group's cues. A candidate-only interval is inserted only when selected.

The review shows both language labels and the shared media preview. **View this section** seeks without autoplay; native preview controls allow playback. Screen subtitles may be translations rather than the spoken language. The app does not claim that either source is more accurate or automatically decide which conflicting text is correct.

**Apply choices** uses the chosen group's complete text and measured cue times. It does not assign word timestamps or estimate new times from text length. Invalid, empty-output or overlapping timing is rejected. Application is one undoable edit; unchanged speech/span cues retain their dubbing cache and manual-rate aliases when cue numbers change. Changed text can require new dubbing. Media, cue, variant, SRT, language, style or pending-edit changes prevent stale application; stopping/closing discards the supplementary result and preserves the current transcript.

## Original text after transcription or OCR

In **Create subtitles from text**, paste text or use **Import TXT**, then click **Create subtitles**. For an existing original transcript in the same project, the original text is the canonical wording. A bounded local matcher first reuses the existing whole cue spans; it does not transcribe again, call an API, or require the Whisper model. A complete, conservative match replaces cue text, preserves cue IDs/times and uses the current one/two-line layout when it fits. Overflow stays visible to QC instead of dropping words or inventing timings. Applying records one Undo.

Saved SRT has cue-level evidence, not word-level evidence. Strong text mismatch or a word crossing ambiguous cue boundaries is rejected with the existing transcript intact. Check content/language or intentionally use a fresh media alignment when needed; there is no silent paid retry. When no original transcript exists (or the active variant is translated), the established audio alignment workflow remains available and still needs the separately installed Whisper model. Japanese's established fresh alignment pipeline is unchanged.

## Owners and verification

- `SubtitleEvidenceComparison.swift`: bounded time-group comparison, explicit choices and existing-cue script mapping.
- `SubtitleComparisonController.swift`: optional offers, private staging, snapshot/cancellation, Undo and DUB aliases; session/scan seams permit no-key fixtures.
- `SubtitleComparisonView.swift`: choice review and secondary-source configuration; Timeline is the only timing editor.
- Existing OCR controller has a supplementary mode with no transcript/vault commit. `MediaEngineServing.runComparisonSpeechSRT` accepts a private output URL and reuses the existing speech services.

Core fixtures cover one-to-many/absent/identical groups, explicit selection, stable IDs, invalid timing, script priority across VI/EN/JA/KO/ZH, minor spelling corrections and mismatch rejection. A TEST-only fake-session hook exercises staging, review/apply, Undo, cancellation/stale results, reminder suppression and script preservation without reading Keychain or using API quota. Synthetic tests and compilation do not certify OCR/ASR accuracy on personal videos or every UI click. See [build and test](build-and-test.md).
