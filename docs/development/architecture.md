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

Burned-in subtitle OCR uses local Vision with a user-selected image region and automatic language detection. A bounded frame worker produces complete timed cues through a streaming accumulator; only a matching project snapshot commits to the existing subtitle session. See [subtitle OCR](subtitle-ocr.md). Automatic sibling-SRT restoration respects a newer working transcript.

## Providers and data

Provider adapters own transport/schema, pure decoders validate fixtures, and session models coordinate jobs. Views do not call REST or read credential values directly. Translation writes only after all cue IDs are accounted for. Dubbing cache identity is independent of cue timing; explicit merges can preserve or combine valid audio locally.

Dubbing uses a two-worker cloud queue, cue-specific cache identities plus an independent speech-reuse index, and opaque Maziao receipt recovery on explicit render intent. Google/Maziao cache CAF; ElevenLabs retains validated original MP3; composite merges remain M4A. A bounded metadata cache shares duration probes across hard links. See [dubbing execution and recovery](dubbing.md) for cancellation, migration and provider limits.

Support is an independent, click-only HTTPS link shared by About and the resource bar. It does not participate in job completion, billing, or shutdown. New-install language selection is tested independently and preserves valid existing choices.
