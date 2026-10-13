# Runtime review — 2026-10-13

## Implemented

- **Word timing lookup:** the subtitle formatter previously filtered every word for every provider segment. One immutable interval index now uses binary bounds on ordered valid timestamps and checks only the relevant slice. Provider order, inclusive ±0.04s tolerance and invalid/unsorted fallback are preserved. This removes repeated full-list scans; it does not change recognition or send additional API requests.
- **Waveform lifecycle:** the workspace owns/cancels the active load and checks media/UUID before applying it. Cancellation propagates into the utility decode worker and releases AVAssetReader. Canceled work does not become a successful cache result.
- **QC lifecycle:** initial analysis uses the same background/debounce path as later updates. Cancellation reaches the worker and the analyzer checks between cues. Glyph measurement no longer runs synchronously over every cue when the workspace first appears.
- **One main app:** the installer builds a release-channel app with embedded Runtime, helpers and notices; validates native fixtures in a disposable copy; verifies signature/hash before replacement; checks exact Applications startup; then removes the legacy TEST bundle. Compatibility build commands delegate to this installer. It retains one previous main app for rollback and preserves user data outside the bundle.
- **Maziao catalog:** both shared and account-owned voice endpoints are paginated and merged by ID, preferring owned metadata. Both pickers expose voices across models with model labels. The observed catalog spelling `vietten_speech` resolves to the provider configuration's `vieten_speech` for selection; raw metadata stays intact. A GET-only check using the updated decoder/workflow found 200 unique voices, two owned voices and one Quân Anh search match. No synthesis was performed for these voices.

## Existing controls retained

Waveform keeps reduced peaks/RMS rather than PCM and a three-item process cache. OCR uses one bounded worker/cropped frames/static-image reuse. Layout is cancellable and debounced, with Core Text and Japanese invariants. Cloud dubbing retains bounded remote/I/O concurrency, cache reuse and known-task recovery. These limits should be changed only with representative measurements.

## Further work worth measuring

1. Profile long real projects during drag/playback and font/QC changes; isolate SwiftUI recomputation or allocations before refactoring the large workspace.
2. Measure export stages and move remaining deprecated AVFoundation calls in a separate change with real codec fixtures.
3. Expand sanitized Groq/Google/ElevenLabs response fixtures and real multilingual recognition/layout evaluation. Synthetic tests cannot certify provider accuracy, voice quality or latency.
4. Consider separating test-only launch hooks from production compilation later; the installed release channel currently ignores them.

These are review opportunities, not measured regressions. No claim of a whole-app speedup percentage or reduced cloud-server time is made. Core QA includes 102 passing cases, interval parity and deterministic worker-cancellation checks; native/package/startup validation is recorded in the current checkpoint.

## Refactor review after the Maziao catalog fix

Review scope: the mapped dubbing/session/settings/catalog/playback owners and their direct call sites. This is a source review, not a full-app profiler run. Current installed main is `20261013-181858`; its catalog change passed 104 core tests, native groups/24 XML checks and 737 localization keys across five locales. The review below changes documentation only; these proposals are not implemented.

### 1. Give provider refreshes explicit task and credential ownership

**First priority: correctness when changing keys during refresh.** `DubbingSessionModel.refreshMaziaoVoiceCatalog` awaits a request and then publishes its result without a refresh generation or credential revision check. Clearing its catalog does not cancel or invalidate the in-flight refresh. `SettingsDubbingPanel.saveMaziaoKey` clears the catalog and schedules another refresh, but the current loading flags can reject that new intent while an old request finishes. `MaziaoAPIClient.send` reloads the key for each page, so a multi-page run can span two accounts if the key changes between pages. These are source-level race conditions; they have not been reproduced with a real account switch.

Introduce a refresh coordinator owning a task, credential revision and result generation. Capture one credential for one GET run outside the UI, invalidate/cancel on save/delete, ignore stale success/error callbacks and allow the newest explicit refresh to proceed. Apply the result guard to quota/account refresh as well. Keep secrets in memory only, never in logs or preferences. Keep the current session properties and selection behavior as the facade so the views and existing render pipeline need minimal changes.

Verify with delayed fake responses: A starts, key B is saved, A completes last; only B's catalog/usage may be published. Also cover deletion while loading, old failure after new success, and cancellation without subsequent page requests. Do not use paid API tests for these cases.

### 2. Prepare playback cue data when it changes

**Second priority: avoid repeated work on the main thread.** `AVPreviewService.observeTime` updates at 30 Hz; `SubtitleTimelineWorkspace` observes `preview.currentTime` and calls dubbing synchronization. Each call currently obtains `DubbingSessionModel.effectiveRenderedCues`, mapping and sorting the whole rendered dictionary, then `DubbingPlaybackCoordinator.synchronize` filters the whole list for active cues. This repeated work is visible in source; its effect on responsiveness has not been measured.

Cache the sorted effective playback snapshot and rebuild it when clip membership, timing or effective rate changes. Then profile whether an interval lookup is worthwhile. Preserve overlapping DUB playback: a lookup must return every active clip, including long clips that start before newer ones. Do not substitute a single-cue binary search or reuse word intervals without considering that overlap rule.

Verify result parity for overlaps, exact start/end boundaries, seeks in both directions, deletion, merge/reindex, render completion, manual-rate edits and fit-to-SUB. Measure main-thread time and allocations on representative long projects before claiming a speedup.

### 3. Separate session responsibilities by lifecycle

**Third priority: maintainability.** The 1,345-line `DubbingSessionModel` owns render/cache orchestration, merge preservation, provider catalogs/credentials, playback adaptation and export status. `SettingsDubbingPanel` also owns provider-specific credential/usage refresh state. The useful first extraction is the refresh coordinator above, not an arbitrary split by file length. Later, isolate render-run state/progress and merge transactions one at a time while the session continues to expose the existing published state and intents.

Use an injectable catalog client so fake tests can exercise the complete refresh lifecycle; the existing pure catalog workflow only verifies paging/merging. Provider-specific schemas and selection rules should stay behind their current owners rather than being collapsed into one generic decoder. Preserve generation checks, receipt recovery, concurrency budgets, cache identities, Undo, cancellation and the established Japanese subtitle path.

### Lower priority

The voice picker currently groups/sorts for both filtered content and its unfiltered summary. Precomputing this projection may help very large catalogs, but the observed 200-voice catalog does not establish a performance problem. Splitting provider models/decoders into separate files or excluding test launch hooks from release compilation can improve organization later; neither warrants a broad rewrite now.

Implementation order: fix refresh ownership first, profile/cache playback data second, then extract session responsibilities in separate reviewable changes. Run the relevant fake regressions and full offline gate before installing each runtime change in the main app. The existing 104-test gate remains the baseline, not evidence that these proposed changes have passed.
