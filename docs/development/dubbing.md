# Dubbing execution and recovery

The current source adds the following behavior after the published 1.0.1 installer. A new source/TEST build is required; publishing source does not update an installed app or replace an existing release.

## Generation and cancellation

`DubbingSessionModel` owns the render snapshot and generation token. Google/ElevenLabs use `DubbingRenderQueue` with at most two in-flight requests. Identical spoken text with the same language, provider, model, voice and generation speed is generated once per run, then hard-linked to the individual cue files. Each cue retains independent timing and manual playback speed. Rate limits are reported as provider failures; there is no automatic provider switch or blind paid retry.

The queue uses structured child tasks and drains them on error/cancellation. Native conversion has its own cancellable utility worker, a 32,768-frame buffer, staging-file validation and a final file move. An older render/progress/cache-load callback cannot replace the current session's state. Completed valid clips remain available when another request fails.

Maziao already uses `multiParts` batches around32 cues/4,000 characters, not one submit per cue. The current pipeline runs up to **two batches**, with a **one-batch** option in Settings → Dubbing → Maziao for accounts with lower concurrency. A shared limiter caps all downloads/conversions at two, including nested batches. Account/input/full-receipt leases remain held through local commit/finish; overlapping inputs or recovered receipts serialize so another worker cannot delete the receipt prematurely. Requests retain existing validation, model/voice and recovery semantics; concurrency/rate-limit failures do not trigger blind paid retries.

## Subtitle duration and manual editing

At the user's request on2026-10-12, default playback now fits the complete generated audio into the SUB span: `rate = audioDuration / subtitleDuration`. Native lane, preview and mix export share this effective rate. This is a local time mapping; it does not regenerate speech, change the provider generation-speed request, or reencode cache files just to fit. Existing explicit manual rates retain precedence.

Drag the right edge of a DUB cue to adjust its duration independently of SUB. Double-click the edge restores explicit natural1×. Right-click → **Fit subtitle duration** removes the override and returns to automatic fit. Changing SUB timing updates the default fit while retaining manual overrides. Original overlapping SUB timings or intentionally stretched DUB can still overlap and require review.

The voice-oriented [Apple timeDomain algorithm](https://developer.apple.com/documentation/avfoundation/avaudiotimepitchalgorithm/timedomain) supports1/32–32 playback rates. Speeds outside0.25–4 are marked for review; a span needing rates outside the native range cannot be matched exactly. Export includes the whole source audio, absorbs small media/SRT rounding differences through time mapping, and reports audio beyond the media or unsupported rates instead of silently cutting words. Native support does not imply intelligible speech at extreme speeds.

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

Context stitching remains outside this change. In particular, the selected Eleven v3 does not support it according to the [official stitching guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/text-to-speech/request-stitching). Any future supported-model context option must include context in the cache identity. No new offline AI model is added.

Live check on2026-10-12: an explicitly authorized TEST probe sent628 characters of fixed English diagnostic text in two tasks/four parts, using the configured Maziao voice/model. Both tasks waited on the provider concurrently; four CAF files validated successfully. Total wall time was36.91s, and both jobs still reported processing at30s. This supports the pipeline contract on that account, not a fixed speedup: no serial comparison, long user video, every model/account or subjective voice-quality benchmark was performed. The [official API document](https://app.maziao.com/api-documentation.md) defines `multiParts` as separate audio files; [Maziao's plans](https://maziao.com/en) describe tier-dependent API concurrency.
