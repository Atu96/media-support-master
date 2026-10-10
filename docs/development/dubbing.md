# Dubbing execution and recovery

The current source adds the following behavior after the published 1.0.1 installer. A new source/TEST build is required; publishing source does not update an installed app or replace an existing release.

## Generation and cancellation

`DubbingSessionModel` owns the render snapshot and generation token. Google/ElevenLabs use `DubbingRenderQueue` with at most two in-flight requests. Identical spoken text with the same language, provider, model, voice and generation speed is generated once per run, then hard-linked to the individual cue files. Each cue retains independent timing and manual playback speed. Rate limits are reported as provider failures; there is no automatic provider switch or blind paid retry.

The queue uses structured child tasks and drains them on error/cancellation. Native conversion has its own cancellable utility worker, a 32,768-frame buffer, staging-file validation and a final file move. An older render/progress/cache-load callback cannot replace the current session's state. Completed valid clips remain available when another request fails.

## Maziao recovery

After submit returns a task ID, `MaziaoTaskJournal` atomically stores that receipt, original part order, character count and SHA-256 input/credential digests under Application Support/MaziaoPendingTasks. Raw keys, cue text and signed result URLs are not stored. Polling retains the existing adaptive interval and timeout policy.

On the next explicit render action, including after relaunch, matching unfinished requests first query the saved task. A subset of the original parts uses the original result indices and timeout size. This also handles a crash during local batch commit and a remaining cue below the minimum submit length. New requests still undergo the normal text-length/batch preflight. A known terminal failed/cancelled task is removed and reported; a later explicit action can create a fresh task. Timeouts, network errors, cancellation and download failures keep the receipt. Receipts are removed after validated local commit. Changing credentials prevents cross-account recovery. Nothing resumes in the background at app launch.

Recovery is not an exactly-once billing guarantee: if a submit was accepted remotely but its response/task ID never reached the app, the client cannot identify that task. Tasks submitted by older builds without a journal cannot be recovered this way. A corrupt journal fails closed instead of silently starting a replacement; unavailable/expired remote tasks require investigation rather than automatic resubmission.

Maziao result audio downloads straight to temporary files, with at most two download/conversion workers. Each result retains its original part position. All batch files are validated before commit; local failures remove staging/partial commits while keeping the remote receipt. Single-cue generation retains the paragraph API contract.

## Cache and audio formats

The v3 cue fingerprint normalizes only the same line breaks removed in the actual TTS request. It retains cue ID and excludes start/end time. A separate SHA-256 speech-content index allows independently generated speech to be reused across cue IDs. Composite M4A audio is excluded from this index because its gaps, overlaps and manual rates are baked into the clip.

Existing v2/v1 cache files are preserved and migrated via aliases when compatible; saved manual playback rates follow the migration. Old ElevenLabs clips at non-default generation speed are incompatible because that adapter previously omitted speed. Explicit audio deletion blocks historical reuse for that cue; a new successful render restores normal reuse. Cache clearing removes the local audio/index, while pending remote receipts remain available to prevent unnecessary resubmission.

ElevenLabs sends `voice_settings.speed` (rate/0.5, bounded to 0.7–1.2) through the pure `ElevenLabsRequestEncoder`. Its original 128 kbps MP3 is validated and cached byte-for-byte, without PCM expansion or a lossy re-encode. Google/Maziao remain CAF; merged clips remain M4A. Existing CAF files are not bulk converted. Cache allocation counts MP3/CAF/M4A, deduplicates hard links and includes reuse-index blocks.

`DubbingAudioDurationCache` retains at most 512 metadata entries, with no audio samples. File device/inode/size/modification time identify a version; hard-linked aliases share a probe, changed or deleted files invalidate it, and concurrent probes are coalesced.

## Checks and remaining scope

Core regressions cover receipt persistence/relaunch/subset ordering/account isolation/cancellation/corruption, the two-worker cap, cache migration/reuse/delete/composite isolation, metadata invalidation, ElevenLabs speed encoding, and original MP3 playback/merge/error preservation. `dubbing-tone.mp3` is an offline synthetic 440 Hz fixture; running tests requires no FFmpeg, key or provider call.

A TEST-only launcher hook exercises the real session with a fake provider and isolated preferences/cache. See [build and test](build-and-test.md). Paid-provider wall-clock performance, long real videos and subjective voice quality need separate measurements; fixture success does not certify those.

Context stitching remains outside this change. In particular, the selected Eleven v3 does not support it according to the [official stitching guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/text-to-speech/request-stitching). Any future supported-model context option must include context in the cache identity. No automatic speed fitting or offline AI model is added.
