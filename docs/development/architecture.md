# Architecture

Media Support Master is a native AppKit/SwiftUI app. Source lives in `build-native/source/MediaSupportMac`.

| Layer | Responsibility |
|---|---|
| App | Launch, preferences, localization, menus and coordination |
| Presentation | Workspace, timeline, settings and user actions |
| Domain | Models, layout/timing rules and provider contracts |
| Infrastructure | AVFoundation, file I/O, Keychain, provider adapters and workflows |

The subtitle timeline is the only timing editor. `SubtitleViewModel` owns subtitle/session state, `AVPreviewService` owns video playback, and `DubbingSessionModel` plus its playback coordinator own dubbing lifecycle.

## Subtitle pipeline

Verified word timing, adaptive pauses and cached waveform evidence feed the local cue planner. Optional semantic refinement returns boundary IDs, never rewritten words. Native Core Text measurements enforce layout; word retiming and conservative speech-edge refinement follow when evidence is valid.

For non-Japanese text, local token/phrase context improves boundaries without requiring punctuation. Available macOS lexical analysis is used without requesting language assets. Japanese retains its existing tailoring. A word/transcript mismatch falls back to segment timing. Manual line breaks are intentional data.

Changing line count or font size schedules cancellable work off the main actor. Only the newest result with a matching project/text/style snapshot can commit to undo history. It does not transcribe again or call an online model.

The Style inspector also exposes a global **Subtitle position** slider, up/down buttons and a position-only reset. It uses the existing persisted `marginBottom` on the 1080 reference canvas (16–960), without editing text, timing, line breaks or dubbing cache identities. Shared Preview/video layers clamp the complete text box inside the frame. FCPXML reserves space for two lines and uses matching Swift/Python position math; original default and lower positions remain compatible.

QC analysis is read-only and uses the selected one/two-line limit. The active Timeline QC menu exposes explicit per-cue layout repair, manual editing and a batch repair for cues exceeding that limit. Repair uses the existing cancellable layout worker and snapshot guards. It preserves characters and original cue spans and creates one Undo step. Planning keeps stable IDs to map unchanged cues exactly, then commits canonical SRT IDs/indexes. The worker creates cache hard links and preserves manual rates for unchanged speech/spans, including composite audio after reopening; conflicting composite/rate aliases fail closed. Long cues can be split with estimated text-weight timing inside their original span; changed/split dubbing may need regeneration. Empty text, overlap and layouts that cannot safely fit remain available for manual review rather than inventing content or removing timing.

The toolbar distinguishes **Extract subtitles from audio** (speech transcription) from **Extract video subtitles** (local OCR of burned-in text). One **Export** menu delegates to the existing SRT/TXT/XML actions. Final video export remains in titlebar settings. These presentation changes do not change providers, credentials or usage behavior.

Burned-in subtitle OCR uses local Vision with a user-selected image region and automatic language detection. A bounded frame worker produces complete timed cues through a streaming accumulator; only a matching project snapshot commits to the existing subtitle session. See [subtitle OCR](subtitle-ocr.md). Automatic sibling-SRT restoration respects a newer working transcript.

## Providers and data

Provider adapters own transport/schema, pure decoders validate fixtures, and session models coordinate jobs. Views do not call REST or read credential values directly. Translation writes only after all cue IDs are accounted for. Dubbing cache identity is independent of cue timing; explicit merges can preserve or combine valid audio locally.

Dubbing uses a two-worker cloud queue, cue-specific cache identities plus an independent speech-reuse index, and opaque Maziao receipt recovery on explicit render intent. Google/Maziao cache CAF; ElevenLabs retains validated original MP3; composite merges remain M4A. A bounded metadata cache shares duration probes across hard links. See [dubbing execution and recovery](dubbing.md) for cancellation, migration and provider limits.

Support is an independent, click-only HTTPS link shared by About and the resource bar. It does not participate in job completion, billing, or shutdown. New-install language selection is tested independently and preserves valid existing choices.
